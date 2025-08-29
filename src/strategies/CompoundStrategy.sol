// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IAbunfiStrategy.sol";

// Compound V3 interfaces
interface IComet {
    function supply(address asset, uint amount) external;
    function withdraw(address asset, uint amount) external;
    function balanceOf(address account) external view returns (uint256);
    function getSupplyRate(uint utilization) external view returns (uint64);
    function getUtilization() external view returns (uint);
    function baseToken() external view returns (address);
    function decimals() external view returns (uint8);
    function accrueAccount(address account) external;
}

interface ICometRewards {
    function claim(address comet, address src, bool shouldAccrue) external;
    function getRewardOwed(address comet, address account) external view returns (uint256);
}

/**
 * @title CompoundStrategy
 * @dev Strategy that deposits USDC into Compound V3 to earn lending yield
 */
contract CompoundStrategy is IAbunfiStrategy, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // State variables
    IERC20 public immutable _asset; // USDC
    IComet public immutable comet; // Compound V3 market
    ICometRewards public immutable cometRewards; // Compound rewards contract
    address public immutable vault;
    
    uint256 public totalDeposited;
    uint256 public lastHarvestTime;
    
    // Constants
    uint256 private constant SCALE_FACTOR = 1e18;
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    
    // Events
    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event Harvested(uint256 yield);
    event RewardsClaimed(uint256 amount);

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    constructor(
        address assetAddress,
        address _comet,
        address _cometRewards,
        address _vault
    ) Ownable(msg.sender) {
        _asset = IERC20(assetAddress);
        comet = IComet(_comet);
        cometRewards = ICometRewards(_cometRewards);
        vault = _vault;

        // Verify that the comet base token matches our asset
        require(comet.baseToken() == assetAddress, "Asset mismatch");

        // Approve Compound market to spend our tokens
        SafeERC20.forceApprove(_asset, _comet, type(uint256).max);

        lastHarvestTime = block.timestamp;
    }

    /**
     * @dev Get the underlying asset address
     */
    function asset() external view override returns (address) {
        return address(_asset);
    }

    /**
     * @dev Deposit USDC into Compound V3
     */
    function deposit(uint256 amount) external override onlyVault nonReentrant {
        require(amount > 0, "Cannot deposit 0");

        // Tokens should already be transferred by vault
        // Approve Compound comet to spend tokens
        SafeERC20.forceApprove(_asset, address(comet), amount);

        // Supply to Compound V3
        comet.supply(address(_asset), amount);

        totalDeposited += amount;

        emit Deposited(amount);
    }

    /**
     * @dev Withdraw specific amount from Compound V3
     */
    function withdraw(uint256 amount) external override onlyVault nonReentrant {
        require(amount > 0, "Cannot withdraw 0");
        require(amount <= totalAssets(), "Insufficient balance");
        
        // Withdraw from Compound V3
        comet.withdraw(address(_asset), amount);
        
        // Transfer to vault
        SafeERC20.safeTransfer(_asset, vault, amount);
        
        if (amount > totalDeposited) {
            totalDeposited = 0;
        } else {
            totalDeposited -= amount;
        }
        
        emit Withdrawn(amount);
    }

    /**
     * @dev Withdraw all assets from Compound V3
     */
    function withdrawAll() external override onlyVault nonReentrant {
        uint256 balance = comet.balanceOf(address(this));
        if (balance > 0) {
            comet.withdraw(address(_asset), balance);
            SafeERC20.safeTransfer(_asset, vault, _asset.balanceOf(address(this)));
            totalDeposited = 0;
            emit Withdrawn(balance);
        }
    }

    /**
     * @dev Harvest yield and claim COMP rewards
     */
    function harvest() external override onlyVault returns (uint256 yield) {
        // Accrue interest first
        comet.accrueAccount(address(this));
        
        uint256 currentBalance = comet.balanceOf(address(this));
        
        if (currentBalance > totalDeposited) {
            yield = currentBalance - totalDeposited;
            totalDeposited = currentBalance; // Update to include compounded yield
        }
        
        // Claim COMP rewards if available
        _claimRewards();
        
        lastHarvestTime = block.timestamp;
        
        if (yield > 0) {
            emit Harvested(yield);
        }
        
        return yield;
    }

    /**
     * @dev Get total assets in strategy (including accrued interest)
     */
    function totalAssets() public view override returns (uint256) {
        return comet.balanceOf(address(this));
    }

    /**
     * @dev Get strategy name
     */
    function name() external pure override returns (string memory) {
        return "Compound V3 USDC Lending Strategy";
    }

    /**
     * @dev Get current APY from Compound V3
     */
    function getAPY() external view override returns (uint256) {
        uint256 utilization = comet.getUtilization();
        uint64 supplyRate = comet.getSupplyRate(utilization);
        
        // Convert from Compound's rate format to basis points (10000 = 100%)
        // Compound rates are per second, so we need to annualize
        uint256 annualRate = uint256(supplyRate) * SECONDS_PER_YEAR;
        
        // Convert to basis points (divide by 1e18 and multiply by 10000)
        return (annualRate * 10000) / SCALE_FACTOR;
    }

    /**
     * @dev Get current supply rate from Compound V3
     */
    function getCurrentSupplyRate() external view returns (uint64) {
        uint256 utilization = comet.getUtilization();
        return comet.getSupplyRate(utilization);
    }

    /**
     * @dev Get pending COMP rewards
     */
    function getPendingRewards() external view returns (uint256) {
        return cometRewards.getRewardOwed(address(comet), address(this));
    }

    /**
     * @dev Claim COMP rewards
     */
    function _claimRewards() internal {
        uint256 pendingRewards = cometRewards.getRewardOwed(address(comet), address(this));
        
        if (pendingRewards > 0) {
            cometRewards.claim(address(comet), address(this), true);
            emit RewardsClaimed(pendingRewards);
        }
    }

    /**
     * @dev Manual function to claim rewards (only owner)
     */
    function claimRewards() external onlyOwner {
        _claimRewards();
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
        uint256 currentBalance = comet.balanceOf(address(this));
        return currentBalance > totalDeposited ? currentBalance - totalDeposited : 0;
    }

    /**
     * @dev Get utilization rate of the Compound market
     */
    function getUtilization() external view returns (uint256) {
        return comet.getUtilization();
    }
}
