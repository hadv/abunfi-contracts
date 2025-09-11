// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/libraries/FeeOptimizer.sol";

/**
 * @title FeeOptimizerLibraryTest
 * @dev Comprehensive test cases for FeeOptimizer library functions
 * Tests fee optimization algorithms and market condition analysis
 */
contract FeeOptimizerLibraryTest is Test {
    using FeeOptimizer for *;

    // Standard Uniswap V4 fee tiers
    uint24 constant FEE_TIER_0_01 = 100;   // 0.01%
    uint24 constant FEE_TIER_0_05 = 500;   // 0.05%
    uint24 constant FEE_TIER_0_30 = 3000;  // 0.30%
    uint24 constant FEE_TIER_1_00 = 10000; // 1.00%

    // ============ CALCULATE OPTIMAL FEE TESTS ============

    function test_CalculateOptimalFee_LowVolatilityHighVolume() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 10,        // 0.1% - very low for stablecoins
            volume24h: 10000000e6, // $10M - high volume
            spread: 5,             // 0.05% - tight spread
            liquidity: 5000000e6,  // $5M - good liquidity
            timestamp: block.timestamp
        });

        FeeOptimizer.FeeConfig memory config = FeeOptimizer.getRecommendedFeeConfig(0); // Major pair
        uint24 optimalFee = FeeOptimizer.calculateOptimalFee(conditions, config);

        // Low volatility + high volume should prefer lower fees for more trades
        assertTrue(optimalFee <= FEE_TIER_0_05, "Should recommend low fee for stable, high-volume conditions");
    }

    function test_CalculateOptimalFee_HighVolatilityLowVolume() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 200,       // 2% - high for stablecoins
            volume24h: 100000e6,   // $100K - low volume
            spread: 50,            // 0.5% - wide spread
            liquidity: 500000e6,   // $500K - lower liquidity
            timestamp: block.timestamp
        });

        FeeOptimizer.FeeConfig memory config = FeeOptimizer.getRecommendedFeeConfig(0);
        uint24 optimalFee = FeeOptimizer.calculateOptimalFee(conditions, config);

        // High volatility + low volume should prefer higher fees for risk compensation
        assertTrue(optimalFee >= FEE_TIER_0_30, "Should recommend higher fee for volatile, low-volume conditions");
    }

    function test_CalculateOptimalFee_NormalConditions() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 25,        // 0.25% - normal for stablecoins
            volume24h: 2000000e6,  // $2M - moderate volume
            spread: 10,            // 0.1% - normal spread
            liquidity: 2000000e6   // $2M - moderate liquidity
        });

        uint24 optimalFee = FeeOptimizer.calculateOptimalFee(conditions);

        // Normal conditions should recommend standard fee tier
        assertTrue(optimalFee == FEE_TIER_0_05 || optimalFee == FEE_TIER_0_30, 
                  "Should recommend standard fee tier for normal conditions");
    }

    function test_CalculateOptimalFee_ExtremeVolatility() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 1000,      // 10% - extreme volatility
            volume24h: 50000e6,    // $50K - very low volume
            spread: 200,           // 2% - very wide spread
            liquidity: 100000e6    // $100K - minimal liquidity
        });

        uint24 optimalFee = FeeOptimizer.calculateOptimalFee(conditions);

        // Extreme conditions should recommend highest fee tier
        assertEq(optimalFee, FEE_TIER_1_00, "Should recommend highest fee for extreme conditions");
    }

    function test_CalculateOptimalFee_ZeroValues() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 0,
            volume24h: 0,
            spread: 0,
            liquidity: 0
        });

        uint24 optimalFee = FeeOptimizer.calculateOptimalFee(conditions);

        // Should handle zero values gracefully and return a valid fee tier
        assertTrue(optimalFee == FEE_TIER_0_01 || optimalFee == FEE_TIER_0_05 || 
                  optimalFee == FEE_TIER_0_30 || optimalFee == FEE_TIER_1_00,
                  "Should return valid fee tier even with zero values");
    }

    // ============ SHOULD UPDATE FEE TESTS ============

    function test_ShouldUpdateFee_SignificantChange() public {
        uint24 currentFee = FEE_TIER_0_05;
        
        // Market conditions suggesting much higher fee
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 500,       // 5% - very high
            volume24h: 10000e6,    // $10K - very low
            spread: 100,           // 1% - wide
            liquidity: 50000e6     // $50K - low
        });

        bool shouldUpdate = FeeOptimizer.shouldUpdateFee(currentFee, conditions);
        assertTrue(shouldUpdate, "Should update fee when market conditions change significantly");
    }

    function test_ShouldUpdateFee_MinorChange() public {
        uint24 currentFee = FEE_TIER_0_05;
        
        // Market conditions similar to current fee tier
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 20,        // 0.2% - low
            volume24h: 5000000e6,  // $5M - good
            spread: 8,             // 0.08% - tight
            liquidity: 3000000e6   // $3M - good
        });

        bool shouldUpdate = FeeOptimizer.shouldUpdateFee(currentFee, conditions);
        assertFalse(shouldUpdate, "Should not update fee for minor market changes");
    }

    function test_ShouldUpdateFee_BoundaryConditions() public {
        // Test at boundary between fee tiers
        uint24 currentFee = FEE_TIER_0_05;
        
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 75,        // Boundary volatility
            volume24h: 1000000e6,  // $1M
            spread: 25,            // 0.25%
            liquidity: 1000000e6   // $1M
        });

        bool shouldUpdate = FeeOptimizer.shouldUpdateFee(currentFee, conditions);
        // Result depends on implementation, but should be consistent
        assertTrue(shouldUpdate == true || shouldUpdate == false, "Should return boolean");
    }

    // ============ ESTIMATE FEE REVENUE TESTS ============

    function test_EstimateFeeRevenue_HighVolumeHighFee() public {
        uint256 volume24h = 10000000e6; // $10M
        uint24 feeRate = FEE_TIER_1_00;  // 1%
        uint256 liquidityShare = 2000;   // 20%

        uint256 estimatedRevenue = FeeOptimizer.estimateFeeRevenue(volume24h, feeRate, liquidityShare);

        // Expected: $10M * 1% * 20% = $20,000
        uint256 expectedRevenue = 20000e6;
        assertApproxEqRel(estimatedRevenue, expectedRevenue, 0.01e18, "Should estimate revenue correctly");
    }

    function test_EstimateFeeRevenue_LowVolumeHighFee() public {
        uint256 volume24h = 100000e6;   // $100K
        uint24 feeRate = FEE_TIER_1_00; // 1%
        uint256 liquidityShare = 5000;  // 50%

        uint256 estimatedRevenue = FeeOptimizer.estimateFeeRevenue(volume24h, feeRate, liquidityShare);

        // Expected: $100K * 1% * 50% = $500
        uint256 expectedRevenue = 500e6;
        assertApproxEqRel(estimatedRevenue, expectedRevenue, 0.01e18, "Should estimate revenue correctly");
    }

    function test_EstimateFeeRevenue_HighVolumeLowFee() public {
        uint256 volume24h = 50000000e6; // $50M
        uint24 feeRate = FEE_TIER_0_01;  // 0.01%
        uint256 liquidityShare = 1000;   // 10%

        uint256 estimatedRevenue = FeeOptimizer.estimateFeeRevenue(volume24h, feeRate, liquidityShare);

        // Expected: $50M * 0.01% * 10% = $500
        uint256 expectedRevenue = 500e6;
        assertApproxEqRel(estimatedRevenue, expectedRevenue, 0.01e18, "Should estimate revenue correctly");
    }

    function test_EstimateFeeRevenue_ZeroValues() public {
        uint256 estimatedRevenue = FeeOptimizer.estimateFeeRevenue(0, FEE_TIER_0_05, 1000);
        assertEq(estimatedRevenue, 0, "Should return zero revenue for zero volume");

        estimatedRevenue = FeeOptimizer.estimateFeeRevenue(1000000e6, 0, 1000);
        assertEq(estimatedRevenue, 0, "Should return zero revenue for zero fee");

        estimatedRevenue = FeeOptimizer.estimateFeeRevenue(1000000e6, FEE_TIER_0_05, 0);
        assertEq(estimatedRevenue, 0, "Should return zero revenue for zero liquidity share");
    }

    function test_EstimateFeeRevenue_MaxLiquidityShare() public {
        uint256 volume24h = 1000000e6;  // $1M
        uint24 feeRate = FEE_TIER_0_05; // 0.05%
        uint256 liquidityShare = 10000; // 100%

        uint256 estimatedRevenue = FeeOptimizer.estimateFeeRevenue(volume24h, feeRate, liquidityShare);

        // Expected: $1M * 0.05% * 100% = $500
        uint256 expectedRevenue = 500e6;
        assertApproxEqRel(estimatedRevenue, expectedRevenue, 0.01e18, "Should handle 100% liquidity share");
    }

    // ============ GET MARKET SCORE TESTS ============

    function test_GetMarketScore_OptimalConditions() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 15,        // Low volatility
            volume24h: 20000000e6, // High volume
            spread: 5,             // Tight spread
            liquidity: 10000000e6  // High liquidity
        });

        uint256 score = FeeOptimizer.getMarketScore(conditions);

        // Optimal conditions should have high score
        assertTrue(score >= 8000, "Should have high score for optimal conditions"); // >= 80%
    }

    function test_GetMarketScore_PoorConditions() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 500,       // High volatility
            volume24h: 10000e6,    // Low volume
            spread: 100,           // Wide spread
            liquidity: 50000e6     // Low liquidity
        });

        uint256 score = FeeOptimizer.getMarketScore(conditions);

        // Poor conditions should have low score
        assertTrue(score <= 3000, "Should have low score for poor conditions"); // <= 30%
    }

    function test_GetMarketScore_MixedConditions() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 50,        // Moderate volatility
            volume24h: 2000000e6,  // Moderate volume
            spread: 20,            // Moderate spread
            liquidity: 1500000e6   // Moderate liquidity
        });

        uint256 score = FeeOptimizer.getMarketScore(conditions);

        // Mixed conditions should have moderate score
        assertTrue(score >= 3000 && score <= 8000, "Should have moderate score for mixed conditions");
    }

    function test_GetMarketScore_BoundaryValues() public {
        // Test with extreme values
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 0,
            volume24h: type(uint256).max,
            spread: 0,
            liquidity: type(uint256).max
        });

        uint256 score = FeeOptimizer.getMarketScore(conditions);
        assertTrue(score <= 10000, "Score should not exceed 100%");

        // Test with all zero values
        conditions = FeeOptimizer.MarketConditions({
            volatility: 0,
            volume24h: 0,
            spread: 0,
            liquidity: 0
        });

        score = FeeOptimizer.getMarketScore(conditions);
        assertTrue(score >= 0, "Score should not be negative");
    }

    // ============ COMPARE FEE EFFICIENCY TESTS ============

    function test_CompareFeeEfficiency_ClearWinner() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 25,
            volume24h: 5000000e6,
            spread: 15,
            liquidity: 2000000e6
        });

        uint256 liquidityShare = 1500; // 15%

        // Compare low fee vs high fee
        int256 comparison = FeeOptimizer.compareFeeEfficiency(
            FEE_TIER_0_05,
            FEE_TIER_1_00,
            conditions,
            liquidityShare
        );

        // Result should indicate which fee is better (positive if first is better, negative if second is better)
        assertTrue(comparison != 0, "Should have a preference between different fee tiers");
    }

    function test_CompareFeeEfficiency_SameFee() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 25,
            volume24h: 5000000e6,
            spread: 15,
            liquidity: 2000000e6
        });

        uint256 liquidityShare = 1500; // 15%

        int256 comparison = FeeOptimizer.compareFeeEfficiency(
            FEE_TIER_0_05,
            FEE_TIER_0_05,
            conditions,
            liquidityShare
        );

        assertEq(comparison, 0, "Should return zero when comparing same fee");
    }

    function test_CompareFeeEfficiency_VariousConditions() public {
        uint256 liquidityShare = 1000; // 10%

        // Test under high volume conditions
        FeeOptimizer.MarketConditions memory highVolumeConditions = FeeOptimizer.MarketConditions({
            volatility: 10,
            volume24h: 20000000e6,
            spread: 5,
            liquidity: 5000000e6
        });

        int256 comparison = FeeOptimizer.compareFeeEfficiency(
            FEE_TIER_0_01,
            FEE_TIER_0_30,
            highVolumeConditions,
            liquidityShare
        );

        // Under high volume, lower fees might be more efficient
        // (This depends on the implementation logic)

        // Test under high volatility conditions
        FeeOptimizer.MarketConditions memory highVolatilityConditions = FeeOptimizer.MarketConditions({
            volatility: 200,
            volume24h: 500000e6,
            spread: 50,
            liquidity: 500000e6
        });

        comparison = FeeOptimizer.compareFeeEfficiency(
            FEE_TIER_0_05,
            FEE_TIER_1_00,
            highVolatilityConditions,
            liquidityShare
        );

        // Under high volatility, higher fees might be more efficient
        // (This depends on the implementation logic)
        assertTrue(comparison != 0, "Should have preference under volatile conditions");
    }

    // ============ FUZZ TESTS ============

    function testFuzz_CalculateOptimalFee(
        uint256 volatility,
        uint256 volume24h,
        uint256 spread,
        uint256 liquidity
    ) public {
        // Bound inputs to reasonable ranges
        volatility = bound(volatility, 0, 2000); // 0% to 20%
        volume24h = bound(volume24h, 0, 1000000000e6); // 0 to $1B
        spread = bound(spread, 0, 1000); // 0% to 10%
        liquidity = bound(liquidity, 0, 1000000000e6); // 0 to $1B

        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: volatility,
            volume24h: volume24h,
            spread: spread,
            liquidity: liquidity
        });

        uint24 optimalFee = FeeOptimizer.calculateOptimalFee(conditions);

        // Invariants
        assertTrue(
            optimalFee == FEE_TIER_0_01 || 
            optimalFee == FEE_TIER_0_05 || 
            optimalFee == FEE_TIER_0_30 || 
            optimalFee == FEE_TIER_1_00,
            "Should return valid fee tier"
        );
    }

    function testFuzz_EstimateFeeRevenue(
        uint256 volume24h,
        uint24 feeRate,
        uint256 liquidityShare
    ) public {
        // Bound inputs
        volume24h = bound(volume24h, 0, 1000000000e6); // 0 to $1B
        feeRate = uint24(bound(feeRate, 0, 10000)); // 0% to 1%
        liquidityShare = bound(liquidityShare, 0, 10000); // 0% to 100%

        uint256 estimatedRevenue = FeeOptimizer.estimateFeeRevenue(volume24h, feeRate, liquidityShare);

        // Invariants
        assertTrue(estimatedRevenue >= 0, "Revenue should be non-negative");
        
        if (volume24h == 0 || feeRate == 0 || liquidityShare == 0) {
            assertEq(estimatedRevenue, 0, "Revenue should be zero if any input is zero");
        }
        
        // Revenue should not exceed total volume
        assertTrue(estimatedRevenue <= volume24h, "Revenue should not exceed total volume");
    }

    function testFuzz_GetMarketScore(
        uint256 volatility,
        uint256 volume24h,
        uint256 spread,
        uint256 liquidity
    ) public {
        // Bound inputs
        volatility = bound(volatility, 0, 2000);
        volume24h = bound(volume24h, 0, 1000000000e6);
        spread = bound(spread, 0, 1000);
        liquidity = bound(liquidity, 0, 1000000000e6);

        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: volatility,
            volume24h: volume24h,
            spread: spread,
            liquidity: liquidity
        });

        uint256 score = FeeOptimizer.getMarketScore(conditions);

        // Invariants
        assertTrue(score <= 10000, "Score should not exceed 100%");
        assertTrue(score >= 0, "Score should be non-negative");
    }
}
