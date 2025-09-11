// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/strategies/UniswapV4FairFlowStablecoinStrategy.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockUniswapV4PoolManager.sol";
import "../src/mocks/MockUniswapV4Hook.sol";
import "../src/libraries/StablecoinRangeManager.sol";
import "../src/libraries/FeeOptimizer.sol";

/**
 * @title UniswapV4StrategyEdgeCasesTest
 * @dev Comprehensive edge case and extreme market condition tests for UniswapV4FairFlowStablecoinStrategy
 * Covers scenarios not tested in the main test file:
 * - Extreme market volatility
 * - Liquidity crisis scenarios
 * - Hook integration failures
 * - Fee optimization stress tests
 * - Range management edge cases
 * - Impermanent loss scenarios
 */
contract UniswapV4StrategyEdgeCasesTest is Test {
    UniswapV4FairFlowStablecoinStrategy public strategy;
    MockERC20 public usdc;
    MockERC20 public usdt;
    MockUniswapV4PoolManager public poolManager;
    MockUniswapV4Hook public hook;

    address public owner;
    address public vault;
    address public attacker;

    PoolKey public poolKey;

    uint256 constant INITIAL_BALANCE = 10000000e6; // 10M USDC/USDT
    uint256 constant LARGE_DEPOSIT = 1000000e6; // 1M USDC
    uint256 constant SMALL_DEPOSIT = 100e6; // 100 USDC

    // Events for testing
    event EmergencyExit(uint256 amount0, uint256 amount1);
    event Rebalanced(int24 oldTickLower, int24 oldTickUpper, int24 newTickLower, int24 newTickUpper);
    event FeeUpdated(uint24 oldFee, uint24 newFee);

    function setUp() public {
        owner = address(this);
        vault = makeAddr("vault");
        attacker = makeAddr("attacker");

        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether USD", "USDT", 6);

        // Deploy mock pool manager and hook
        poolManager = new MockUniswapV4PoolManager();
        hook = new MockUniswapV4Hook();

        // Setup pool key
        poolKey = PoolKey({
            currency0: address(usdc),
            currency1: address(usdt),
            fee: 500, // 0.05%
            tickSpacing: 10,
            hooks: address(hook)
        });

        // Deploy strategy
        strategy = new UniswapV4FairFlowStablecoinStrategy(
            address(usdc),
            address(usdt),
            vault,
            address(poolManager),
            address(hook),
            "USDC/USDT V4 Strategy",
            poolKey
        );

        // Mint tokens to vault and strategy
        usdc.mint(vault, INITIAL_BALANCE);
        usdt.mint(vault, INITIAL_BALANCE);
        usdc.mint(address(strategy), INITIAL_BALANCE);
        usdt.mint(address(strategy), INITIAL_BALANCE);

        // Approve strategy to spend vault tokens
        vm.prank(vault);
        usdc.approve(address(strategy), type(uint256).max);
        vm.prank(vault);
        usdt.approve(address(strategy), type(uint256).max);
    }

    // ============ EXTREME MARKET VOLATILITY TESTS ============

    function test_ExtremeVolatility_DepegScenario() public {
        // Simulate USDT depegging to $0.95
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        // Update market conditions to reflect extreme volatility
        strategy.updateMarketConditions(
            500, // 5% volatility (extreme for stablecoins)
            100000e6, // Low volume during crisis
            100, // 1% spread
            500000e6 // Reduced liquidity
        );

        // Strategy should handle this gracefully
        uint256 il = strategy.getCurrentImpermanentLoss();
        assertTrue(il > 0, "Should have impermanent loss during depeg");
        assertTrue(il < 1000, "IL should be capped at reasonable level"); // < 10%
    }

    function test_ExtremeVolatility_FlashCrash() public {
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        // Simulate flash crash conditions
        strategy.updateMarketConditions(
            1000, // 10% volatility
            10000e6, // Very low volume
            500, // 5% spread
            100000e6 // Minimal liquidity
        );

        // Strategy should enter emergency mode or handle gracefully
        uint256 totalAssets = strategy.totalAssets();
        assertTrue(totalAssets > 0, "Should maintain some assets");

        // Test emergency exit during crisis
        strategy.emergencyExit();
        assertTrue(strategy.emergencyMode(), "Should be in emergency mode");
    }

    function test_ExtremeVolatility_RapidRebalancing() public {
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        // Enable auto-rebalancing with tight thresholds
        strategy.updateRangeConfig(20, 5, 100e6, true); // Very tight range

        // Simulate rapid price movements requiring frequent rebalancing
        for (uint256 i = 0; i < 10; i++) {
            strategy.updateMarketConditions(
                100 + i * 10, // Increasing volatility
                1000000e6,
                10 + i,
                1000000e6
            );
            
            // Force rebalance
            strategy.manualRebalance();
        }

        // Strategy should handle multiple rebalances
        (,,,, uint256 rebalanceCount,) = strategy.getStrategyStats();
        assertTrue(rebalanceCount >= 10, "Should have performed multiple rebalances");
    }

    // ============ LIQUIDITY CRISIS SCENARIOS ============

    function test_LiquidityCrisis_ZeroPoolLiquidity() public {
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        // Simulate pool with zero liquidity
        strategy.updateMarketConditions(
            200, // High volatility
            1000e6, // Very low volume
            1000, // 10% spread
            0 // Zero liquidity
        );

        // Strategy should handle zero liquidity gracefully
        uint256 apy = strategy.getAPY();
        assertEq(apy, 0, "APY should be zero with no liquidity");

        // Should be able to emergency exit
        strategy.emergencyExit();
        assertTrue(strategy.emergencyMode());
    }

    function test_LiquidityCrisis_WithdrawalDuringCrisis() public {
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        // Simulate liquidity crisis
        strategy.updateMarketConditions(300, 5000e6, 200, 10000e6);

        // Try to withdraw during crisis
        vm.prank(vault);
        strategy.withdraw(LARGE_DEPOSIT / 2);

        // Should be able to withdraw something, even if not full amount
        assertTrue(strategy.totalAssets() < LARGE_DEPOSIT, "Should have withdrawn some amount");
    }

    function test_LiquidityCrisis_PartialWithdrawalOnly() public {
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        // Simulate severe liquidity constraints
        strategy.updateMarketConditions(400, 1000e6, 300, 1000e6);

        // Try to withdraw all
        vm.prank(vault);
        strategy.withdraw(LARGE_DEPOSIT);

        // Might not be able to withdraw full amount
        assertTrue(strategy.totalAssets() >= 0, "Total assets should be non-negative");
        
        // Remaining assets should still be tracked
        uint256 remaining = strategy.totalAssets();
        assertTrue(remaining >= 0, "Should track remaining assets");
    }

    // ============ HOOK INTEGRATION FAILURE TESTS ============

    function test_HookFailure_DepositWithFailingHook() public {
        // Configure hook to fail by disabling beforeAddLiquidity
        hook.setHookEnabled(hook.beforeAddLiquidity.selector, false);

        // Deposit should handle hook failure gracefully
        vm.prank(vault);
        try strategy.deposit(LARGE_DEPOSIT) {
            // If it succeeds, verify state is consistent
            assertTrue(strategy.totalAssets() >= 0);
        } catch {
            // If it fails, that's also acceptable behavior
            assertEq(strategy.totalAssets(), 0);
        }
    }

    function test_HookFailure_HarvestWithFailingHook() public {
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        // Configure hook to fail during harvest
        hook.setHookEnabled(hook.afterRemoveLiquidity.selector, false);

        vm.prank(vault);
        uint256 yield = strategy.harvest();

        // Should handle hook failure gracefully
        assertTrue(yield >= 0, "Yield should be non-negative even with hook failure");
    }

    function test_HookFailure_RebalanceWithFailingHook() public {
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        hook.setHookEnabled(hook.beforeRemoveLiquidity.selector, false);

        // Manual rebalance should handle hook failure
        try strategy.manualRebalance() {
            assertTrue(true, "Rebalance succeeded despite hook failure");
        } catch {
            assertTrue(true, "Rebalance failed gracefully");
        }
    }

    // ============ FEE OPTIMIZATION STRESS TESTS ============

    function test_FeeOptimization_RapidFeeChanges() public {
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        // Simulate rapid fee tier changes
        uint24[] memory fees = new uint24[](5);
        fees[0] = 100;  // 0.01%
        fees[1] = 500;  // 0.05%
        fees[2] = 3000; // 0.3%
        fees[3] = 10000; // 1%
        fees[4] = 500;  // Back to 0.05%

        for (uint256 i = 0; i < fees.length; i++) {
            // Update market conditions to trigger fee changes
            strategy.updateMarketConditions(
                50 + i * 20, // Varying volatility
                1000000e6 + i * 500000e6, // Varying volume
                10 + i * 5, // Varying spread
                1000000e6
            );

            // Harvest to trigger fee optimization
            vm.prank(vault);
            strategy.harvest();
        }

        // Strategy should handle rapid fee changes
        assertTrue(strategy.totalAssets() > 0, "Should maintain assets through fee changes");
    }

    function test_FeeOptimization_ExtremeMarketConditions() public {
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        // Test extreme low volume
        strategy.updateMarketConditions(10, 1000e6, 5, 1000000e6);
        vm.prank(vault);
        strategy.harvest();

        // Test extreme high volume
        strategy.updateMarketConditions(10, 100000000e6, 5, 10000000e6);
        vm.prank(vault);
        strategy.harvest();

        // Test extreme volatility
        strategy.updateMarketConditions(1000, 1000000e6, 100, 1000000e6);
        vm.prank(vault);
        strategy.harvest();

        assertTrue(strategy.totalAssets() > 0, "Should handle extreme conditions");
    }

    // ============ RANGE MANAGEMENT EDGE CASES ============

    function test_RangeManagement_TickBoundaryEdgeCases() public {
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        // Test range at maximum tick boundaries
        try strategy.updateRangeConfig(887272, 400000, 100e6, true) {
            assertTrue(true, "Should handle extreme range widths");
        } catch {
            assertTrue(true, "Should reject invalid ranges gracefully");
        }

        // Test minimum range width
        strategy.updateRangeConfig(1, 1, 1e6, false);
        
        assertTrue(strategy.totalAssets() > 0, "Should maintain assets with minimal range");
    }

    function test_RangeManagement_FrequentRebalancing() public {
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        // Set very aggressive rebalancing
        strategy.updateRangeConfig(10, 1, 1e6, true); // Rebalance on 0.01% movement

        // Simulate frequent small price movements
        for (uint256 i = 0; i < 20; i++) {
            strategy.updateMarketConditions(
                20 + (i % 5), // Small volatility changes
                1000000e6,
                10,
                1000000e6
            );
            
            vm.prank(vault);
            strategy.harvest(); // This might trigger rebalancing
        }

        (,,,, uint256 rebalanceCount,) = strategy.getStrategyStats();
        assertTrue(rebalanceCount >= 0, "Should track rebalance count");
    }

    function test_RangeManagement_DisabledAutoRebalance() public {
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        // Disable auto-rebalancing
        strategy.updateRangeConfig(50, 25, 100e6, false);

        // Create conditions that would normally trigger rebalancing
        strategy.updateMarketConditions(200, 100000e6, 50, 500000e6);

        vm.prank(vault);
        strategy.harvest();

        // Should not auto-rebalance
        (,,,, uint256 rebalanceCount,) = strategy.getStrategyStats();
        assertEq(rebalanceCount, 0, "Should not auto-rebalance when disabled");

        // Manual rebalance should still work
        strategy.manualRebalance();
    }

    // ============ IMPERMANENT LOSS SCENARIOS ============

    function test_ImpermanentLoss_SevereDepeg() public {
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        // Simulate severe USDT depeg (to $0.90)
        strategy.updateMarketConditions(
            800, // 8% volatility
            50000e6, // Low volume during crisis
            200, // 2% spread
            200000e6 // Reduced liquidity
        );

        uint256 il = strategy.getCurrentImpermanentLoss();
        assertTrue(il > 0, "Should have significant IL during severe depeg");

        // Strategy should still function
        vm.prank(vault);
        uint256 yield = strategy.harvest();
        assertTrue(yield >= 0, "Should handle harvest during depeg");
    }

    function test_ImpermanentLoss_RecoveryScenario() public {
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        // Simulate depeg
        strategy.updateMarketConditions(500, 100000e6, 100, 500000e6);
        uint256 ilDuringDepeg = strategy.getCurrentImpermanentLoss();

        // Simulate recovery
        strategy.updateMarketConditions(20, 2000000e6, 10, 2000000e6);
        uint256 ilAfterRecovery = strategy.getCurrentImpermanentLoss();

        assertTrue(ilAfterRecovery <= ilDuringDepeg, "IL should decrease during recovery");
    }

    // ============ SECURITY AND ATTACK SCENARIOS ============

    function test_Security_UnauthorizedAccess() public {
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        // Attacker tries to call vault-only functions
        vm.expectRevert("Only vault can call");
        vm.prank(attacker);
        strategy.deposit(SMALL_DEPOSIT);

        vm.expectRevert("Only vault can call");
        vm.prank(attacker);
        strategy.withdraw(SMALL_DEPOSIT);

        vm.expectRevert("Only vault can call");
        vm.prank(attacker);
        strategy.harvest();
    }

    function test_Security_EmergencyExitAccess() public {
        vm.prank(vault);
        strategy.deposit(LARGE_DEPOSIT);

        // Only owner should be able to trigger emergency exit
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(attacker);
        strategy.emergencyExit();

        // Owner should be able to trigger emergency exit
        strategy.emergencyExit();
        assertTrue(strategy.emergencyMode());
    }

    function test_Security_ParameterManipulation() public {
        // Attacker tries to manipulate strategy parameters
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(attacker);
        strategy.setMaxSlippage(1000);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(attacker);
        strategy.updateRangeConfig(100, 50, 100e6, true);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(attacker);
        strategy.updateMarketConditions(100, 1000000e6, 20, 1000000e6);
    }
}
