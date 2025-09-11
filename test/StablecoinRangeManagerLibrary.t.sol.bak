// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/libraries/StablecoinRangeManager.sol";

/**
 * @title StablecoinRangeManagerLibraryTest
 * @dev Comprehensive test cases for StablecoinRangeManager library functions
 * Tests all library functions in isolation with various edge cases and scenarios
 */
contract StablecoinRangeManagerLibraryTest is Test {
    using StablecoinRangeManager for *;

    // Test constants
    int24 constant CURRENT_TICK = 0; // Assuming 1:1 price for stablecoins
    int24 constant MAX_TICK = 887272;
    int24 constant MIN_TICK = -887272;
    int24 constant TICK_SPACING = 10;

    // ============ CALCULATE OPTIMAL RANGE TESTS ============

    function test_CalculateOptimalRange_NormalConditions() public {
        uint256 rangeWidth = 50; // 0.5%
        
        (int24 tickLower, int24 tickUpper) = StablecoinRangeManager.calculateOptimalRange(CURRENT_TICK, rangeWidth);
        
        assertTrue(tickLower < tickUpper, "Lower tick should be less than upper tick");
        assertTrue(tickLower < CURRENT_TICK, "Lower tick should be below current tick");
        assertTrue(tickUpper > CURRENT_TICK, "Upper tick should be above current tick");
        
        // Check tick spacing alignment
        assertEq(tickLower % TICK_SPACING, 0, "Lower tick should be aligned to tick spacing");
        assertEq(tickUpper % TICK_SPACING, 0, "Upper tick should be aligned to tick spacing");
    }

    function test_CalculateOptimalRange_TightRange() public {
        uint256 rangeWidth = 10; // 0.1% - very tight
        
        (int24 tickLower, int24 tickUpper) = StablecoinRangeManager.calculateOptimalRange(CURRENT_TICK, rangeWidth);
        
        assertTrue(tickUpper - tickLower > 0, "Range should be positive");
        assertTrue(tickUpper - tickLower < 2000, "Tight range should be small"); // Reasonable upper bound
    }

    function test_CalculateOptimalRange_WideRange() public {
        uint256 rangeWidth = 200; // 2% - wide range
        
        (int24 tickLower, int24 tickUpper) = StablecoinRangeManager.calculateOptimalRange(CURRENT_TICK, rangeWidth);
        
        assertTrue(tickUpper - tickLower > 10000, "Wide range should be large");
        assertTrue(tickLower > MIN_TICK, "Should not exceed minimum tick");
        assertTrue(tickUpper < MAX_TICK, "Should not exceed maximum tick");
    }

    function test_CalculateOptimalRange_ExtremeCurrentTick() public {
        // Test near maximum tick
        int24 extremeTick = MAX_TICK - 10000;
        uint256 rangeWidth = 100;
        
        (int24 tickLower, int24 tickUpper) = StablecoinRangeManager.calculateOptimalRange(extremeTick, rangeWidth);
        
        assertTrue(tickLower <= extremeTick, "Lower tick should not exceed current tick");
        assertTrue(tickUpper <= MAX_TICK, "Upper tick should not exceed maximum");
        
        // Test near minimum tick
        extremeTick = MIN_TICK + 10000;
        (tickLower, tickUpper) = StablecoinRangeManager.calculateOptimalRange(extremeTick, rangeWidth);
        
        assertTrue(tickLower >= MIN_TICK, "Lower tick should not go below minimum");
        assertTrue(tickUpper >= extremeTick, "Upper tick should not be below current tick");
    }

    function test_CalculateOptimalRange_ZeroRangeWidth() public {
        uint256 rangeWidth = 0;
        
        (int24 tickLower, int24 tickUpper) = StablecoinRangeManager.calculateOptimalRange(CURRENT_TICK, rangeWidth);
        
        // Should still create a minimal range
        assertTrue(tickUpper > tickLower, "Should create minimal range even with zero width");
    }

    // ============ NEEDS REBALANCING TESTS ============

    function test_NeedsRebalancing_WithinRange() public {
        StablecoinRangeManager.PositionInfo memory position = StablecoinRangeManager.PositionInfo({
            tickLower: -500,
            tickUpper: 500,
            liquidity: 1000,
            lastUpdate: block.timestamp,
            isActive: true
        });

        StablecoinRangeManager.RangeConfig memory config = StablecoinRangeManager.RangeConfig({
            rangeWidth: 50,
            rebalanceThreshold: 25,
            minLiquidity: 100e6,
            autoRebalance: true
        });

        int24 currentTick = 0; // Within range
        
        bool needsRebalancing = StablecoinRangeManager.needsRebalancing(currentTick, position, config);
        assertFalse(needsRebalancing, "Should not need rebalancing when within range");
    }

    function test_NeedsRebalancing_OutsideRange() public {
        StablecoinRangeManager.PositionInfo memory position = StablecoinRangeManager.PositionInfo({
            tickLower: -200,
            tickUpper: 200,
            liquidity: 1000,
            lastUpdate: block.timestamp,
            isActive: true
        });

        StablecoinRangeManager.RangeConfig memory config = StablecoinRangeManager.RangeConfig({
            rangeWidth: 50,
            rebalanceThreshold: 25,
            minLiquidity: 100e6,
            autoRebalance: true
        });

        int24 currentTick = 300; // Outside range
        
        bool needsRebalancing = StablecoinRangeManager.needsRebalancing(currentTick, position, config);
        assertTrue(needsRebalancing, "Should need rebalancing when outside range");
    }

    function test_NeedsRebalancing_NearThreshold() public {
        StablecoinRangeManager.PositionInfo memory position = StablecoinRangeManager.PositionInfo({
            tickLower: -1000,
            tickUpper: 1000,
            liquidity: 1000,
            lastUpdate: block.timestamp,
            isActive: true
        });

        StablecoinRangeManager.RangeConfig memory config = StablecoinRangeManager.RangeConfig({
            rangeWidth: 100,
            rebalanceThreshold: 25, // 25% of range width
            minLiquidity: 100e6,
            autoRebalance: true
        });

        // Test at threshold boundary
        int24 thresholdTick = 750; // 75% of range width from center
        
        bool needsRebalancing = StablecoinRangeManager.needsRebalancing(thresholdTick, position, config);
        assertTrue(needsRebalancing, "Should need rebalancing at threshold");
    }

    function test_NeedsRebalancing_AutoRebalanceDisabled() public {
        StablecoinRangeManager.PositionInfo memory position = StablecoinRangeManager.PositionInfo({
            tickLower: -200,
            tickUpper: 200,
            liquidity: 1000,
            lastUpdate: block.timestamp,
            isActive: true
        });

        StablecoinRangeManager.RangeConfig memory config = StablecoinRangeManager.RangeConfig({
            rangeWidth: 50,
            rebalanceThreshold: 25,
            minLiquidity: 100e6,
            autoRebalance: false // Disabled
        });

        int24 currentTick = 300; // Outside range
        
        bool needsRebalancing = StablecoinRangeManager.needsRebalancing(currentTick, position, config);
        assertFalse(needsRebalancing, "Should not need rebalancing when auto-rebalance disabled");
    }

    function test_NeedsRebalancing_InactivePosition() public {
        StablecoinRangeManager.PositionInfo memory position = StablecoinRangeManager.PositionInfo({
            tickLower: -200,
            tickUpper: 200,
            liquidity: 1000,
            lastUpdate: block.timestamp,
            isActive: false // Inactive
        });

        StablecoinRangeManager.RangeConfig memory config = StablecoinRangeManager.RangeConfig({
            rangeWidth: 50,
            rebalanceThreshold: 25,
            minLiquidity: 100e6,
            autoRebalance: true
        });

        int24 currentTick = 300; // Outside range
        
        bool needsRebalancing = StablecoinRangeManager.needsRebalancing(currentTick, position, config);
        assertFalse(needsRebalancing, "Should not need rebalancing for inactive position");
    }

    // ============ CALCULATE LIQUIDITY AMOUNTS TESTS ============

    function test_CalculateLiquidityAmounts_BalancedAmounts() public {
        int24 tickLower = -500;
        int24 tickUpper = 500;
        uint256 amount0Desired = 1000e6; // 1000 USDC
        uint256 amount1Desired = 1000e6; // 1000 USDT
        int24 currentTick = 0; // Balanced position

        (uint128 liquidity, uint256 amount0, uint256 amount1) = StablecoinRangeManager.calculateLiquidityAmounts(
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            currentTick
        );

        assertTrue(liquidity > 0, "Should calculate positive liquidity");
        assertTrue(amount0 <= amount0Desired, "Amount0 should not exceed desired");
        assertTrue(amount1 <= amount1Desired, "Amount1 should not exceed desired");
        assertTrue(amount0 > 0 || amount1 > 0, "At least one amount should be positive");
    }

    function test_CalculateLiquidityAmounts_UnbalancedAmounts() public {
        int24 tickLower = -500;
        int24 tickUpper = 500;
        uint256 amount0Desired = 2000e6; // More USDC
        uint256 amount1Desired = 500e6;  // Less USDT
        int24 currentTick = 0;

        (uint128 liquidity, uint256 amount0, uint256 amount1) = StablecoinRangeManager.calculateLiquidityAmounts(
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            currentTick
        );

        assertTrue(liquidity > 0, "Should calculate positive liquidity");
        // The function should optimize for the limiting factor
        assertTrue(amount0 <= amount0Desired, "Amount0 should not exceed desired");
        assertTrue(amount1 <= amount1Desired, "Amount1 should not exceed desired");
    }

    function test_CalculateLiquidityAmounts_EdgeCaseTicks() public {
        // Test with very wide range
        int24 tickLower = -50000;
        int24 tickUpper = 50000;
        uint256 amount0Desired = 1000e6;
        uint256 amount1Desired = 1000e6;
        int24 currentTick = 0;

        (uint128 liquidity, uint256 amount0, uint256 amount1) = StablecoinRangeManager.calculateLiquidityAmounts(
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            currentTick
        );

        assertTrue(liquidity > 0, "Should handle wide ranges");

        // Test with very narrow range
        tickLower = -10;
        tickUpper = 10;

        (liquidity, amount0, amount1) = StablecoinRangeManager.calculateLiquidityAmounts(
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            currentTick
        );

        assertTrue(liquidity > 0, "Should handle narrow ranges");
    }

    // ============ GET RECOMMENDED CONFIG TESTS ============

    function test_GetRecommendedConfig_LowVolatility() public {
        uint256 volatility = 5; // Very low volatility
        uint256 volume24h = 1000000e6; // Normal volume

        StablecoinRangeManager.RangeConfig memory config = StablecoinRangeManager.getRecommendedConfig(volatility, volume24h);

        assertTrue(config.rangeWidth <= 50, "Should recommend tight range for low volatility");
        assertTrue(config.autoRebalance, "Should enable auto-rebalance for stable conditions");
        assertTrue(config.minLiquidity > 0, "Should set minimum liquidity");
    }

    function test_GetRecommendedConfig_HighVolatility() public {
        uint256 volatility = 100; // High volatility
        uint256 volume24h = 500000e6; // Lower volume during volatility

        StablecoinRangeManager.RangeConfig memory config = StablecoinRangeManager.getRecommendedConfig(volatility, volume24h);

        assertTrue(config.rangeWidth >= 50, "Should recommend wider range for high volatility");
        assertFalse(config.autoRebalance, "Should disable auto-rebalance for volatile conditions");
        assertTrue(config.rebalanceThreshold >= 25, "Should have higher rebalance threshold");
    }

    function test_GetRecommendedConfig_HighVolume() public {
        uint256 volatility = 25; // Normal volatility
        uint256 volume24h = 20000000e6; // Very high volume

        StablecoinRangeManager.RangeConfig memory config = StablecoinRangeManager.getRecommendedConfig(volatility, volume24h);

        // High volume should optimize for fee collection
        assertTrue(config.rangeWidth <= 100, "Should optimize range for fee collection");
        assertTrue(config.autoRebalance, "Should enable auto-rebalance for high volume");
    }

    function test_GetRecommendedConfig_ExtremeConditions() public {
        // Test extreme low volatility
        uint256 volatility = 0;
        uint256 volume24h = 1000000e6;

        StablecoinRangeManager.RangeConfig memory config = StablecoinRangeManager.getRecommendedConfig(volatility, volume24h);
        assertTrue(config.rangeWidth > 0, "Should handle zero volatility");

        // Test extreme high volatility
        volatility = 1000; // 10%
        config = StablecoinRangeManager.getRecommendedConfig(volatility, volume24h);
        assertTrue(config.rangeWidth > 50, "Should recommend wide range for extreme volatility");

        // Test zero volume
        volatility = 25;
        volume24h = 0;
        config = StablecoinRangeManager.getRecommendedConfig(volatility, volume24h);
        assertTrue(config.minLiquidity > 0, "Should handle zero volume");
    }

    // ============ FUZZ TESTS ============

    function testFuzz_CalculateOptimalRange(uint256 rangeWidth, int24 currentTick) public {
        // Bound inputs to reasonable ranges
        rangeWidth = bound(rangeWidth, 1, 1000); // 0.01% to 10%
        currentTick = int24(bound(int256(currentTick), int256(MIN_TICK + 50000), int256(MAX_TICK - 50000)));

        (int24 tickLower, int24 tickUpper) = StablecoinRangeManager.calculateOptimalRange(currentTick, rangeWidth);

        // Invariants
        assertTrue(tickLower < tickUpper, "Lower tick must be less than upper tick");
        assertTrue(tickLower >= MIN_TICK, "Lower tick must be within bounds");
        assertTrue(tickUpper <= MAX_TICK, "Upper tick must be within bounds");
        assertEq(tickLower % TICK_SPACING, 0, "Lower tick must be aligned");
        assertEq(tickUpper % TICK_SPACING, 0, "Upper tick must be aligned");
    }

    function testFuzz_NeedsRebalancing(int24 currentTick, int24 tickLower, int24 tickUpper, uint256 threshold) public {
        // Bound inputs
        threshold = bound(threshold, 1, 100);
        tickLower = int24(bound(int256(tickLower), int256(MIN_TICK), int256(MAX_TICK - 1000)));
        tickUpper = int24(bound(int256(tickUpper), int256(tickLower + 100), int256(MAX_TICK)));
        currentTick = int24(bound(int256(currentTick), int256(MIN_TICK), int256(MAX_TICK)));

        StablecoinRangeManager.PositionInfo memory position = StablecoinRangeManager.PositionInfo({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: 1000,
            lastUpdate: block.timestamp,
            isActive: true
        });

        StablecoinRangeManager.RangeConfig memory config = StablecoinRangeManager.RangeConfig({
            rangeWidth: 50,
            rebalanceThreshold: threshold,
            minLiquidity: 100e6,
            autoRebalance: true
        });

        bool needsRebalancing = StablecoinRangeManager.needsRebalancing(currentTick, position, config);

        // If current tick is outside the range, should need rebalancing
        if (currentTick < tickLower || currentTick > tickUpper) {
            assertTrue(needsRebalancing, "Should need rebalancing when outside range");
        }
    }
}
