// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title StablecoinRangeManager
 * @dev Library for managing concentrated liquidity ranges for stablecoin pairs
 */
library StablecoinRangeManager {
    using Math for uint256;

    // Constants for stablecoin optimization
    uint256 private constant PRICE_PRECISION = 1e18;
    int24 private constant TICK_SPACING = 10; // Typical for stablecoin pools
    int24 private constant MAX_TICK = 887272;
    int24 private constant MIN_TICK = -887272;

    // Default range parameters for stablecoins
    uint256 private constant DEFAULT_RANGE_WIDTH = 50; // 0.5% range width
    uint256 private constant TIGHT_RANGE_WIDTH = 20; // 0.2% for very stable pairs
    uint256 private constant WIDE_RANGE_WIDTH = 100; // 1.0% for volatile periods

    struct RangeConfig {
        uint256 rangeWidth; // Range width in basis points
        uint256 rebalanceThreshold; // Threshold to trigger rebalancing
        uint256 minLiquidity; // Minimum liquidity to maintain
        bool autoRebalance; // Enable automatic rebalancing
    }

    struct PositionInfo {
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 lastUpdate;
        bool isActive;
    }

    /**
     * @dev Calculate optimal tick range for stablecoin pair
     * @param currentTick Current pool tick
     * @param rangeWidth Range width in basis points
     * @return tickLower Lower tick boundary
     * @return tickUpper Upper tick boundary
     */
    function calculateOptimalRange(int24 currentTick, uint256 rangeWidth)
        internal
        pure
        returns (int24 tickLower, int24 tickUpper)
    {
        // Calculate tick range based on price range
        int24 tickRange = int24(uint24(rangeWidth * 100)); // Convert basis points to ticks

        tickLower = currentTick - tickRange;
        tickUpper = currentTick + tickRange;

        // Ensure ticks are within bounds and properly spaced
        tickLower = _alignTick(tickLower, TICK_SPACING);
        tickUpper = _alignTick(tickUpper, TICK_SPACING);

        // Ensure ticks are within valid range
        if (tickLower < MIN_TICK) tickLower = MIN_TICK;
        if (tickUpper > MAX_TICK) tickUpper = MAX_TICK;

        require(tickLower < tickUpper, "Invalid tick range");
    }

    /**
     * @dev Check if position needs rebalancing
     * @param currentTick Current pool tick
     * @param position Position information
     * @param config Range configuration
     * @return needsRebalance Whether rebalancing is needed
     */
    function needsRebalancing(int24 currentTick, PositionInfo memory position, RangeConfig memory config)
        internal
        pure
        returns (bool needsRebalance)
    {
        if (!position.isActive || !config.autoRebalance) {
            return false;
        }

        // Calculate distance from range center
        int24 rangeCenter = (position.tickLower + position.tickUpper) / 2;
        int24 tickDistance = currentTick > rangeCenter ? currentTick - rangeCenter : rangeCenter - currentTick;

        // Calculate rebalance threshold in ticks
        int24 rebalanceThresholdTicks = int24(uint24(config.rebalanceThreshold * 100));

        return tickDistance > rebalanceThresholdTicks;
    }

    /**
     * @dev Calculate new range for rebalancing
     * @param currentTick Current pool tick
     * @param config Range configuration
     * @return newTickLower New lower tick
     * @return newTickUpper New upper tick
     */
    function calculateRebalanceRange(int24 currentTick, RangeConfig memory config)
        internal
        pure
        returns (int24 newTickLower, int24 newTickUpper)
    {
        return calculateOptimalRange(currentTick, config.rangeWidth);
    }

    /**
     * @dev Calculate liquidity amounts for given range
     * @param tickLower Lower tick
     * @param tickUpper Upper tick
     * @param amount0Desired Desired amount of token0
     * @param amount1Desired Desired amount of token1
     * @param currentTick Current pool tick
     * @return liquidity Calculated liquidity
     * @return amount0 Actual amount0 needed
     * @return amount1 Actual amount1 needed
     */
    function calculateLiquidityAmounts(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        int24 currentTick
    ) internal pure returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        // Simplified calculation for stablecoins (assuming 1:1 ratio)
        // In production, this would use proper Uniswap V3 math

        if (currentTick < tickLower) {
            // Price below range, only token0 needed
            amount0 = amount0Desired;
            amount1 = 0;
            liquidity = uint128(amount0Desired);
        } else if (currentTick >= tickUpper) {
            // Price above range, only token1 needed
            amount0 = 0;
            amount1 = amount1Desired;
            liquidity = uint128(amount1Desired);
        } else {
            // Price in range, both tokens needed
            uint256 totalDesired = amount0Desired + amount1Desired;
            amount0 = totalDesired / 2;
            amount1 = totalDesired / 2;
            liquidity = uint128(totalDesired);
        }
    }

    /**
     * @dev Get recommended range configuration based on market conditions
     * @param volatility Market volatility indicator (basis points)
     * @param volume24h 24h trading volume
     * @return config Recommended range configuration
     */
    function getRecommendedConfig(uint256 volatility, uint256 volume24h)
        internal
        pure
        returns (RangeConfig memory config)
    {
        if (volatility < 10) {
            // Very stable conditions
            config = RangeConfig({
                rangeWidth: TIGHT_RANGE_WIDTH,
                rebalanceThreshold: 15,
                minLiquidity: 1000e6, // 1000 USDC
                autoRebalance: true
            });
        } else if (volatility < 50) {
            // Normal conditions
            config = RangeConfig({
                rangeWidth: DEFAULT_RANGE_WIDTH,
                rebalanceThreshold: 25,
                minLiquidity: 500e6, // 500 USDC
                autoRebalance: true
            });
        } else {
            // High volatility
            config = RangeConfig({
                rangeWidth: WIDE_RANGE_WIDTH,
                rebalanceThreshold: 50,
                minLiquidity: 100e6, // 100 USDC
                autoRebalance: false // Manual rebalancing in volatile conditions
            });
        }

        // Adjust for high volume (tighter ranges for more fees)
        if (volume24h > 10000000e6) {
            // > 10M USDC volume
            config.rangeWidth = config.rangeWidth * 80 / 100; // 20% tighter
        }
    }

    /**
     * @dev Align tick to tick spacing
     * @param tick Tick to align
     * @param tickSpacing Tick spacing
     * @return alignedTick Aligned tick
     */
    function _alignTick(int24 tick, int24 tickSpacing) private pure returns (int24 alignedTick) {
        if (tick >= 0) {
            alignedTick = (tick / tickSpacing) * tickSpacing;
        } else {
            alignedTick = ((tick - tickSpacing + 1) / tickSpacing) * tickSpacing;
        }
    }

    /**
     * @dev Calculate price from tick
     * @param tick Pool tick
     * @return price Price as Q64.96
     */
    function tickToPrice(int24 tick) internal pure returns (uint160 price) {
        // Simplified price calculation
        // In production, use proper Uniswap V3 math library
        if (tick == 0) {
            price = uint160(PRICE_PRECISION);
        } else {
            // Approximate calculation for demonstration
            price = uint160(PRICE_PRECISION * uint256(int256(1001000 + tick)) / 1000000);
        }
    }

    /**
     * @dev Calculate tick from price
     * @param price Price as Q64.96
     * @return tick Pool tick
     */
    function priceToTick(uint160 price) internal pure returns (int24 tick) {
        // Simplified tick calculation
        // In production, use proper Uniswap V3 math library
        if (price == PRICE_PRECISION) {
            tick = 0;
        } else {
            // Approximate calculation for demonstration
            tick = int24(int256(price * 1000000 / PRICE_PRECISION) - 1001000);
        }
    }
}
