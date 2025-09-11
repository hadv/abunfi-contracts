// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/libraries/StablecoinRangeManager.sol";

contract StablecoinRangeManagerLibraryTest is Test {
    using StablecoinRangeManager for StablecoinRangeManager.RangeConfig;

    StablecoinRangeManager.RangeConfig public config;
    
    uint256 public constant TARGET_PRICE = 1000000; // 1.0 in 6 decimals
    uint256 public constant DEFAULT_RANGE_WIDTH = 200; // 2%
    uint256 public constant MAX_RANGE_WIDTH = 1000; // 10%
    uint256 public constant MIN_RANGE_WIDTH = 50; // 0.5%

    event RangeUpdated(int24 lowerTick, int24 upperTick, uint256 price);
    event RangeOptimized(uint256 oldWidth, uint256 newWidth);

    function setUp() public {
        config = StablecoinRangeManager.RangeConfig({
            targetPrice: TARGET_PRICE,
            rangeWidth: DEFAULT_RANGE_WIDTH,
            maxRangeWidth: MAX_RANGE_WIDTH,
            minRangeWidth: MIN_RANGE_WIDTH,
            tickSpacing: 60,
            lastUpdateTime: block.timestamp,
            volatilityBuffer: 100 // 1%
        });
    }

    // ============ Range Calculation Tests ============

    function test_CalculateOptimalRange_AtTarget() public {
        (int24 lowerTick, int24 upperTick) = config.calculateOptimalRange(TARGET_PRICE);
        
        assertLt(lowerTick, 0, "Lower tick should be negative");
        assertGt(upperTick, 0, "Upper tick should be positive");
        assertEq(upperTick, -lowerTick, "Range should be symmetric around target");
    }

    function test_CalculateOptimalRange_AboveTarget() public {
        uint256 priceAbove = TARGET_PRICE * 1050 / 1000; // 5% above target
        
        (int24 lowerTick, int24 upperTick) = config.calculateOptimalRange(priceAbove);
        
        assertLt(lowerTick, 0, "Lower tick should be negative");
        assertGt(upperTick, 0, "Upper tick should be positive");
        
        // Range should be shifted upward
        assertTrue(upperTick > -lowerTick, "Range should be skewed upward");
    }

    function test_CalculateOptimalRange_BelowTarget() public {
        uint256 priceBelow = TARGET_PRICE * 950 / 1000; // 5% below target
        
        (int24 lowerTick, int24 upperTick) = config.calculateOptimalRange(priceBelow);
        
        assertLt(lowerTick, 0, "Lower tick should be negative");
        assertGt(upperTick, 0, "Upper tick should be positive");
        
        // Range should be shifted downward
        assertTrue(-lowerTick > upperTick, "Range should be skewed downward");
    }

    function test_CalculateOptimalRange_ExtremePrice() public {
        uint256 extremePrice = TARGET_PRICE * 2; // 100% above target
        
        (int24 lowerTick, int24 upperTick) = config.calculateOptimalRange(extremePrice);
        
        // Should still return valid ticks
        assertLt(lowerTick, upperTick, "Lower tick should be less than upper tick");
    }

    // ============ Range Width Optimization Tests ============

    function test_OptimizeRangeWidth_LowVolatility() public {
        // Simulate low volatility scenario
        uint256[] memory recentPrices = new uint256[](5);
        recentPrices[0] = 999000;
        recentPrices[1] = 1000000;
        recentPrices[2] = 1001000;
        recentPrices[3] = 999500;
        recentPrices[4] = 1000500;

        uint256 newWidth = config.optimizeRangeWidth(recentPrices);
        
        assertLt(newWidth, DEFAULT_RANGE_WIDTH, "Range width should decrease in low volatility");
        assertGe(newWidth, MIN_RANGE_WIDTH, "Range width should not go below minimum");
    }

    function test_OptimizeRangeWidth_HighVolatility() public {
        // Simulate high volatility scenario
        uint256[] memory recentPrices = new uint256[](5);
        recentPrices[0] = 950000;
        recentPrices[1] = 1050000;
        recentPrices[2] = 980000;
        recentPrices[3] = 1030000;
        recentPrices[4] = 1000000;

        uint256 newWidth = config.optimizeRangeWidth(recentPrices);
        
        assertGt(newWidth, DEFAULT_RANGE_WIDTH, "Range width should increase in high volatility");
        assertLe(newWidth, MAX_RANGE_WIDTH, "Range width should not exceed maximum");
    }

    function test_OptimizeRangeWidth_EmptyPrices() public {
        uint256[] memory emptyPrices = new uint256[](0);
        
        uint256 newWidth = config.optimizeRangeWidth(emptyPrices);
        
        assertEq(newWidth, DEFAULT_RANGE_WIDTH, "Should return default width for empty prices");
    }

    function test_OptimizeRangeWidth_SinglePrice() public {
        uint256[] memory singlePrice = new uint256[](1);
        singlePrice[0] = TARGET_PRICE;
        
        uint256 newWidth = config.optimizeRangeWidth(singlePrice);
        
        assertEq(newWidth, MIN_RANGE_WIDTH, "Should return minimum width for single price");
    }

    // ============ Volatility Calculation Tests ============

    function test_CalculateVolatility_StablePrices() public {
        uint256[] memory stablePrices = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            stablePrices[i] = TARGET_PRICE;
        }

        uint256 volatility = config.calculateVolatility(stablePrices);
        
        assertEq(volatility, 0, "Volatility should be zero for stable prices");
    }

    function test_CalculateVolatility_VolatilePrices() public {
        uint256[] memory volatilePrices = new uint256[](5);
        volatilePrices[0] = 900000;
        volatilePrices[1] = 1100000;
        volatilePrices[2] = 950000;
        volatilePrices[3] = 1050000;
        volatilePrices[4] = 1000000;

        uint256 volatility = config.calculateVolatility(volatilePrices);
        
        assertGt(volatility, 0, "Volatility should be positive for volatile prices");
        assertLt(volatility, 10000, "Volatility should be reasonable");
    }

    function test_CalculateVolatility_TrendingPrices() public {
        uint256[] memory trendingPrices = new uint256[](5);
        trendingPrices[0] = 1000000;
        trendingPrices[1] = 1010000;
        trendingPrices[2] = 1020000;
        trendingPrices[3] = 1030000;
        trendingPrices[4] = 1040000;

        uint256 volatility = config.calculateVolatility(trendingPrices);
        
        assertGt(volatility, 0, "Volatility should be positive for trending prices");
    }

    // ============ Tick Conversion Tests ============

    function test_PriceToTick_TargetPrice() public {
        int24 tick = config.priceToTick(TARGET_PRICE);
        
        assertEq(tick, 0, "Target price should convert to tick 0");
    }

    function test_PriceToTick_DoublePrice() public {
        int24 tick = config.priceToTick(TARGET_PRICE * 2);
        
        assertGt(tick, 0, "Double price should convert to positive tick");
    }

    function test_PriceToTick_HalfPrice() public {
        int24 tick = config.priceToTick(TARGET_PRICE / 2);
        
        assertLt(tick, 0, "Half price should convert to negative tick");
    }

    function test_TickToPrice_ZeroTick() public {
        uint256 price = config.tickToPrice(0);
        
        assertEq(price, TARGET_PRICE, "Tick 0 should convert to target price");
    }

    function test_TickToPrice_PositiveTick() public {
        int24 positiveTick = 6931; // Approximately ln(2) * 10000
        uint256 price = config.tickToPrice(positiveTick);
        
        assertGt(price, TARGET_PRICE, "Positive tick should convert to higher price");
    }

    function test_TickToPrice_NegativeTick() public {
        int24 negativeTick = -6931; // Approximately -ln(2) * 10000
        uint256 price = config.tickToPrice(negativeTick);
        
        assertLt(price, TARGET_PRICE, "Negative tick should convert to lower price");
    }

    // ============ Range Validation Tests ============

    function test_ValidateRange_ValidRange() public {
        (int24 lowerTick, int24 upperTick) = config.calculateOptimalRange(TARGET_PRICE);
        
        bool isValid = config.validateRange(lowerTick, upperTick, TARGET_PRICE);
        
        assertTrue(isValid, "Calculated range should be valid");
    }

    function test_ValidateRange_InvalidOrder() public {
        bool isValid = config.validateRange(100, -100, TARGET_PRICE);
        
        assertFalse(isValid, "Range with lower > upper should be invalid");
    }

    function test_ValidateRange_TooWide() public {
        int24 lowerTick = -10000;
        int24 upperTick = 10000;
        
        bool isValid = config.validateRange(lowerTick, upperTick, TARGET_PRICE);
        
        assertFalse(isValid, "Excessively wide range should be invalid");
    }

    function test_ValidateRange_TooNarrow() public {
        int24 lowerTick = -1;
        int24 upperTick = 1;
        
        bool isValid = config.validateRange(lowerTick, upperTick, TARGET_PRICE);
        
        assertFalse(isValid, "Excessively narrow range should be invalid");
    }

    // ============ Dynamic Adjustment Tests ============

    function test_AdjustForMarketConditions_BullMarket() public {
        // Simulate bull market conditions
        uint256[] memory bullPrices = new uint256[](5);
        bullPrices[0] = 1000000;
        bullPrices[1] = 1020000;
        bullPrices[2] = 1040000;
        bullPrices[3] = 1060000;
        bullPrices[4] = 1080000;

        (int24 lowerTick, int24 upperTick) = config.adjustForMarketConditions(bullPrices, TARGET_PRICE);
        
        assertGt(upperTick, -lowerTick, "Range should be skewed upward in bull market");
    }

    function test_AdjustForMarketConditions_BearMarket() public {
        // Simulate bear market conditions
        uint256[] memory bearPrices = new uint256[](5);
        bearPrices[0] = 1000000;
        bearPrices[1] = 980000;
        bearPrices[2] = 960000;
        bearPrices[3] = 940000;
        bearPrices[4] = 920000;

        (int24 lowerTick, int24 upperTick) = config.adjustForMarketConditions(bearPrices, TARGET_PRICE);
        
        assertGt(-lowerTick, upperTick, "Range should be skewed downward in bear market");
    }

    function test_AdjustForMarketConditions_SidewaysMarket() public {
        // Simulate sideways market conditions
        uint256[] memory sidewaysPrices = new uint256[](5);
        sidewaysPrices[0] = 995000;
        sidewaysPrices[1] = 1005000;
        sidewaysPrices[2] = 998000;
        sidewaysPrices[3] = 1002000;
        sidewaysPrices[4] = 1000000;

        (int24 lowerTick, int24 upperTick) = config.adjustForMarketConditions(sidewaysPrices, TARGET_PRICE);
        
        // Range should be approximately symmetric
        int24 rangeDiff = (upperTick + lowerTick);
        assertLt(rangeDiff, 100, "Range should be approximately symmetric in sideways market");
        assertGt(rangeDiff, -100, "Range should be approximately symmetric in sideways market");
    }

    // ============ Edge Cases ============

    function test_EdgeCase_ZeroPrice() public {
        vm.expectRevert("Invalid price");
        config.priceToTick(0);
    }

    function test_EdgeCase_ExtremelyHighPrice() public {
        uint256 extremePrice = type(uint256).max;
        
        vm.expectRevert("Price too high");
        config.priceToTick(extremePrice);
    }

    function test_EdgeCase_MaximumTick() public {
        int24 maxTick = 887272; // Maximum valid tick in Uniswap V3
        
        uint256 price = config.tickToPrice(maxTick);
        assertGt(price, TARGET_PRICE, "Maximum tick should convert to very high price");
    }

    function test_EdgeCase_MinimumTick() public {
        int24 minTick = -887272; // Minimum valid tick in Uniswap V3
        
        uint256 price = config.tickToPrice(minTick);
        assertLt(price, TARGET_PRICE, "Minimum tick should convert to very low price");
    }

    function test_EdgeCase_TickSpacingAlignment() public {
        (int24 lowerTick, int24 upperTick) = config.calculateOptimalRange(TARGET_PRICE);
        
        assertEq(lowerTick % config.tickSpacing, 0, "Lower tick should be aligned to tick spacing");
        assertEq(upperTick % config.tickSpacing, 0, "Upper tick should be aligned to tick spacing");
    }

    // ============ Gas Optimization Tests ============

    function test_GasOptimization_CalculateRange() public {
        uint256 gasStart = gasleft();
        
        config.calculateOptimalRange(TARGET_PRICE);
        
        uint256 gasUsed = gasStart - gasleft();
        assertLt(gasUsed, 50000, "Range calculation should be gas efficient");
    }

    function test_GasOptimization_OptimizeWidth() public {
        uint256[] memory prices = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            prices[i] = TARGET_PRICE + (i * 1000);
        }

        uint256 gasStart = gasleft();
        
        config.optimizeRangeWidth(prices);
        
        uint256 gasUsed = gasStart - gasleft();
        assertLt(gasUsed, 100000, "Width optimization should be gas efficient");
    }
}
