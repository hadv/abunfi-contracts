// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IAbunfiStrategy.sol";
import "../mocks/MockERC20.sol";

// Aave V3 interfaces
interface IPool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function getReserveData(address asset) external view returns (ReserveData memory);
}

interface IPoolDataProvider {
    function getReserveData(address asset) external view returns (
        uint256 unbacked,
        uint256 accruedToTreasuryScaled,
        uint256 totalAToken,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 liquidityRate,
        uint256 variableBorrowRate,
        uint256 stableBorrowRate,
        uint256 averageStableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex,
        uint40 lastUpdateTimestamp
    );
    
    function getUserReserveData(address asset, address user) external view returns (
        uint256 currentATokenBalance,
        uint256 currentStableDebt,
        uint256 currentVariableDebt,
        uint256 principalStableDebt,
        uint256 scaledVariableDebt,
        uint256 stableBorrowRate,
        uint256 liquidityRate,
        uint40 stableRateLastUpdated,
        bool usageAsCollateralEnabled
    );
}

struct ReserveData {
    uint256 configuration;
    uint128 liquidityIndex;
    uint128 currentLiquidityRate;
    uint128 variableBorrowIndex;
    uint128 currentVariableBorrowRate;
    uint128 currentStableBorrowRate;
    uint40 lastUpdateTimestamp;
    uint16 id;
    address aTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    address interestRateStrategyAddress;
    uint128 accruedToTreasury;
    uint128 unbacked;
    uint128 isolationModeTotalDebt;
}

/**
 * @title AaveStrategy
 * @dev Strategy that deposits USDC into Aave V3 to earn lending yield
 */
contract AaveStrategy is IAbunfiStrategy, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // State variables
    IERC20 public immutable _asset; // USDC
    IERC20 public immutable aToken; // aUSDC
    IPool public immutable aavePool;
    IPoolDataProvider public immutable dataProvider;
    address public immutable vault;
    
    uint256 public totalDeposited;
    uint256 public lastHarvestTime;
    
    // Constants
    uint256 private constant RAY = 1e27;
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    
    // Events
    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event Harvested(uint256 yield);

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    constructor(
        address assetAddress,
        address _aavePool,
        address _dataProvider,
        address _vault
    ) Ownable(msg.sender) {
        _asset = IERC20(assetAddress);
        aavePool = IPool(_aavePool);
        dataProvider = IPoolDataProvider(_dataProvider);
        vault = _vault;

        // Get aToken address from Aave
        ReserveData memory reserveData = aavePool.getReserveData(assetAddress);
        require(reserveData.aTokenAddress != address(0), "Invalid aToken address");
        aToken = IERC20(reserveData.aTokenAddress);

        // Approve Aave pool to spend our tokens
        SafeERC20.forceApprove(_asset, _aavePool, type(uint256).max);

        lastHarvestTime = block.timestamp;
    }

    /**
     * @dev Get the underlying asset address
     */
    function asset() external view override returns (address) {
        return address(_asset);
    }

    /**
     * @dev Deposit USDC into Aave
     */
    function deposit(uint256 amount) external override onlyVault nonReentrant {
        require(amount > 0, "Cannot deposit 0");

        // Tokens should already be transferred by vault
        // Approve Aave pool to spend tokens
        SafeERC20.forceApprove(_asset, address(aavePool), amount);

        // Supply to Aave
        aavePool.supply(address(_asset), amount, address(this), 0);

        totalDeposited += amount;

        emit Deposited(amount);
    }

    /**
     * @dev Withdraw specific amount from Aave
     */
    function withdraw(uint256 amount) external override onlyVault nonReentrant {
        require(amount > 0, "Cannot withdraw 0");
        require(amount <= totalDeposited, "Insufficient balance");

        // Withdraw from Aave
        uint256 withdrawn = aavePool.withdraw(address(_asset), amount, vault);

        totalDeposited -= withdrawn;

        emit Withdrawn(withdrawn);
    }

    /**
     * @dev Withdraw all assets from Aave
     */
    function withdrawAll() external override onlyVault nonReentrant {
        if (totalDeposited > 0) {
            uint256 withdrawn = aavePool.withdraw(address(_asset), totalDeposited, vault);
            totalDeposited = 0;
            emit Withdrawn(withdrawn);
        }
    }

    /**
     * @dev Harvest yield (for Aave, yield is automatically compounded)
     */
    function harvest() external override onlyVault returns (uint256 yield) {
        // Calculate actual yield based on aToken balance vs totalDeposited
        uint256 currentBalance = aToken.balanceOf(address(this));

        if (currentBalance > totalDeposited) {
            yield = currentBalance - totalDeposited;
            totalDeposited = currentBalance;
            lastHarvestTime = block.timestamp;
            emit Harvested(yield);
        }

        return yield;
    }

    /**
     * @dev Get total assets in strategy (including accrued interest)
     */
    function totalAssets() public view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    /**
     * @dev Get strategy name
     */
    function name() external pure override returns (string memory) {
        return "Aave USDC Lending Strategy";
    }

    /**
     * @dev Get current APY from Aave
     */
    function getAPY() external view override returns (uint256) {
        (, , , , , uint256 liquidityRate, , , , , , ) = dataProvider.getReserveData(address(_asset));
        
        // Convert from ray (1e27) to basis points (10000 = 100%)
        // APY = (1 + liquidityRate/RAY)^SECONDS_PER_YEAR - 1
        // Simplified calculation for display purposes
        return (liquidityRate * 10000) / RAY;
    }

    /**
     * @dev Get current lending rate from Aave
     */
    function getCurrentLendingRate() external view returns (uint256) {
        (, , , , , uint256 liquidityRate, , , , , , ) = dataProvider.getReserveData(address(_asset));
        return liquidityRate;
    }

    /**
     * @dev Get user reserve data from Aave
     */
    function getUserReserveData() external view returns (
        uint256 currentATokenBalance,
        uint256 liquidityRate
    ) {
        (currentATokenBalance, , , , , , liquidityRate, , ) = dataProvider.getUserReserveData(
            address(_asset),
            address(this)
        );
    }

    /**
     * @dev Emergency function to recover tokens
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /**
     * @dev Get accrued yield since last harvest
     */
    function getAccruedYield() external view returns (uint256) {
        uint256 currentBalance = aToken.balanceOf(address(this));
        return currentBalance > totalDeposited ? currentBalance - totalDeposited : 0;
    }
}
