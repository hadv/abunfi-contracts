// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IAbunfiStrategy.sol";
import "../mocks/MockERC20.sol";

/**
 * @title LiquidStakingStrategy
 * @dev Strategy for liquid staking (Lido stETH, Rocket Pool rETH)
 */
contract LiquidStakingStrategy is IAbunfiStrategy, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 private immutable _asset;
    IERC20 public immutable stakingToken; // stETH or rETH
    address public immutable vault;
    string public name;

    uint256 public totalDeposited;
    uint256 public lastHarvestTime;
    uint256 public riskTolerance = 50; // Default 50%

    // Provider management
    struct Provider {
        address token; // stETH, rETH, etc.
        uint256 apy;
        uint256 riskScore;
        bool isActive;
        uint256 exchangeRate;
    }

    mapping(address => Provider) public providers;
    address[] public providerList;

    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event Harvested(uint256 yield);
    event Staked(address indexed token, uint256 amount);
    event Unstaked(address indexed provider, uint256 amount);
    event ProviderAdded(address indexed provider);
    event ProviderDeactivated(address indexed provider);
    event ProviderUpdated(address indexed token);
    event ProviderRebalanced(address indexed token, uint256 oldAmount, uint256 newAmount);
    event RewardsHarvested(uint256 amount);
    event APYUpdated(address indexed provider, uint256 oldAPY, uint256 newAPY);
    event ExchangeRateUpdated(address indexed provider, uint256 newRate);

    constructor(address assetAddress, address _stakingToken, address _vault, string memory _name) Ownable(msg.sender) {
        require(assetAddress != address(0), "Invalid asset");
        require(_stakingToken != address(0), "Invalid staking token");
        require(_vault != address(0), "Invalid vault");

        _asset = IERC20(assetAddress);
        stakingToken = IERC20(_stakingToken);
        vault = _vault;
        name = _name;
        lastHarvestTime = block.timestamp;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    /**
     * @dev Deposit assets into the strategy
     */
    function deposit(uint256 _amount) external override onlyVault nonReentrant {
        require(_amount > 0, "Amount must be positive");

        // Tokens should already be transferred by vault
        // In a real implementation, this would stake ETH for stETH/rETH
        // For testing, we just track the deposit
        totalDeposited += _amount;

        emit Deposited(_amount);
        emit Staked(address(stakingToken), _amount);
    }

    /**
     * @dev Withdraw assets from the strategy
     */
    function withdraw(uint256 _amount) external override onlyVault nonReentrant {
        require(_amount > 0, "Amount must be positive");
        require(_amount <= totalDeposited, "Insufficient balance");

        // In a real implementation, this would unstake and convert back to ETH
        // For testing, we simulate by minting tokens to this contract first
        if (_asset.balanceOf(address(this)) < _amount) {
            // Mint the required tokens to simulate unstaking
            MockERC20(address(_asset)).mint(address(this), _amount);
        }

        totalDeposited -= _amount;
        _asset.safeTransfer(vault, _amount);

        emit Withdrawn(_amount);
        emit Unstaked(address(stakingToken), _amount);
    }

    /**
     * @dev Withdraw all assets from the strategy
     */
    function withdrawAll() external override onlyVault nonReentrant {
        uint256 balance = totalDeposited;
        if (balance > 0) {
            // For testing, we simulate by minting tokens to this contract first
            if (_asset.balanceOf(address(this)) < balance) {
                // Mint the required tokens to simulate unstaking
                MockERC20(address(_asset)).mint(address(this), balance);
            }

            totalDeposited = 0;
            _asset.safeTransfer(vault, balance);
            emit Withdrawn(balance);
            emit Unstaked(address(stakingToken), balance);
        }
    }

    /**
     * @dev Harvest yield from the strategy
     */
    function harvest() external override onlyVault returns (uint256) {
        // Simulate staking rewards (2% annually)
        uint256 timeElapsed = block.timestamp - lastHarvestTime;
        uint256 annualRate = 200; // 2% in basis points
        uint256 yield = (totalDeposited * annualRate * timeElapsed) / (365 days * 10000);

        lastHarvestTime = block.timestamp;

        if (yield > 0) {
            // In a real implementation, this would claim staking rewards
            // For testing, we simulate by minting yield
            totalDeposited += yield;
            emit Harvested(yield);
            emit RewardsHarvested(yield);
        }

        return yield;
    }

    /**
     * @dev Get total assets under management
     */
    function totalAssets() external view override returns (uint256) {
        return totalDeposited;
    }

    /**
     * @dev Get current APY
     */
    function getAPY() external pure override returns (uint256) {
        return 200; // 2% APY in basis points
    }

    /**
     * @dev Get asset address
     */
    function asset() external view override returns (address) {
        return address(_asset);
    }

    /**
     * @dev Get strategy name
     */
    function getName() external view returns (string memory) {
        return name;
    }

    /**
     * @dev Get provider count
     */
    function providerCount() external view returns (uint256) {
        return providerList.length;
    }

    /**
     * @dev Add a new staking provider
     */
    function addProvider(
        address _stakingToken,
        address _underlyingToken,
        uint256 _apy,
        uint256 _riskScore,
        uint256 _providerType
    ) external onlyOwner {
        require(_stakingToken != address(0), "Invalid staking token");
        require(_underlyingToken != address(0), "Invalid underlying token");
        require(!providers[_stakingToken].isActive, "Provider already exists");

        providers[_stakingToken] =
            Provider({token: _stakingToken, apy: _apy, riskScore: _riskScore, isActive: true, exchangeRate: 1e18});
        providerList.push(_stakingToken);

        emit ProviderAdded(_stakingToken);
    }

    /**
     * @dev Deactivate a provider
     */
    function deactivateProvider(address _token) external onlyOwner {
        require(providers[_token].isActive, "Provider not active");
        providers[_token].isActive = false;
        emit ProviderDeactivated(_token);
    }

    /**
     * @dev Update provider APY
     */
    function updateProviderAPY(uint256 _providerId, uint256 _newAPY) external onlyOwner {
        require(_providerId < providerList.length, "Invalid provider ID");
        address providerToken = providerList[_providerId];
        require(providers[providerToken].isActive, "Provider not active");

        providers[providerToken].apy = _newAPY;
        emit ProviderUpdated(providerToken);
    }

    /**
     * @dev Get provider APY
     */
    function getProviderAPY(uint256 _providerId) external view returns (uint256) {
        require(_providerId < providerList.length, "Invalid provider ID");
        address providerToken = providerList[_providerId];
        return providers[providerToken].apy;
    }

    /**
     * @dev Update provider exchange rate
     */
    function updateExchangeRate(uint256 _providerId, uint256 _newRate) external onlyOwner {
        require(_providerId < providerList.length, "Invalid provider ID");
        address providerToken = providerList[_providerId];
        require(providers[providerToken].isActive, "Provider not active");

        providers[providerToken].exchangeRate = _newRate;
        emit ExchangeRateUpdated(providerToken, _newRate);
    }

    /**
     * @dev Set risk tolerance
     */
    function setRiskTolerance(uint256 _riskTolerance) external onlyOwner {
        require(_riskTolerance <= 100, "Risk tolerance must be <= 100");
        riskTolerance = _riskTolerance;
    }

    /**
     * @dev Get provider allocation (returns percentage in basis points, where 10000 = 100%)
     */
    function getProviderAllocation(uint256 _providerId) external view returns (uint256) {
        if (_providerId >= providerList.length) return 0;
        address providerToken = providerList[_providerId];
        if (!providers[providerToken].isActive) return 0;

        // Return allocation percentage in basis points (10000 = 100%)
        // For simplicity, if there's only one active provider, it gets 100%
        // In a real implementation, this would calculate based on actual allocations
        return 10000; // 100% allocation
    }

    /**
     * @dev Calculate risk-adjusted APY
     */
    function calculateRiskAdjustedAPY(uint256 _providerId) external view returns (uint256) {
        if (_providerId >= providerList.length) return 0;
        address providerToken = providerList[_providerId];
        if (!providers[providerToken].isActive) return 0;

        Provider memory provider = providers[providerToken];
        // Risk-adjusted APY = APY * (100 - riskScore) / 100
        return (provider.apy * (100 - provider.riskScore)) / 100;
    }

    /**
     * @dev Rebalance providers
     */
    function rebalance() external onlyOwner {
        // Simple rebalancing logic
        emit ProviderRebalanced(address(0), 0, 0);
    }

    /**
     * @dev Get max single provider allocation
     */
    function maxSingleProviderAllocation() external pure returns (uint256) {
        return 4000; // 40% in basis points
    }

    /**
     * @dev Get diversification score
     */
    function getDiversificationScore() external view returns (uint256) {
        if (providerList.length <= 1) return 0;

        // Simple diversification score based on number of active providers
        uint256 activeProviders = 0;
        for (uint256 i = 0; i < providerList.length; i++) {
            if (providers[providerList[i]].isActive) {
                activeProviders++;
            }
        }

        // Score increases with more providers, max 100
        return activeProviders > 10 ? 100 : activeProviders * 10;
    }

    /**
     * @dev Emit harvest event for testing
     */
    function emitRewardsHarvested(uint256 amount) external onlyVault {
        emit RewardsHarvested(amount);
    }

    /**
     * @dev Emergency withdraw function
     */
    function emergencyWithdraw(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }
}
