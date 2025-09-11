// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/libraries/FeeOptimizer.sol";

contract FeeOptimizerLibraryTest is Test {
    using FeeOptimizer for FeeOptimizer.FeeConfig;

    FeeOptimizer.FeeConfig public config;
    
    uint256 public constant BASE_FEE = 3000; // 0.3%
    uint256 public constant MIN_FEE = 500; // 0.05%
    uint256 public constant MAX_FEE = 10000; // 1%
    uint256 public constant TARGET_UTILIZATION = 8000; // 80%

    event FeeUpdated(uint256 oldFee, uint256 newFee, uint256 utilization);
    event OptimizationTriggered(uint256 poolVolume, uint256 marketVolatility);

    function setUp() public {
        config = FeeOptimizer.FeeConfig({
            baseFee: BASE_FEE,
            minFee: MIN_FEE,
            maxFee: MAX_FEE,
            targetUtilization: TARGET_UTILIZATION,
            adjustmentFactor: 1000, // 10%
            lastUpdateTime: block.timestamp,
            currentFee: BASE_FEE
        });
    }

    // ============ Fee Calculation Tests ============

    function test_CalculateOptimalFee_AtTarget() public {
        uint256 currentUtilization = TARGET_UTILIZATION;
        uint256 poolVolume = 1000000e6;
        uint256 marketVolatility = 500; // 5%

        uint256 optimalFee = config.calculateOptimalFee(
            currentUtilization,
            poolVolume,
            marketVolatility
        );

        assertEq(optimalFee, BASE_FEE, "Fee should remain at base when at target utilization");
    }

    function test_CalculateOptimalFee_HighUtilization() public {
        uint256 highUtilization = 9500; // 95%
        uint256 poolVolume = 1000000e6;
        uint256 marketVolatility = 500;

        uint256 optimalFee = config.calculateOptimalFee(
            highUtilization,
            poolVolume,
            marketVolatility
        );

        assertGt(optimalFee, BASE_FEE, "Fee should increase with high utilization");
        assertLe(optimalFee, MAX_FEE, "Fee should not exceed maximum");
    }

    function test_CalculateOptimalFee_LowUtilization() public {
        uint256 lowUtilization = 2000; // 20%
        uint256 poolVolume = 1000000e6;
        uint256 marketVolatility = 500;

        uint256 optimalFee = config.calculateOptimalFee(
            lowUtilization,
            poolVolume,
            marketVolatility
        );

        assertLt(optimalFee, BASE_FEE, "Fee should decrease with low utilization");
        assertGe(optimalFee, MIN_FEE, "Fee should not go below minimum");
    }

    function test_CalculateOptimalFee_HighVolatility() public {
        uint256 currentUtilization = TARGET_UTILIZATION;
        uint256 poolVolume = 1000000e6;
        uint256 highVolatility = 2000; // 20%

        uint256 optimalFee = config.calculateOptimalFee(
            currentUtilization,
            poolVolume,
            highVolatility
        );

        assertGt(optimalFee, BASE_FEE, "Fee should increase with high volatility");
    }

    function test_CalculateOptimalFee_LowVolume() public {
        uint256 currentUtilization = TARGET_UTILIZATION;
        uint256 lowVolume = 10000e6; // Low volume
        uint256 marketVolatility = 500;

        uint256 optimalFee = config.calculateOptimalFee(
            currentUtilization,
            lowVolume,
            marketVolatility
        );

        assertGt(optimalFee, BASE_FEE, "Fee should increase with low volume to incentivize liquidity");
    }

    // ============ Fee Update Logic Tests ============

    function test_UpdateFee_SignificantChange() public {
        uint256 newOptimalFee = BASE_FEE * 150 / 100; // 50% increase
        
        vm.expectEmit(true, true, false, true);
        emit FeeUpdated(BASE_FEE, newOptimalFee, TARGET_UTILIZATION);

        bool updated = config.updateFee(newOptimalFee, TARGET_UTILIZATION);

        assertTrue(updated, "Fee should be updated for significant change");
        assertEq(config.currentFee, newOptimalFee, "Current fee should be updated");
    }

    function test_UpdateFee_MinimalChange() public {
        uint256 newOptimalFee = BASE_FEE * 101 / 100; // 1% increase
        
        bool updated = config.updateFee(newOptimalFee, TARGET_UTILIZATION);

        assertFalse(updated, "Fee should not be updated for minimal change");
        assertEq(config.currentFee, BASE_FEE, "Current fee should remain unchanged");
    }

    function test_UpdateFee_ExceedsMaximum() public {
        uint256 excessiveFee = MAX_FEE + 1000;
        
        bool updated = config.updateFee(excessiveFee, TARGET_UTILIZATION);

        assertTrue(updated, "Fee should be updated but capped");
        assertEq(config.currentFee, MAX_FEE, "Current fee should be capped at maximum");
    }

    function test_UpdateFee_BelowMinimum() public {
        uint256 tooLowFee = MIN_FEE - 100;
        
        bool updated = config.updateFee(tooLowFee, TARGET_UTILIZATION);

        assertTrue(updated, "Fee should be updated but floored");
        assertEq(config.currentFee, MIN_FEE, "Current fee should be floored at minimum");
    }

    // ============ Utilization Impact Tests ============

    function test_UtilizationImpact_LinearRelationship() public {
        uint256 poolVolume = 1000000e6;
        uint256 marketVolatility = 500;

        // Test various utilization levels
        uint256[] memory utilizations = new uint256[](5);
        utilizations[0] = 2000; // 20%
        utilizations[1] = 4000; // 40%
        utilizations[2] = 6000; // 60%
        utilizations[3] = 8000; // 80%
        utilizations[4] = 9500; // 95%

        uint256 previousFee = 0;
        for (uint256 i = 0; i < utilizations.length; i++) {
            uint256 fee = config.calculateOptimalFee(
                utilizations[i],
                poolVolume,
                marketVolatility
            );

            if (i > 0) {
                assertGe(fee, previousFee, "Fee should increase with utilization");
            }
            previousFee = fee;
        }
    }

    function test_UtilizationImpact_ExtremeValues() public {
        uint256 poolVolume = 1000000e6;
        uint256 marketVolatility = 500;

        // Test 0% utilization
        uint256 zeroUtilizationFee = config.calculateOptimalFee(0, poolVolume, marketVolatility);
        assertEq(zeroUtilizationFee, MIN_FEE, "Zero utilization should result in minimum fee");

        // Test 100% utilization
        uint256 fullUtilizationFee = config.calculateOptimalFee(10000, poolVolume, marketVolatility);
        assertEq(fullUtilizationFee, MAX_FEE, "Full utilization should result in maximum fee");
    }

    // ============ Market Condition Tests ============

    function test_MarketConditions_VolatilityImpact() public {
        uint256 currentUtilization = TARGET_UTILIZATION;
        uint256 poolVolume = 1000000e6;

        uint256 lowVolFee = config.calculateOptimalFee(currentUtilization, poolVolume, 100); // 1%
        uint256 medVolFee = config.calculateOptimalFee(currentUtilization, poolVolume, 500); // 5%
        uint256 highVolFee = config.calculateOptimalFee(currentUtilization, poolVolume, 1500); // 15%

        assertLt(lowVolFee, medVolFee, "Fee should increase with volatility");
        assertLt(medVolFee, highVolFee, "Fee should continue increasing with higher volatility");
    }

    function test_MarketConditions_VolumeImpact() public {
        uint256 currentUtilization = TARGET_UTILIZATION;
        uint256 marketVolatility = 500;

        uint256 lowVolumeFee = config.calculateOptimalFee(currentUtilization, 100000e6, marketVolatility);
        uint256 medVolumeFee = config.calculateOptimalFee(currentUtilization, 1000000e6, marketVolatility);
        uint256 highVolumeFee = config.calculateOptimalFee(currentUtilization, 10000000e6, marketVolatility);

        assertGt(lowVolumeFee, medVolumeFee, "Fee should decrease with higher volume");
        assertGe(medVolumeFee, highVolumeFee, "Fee should continue decreasing with very high volume");
    }

    // ============ Time-based Adjustments ============

    function test_TimeBasedAdjustment_RecentUpdate() public {
        // Set last update to very recent
        config.lastUpdateTime = block.timestamp - 1 minutes;

        uint256 newOptimalFee = BASE_FEE * 200 / 100; // 100% increase
        bool shouldUpdate = config.shouldUpdateFee(newOptimalFee);

        assertFalse(shouldUpdate, "Should not update fee too frequently");
    }

    function test_TimeBasedAdjustment_StaleUpdate() public {
        // Set last update to long ago
        config.lastUpdateTime = block.timestamp - 1 hours;

        uint256 newOptimalFee = BASE_FEE * 110 / 100; // 10% increase
        bool shouldUpdate = config.shouldUpdateFee(newOptimalFee);

        assertTrue(shouldUpdate, "Should update fee after sufficient time");
    }

    // ============ Edge Cases ============

    function test_EdgeCase_ZeroVolume() public {
        uint256 fee = config.calculateOptimalFee(TARGET_UTILIZATION, 0, 500);
        
        assertEq(fee, MAX_FEE, "Zero volume should result in maximum fee");
    }

    function test_EdgeCase_ZeroVolatility() public {
        uint256 fee = config.calculateOptimalFee(TARGET_UTILIZATION, 1000000e6, 0);
        
        assertLe(fee, BASE_FEE, "Zero volatility should not increase fee above base");
    }

    function test_EdgeCase_ExtremeVolatility() public {
        uint256 extremeVolatility = 10000; // 100%
        uint256 fee = config.calculateOptimalFee(TARGET_UTILIZATION, 1000000e6, extremeVolatility);
        
        assertEq(fee, MAX_FEE, "Extreme volatility should result in maximum fee");
    }

    function test_EdgeCase_InvalidUtilization() public {
        vm.expectRevert("Invalid utilization");
        config.calculateOptimalFee(10001, 1000000e6, 500); // > 100%
    }

    // ============ Fee Smoothing Tests ============

    function test_FeeSmoothing_GradualAdjustment() public {
        uint256 targetFee = BASE_FEE * 200 / 100; // 100% increase
        
        // First update should be partial
        config.updateFee(targetFee, TARGET_UTILIZATION);
        uint256 firstUpdate = config.currentFee;
        
        assertGt(firstUpdate, BASE_FEE, "Fee should increase");
        assertLt(firstUpdate, targetFee, "Fee should not jump to target immediately");

        // Advance time and update again
        vm.warp(block.timestamp + 1 hours);
        config.updateFee(targetFee, TARGET_UTILIZATION);
        uint256 secondUpdate = config.currentFee;
        
        assertGt(secondUpdate, firstUpdate, "Fee should continue adjusting toward target");
    }

    function test_FeeSmoothing_MaxAdjustmentPerUpdate() public {
        uint256 extremeTargetFee = MAX_FEE;
        
        config.updateFee(extremeTargetFee, TARGET_UTILIZATION);
        
        uint256 maxIncrease = BASE_FEE * (10000 + config.adjustmentFactor) / 10000;
        assertLe(config.currentFee, maxIncrease, "Fee adjustment should be limited per update");
    }

    // ============ Revenue Estimation Tests ============

    function test_EstimateRevenue_BaseFee() public {
        uint256 volume = 1000000e6;
        uint256 expectedRevenue = volume * BASE_FEE / 1000000; // Fee in basis points

        uint256 actualRevenue = config.estimateRevenue(volume, BASE_FEE);
        
        assertEq(actualRevenue, expectedRevenue, "Revenue calculation should be accurate");
    }

    function test_EstimateRevenue_ZeroVolume() public {
        uint256 revenue = config.estimateRevenue(0, BASE_FEE);
        
        assertEq(revenue, 0, "Zero volume should result in zero revenue");
    }

    function test_EstimateRevenue_ZeroFee() public {
        uint256 revenue = config.estimateRevenue(1000000e6, 0);
        
        assertEq(revenue, 0, "Zero fee should result in zero revenue");
    }

    // ============ Performance Tests ============

    function test_Performance_OptimalFeeCalculation() public {
        uint256 gasStart = gasleft();
        
        config.calculateOptimalFee(TARGET_UTILIZATION, 1000000e6, 500);
        
        uint256 gasUsed = gasStart - gasleft();
        assertLt(gasUsed, 50000, "Fee calculation should be gas efficient");
    }

    function test_Performance_BatchFeeUpdates() public {
        uint256 gasStart = gasleft();
        
        // Simulate multiple fee updates
        for (uint256 i = 0; i < 10; i++) {
            uint256 utilization = 5000 + (i * 500); // 50% to 95%
            uint256 fee = config.calculateOptimalFee(utilization, 1000000e6, 500);
            config.updateFee(fee, utilization);
        }
        
        uint256 gasUsed = gasStart - gasleft();
        assertLt(gasUsed, 500000, "Batch updates should be reasonably gas efficient");
    }
}
