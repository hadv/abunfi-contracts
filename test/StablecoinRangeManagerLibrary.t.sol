// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/libraries/StablecoinRangeManager.sol";

contract StablecoinRangeManagerLibraryTest is Test {
    StablecoinRangeManager.RangeConfig public config;
    
    uint256 public constant TARGET_PRICE = 1000000; // 1.0 in 6 decimals
    uint256 public constant DEFAULT_RANGE_WIDTH = 200; // 2%
    uint256 public constant MAX_RANGE_WIDTH = 1000; // 10%
    uint256 public constant MIN_RANGE_WIDTH = 50; // 0.5%
    uint256 public constant REBALANCE_THRESHOLD = 500; // 5%
    uint256 public constant MIN_LIQUIDITY = 1000e6; // $1000

    event RangeUpdated(int24 lowerTick, int24 upperTick, uint256 price);
    event RangeOptimized(uint256 oldWidth, uint256 newWidth);

    function setUp() public {
        config = StablecoinRangeManager.RangeConfig({
            rangeWidth: DEFAULT_RANGE_WIDTH,
            rebalanceThreshold: REBALANCE_THRESHOLD,
            minLiquidity: MIN_LIQUIDITY,
            autoRebalance: true
        });
    }

    // ============ Range Calculation Tests ============

    function test_CalculateOptimalRange_AtTarget() public {
        int24 currentTick = 0; // At target price
        (int24 lowerTick, int24 upperTick) = StablecoinRangeManager.calculateOptimalRange(currentTick, DEFAULT_RANGE_WIDTH);

        assertLt(lowerTick, 0, "Lower tick should be negative");
        assertGt(upperTick, 0, "Upper tick should be positive");
        assertEq(upperTick, -lowerTick, "Range should be symmetric around target");
    }

    function test_CalculateOptimalRange_AboveTarget() public {
        int24 currentTick = 100; // Above target price

        (int24 lowerTick, int24 upperTick) = StablecoinRangeManager.calculateOptimalRange(currentTick, DEFAULT_RANGE_WIDTH);

        assertLt(lowerTick, currentTick, "Lower tick should be below current");
        assertGt(upperTick, currentTick, "Upper tick should be above current");

        // Range should be centered around current tick
        assertApproxEqAbs(upperTick - currentTick, currentTick - lowerTick, 60, "Range should be symmetric");
    }

    function test_CalculateOptimalRange_BelowTarget() public {
        int24 currentTick = -100; // Below target price

        (int24 lowerTick, int24 upperTick) = StablecoinRangeManager.calculateOptimalRange(currentTick, DEFAULT_RANGE_WIDTH);

        assertLt(lowerTick, currentTick, "Lower tick should be below current");
        assertGt(upperTick, currentTick, "Upper tick should be above current");

        // Range should be centered around current tick
        assertApproxEqAbs(upperTick - currentTick, currentTick - lowerTick, 60, "Range should be symmetric");
    }

    function test_CalculateOptimalRange_WideRange() public {
        int24 currentTick = 0;
        uint256 wideRangeWidth = 1000; // 10%

        (int24 lowerTick, int24 upperTick) = StablecoinRangeManager.calculateOptimalRange(currentTick, wideRangeWidth);

        // Should return valid ticks with wider range
        assertLt(lowerTick, upperTick, "Lower tick should be less than upper tick");
        assertGt(upperTick - lowerTick, 200, "Wide range should have significant width");
    }

    // ============ Rebalance Range Tests ============

    function test_CalculateRebalanceRange() public {
        int24 currentTick = 50;

        (int24 newLowerTick, int24 newUpperTick) = StablecoinRangeManager.calculateRebalanceRange(currentTick, config);

        assertLt(newLowerTick, currentTick, "New lower tick should be below current");
        assertGt(newUpperTick, currentTick, "New upper tick should be above current");
        assertLt(newLowerTick, newUpperTick, "Lower tick should be less than upper tick");
    }

    // ============ Recommended Config Tests ============

    function test_GetRecommendedConfig_LowVolatility() public {
        uint256 lowVolatility = 5; // 0.05%
        uint256 highVolume = 10000000e6; // $10M

        StablecoinRangeManager.RangeConfig memory recommendedConfig = StablecoinRangeManager.getRecommendedConfig(lowVolatility, highVolume);

        assertLt(recommendedConfig.rangeWidth, 100, "Low volatility should recommend tight range");
        assertTrue(recommendedConfig.autoRebalance, "Auto rebalance should be enabled");
    }

    function test_GetRecommendedConfig_HighVolatility() public {
        uint256 highVolatility = 100; // 1%
        uint256 lowVolume = 100000e6; // $100k

        StablecoinRangeManager.RangeConfig memory recommendedConfig = StablecoinRangeManager.getRecommendedConfig(highVolatility, lowVolume);

        assertGt(recommendedConfig.rangeWidth, 50, "High volatility should recommend wider range");
        assertTrue(recommendedConfig.autoRebalance, "Auto rebalance should be enabled");
    }

    // ============ Liquidity Calculation Tests ============

    function test_CalculateLiquidityAmounts() public {
        int24 tickLower = -100;
        int24 tickUpper = 100;
        uint256 amount0Desired = 1000e6; // 1000 USDC
        uint256 amount1Desired = 1000e6; // 1000 USDT
        int24 currentTick = 0;

        (uint128 liquidity, uint256 amount0, uint256 amount1) = StablecoinRangeManager.calculateLiquidityAmounts(
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            currentTick
        );

        assertGt(liquidity, 0, "Liquidity should be positive");
        assertLe(amount0, amount0Desired, "Amount0 should not exceed desired");
        assertLe(amount1, amount1Desired, "Amount1 should not exceed desired");
    }

    // ============ Tick Conversion Tests ============

    function test_TickToPrice_ZeroTick() public {
        uint160 price = StablecoinRangeManager.tickToPrice(0);

        assertGt(price, 0, "Tick 0 should convert to positive price");
    }

    function test_TickToPrice_PositiveTick() public {
        int24 positiveTick = 100;
        uint160 price = StablecoinRangeManager.tickToPrice(positiveTick);

        assertGt(price, 0, "Positive tick should convert to positive price");
    }

    function test_TickToPrice_NegativeTick() public {
        int24 negativeTick = -100;
        uint160 price = StablecoinRangeManager.tickToPrice(negativeTick);

        assertGt(price, 0, "Negative tick should convert to positive price");
    }

    function test_PriceToTick_HighPrice() public {
        uint160 highPrice = 2**96; // High price
        int24 tick = StablecoinRangeManager.priceToTick(highPrice);

        assertGt(tick, 0, "High price should convert to positive tick");
    }

    function test_PriceToTick_LowPrice() public {
        uint160 lowPrice = 2**64; // Low price
        int24 tick = StablecoinRangeManager.priceToTick(lowPrice);

        assertLt(tick, 0, "Low price should convert to negative tick");
    }

    // ============ Edge Cases ============

    function test_EdgeCase_MaximumTick() public {
        int24 maxTick = 887272; // Maximum valid tick in Uniswap V3

        uint160 price = StablecoinRangeManager.tickToPrice(maxTick);
        assertGt(price, 0, "Maximum tick should convert to positive price");
    }

    function test_EdgeCase_MinimumTick() public {
        int24 minTick = -887272; // Minimum valid tick in Uniswap V3

        uint160 price = StablecoinRangeManager.tickToPrice(minTick);
        assertGt(price, 0, "Minimum tick should convert to positive price");
    }

    // ============ Gas Optimization Tests ============

    function test_GasOptimization_CalculateRange() public {
        uint256 gasStart = gasleft();

        StablecoinRangeManager.calculateOptimalRange(0, DEFAULT_RANGE_WIDTH);

        uint256 gasUsed = gasStart - gasleft();
        assertLt(gasUsed, 50000, "Range calculation should be gas efficient");
    }

    function test_GasOptimization_RebalanceRange() public {
        uint256 gasStart = gasleft();

        StablecoinRangeManager.calculateRebalanceRange(0, config);

        uint256 gasUsed = gasStart - gasleft();
        assertLt(gasUsed, 50000, "Rebalance calculation should be gas efficient");
    }
}
