// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IAbunfiStrategy.sol";
import "../interfaces/IPoolManager.sol";
import "../interfaces/IUniswapV4Hook.sol";
import "../libraries/StablecoinRangeManager.sol";
import "../libraries/FeeOptimizer.sol";

/**
 * @title UniswapV4FairFlowStablecoinStrategy
 * @dev Advanced liquidity providing strategy for stablecoin pairs in Uniswap V4
 * Features: Concentrated liquidity, dynamic fees, automated rebalancing, hooks integration
 */
contract UniswapV4FairFlowStablecoinStrategy is IAbunfiStrategy, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using StablecoinRangeManager for *;
    using FeeOptimizer for *;

    // Core strategy parameters
    IERC20 private immutable _asset;
    IERC20 private immutable _pairedAsset;
    address public immutable vault;
    address public immutable poolManager;
    address public immutable hook;
    string public name;

    // Pool configuration
    PoolKey public poolKey;
    uint24 public currentFee;
    int24 public tickSpacing;

    // Position management
    StablecoinRangeManager.PositionInfo public currentPosition;
    StablecoinRangeManager.RangeConfig public rangeConfig;
    FeeOptimizer.FeeConfig public feeConfig;
    FeeOptimizer.MarketConditions public marketConditions;

    // Strategy state
    uint256 public totalDeposited;
    uint256 public totalFeesClaimed;
    uint256 public lastHarvestTime;
    uint256 public lastRebalanceTime;
    uint256 public lastFeeUpdateTime;
    uint256 public rebalanceCount;

    // Risk management
    uint256 public maxSlippage = 100; // 1% in basis points
    uint256 public emergencyExitThreshold = 500; // 5% IL threshold
    bool public emergencyMode = false;

    // Events
    event Deposited(uint256 amount0, uint256 amount1, uint128 liquidity);
    event Withdrawn(uint256 amount0, uint256 amount1, uint128 liquidity);
    event Harvested(uint256 fees0, uint256 fees1);
    event Rebalanced(int24 oldTickLower, int24 oldTickUpper, int24 newTickLower, int24 newTickUpper);
    event FeeUpdated(uint24 oldFee, uint24 newFee);
    event EmergencyExit(uint256 amount0, uint256 amount1);
    event RangeConfigUpdated(uint256 rangeWidth, uint256 rebalanceThreshold);
    event MarketConditionsUpdated(uint256 volatility, uint256 volume24h);

    constructor(
        address assetAddress,
        address pairedAssetAddress,
        address _vault,
        address _poolManager,
        address _hook,
        string memory _name,
        PoolKey memory _poolKey
    ) Ownable(msg.sender) {
        require(assetAddress != address(0), "Invalid asset");
        require(pairedAssetAddress != address(0), "Invalid paired asset");
        require(_vault != address(0), "Invalid vault");
        require(_poolManager != address(0), "Invalid pool manager");

        _asset = IERC20(assetAddress);
        _pairedAsset = IERC20(pairedAssetAddress);
        vault = _vault;
        poolManager = _poolManager;
        hook = _hook;
        name = _name;
        poolKey = _poolKey;

        // Initialize with default configurations
        rangeConfig = StablecoinRangeManager.getRecommendedConfig(25, 100000e6); // Medium volatility
        feeConfig = FeeOptimizer.getRecommendedFeeConfig(0); // Major pair
        currentFee = feeConfig.baseFee;
        tickSpacing = _poolKey.tickSpacing;

        lastHarvestTime = block.timestamp;
        lastRebalanceTime = block.timestamp;
        lastFeeUpdateTime = block.timestamp;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    modifier notEmergency() {
        require(!emergencyMode, "Emergency mode active");
        _;
    }

    /**
     * @dev Deposit assets into the strategy
     */
    function deposit(uint256 _amount) external override onlyVault nonReentrant notEmergency {
        require(_amount > 0, "Amount must be positive");

        // Calculate optimal amounts for both tokens
        uint256 amount0Desired = _amount / 2;
        uint256 amount1Desired = _amount / 2;

        // Get current pool state
        (uint160 sqrtPriceX96, int24 currentTick,,) = IPoolManager(poolManager).getSlot0(poolKey);

        // Calculate or update position range
        if (!currentPosition.isActive) {
            (int24 tickLower, int24 tickUpper) = StablecoinRangeManager.calculateOptimalRange(
                currentTick,
                rangeConfig.rangeWidth
            );
            
            currentPosition = StablecoinRangeManager.PositionInfo({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidity: 0,
                lastUpdate: block.timestamp,
                isActive: true
            });
        }

        // Calculate liquidity amounts
        (uint128 liquidity, uint256 amount0, uint256 amount1) = StablecoinRangeManager.calculateLiquidityAmounts(
            currentPosition.tickLower,
            currentPosition.tickUpper,
            amount0Desired,
            amount1Desired,
            currentTick
        );

        // Add liquidity to pool
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: currentPosition.tickLower,
            tickUpper: currentPosition.tickUpper,
            liquidityDelta: int256(uint256(liquidity)),
            salt: bytes32(0)
        });

        // Execute liquidity addition through pool manager
        IPoolManager(poolManager).modifyLiquidity(poolKey, params, "");

        // Update position state
        currentPosition.liquidity += liquidity;
        currentPosition.lastUpdate = block.timestamp;
        totalDeposited += amount0 + amount1;

        emit Deposited(amount0, amount1, liquidity);
    }

    /**
     * @dev Withdraw assets from the strategy
     */
    function withdraw(uint256 _amount) external override onlyVault nonReentrant {
        require(_amount > 0, "Amount must be positive");
        require(_amount <= totalDeposited, "Insufficient balance");

        // Calculate liquidity to remove
        uint128 liquidityToRemove = uint128((_amount * currentPosition.liquidity) / totalDeposited);

        // Remove liquidity from pool
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: currentPosition.tickLower,
            tickUpper: currentPosition.tickUpper,
            liquidityDelta: -int256(uint256(liquidityToRemove)),
            salt: bytes32(0)
        });

        (BalanceDelta memory delta,) = IPoolManager(poolManager).modifyLiquidity(poolKey, params, "");

        // Update position state
        currentPosition.liquidity -= liquidityToRemove;
        totalDeposited -= _amount;

        // Transfer tokens back to vault
        uint256 amount0 = uint256(uint128(-delta.amount0));
        uint256 amount1 = uint256(uint128(-delta.amount1));
        
        if (amount0 > 0) _asset.safeTransfer(vault, amount0);
        if (amount1 > 0) _pairedAsset.safeTransfer(vault, amount1);

        emit Withdrawn(amount0, amount1, liquidityToRemove);
    }

    /**
     * @dev Withdraw all assets from the strategy
     */
    function withdrawAll() external override onlyVault nonReentrant {
        if (currentPosition.liquidity > 0) {
            // Remove all liquidity
            IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
                tickLower: currentPosition.tickLower,
                tickUpper: currentPosition.tickUpper,
                liquidityDelta: -int256(uint256(currentPosition.liquidity)),
                salt: bytes32(0)
            });

            (BalanceDelta memory delta,) = IPoolManager(poolManager).modifyLiquidity(poolKey, params, "");

            // Transfer all tokens back to vault
            uint256 amount0 = uint256(uint128(-delta.amount0));
            uint256 amount1 = uint256(uint128(-delta.amount1));
            
            if (amount0 > 0) _asset.safeTransfer(vault, amount0);
            if (amount1 > 0) _pairedAsset.safeTransfer(vault, amount1);

            emit Withdrawn(amount0, amount1, currentPosition.liquidity);

            // Reset position
            currentPosition.liquidity = 0;
            currentPosition.isActive = false;
            totalDeposited = 0;
        }
    }

    /**
     * @dev Harvest fees and compound
     */
    function harvest() external override onlyVault returns (uint256) {
        // Collect fees from position
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: currentPosition.tickLower,
            tickUpper: currentPosition.tickUpper,
            liquidityDelta: 0, // No liquidity change, just collect fees
            salt: bytes32(0)
        });

        (, BalanceDelta memory feesAccrued) = IPoolManager(poolManager).modifyLiquidity(poolKey, params, "");

        uint256 fees0 = uint256(uint128(feesAccrued.amount0));
        uint256 fees1 = uint256(uint128(feesAccrued.amount1));
        uint256 totalFees = fees0 + fees1;

        if (totalFees > 0) {
            totalFeesClaimed += totalFees;
            lastHarvestTime = block.timestamp;

            // Compound fees by adding them back as liquidity
            if (totalFees >= rangeConfig.minLiquidity) {
                _compoundFees(fees0, fees1);
            }

            emit Harvested(fees0, fees1);
        }

        // Check if rebalancing is needed
        _checkAndRebalance();

        // Check if fee update is needed
        _checkAndUpdateFees();

        return totalFees;
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
    function getAPY() external view override returns (uint256) {
        if (totalDeposited == 0) return 0;
        
        return FeeOptimizer.estimateAPY(
            marketConditions,
            currentFee,
            5000 // Assume 50% liquidity share for estimation
        );
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

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @dev Compound fees by adding them back as liquidity
     */
    function _compoundFees(uint256 fees0, uint256 fees1) internal {
        if (fees0 + fees1 < rangeConfig.minLiquidity) return;

        // Get current tick
        (, int24 currentTick,,) = IPoolManager(poolManager).getSlot0(poolKey);

        // Calculate liquidity to add
        (uint128 liquidity, uint256 amount0, uint256 amount1) = StablecoinRangeManager.calculateLiquidityAmounts(
            currentPosition.tickLower,
            currentPosition.tickUpper,
            fees0,
            fees1,
            currentTick
        );

        if (liquidity > 0) {
            // Add liquidity
            IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
                tickLower: currentPosition.tickLower,
                tickUpper: currentPosition.tickUpper,
                liquidityDelta: int256(uint256(liquidity)),
                salt: bytes32(0)
            });

            IPoolManager(poolManager).modifyLiquidity(poolKey, params, "");

            currentPosition.liquidity += liquidity;
            totalDeposited += amount0 + amount1;
        }
    }

    /**
     * @dev Check if rebalancing is needed and execute if necessary
     */
    function _checkAndRebalance() internal {
        if (!rangeConfig.autoRebalance) return;

        (, int24 currentTick,,) = IPoolManager(poolManager).getSlot0(poolKey);

        if (StablecoinRangeManager.needsRebalancing(currentTick, currentPosition, rangeConfig)) {
            _executeRebalance(currentTick);
        }
    }

    /**
     * @dev Execute rebalancing
     */
    function _executeRebalance(int24 currentTick) internal {
        // Store old range
        int24 oldTickLower = currentPosition.tickLower;
        int24 oldTickUpper = currentPosition.tickUpper;

        // Remove all liquidity from current position
        if (currentPosition.liquidity > 0) {
            IPoolManager.ModifyLiquidityParams memory removeParams = IPoolManager.ModifyLiquidityParams({
                tickLower: currentPosition.tickLower,
                tickUpper: currentPosition.tickUpper,
                liquidityDelta: -int256(uint256(currentPosition.liquidity)),
                salt: bytes32(0)
            });

            (BalanceDelta memory delta,) = IPoolManager(poolManager).modifyLiquidity(poolKey, removeParams, "");

            // Calculate new range
            (int24 newTickLower, int24 newTickUpper) = StablecoinRangeManager.calculateRebalanceRange(
                currentTick,
                rangeConfig
            );

            // Add liquidity to new range
            uint256 amount0 = uint256(uint128(-delta.amount0));
            uint256 amount1 = uint256(uint128(-delta.amount1));

            (uint128 newLiquidity,,) = StablecoinRangeManager.calculateLiquidityAmounts(
                newTickLower,
                newTickUpper,
                amount0,
                amount1,
                currentTick
            );

            IPoolManager.ModifyLiquidityParams memory addParams = IPoolManager.ModifyLiquidityParams({
                tickLower: newTickLower,
                tickUpper: newTickUpper,
                liquidityDelta: int256(uint256(newLiquidity)),
                salt: bytes32(0)
            });

            IPoolManager(poolManager).modifyLiquidity(poolKey, addParams, "");

            // Update position
            currentPosition.tickLower = newTickLower;
            currentPosition.tickUpper = newTickUpper;
            currentPosition.liquidity = newLiquidity;
            currentPosition.lastUpdate = block.timestamp;

            lastRebalanceTime = block.timestamp;
            rebalanceCount++;

            emit Rebalanced(oldTickLower, oldTickUpper, newTickLower, newTickUpper);
        }
    }

    /**
     * @dev Check if fee update is needed and execute if necessary
     */
    function _checkAndUpdateFees() internal {
        if (!feeConfig.dynamicEnabled) return;

        if (FeeOptimizer.needsFeeUpdate(
            lastFeeUpdateTime,
            feeConfig.updateFrequency,
            marketConditions,
            currentFee,
            feeConfig
        )) {
            uint24 newFee = FeeOptimizer.calculateOptimalFee(marketConditions, feeConfig);

            if (newFee != currentFee) {
                uint24 oldFee = currentFee;
                currentFee = newFee;
                lastFeeUpdateTime = block.timestamp;

                emit FeeUpdated(oldFee, newFee);
            }
        }
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @dev Update range configuration
     */
    function updateRangeConfig(
        uint256 _rangeWidth,
        uint256 _rebalanceThreshold,
        uint256 _minLiquidity,
        bool _autoRebalance
    ) external onlyOwner {
        rangeConfig.rangeWidth = _rangeWidth;
        rangeConfig.rebalanceThreshold = _rebalanceThreshold;
        rangeConfig.minLiquidity = _minLiquidity;
        rangeConfig.autoRebalance = _autoRebalance;

        emit RangeConfigUpdated(_rangeWidth, _rebalanceThreshold);
    }

    /**
     * @dev Update market conditions (typically called by oracle or keeper)
     */
    function updateMarketConditions(
        uint256 _volatility,
        uint256 _volume24h,
        uint256 _spread,
        uint256 _liquidity
    ) external onlyOwner {
        marketConditions.volatility = _volatility;
        marketConditions.volume24h = _volume24h;
        marketConditions.spread = _spread;
        marketConditions.liquidity = _liquidity;
        marketConditions.timestamp = block.timestamp;

        emit MarketConditionsUpdated(_volatility, _volume24h);
    }

    /**
     * @dev Manual rebalance trigger
     */
    function manualRebalance() external onlyOwner {
        (, int24 currentTick,,) = IPoolManager(poolManager).getSlot0(poolKey);
        _executeRebalance(currentTick);
    }

    /**
     * @dev Emergency exit - withdraw all liquidity
     */
    function emergencyExit() external onlyOwner {
        emergencyMode = true;

        if (currentPosition.liquidity > 0) {
            IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
                tickLower: currentPosition.tickLower,
                tickUpper: currentPosition.tickUpper,
                liquidityDelta: -int256(uint256(currentPosition.liquidity)),
                salt: bytes32(0)
            });

            (BalanceDelta memory delta,) = IPoolManager(poolManager).modifyLiquidity(poolKey, params, "");

            uint256 amount0 = uint256(uint128(-delta.amount0));
            uint256 amount1 = uint256(uint128(-delta.amount1));

            emit EmergencyExit(amount0, amount1);

            currentPosition.liquidity = 0;
            currentPosition.isActive = false;
            totalDeposited = 0;
        }
    }

    /**
     * @dev Resume normal operations after emergency
     */
    function resumeOperations() external onlyOwner {
        emergencyMode = false;
    }

    /**
     * @dev Set maximum slippage tolerance
     */
    function setMaxSlippage(uint256 _maxSlippage) external onlyOwner {
        require(_maxSlippage <= 1000, "Slippage too high"); // Max 10%
        maxSlippage = _maxSlippage;
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Get current position information
     */
    function getCurrentPosition() external view returns (
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 lastUpdate,
        bool isActive
    ) {
        return (
            currentPosition.tickLower,
            currentPosition.tickUpper,
            currentPosition.liquidity,
            currentPosition.lastUpdate,
            currentPosition.isActive
        );
    }

    /**
     * @dev Get strategy statistics
     */
    function getStrategyStats() external view returns (
        uint256 _totalDeposited,
        uint256 _totalFeesClaimed,
        uint256 _rebalanceCount,
        uint256 _lastHarvestTime,
        uint256 _lastRebalanceTime,
        bool _emergencyMode
    ) {
        return (
            totalDeposited,
            totalFeesClaimed,
            rebalanceCount,
            lastHarvestTime,
            lastRebalanceTime,
            emergencyMode
        );
    }

    /**
     * @dev Calculate current impermanent loss
     */
    function getCurrentImpermanentLoss() external view returns (uint256) {
        (uint160 sqrtPriceX96,,,) = IPoolManager(poolManager).getSlot0(poolKey);

        // Convert to price ratio (simplified)
        uint256 currentRatio = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / (2**192);
        uint256 initialRatio = 1e18; // Assume 1:1 initial ratio for stablecoins

        return FeeOptimizer.calculateImpermanentLoss(currentRatio, initialRatio);
    }

    /**
     * @dev Get estimated next rebalance time
     */
    function getNextRebalanceTime() external view returns (uint256) {
        if (!rangeConfig.autoRebalance) return 0;

        (, int24 currentTick,,) = IPoolManager(poolManager).getSlot0(poolKey);

        if (StablecoinRangeManager.needsRebalancing(currentTick, currentPosition, rangeConfig)) {
            return block.timestamp; // Needs rebalancing now
        }

        // Estimate based on current price movement (simplified)
        return lastRebalanceTime + 24 hours; // Default to daily check
    }
}
