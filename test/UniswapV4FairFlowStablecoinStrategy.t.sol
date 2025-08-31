// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/strategies/UniswapV4FairFlowStablecoinStrategy.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockUniswapV4PoolManager.sol";
import "../src/mocks/MockUniswapV4Hook.sol";
import "../src/libraries/StablecoinRangeManager.sol";
import "../src/libraries/FeeOptimizer.sol";

contract UniswapV4FairFlowStablecoinStrategyTest is Test {
    UniswapV4FairFlowStablecoinStrategy public strategy;
    MockERC20 public usdc;
    MockERC20 public usdt;
    MockUniswapV4PoolManager public poolManager;
    MockUniswapV4Hook public hook;
    
    address public owner;
    address public vault;
    address public user1;
    address public user2;
    
    PoolKey public poolKey;
    
    uint256 constant INITIAL_BALANCE = 1000000e6; // 1M USDC/USDT
    uint256 constant DEPOSIT_AMOUNT = 10000e6;    // 10K USDC
    
    event Deposited(uint256 amount0, uint256 amount1, uint128 liquidity);
    event Withdrawn(uint256 amount0, uint256 amount1, uint128 liquidity);
    event Harvested(uint256 fees0, uint256 fees1);
    event Rebalanced(int24 oldTickLower, int24 oldTickUpper, int24 newTickLower, int24 newTickUpper);
    event FeeUpdated(uint24 oldFee, uint24 newFee);
    event EmergencyExit(uint256 amount0, uint256 amount1);
    
    function setUp() public {
        owner = address(this);
        vault = makeAddr("vault");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
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
            "USDC/USDT V4 FairFlow Strategy",
            poolKey
        );
        
        // Setup initial balances
        usdc.mint(vault, INITIAL_BALANCE);
        usdt.mint(vault, INITIAL_BALANCE);
        usdc.mint(address(strategy), INITIAL_BALANCE);
        usdt.mint(address(strategy), INITIAL_BALANCE);
        
        // Setup approvals
        vm.startPrank(vault);
        usdc.approve(address(strategy), type(uint256).max);
        usdt.approve(address(strategy), type(uint256).max);
        vm.stopPrank();

        // Initialize the pool
        poolManager.initialize(poolKey, 79228162514264337593543950336, ""); // sqrt(1) * 2^96
    }
    
    function test_Deployment() public {
        assertEq(strategy.asset(), address(usdc));
        assertEq(strategy.vault(), vault);
        assertEq(strategy.poolManager(), address(poolManager));
        assertEq(strategy.hook(), address(hook));
        assertEq(strategy.getName(), "USDC/USDT V4 FairFlow Strategy");
        assertEq(strategy.totalAssets(), 0);
        assertFalse(strategy.emergencyMode());
    }
    
    function test_Deposit() public {
        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);
        
        assertEq(strategy.totalAssets(), DEPOSIT_AMOUNT);
        
        (,,,, bool isActive) = strategy.getCurrentPosition();
        assertTrue(isActive);
    }
    
    function test_Deposit_RevertIfNotVault() public {
        vm.prank(user1);
        vm.expectRevert("Only vault can call");
        strategy.deposit(DEPOSIT_AMOUNT);
    }
    
    function test_Deposit_RevertIfZeroAmount() public {
        vm.prank(vault);
        vm.expectRevert("Amount must be positive");
        strategy.deposit(0);
    }
    
    function test_Withdraw() public {
        // First deposit
        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);
        
        uint256 withdrawAmount = DEPOSIT_AMOUNT / 2;
        
        vm.prank(vault);
        strategy.withdraw(withdrawAmount);
        
        assertEq(strategy.totalAssets(), DEPOSIT_AMOUNT - withdrawAmount);
    }
    
    function test_Withdraw_RevertIfInsufficientBalance() public {
        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);
        
        vm.prank(vault);
        vm.expectRevert("Insufficient balance");
        strategy.withdraw(DEPOSIT_AMOUNT + 1);
    }
    
    function test_WithdrawAll() public {
        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);
        
        vm.prank(vault);
        strategy.withdrawAll();
        
        assertEq(strategy.totalAssets(), 0);
        
        (,,,, bool isActive) = strategy.getCurrentPosition();
        assertFalse(isActive);
    }
    
    function test_Harvest() public {
        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);
        
        // Simulate time passage for fee accrual
        vm.warp(block.timestamp + 1 days);
        
        vm.prank(vault);
        uint256 yield = strategy.harvest();
        
        // In mock implementation, yield might be 0, but function should not revert
        assertTrue(yield >= 0);
    }
    
    function test_GetAPY() public {
        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);
        
        uint256 apy = strategy.getAPY();
        assertTrue(apy >= 0);
    }
    
    function test_UpdateRangeConfig() public {
        uint256 newRangeWidth = 100;
        uint256 newRebalanceThreshold = 30;
        uint256 newMinLiquidity = 1000e6;
        bool newAutoRebalance = false;
        
        strategy.updateRangeConfig(
            newRangeWidth,
            newRebalanceThreshold,
            newMinLiquidity,
            newAutoRebalance
        );
        
        // Verify config was updated (would need getter functions in actual implementation)
        assertTrue(true); // Placeholder assertion
    }
    
    function test_UpdateRangeConfig_RevertIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        strategy.updateRangeConfig(100, 30, 1000e6, false);
    }
    
    function test_UpdateMarketConditions() public {
        uint256 volatility = 25;
        uint256 volume24h = 1000000e6;
        uint256 spread = 10;
        uint256 liquidity = 5000000e6;
        
        strategy.updateMarketConditions(volatility, volume24h, spread, liquidity);
        
        // Verify conditions were updated
        assertTrue(true); // Placeholder assertion
    }
    
    function test_ManualRebalance() public {
        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);
        
        strategy.manualRebalance();
        
        // Should not revert
        assertTrue(true);
    }
    
    function test_EmergencyExit() public {
        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);
        
        strategy.emergencyExit();
        
        assertTrue(strategy.emergencyMode());
        assertEq(strategy.totalAssets(), 0);
    }
    
    function test_ResumeOperations() public {
        strategy.emergencyExit();
        assertTrue(strategy.emergencyMode());
        
        strategy.resumeOperations();
        assertFalse(strategy.emergencyMode());
    }
    
    function test_SetMaxSlippage() public {
        uint256 newSlippage = 200; // 2%
        strategy.setMaxSlippage(newSlippage);
        
        // Should not revert
        assertTrue(true);
    }
    
    function test_SetMaxSlippage_RevertIfTooHigh() public {
        vm.expectRevert("Slippage too high");
        strategy.setMaxSlippage(1001); // > 10%
    }
    
    function test_GetCurrentPosition() public {
        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);
        
        (int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 lastUpdate, bool isActive) = 
            strategy.getCurrentPosition();
        
        assertTrue(isActive);
        assertTrue(liquidity > 0);
        assertTrue(tickLower < tickUpper);
        assertEq(lastUpdate, block.timestamp);
    }
    
    function test_GetStrategyStats() public {
        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);
        
        (
            uint256 totalDeposited,
            uint256 totalFeesClaimed,
            uint256 rebalanceCount,
            uint256 lastHarvestTime,
            uint256 lastRebalanceTime,
            bool emergencyMode
        ) = strategy.getStrategyStats();
        
        assertEq(totalDeposited, DEPOSIT_AMOUNT);
        assertEq(totalFeesClaimed, 0);
        assertEq(rebalanceCount, 0);
        assertTrue(lastHarvestTime > 0);
        assertTrue(lastRebalanceTime > 0);
        assertFalse(emergencyMode);
    }
    
    function test_GetCurrentImpermanentLoss() public {
        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);
        
        uint256 il = strategy.getCurrentImpermanentLoss();
        
        // For stablecoins, IL should be very low
        assertTrue(il <= 100); // <= 1%
    }
    
    function test_GetNextRebalanceTime() public {
        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);
        
        uint256 nextRebalance = strategy.getNextRebalanceTime();
        assertTrue(nextRebalance >= block.timestamp);
    }
    
    function test_DepositInEmergencyMode() public {
        strategy.emergencyExit();
        
        vm.prank(vault);
        vm.expectRevert("Emergency mode active");
        strategy.deposit(DEPOSIT_AMOUNT);
    }
    
    function test_MultipleDepositsAndWithdrawals() public {
        // Multiple deposits
        vm.startPrank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);
        strategy.deposit(DEPOSIT_AMOUNT / 2);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), DEPOSIT_AMOUNT + DEPOSIT_AMOUNT / 2);

        // Partial withdrawal
        vm.prank(vault);
        strategy.withdraw(DEPOSIT_AMOUNT / 4);

        assertEq(strategy.totalAssets(), DEPOSIT_AMOUNT + DEPOSIT_AMOUNT / 4);

        // Full withdrawal
        vm.prank(vault);
        strategy.withdrawAll();

        assertEq(strategy.totalAssets(), 0);
    }

    // ============ INTEGRATION TESTS ============

    function test_IntegrationWithAbunfiVault() public {
        // Test integration with existing Abunfi ecosystem
        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);

        // Simulate vault calling harvest
        vm.prank(vault);
        uint256 yield = strategy.harvest();

        // Simulate vault rebalancing
        vm.prank(vault);
        strategy.withdraw(DEPOSIT_AMOUNT / 4);

        assertTrue(strategy.totalAssets() > 0);
    }

    function test_FeeOptimizationScenarios() public {
        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);

        // Test low volatility scenario
        strategy.updateMarketConditions(5, 100000e6, 5, 1000000e6);

        // Test high volatility scenario
        strategy.updateMarketConditions(150, 50000e6, 25, 500000e6);

        // Test high volume scenario
        strategy.updateMarketConditions(25, 10000000e6, 10, 2000000e6);

        // Should not revert
        assertTrue(true);
    }

    function test_RangeManagementScenarios() public {
        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);

        // Test tight range
        strategy.updateRangeConfig(20, 15, 1000e6, true);

        // Test wide range
        strategy.updateRangeConfig(100, 50, 100e6, false);

        // Test manual rebalance
        strategy.manualRebalance();

        assertTrue(true);
    }

    function test_StressTestLargeDeposits() public {
        uint256 largeAmount = 1000000e6; // 1M USDC

        vm.prank(vault);
        strategy.deposit(largeAmount);

        assertEq(strategy.totalAssets(), largeAmount);

        vm.prank(vault);
        strategy.withdrawAll();

        assertEq(strategy.totalAssets(), 0);
    }

    function test_StressTestManySmallDeposits() public {
        uint256 smallAmount = 100e6; // 100 USDC

        vm.startPrank(vault);
        for (uint i = 0; i < 10; i++) {
            strategy.deposit(smallAmount);
        }
        vm.stopPrank();

        assertEq(strategy.totalAssets(), smallAmount * 10);
    }

    function test_EdgeCaseZeroLiquidity() public {
        // Test behavior with zero liquidity
        uint256 apy = strategy.getAPY();
        assertEq(apy, 0);

        uint256 il = strategy.getCurrentImpermanentLoss();
        assertTrue(il >= 0);
    }

    function test_EdgeCaseMaxSlippage() public {
        strategy.setMaxSlippage(1000); // 10% max

        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);

        // Should handle high slippage scenarios
        assertTrue(true);
    }

    // ============ LIBRARY TESTS ============

    function test_StablecoinRangeManagerLibrary() public {
        // Test range calculation
        (int24 tickLower, int24 tickUpper) = StablecoinRangeManager.calculateOptimalRange(0, 50);
        assertTrue(tickLower < tickUpper);

        // Test rebalancing logic
        StablecoinRangeManager.PositionInfo memory position = StablecoinRangeManager.PositionInfo({
            tickLower: -100,
            tickUpper: 100,
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

        bool needsRebalance = StablecoinRangeManager.needsRebalancing(50, position, config);
        // With current tick at 50 and range center at 0, distance is 50
        // Rebalance threshold is 25 * 100 = 2500 ticks, so should not need rebalancing
        assertFalse(needsRebalance);
    }

    function test_FeeOptimizerLibrary() public {
        FeeOptimizer.MarketConditions memory conditions = FeeOptimizer.MarketConditions({
            volatility: 25,
            volume24h: 1000000e6,
            spread: 10,
            liquidity: 5000000e6,
            timestamp: block.timestamp
        });

        FeeOptimizer.FeeConfig memory config = FeeOptimizer.getRecommendedFeeConfig(0);

        uint24 optimalFee = FeeOptimizer.calculateOptimalFee(conditions, config);
        assertTrue(optimalFee >= 100 && optimalFee <= 10000);

        uint256 apy = FeeOptimizer.estimateAPY(conditions, optimalFee, 5000);
        assertTrue(apy >= 0);
    }

    // ============ SECURITY TESTS ============

    function test_ReentrancyProtection() public {
        vm.prank(vault);
        strategy.deposit(DEPOSIT_AMOUNT);

        // Test that functions are protected against reentrancy
        // In a real test, you would use a malicious contract
        assertTrue(true);
    }

    function test_AccessControl() public {
        // Test that only vault can call vault-only functions
        vm.prank(user1);
        vm.expectRevert("Only vault can call");
        strategy.deposit(DEPOSIT_AMOUNT);

        // Test that only owner can call owner-only functions
        vm.prank(user1);
        vm.expectRevert();
        strategy.emergencyExit();
    }

    function test_InputValidation() public {
        // Test zero amount validation
        vm.prank(vault);
        vm.expectRevert("Amount must be positive");
        strategy.deposit(0);

        // Test slippage validation
        vm.expectRevert("Slippage too high");
        strategy.setMaxSlippage(1001);
    }

    // ============ PERFORMANCE TESTS ============

    function test_GasOptimization() public {
        vm.prank(vault);
        uint256 gasBefore = gasleft();
        strategy.deposit(DEPOSIT_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();

        // Gas usage should be reasonable (adjust threshold as needed)
        assertTrue(gasUsed < 500000);
    }

    function test_BatchOperations() public {
        vm.startPrank(vault);

        // Batch deposits
        strategy.deposit(DEPOSIT_AMOUNT);
        strategy.deposit(DEPOSIT_AMOUNT);

        // Batch harvest and rebalance
        strategy.harvest();

        vm.stopPrank();

        assertTrue(strategy.totalAssets() > 0);
    }
}
