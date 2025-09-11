// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/libraries/FeeOptimizer.sol";

contract FeeOptimizerLibraryTest is Test {
    FeeOptimizer.FeeConfig public config;
    
    uint256 public constant BASE_FEE = 3000; // 0.3%
    uint256 public constant MIN_FEE = 500; // 0.05%
    uint256 public constant MAX_FEE = 10000; // 1%
    uint256 public constant TARGET_UTILIZATION = 8000; // 80%

    event FeeUpdated(uint256 oldFee, uint256 newFee, uint256 utilization);
    event OptimizationTriggered(uint256 poolVolume, uint256 marketVolatility);

    function setUp() public {
        config = FeeOptimizer.FeeConfig({
            baseFee: uint24(BASE_FEE),
            volatilityMultiplier: uint24(1000), // 10%
            volumeThreshold: 1000000e6, // $1M volume threshold
            updateFrequency: 3600, // 1 hour
            dynamicEnabled: true
        });
    }

    // ============ Fee Calculation Tests ============

    function test_CalculateOptimalFee_AtTarget() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 50, // 0.5% - low volatility
            volume24h: 1000000e6,
            spread: 10, // 0.1%
            liquidity: 2000000e6, // $2M
            timestamp: block.timestamp
        });

        uint24 optimalFee = FeeOptimizer.calculateOptimalFee(conditions, config);

        assertEq(optimalFee, BASE_FEE, "Fee should remain at base for normal conditions");
    }

    function test_CalculateOptimalFee_HighVolatility() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 150, // 1.5% - high volatility
            volume24h: 500000e6,
            spread: 30, // 0.3%
            liquidity: 1000000e6, // $1M
            timestamp: block.timestamp
        });

        uint24 optimalFee = FeeOptimizer.calculateOptimalFee(conditions, config);

        assertGt(optimalFee, BASE_FEE, "Fee should increase with high volatility");
    }

    function test_CalculateOptimalFee_LowVolatility() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 5, // 0.05% - very low volatility
            volume24h: 2000000e6, // High volume
            spread: 5, // 0.05%
            liquidity: 3000000e6, // $3M
            timestamp: block.timestamp
        });

        uint24 optimalFee = FeeOptimizer.calculateOptimalFee(conditions, config);

        assertLt(optimalFee, BASE_FEE, "Fee should decrease with low volatility and high volume");
    }

    function test_CalculateOptimalFee_LowLiquidity() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 50, // 0.5%
            volume24h: 1000000e6,
            spread: 20, // 0.2%
            liquidity: 500000e6, // $500k - low liquidity
            timestamp: block.timestamp
        });

        uint24 optimalFee = FeeOptimizer.calculateOptimalFee(conditions, config);

        assertGt(optimalFee, BASE_FEE, "Fee should increase with low liquidity");
    }

    function test_CalculateOptimalFee_DisabledDynamic() public {
        config.dynamicEnabled = false;

        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 200, // 2% - very high volatility
            volume24h: 10000e6, // Low volume
            spread: 100, // 1%
            liquidity: 100000e6, // $100k - very low liquidity
            timestamp: block.timestamp
        });

        uint24 optimalFee = FeeOptimizer.calculateOptimalFee(conditions, config);

        assertEq(optimalFee, BASE_FEE, "Fee should remain at base when dynamic pricing is disabled");
    }

    // ============ Fee Revenue Tests ============

    function test_CalculateFeeRevenue() public {
        uint256 volume = 1000000e6; // $1M volume
        uint24 feeRate = 3000; // 0.3%

        uint256 revenue = FeeOptimizer.calculateFeeRevenue(volume, feeRate);

        assertEq(revenue, 3000e6, "Fee revenue should be 0.3% of volume");
    }

    function test_EstimateAPY() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 50,
            volume24h: 1000000e6,
            spread: 10,
            liquidity: 2000000e6,
            timestamp: block.timestamp
        });

        uint24 feeRate = 3000; // 0.3%
        uint256 liquidityShare = 1000; // 10% of pool

        uint256 apy = FeeOptimizer.estimateAPY(conditions, feeRate, liquidityShare);

        assertGt(apy, 0, "APY should be positive");
    }

    // ============ Recommended Config Tests ============

    function test_GetRecommendedFeeConfig_MajorPairs() public {
        FeeOptimizer.FeeConfig memory majorConfig = FeeOptimizer.getRecommendedFeeConfig(0);

        assertEq(majorConfig.baseFee, 100, "Major pairs should have 0.01% base fee");
        assertTrue(majorConfig.dynamicEnabled, "Dynamic fees should be enabled for major pairs");
    }

    function test_GetRecommendedFeeConfig_MinorPairs() public {
        FeeOptimizer.FeeConfig memory minorConfig = FeeOptimizer.getRecommendedFeeConfig(1);

        assertEq(minorConfig.baseFee, 300, "Minor pairs should have 0.03% base fee");
        assertTrue(minorConfig.dynamicEnabled, "Dynamic fees should be enabled for minor pairs");
    }

    function test_GetRecommendedFeeConfig_ExoticPairs() public {
        FeeOptimizer.FeeConfig memory exoticConfig = FeeOptimizer.getRecommendedFeeConfig(2);

        assertEq(exoticConfig.baseFee, 1000, "Exotic pairs should have 0.1% base fee");
        assertTrue(exoticConfig.dynamicEnabled, "Dynamic fees should be enabled for exotic pairs");
    }

    function test_CalculateImpermanentLoss() public {
        uint256 initialRatio = 1e18; // 1:1 ratio
        uint256 newRatio = 1.1e18; // 1.1:1 ratio (10% price change)

        uint256 il = FeeOptimizer.calculateImpermanentLoss(newRatio, initialRatio);

        assertGt(il, 0, "Impermanent loss should be positive for price deviation");
        assertLt(il, 1000, "IL should be less than 10% for small price changes");
    }

    // ============ Fee Update Logic Tests ============

    function test_NeedsFeeUpdate_RecentUpdate() public {
        uint256 lastUpdate = block.timestamp - 30 minutes;
        uint256 updateFrequency = 1 hours;

        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 50,
            volume24h: 1000000e6,
            spread: 10,
            liquidity: 2000000e6,
            timestamp: block.timestamp
        });

        uint24 currentFee = uint24(BASE_FEE);

        bool needsUpdate = FeeOptimizer.needsFeeUpdate(
            lastUpdate,
            updateFrequency,
            conditions,
            currentFee,
            config
        );

        assertFalse(needsUpdate, "Should not update fee too frequently");
    }

    function test_NeedsFeeUpdate_StaleUpdate() public {
        uint256 lastUpdate = block.timestamp - 2 hours;
        uint256 updateFrequency = 1 hours;

        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 150, // High volatility
            volume24h: 500000e6,
            spread: 30,
            liquidity: 1000000e6,
            timestamp: block.timestamp
        });

        uint24 currentFee = uint24(BASE_FEE);

        bool needsUpdate = FeeOptimizer.needsFeeUpdate(
            lastUpdate,
            updateFrequency,
            conditions,
            currentFee,
            config
        );

        assertTrue(needsUpdate, "Should update fee after sufficient time with market changes");
    }

    // ============ Profitability Tests ============

    function test_IsUpdateProfitable_HighGasCost() public {
        uint256 feeIncrease = 100e6; // $100 additional revenue
        uint256 gasPrice = 50 gwei;
        uint256 gasUsed = 100000; // 100k gas

        bool profitable = FeeOptimizer.isUpdateProfitable(feeIncrease, gasPrice, gasUsed);

        assertTrue(profitable, "Update should be profitable when revenue exceeds gas cost");
    }

    function test_IsUpdateProfitable_LowGasCost() public {
        uint256 feeIncrease = 1e6; // $1 additional revenue
        uint256 gasPrice = 100 gwei;
        uint256 gasUsed = 100000; // 100k gas (expensive)

        bool profitable = FeeOptimizer.isUpdateProfitable(feeIncrease, gasPrice, gasUsed);

        assertFalse(profitable, "Update should not be profitable when gas cost exceeds revenue");
    }

    // ============ Edge Cases ============

    function test_EdgeCase_ZeroVolume() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 50,
            volume24h: 0, // Zero volume
            spread: 10,
            liquidity: 1000000e6,
            timestamp: block.timestamp
        });

        uint24 fee = FeeOptimizer.calculateOptimalFee(conditions, config);

        assertEq(fee, BASE_FEE, "Zero volume should return base fee");
    }

    function test_EdgeCase_ExtremeVolatility() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 1000, // 10% - extreme volatility
            volume24h: 1000000e6,
            spread: 100, // 1%
            liquidity: 500000e6,
            timestamp: block.timestamp
        });

        uint24 fee = FeeOptimizer.calculateOptimalFee(conditions, config);

        assertGt(fee, BASE_FEE, "Extreme volatility should increase fee");
    }

    function test_CalculateFeeRevenue_ZeroVolume() public {
        uint256 revenue = FeeOptimizer.calculateFeeRevenue(0, uint24(BASE_FEE));

        assertEq(revenue, 0, "Zero volume should result in zero revenue");
    }

    function test_CalculateFeeRevenue_ZeroFee() public {
        uint256 revenue = FeeOptimizer.calculateFeeRevenue(1000000e6, 0);

        assertEq(revenue, 0, "Zero fee should result in zero revenue");
    }

    // ============ Performance Tests ============

    function test_Performance_OptimalFeeCalculation() public {
        uint256 gasStart = gasleft();

        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 50,
            volume24h: 1000000e6,
            spread: 10,
            liquidity: 2000000e6,
            timestamp: block.timestamp
        });

        FeeOptimizer.calculateOptimalFee(conditions, config);

        uint256 gasUsed = gasStart - gasleft();
        assertLt(gasUsed, 50000, "Fee calculation should be gas efficient");
    }
}
