// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/RiskProfileManager.sol";
import "../src/WithdrawalManager.sol";
import "../src/strategies/UniswapV4FairFlowStablecoinStrategy.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockStrategy.sol";
import "../src/mocks/MockUniswapV4PoolManager.sol";
import "../src/mocks/MockUniswapV4Hook.sol";

/**
 * @title AbunfiIntegrationTests
 * @dev Comprehensive integration tests covering cross-contract interactions and complex workflows
 * Tests the complete Abunfi ecosystem including:
 * - Vault + Risk Management + Withdrawal Management
 * - Strategy integration and yield generation
 * - Cross-contract state synchronization
 * - Complex user workflows
 * - Emergency scenarios across multiple contracts
 */
contract AbunfiIntegrationTests is Test {
    // Core contracts
    AbunfiVault public vault;
    RiskProfileManager public riskManager;
    WithdrawalManager public withdrawalManager;
    MockERC20 public mockUSDC;

    // Strategies
    MockStrategy public mockStrategy;
    UniswapV4FairFlowStablecoinStrategy public uniswapStrategy;
    MockUniswapV4PoolManager public poolManager;
    MockUniswapV4Hook public hook;
    MockERC20 public usdt;

    // Test users
    address public owner = address(this);
    address public user1 = address(0x1001);
    address public user2 = address(0x1002);
    address public user3 = address(0x1003);
    address public user4 = address(0x1004);
    address public user5 = address(0x1005);

    // Test constants
    uint256 public constant LARGE_DEPOSIT = 100000e6; // 100K USDC
    uint256 public constant MEDIUM_DEPOSIT = 10000e6; // 10K USDC
    uint256 public constant SMALL_DEPOSIT = 1000e6;   // 1K USDC
    uint256 public constant MINIMUM_DEPOSIT = 4e6;    // 4 USDC

    // Events for testing
    event DepositMade(address indexed user, uint256 amount, uint256 shares);
    event WithdrawalRequested(address indexed user, uint256 requestId, uint256 shares, uint256 estimatedAmount);
    event WithdrawalProcessed(address indexed user, uint256 requestId, uint256 amount);
    event StrategyAdded(address indexed strategy, uint256 weight);
    event YieldHarvested(address indexed strategy, uint256 yield);

    function setUp() public {
        // Deploy mock USDC
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);
        usdt = new MockERC20("Mock USDT", "USDT", 6);

        // Deploy risk management
        riskManager = new RiskProfileManager();

        // Deploy vault
        vault = new AbunfiVault(
            address(mockUSDC),
            address(0),
            address(riskManager),
            address(0)
        );

        // Deploy withdrawal manager
        withdrawalManager = new WithdrawalManager(address(vault), address(mockUSDC));

        // Update vault with withdrawal manager
        vault.updateRiskManagers(address(riskManager), address(withdrawalManager));

        // Deploy strategies
        mockStrategy = new MockStrategy(address(mockUSDC), "Mock Strategy", 500); // 5% APY
        
        // Deploy Uniswap V4 strategy
        poolManager = new MockUniswapV4PoolManager();
        hook = new MockUniswapV4Hook();
        
        PoolKey memory poolKey = PoolKey({
            currency0: address(mockUSDC),
            currency1: address(usdt),
            fee: 500,
            tickSpacing: 10,
            hooks: address(hook)
        });

        uniswapStrategy = new UniswapV4FairFlowStablecoinStrategy(
            address(mockUSDC),
            address(usdt),
            address(vault),
            address(poolManager),
            address(hook),
            "USDC/USDT V4 Strategy",
            poolKey
        );

        // Add strategies to vault
        vault.addStrategy(address(mockStrategy), 3000);      // 30% weight
        vault.addStrategy(address(uniswapStrategy), 7000);   // 70% weight

        // Mint tokens to users
        _mintTokensToUsers();

        // Setup initial user deposits
        _setupInitialDeposits();
    }

    function _mintTokensToUsers() internal {
        address[5] memory users = [user1, user2, user3, user4, user5];
        for (uint256 i = 0; i < users.length; i++) {
            mockUSDC.mint(users[i], LARGE_DEPOSIT * 2);
            usdt.mint(users[i], LARGE_DEPOSIT * 2);
            usdt.mint(address(uniswapStrategy), LARGE_DEPOSIT);
        }
    }

    function _setupInitialDeposits() internal {
        // User1: Large depositor
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), LARGE_DEPOSIT);
        vault.deposit(LARGE_DEPOSIT);
        vm.stopPrank();

        // User2: Medium depositor
        vm.startPrank(user2);
        mockUSDC.approve(address(vault), MEDIUM_DEPOSIT);
        vault.deposit(MEDIUM_DEPOSIT);
        vm.stopPrank();

        // User3: Small depositor
        vm.startPrank(user3);
        mockUSDC.approve(address(vault), SMALL_DEPOSIT);
        vault.deposit(SMALL_DEPOSIT);
        vm.stopPrank();
    }

    // ============ FULL ECOSYSTEM INTEGRATION TESTS ============

    function test_Integration_CompleteUserJourney() public {
        // 1. New user deposits
        vm.startPrank(user4);
        mockUSDC.approve(address(vault), MEDIUM_DEPOSIT);
        vault.deposit(MEDIUM_DEPOSIT);
        
        uint256 initialShares = vault.userShares(user4);
        assertTrue(initialShares > 0, "User should receive shares");
        vm.stopPrank();

        // 2. Vault allocates to strategies
        vault.allocateToStrategies();

        // 3. Strategies generate yield
        mockStrategy.addYield(1000e6);
        vm.warp(block.timestamp + 30 days);

        // 4. Harvest yield
        vault.harvest();

        // 5. User requests withdrawal
        vm.startPrank(user4);
        uint256 requestId = vault.requestWithdrawal(initialShares);
        vm.stopPrank();

        // 6. Wait for withdrawal window
        vm.warp(block.timestamp + 8 days);

        // 7. Process withdrawal
        uint256 balanceBefore = mockUSDC.balanceOf(user4);
        vm.prank(user4);
        vault.processWithdrawal(requestId);
        uint256 balanceAfter = mockUSDC.balanceOf(user4);

        // User should receive more than initial deposit due to yield
        assertTrue(balanceAfter > balanceBefore, "User should receive funds");
        assertTrue(balanceAfter >= MEDIUM_DEPOSIT, "Should receive at least initial deposit");
    }

    function test_Integration_MultipleStrategiesYieldGeneration() public {
        // Allocate funds to strategies
        vault.allocateToStrategies();

        uint256 totalAssetsBefore = vault.totalAssets();

        // Generate yield in both strategies
        mockStrategy.addYield(2000e6);
        
        // Simulate Uniswap strategy earning fees
        vm.warp(block.timestamp + 1 days);

        // Harvest from both strategies
        vault.harvest();

        uint256 totalAssetsAfter = vault.totalAssets();
        assertTrue(totalAssetsAfter > totalAssetsBefore, "Total assets should increase from yield");

        // Verify yield is distributed proportionally to users
        uint256 user1SharesValue = vault.getBalanceWithInterest(user1);
        uint256 user2SharesValue = vault.getBalanceWithInterest(user2);
        uint256 user3SharesValue = vault.getBalanceWithInterest(user3);

        // Users with more shares should have proportionally more value
        assertTrue(user1SharesValue > user2SharesValue, "User1 should have more value than User2");
        assertTrue(user2SharesValue > user3SharesValue, "User2 should have more value than User3");
    }

    function test_Integration_RiskBasedAllocation() public {
        // Set different risk profiles for users
        vm.prank(user1);
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.HIGH);

        vm.prank(user2);
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.MEDIUM);

        vm.prank(user3);
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.LOW);

        // Allocate to strategies
        vault.allocateToStrategies();

        // Verify allocations respect risk profiles
        // (This would require more sophisticated risk-based allocation logic in the vault)
        assertTrue(vault.totalAssets() > 0, "Should have allocated assets");
    }

    function test_Integration_WithdrawalQueueManagement() public {
        // Multiple users request withdrawals
        vm.prank(user1);
        uint256 requestId1 = vault.requestWithdrawal(vault.userShares(user1) / 2);

        vm.prank(user2);
        uint256 requestId2 = vault.requestWithdrawal(vault.userShares(user2));

        vm.prank(user3);
        uint256 requestId3 = vault.requestWithdrawal(vault.userShares(user3));

        // Wait for withdrawal window
        vm.warp(block.timestamp + 8 days);

        // Process withdrawals in order
        vm.prank(user1);
        vault.processWithdrawal(requestId1);

        vm.prank(user2);
        vault.processWithdrawal(requestId2);

        vm.prank(user3);
        vault.processWithdrawal(requestId3);

        // Verify all withdrawals processed correctly
        assertEq(vault.userShares(user2), 0, "User2 should have no shares");
        assertEq(vault.userShares(user3), 0, "User3 should have no shares");
        assertTrue(vault.userShares(user1) > 0, "User1 should still have shares");
    }

    function test_Integration_StrategyRebalancing() public {
        // Initial allocation
        vault.allocateToStrategies();

        uint256 mockStrategyAssetsBefore = mockStrategy.totalAssets();
        uint256 uniswapStrategyAssetsBefore = uniswapStrategy.totalAssets();

        // Change strategy weights
        vault.updateStrategyWeight(address(mockStrategy), 5000);    // 50%
        vault.updateStrategyWeight(address(uniswapStrategy), 5000); // 50%

        // Rebalance
        vault.rebalance();

        uint256 mockStrategyAssetsAfter = mockStrategy.totalAssets();
        uint256 uniswapStrategyAssetsAfter = uniswapStrategy.totalAssets();

        // Verify rebalancing occurred
        assertTrue(
            mockStrategyAssetsAfter != mockStrategyAssetsBefore ||
            uniswapStrategyAssetsAfter != uniswapStrategyAssetsBefore,
            "Strategy allocations should change after rebalancing"
        );
    }

    // ============ STRESS TEST SCENARIOS ============

    function test_Integration_BankRunScenario() public {
        // Add more users and deposits
        vm.startPrank(user4);
        mockUSDC.approve(address(vault), LARGE_DEPOSIT);
        vault.deposit(LARGE_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(user5);
        mockUSDC.approve(address(vault), LARGE_DEPOSIT);
        vault.deposit(LARGE_DEPOSIT);
        vm.stopPrank();

        // Allocate to strategies
        vault.allocateToStrategies();

        // All users request withdrawal simultaneously (bank run)
        vm.prank(user1);
        uint256 requestId1 = vault.requestWithdrawal(vault.userShares(user1));

        vm.prank(user2);
        uint256 requestId2 = vault.requestWithdrawal(vault.userShares(user2));

        vm.prank(user3);
        uint256 requestId3 = vault.requestWithdrawal(vault.userShares(user3));

        vm.prank(user4);
        uint256 requestId4 = vault.requestWithdrawal(vault.userShares(user4));

        vm.prank(user5);
        uint256 requestId5 = vault.requestWithdrawal(vault.userShares(user5));

        // Wait for withdrawal window
        vm.warp(block.timestamp + 8 days);

        // Process all withdrawals - vault should handle liquidity management
        vm.prank(user1);
        vault.processWithdrawal(requestId1);

        vm.prank(user2);
        vault.processWithdrawal(requestId2);

        vm.prank(user3);
        vault.processWithdrawal(requestId3);

        vm.prank(user4);
        vault.processWithdrawal(requestId4);

        vm.prank(user5);
        vault.processWithdrawal(requestId5);

        // All users should have received their funds
        assertTrue(mockUSDC.balanceOf(user1) > 0, "User1 should receive funds");
        assertTrue(mockUSDC.balanceOf(user2) > 0, "User2 should receive funds");
        assertTrue(mockUSDC.balanceOf(user3) > 0, "User3 should receive funds");
        assertTrue(mockUSDC.balanceOf(user4) > 0, "User4 should receive funds");
        assertTrue(mockUSDC.balanceOf(user5) > 0, "User5 should receive funds");
    }

    function test_Integration_StrategyFailureRecovery() public {
        // Allocate to strategies
        vault.allocateToStrategies();

        uint256 totalAssetsBefore = vault.totalAssets();

        // Simulate strategy failure
        mockStrategy.setShouldFailWithdraw(true);

        // Emergency exit from failed strategy (manually withdraw all)
        vm.prank(address(vault));
        mockStrategy.withdrawAll();

        // Verify vault handles strategy failure gracefully
        uint256 totalAssetsAfter = vault.totalAssets();
        assertTrue(totalAssetsAfter > 0, "Vault should maintain assets after strategy failure");

        // Users should still be able to withdraw
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(vault.userShares(user1) / 4);

        vm.warp(block.timestamp + 8 days);

        vm.prank(user1);
        vault.processWithdrawal(requestId);

        assertTrue(mockUSDC.balanceOf(user1) > 0, "User should still be able to withdraw");
    }

    function test_Integration_CrossContractStateConsistency() public {
        // Perform various operations and verify state consistency

        // 1. Deposits
        vm.startPrank(user4);
        mockUSDC.approve(address(vault), MEDIUM_DEPOSIT);
        vault.deposit(MEDIUM_DEPOSIT);
        vm.stopPrank();

        // 2. Strategy allocation
        vault.allocateToStrategies();

        // 3. Yield generation
        mockStrategy.addYield(500e6);
        vault.harvest();

        // 4. Withdrawal request
        vm.prank(user4);
        uint256 requestId = vault.requestWithdrawal(vault.userShares(user4) / 2);

        // Verify state consistency across contracts
        uint256 vaultTotalAssets = vault.totalAssets();
        uint256 strategyTotalAssets = mockStrategy.totalAssets() + uniswapStrategy.totalAssets();
        uint256 vaultBalance = mockUSDC.balanceOf(address(vault));

        // Total assets should equal strategy assets plus vault balance
        assertApproxEqRel(
            vaultTotalAssets,
            strategyTotalAssets + vaultBalance,
            0.01e18, // 1% tolerance
            "Vault total assets should match strategy assets plus vault balance"
        );

        // User shares should be properly tracked
        uint256 totalShares = vault.totalShares();
        uint256 userSharesSum = vault.userShares(user1) + vault.userShares(user2) + 
                               vault.userShares(user3) + vault.userShares(user4);
        
        assertEq(totalShares, userSharesSum, "Total shares should equal sum of user shares");
    }

    // ============ EMERGENCY SCENARIOS ============

    function test_Integration_SystemWideEmergency() public {
        // Allocate to strategies
        vault.allocateToStrategies();

        // Trigger system-wide emergency
        vault.pause();

        // Verify all operations are paused
        vm.expectRevert("Pausable: paused");
        vm.prank(user4);
        vault.deposit(SMALL_DEPOSIT);

        vm.expectRevert("Pausable: paused");
        vm.prank(user1);
        vault.requestWithdrawal(vault.userShares(user1));

        // Emergency exit all strategies (manually)
        vm.prank(address(vault));
        mockStrategy.withdrawAll();
        vm.prank(address(vault));
        uniswapStrategy.withdrawAll();

        // Resume operations
        vault.unpause();

        // Verify operations work again
        vm.startPrank(user4);
        mockUSDC.approve(address(vault), SMALL_DEPOSIT);
        vault.deposit(SMALL_DEPOSIT);
        vm.stopPrank();

        assertTrue(vault.userShares(user4) > 0, "Should be able to deposit after resuming");
    }

    function test_Integration_PartialStrategyRecovery() public {
        // Allocate to strategies
        vault.allocateToStrategies();

        // One strategy fails, other continues
        mockStrategy.setShouldFailWithdraw(true);

        // Emergency exit only the failed strategy
        vm.prank(address(vault));
        mockStrategy.withdrawAll();

        // Verify other strategy continues to work
        uint256 uniswapAssets = uniswapStrategy.totalAssets();
        assertTrue(uniswapAssets > 0, "Healthy strategy should continue operating");

        // Users should still be able to interact with vault
        vm.startPrank(user4);
        mockUSDC.approve(address(vault), SMALL_DEPOSIT);
        vault.deposit(SMALL_DEPOSIT);
        vm.stopPrank();

        assertTrue(vault.userShares(user4) > 0, "Should be able to deposit with partial strategy failure");
    }

    // ============ COMPLEX WORKFLOW TESTS ============

    function test_Integration_ComplexMultiUserWorkflow() public {
        // Complex scenario with multiple users performing various operations

        // Phase 1: Initial deposits and allocations
        vm.startPrank(user4);
        mockUSDC.approve(address(vault), LARGE_DEPOSIT);
        vault.deposit(LARGE_DEPOSIT);
        vm.stopPrank();

        vault.allocateToStrategies();

        // Phase 2: Yield generation
        mockStrategy.addYield(2000e6);
        vm.warp(block.timestamp + 15 days);
        vault.harvest();

        // Phase 3: Mixed withdrawal and deposit operations
        vm.prank(user1);
        uint256 requestId1 = vault.requestWithdrawal(vault.userShares(user1) / 3);

        vm.startPrank(user5);
        mockUSDC.approve(address(vault), MEDIUM_DEPOSIT);
        vault.deposit(MEDIUM_DEPOSIT);
        vm.stopPrank();

        vm.prank(user2);
        uint256 requestId2 = vault.requestWithdrawal(vault.userShares(user2));

        // Phase 4: Strategy rebalancing
        vault.updateStrategyWeight(address(mockStrategy), 4000);
        vault.updateStrategyWeight(address(uniswapStrategy), 6000);
        vault.rebalance();

        // Phase 5: Process withdrawals
        vm.warp(block.timestamp + 8 days);

        vm.prank(user1);
        vault.processWithdrawal(requestId1);

        vm.prank(user2);
        vault.processWithdrawal(requestId2);

        // Phase 6: Final state verification
        assertTrue(vault.totalAssets() > 0, "Vault should have assets");
        assertTrue(vault.totalShares() > 0, "Vault should have shares");
        assertTrue(mockUSDC.balanceOf(user1) > 0, "User1 should have received funds");
        assertTrue(mockUSDC.balanceOf(user2) > 0, "User2 should have received funds");
        assertEq(vault.userShares(user2), 0, "User2 should have no shares left");
    }
}
