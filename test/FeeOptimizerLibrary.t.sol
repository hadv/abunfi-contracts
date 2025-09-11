// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/libraries/FeeOptimizer.sol";

/**
 * @title FeeOptimizerLibraryTest
 * @dev Basic test cases for FeeOptimizer library functions
 */
contract FeeOptimizerLibraryTest is Test {
    // Standard Uniswap V4 fee tiers
    uint24 constant FEE_TIER_0_01 = 100;   // 0.01%
    uint24 constant FEE_TIER_0_05 = 500;   // 0.05%
    uint24 constant FEE_TIER_0_30 = 3000;  // 0.30%
    uint24 constant FEE_TIER_1_00 = 10000; // 1.00%

    // ============ BASIC FUNCTIONALITY TESTS ============

    function test_GetRecommendedFeeConfig() public {
        // Test major pair configuration
        FeeOptimizer.FeeConfig memory majorConfig = FeeOptimizer.getRecommendedFeeConfig(0);
        assertTrue(majorConfig.baseFee > 0, "Major pair should have positive base fee");
        assertTrue(majorConfig.dynamicEnabled, "Major pair should have dynamic fees enabled");

        // Test minor pair configuration
        FeeOptimizer.FeeConfig memory minorConfig = FeeOptimizer.getRecommendedFeeConfig(1);
        assertTrue(minorConfig.baseFee > 0, "Minor pair should have positive base fee");
        assertTrue(minorConfig.baseFee >= majorConfig.baseFee, "Minor pair should have higher base fee");

        // Test exotic pair configuration
        FeeOptimizer.FeeConfig memory exoticConfig = FeeOptimizer.getRecommendedFeeConfig(2);
        assertTrue(exoticConfig.baseFee > 0, "Exotic pair should have positive base fee");
        assertTrue(exoticConfig.baseFee >= minorConfig.baseFee, "Exotic pair should have highest base fee");
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
            liquidity: 2000000e6,  // $2M - moderate liquidity
            timestamp: block.timestamp
        });

        FeeOptimizer.FeeConfig memory config = FeeOptimizer.getRecommendedFeeConfig(0);
        uint24 optimalFee = FeeOptimizer.calculateOptimalFee(conditions, config);

        // Normal conditions should recommend standard fee tier
        assertTrue(optimalFee == FEE_TIER_0_05 || optimalFee == FEE_TIER_0_30,
                  "Should recommend standard fee tier for normal conditions");
    }

    function test_CalculateOptimalFee_ExtremeVolatility() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 1000,      // 10% - extreme volatility
            volume24h: 50000e6,    // $50K - very low volume
            spread: 200,           // 2% - very wide spread
            liquidity: 100000e6,   // $100K - minimal liquidity
            timestamp: block.timestamp
        });

        FeeOptimizer.FeeConfig memory config = FeeOptimizer.getRecommendedFeeConfig(0);
        uint24 optimalFee = FeeOptimizer.calculateOptimalFee(conditions, config);

        // Extreme conditions should recommend highest fee tier
        assertEq(optimalFee, FEE_TIER_1_00, "Should recommend highest fee for extreme conditions");
    }

    function test_CalculateOptimalFee_ZeroValues() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 0,
            volume24h: 0,
            spread: 0,
            liquidity: 0,
            timestamp: block.timestamp
        });

        FeeOptimizer.FeeConfig memory config = FeeOptimizer.getRecommendedFeeConfig(0);
        uint24 optimalFee = FeeOptimizer.calculateOptimalFee(conditions, config);

        // Should handle zero values gracefully and return a valid fee tier
        assertTrue(optimalFee >= FEE_TIER_0_01 && optimalFee <= FEE_TIER_1_00,
                  "Should return valid fee tier even with zero values");
    }

    function test_CalculateFeeRevenue() public {
        uint256 volume = 1000000e6; // $1M
        uint24 feeRate = FEE_TIER_0_05; // 0.05%

        uint256 revenue = FeeOptimizer.calculateFeeRevenue(volume, feeRate);

        // Expected: $1M * 0.05% = $500
        assertEq(revenue, 500e6, "Should calculate fee revenue correctly");
    }

    function test_EstimateAPY() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 25,
            volume24h: 5000000e6, // $5M daily volume
            spread: 10,
            liquidity: 2000000e6, // $2M liquidity
            timestamp: block.timestamp
        });

        uint24 feeRate = FEE_TIER_0_05;
        uint256 liquidityShare = 1000; // 10%

        uint256 apy = FeeOptimizer.estimateAPY(conditions, feeRate, liquidityShare);

        // Should return a reasonable APY
        assertTrue(apy >= 0 && apy <= 10000, "APY should be between 0% and 100%");
    }

    function test_CalculateImpermanentLoss() public {
        uint256 initialRatio = 1e18; // 1:1 ratio
        uint256 currentRatio = 1.01e18; // 1% price deviation

        uint256 il = FeeOptimizer.calculateImpermanentLoss(currentRatio, initialRatio);

        // Should calculate some impermanent loss for price deviation
        assertTrue(il > 0, "Should calculate positive IL for price deviation");
        assertTrue(il <= 100, "IL should be capped at reasonable maximum");
    }

    function test_NeedsFeeUpdate() public {
        uint24 currentFee = FEE_TIER_0_05;

        // Market conditions suggesting much higher fee
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 500,       // 5% - very high
            volume24h: 10000e6,    // $10K - very low
            spread: 100,           // 1% - wide
            liquidity: 50000e6,    // $50K - low
            timestamp: block.timestamp
        });

        FeeOptimizer.FeeConfig memory config = FeeOptimizer.getRecommendedFeeConfig(0);
        bool shouldUpdate = FeeOptimizer.needsFeeUpdate(
            block.timestamp - 3600, // Last update 1 hour ago
            3600, // Update frequency 1 hour
            conditions,
            currentFee,
            config
        );
        assertTrue(shouldUpdate, "Should update fee when market conditions change significantly");
    }
}
