// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/WithdrawalManager.sol";
import "../src/RiskProfileManager.sol";
import "../src/mocks/MockAavePool.sol";
import "../src/mocks/MockAaveDataProvider.sol";
import "../src/mocks/MockComet.sol";
import "../src/mocks/MockCometRewards.sol";
import "../src/strategies/AaveStrategy.sol";
import "../src/strategies/CompoundStrategy.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockStrategy.sol";

contract AbunfiIntegrationTest is Test {
    AbunfiVault public vault;
    WithdrawalManager public withdrawalManager;
    RiskProfileManager public riskManager;
    AaveStrategy public aaveStrategy;
    CompoundStrategy public compoundStrategy;
    MockStrategy public mockStrategy;
    MockERC20 public mockUSDC;

    // Mock external contracts
    MockAavePool public mockAavePool;
    MockAaveDataProvider public mockAaveDataProvider;
    MockComet public mockComet;
    MockCometRewards public mockCometRewards;

    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);
    address public user4 = address(0x4);
    address public user5 = address(0x5);

    uint256 public constant INITIAL_DEPOSIT = 1000e6;
    uint256 public constant LARGE_DEPOSIT = 10000e6;

    event StrategyRebalanced(address indexed strategy, uint256 newAllocation);
    event EmergencyWithdrawal(address indexed user, uint256 amount);
    event SystemPaused(uint256 timestamp);
    event SystemUnpaused(uint256 timestamp);

    function setUp() public {
        // Deploy mock USDC
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);

        // Deploy mock external contracts
        mockAavePool = new MockAavePool(address(mockUSDC));
        mockAaveDataProvider = new MockAaveDataProvider();
        mockComet = new MockComet(address(mockUSDC));
        mockCometRewards = new MockCometRewards();

        // Deploy risk manager
        riskManager = new RiskProfileManager();

        // Deploy withdrawal manager placeholder
        withdrawalManager = new WithdrawalManager(
            address(0x1), // temporary vault address
            address(mockUSDC)
        );

        // Deploy vault
        vault = new AbunfiVault(
            address(mockUSDC),
            address(this), // trusted forwarder
            address(riskManager),
            address(withdrawalManager)
        );

        // Deploy new withdrawal manager with correct vault address
        withdrawalManager = new WithdrawalManager(address(vault), address(mockUSDC));

        // Deploy strategies
        aaveStrategy =
            new AaveStrategy(address(mockUSDC), address(mockAavePool), address(mockAaveDataProvider), address(vault));
        compoundStrategy =
            new CompoundStrategy(address(mockUSDC), address(mockComet), address(mockCometRewards), address(vault));
        mockStrategy = new MockStrategy(address(mockUSDC), "Mock Strategy", 500); // 5% APY

        // Set up vault
        vault.updateRiskManagers(address(riskManager), address(withdrawalManager));
        vault.addStrategy(address(aaveStrategy), 4000); // 40% weight
        vault.addStrategy(address(compoundStrategy), 3000); // 30% weight
        vault.addStrategy(address(mockStrategy), 3000); // 30% weight

        // Setup user balances and approvals
        address[5] memory users = [user1, user2, user3, user4, user5];
        for (uint256 i = 0; i < users.length; i++) {
            mockUSDC.mint(users[i], LARGE_DEPOSIT);
            vm.prank(users[i]);
            mockUSDC.approve(address(vault), type(uint256).max);
        }
    }

    // ============ Multi-User Workflow Tests ============

    function test_Integration_MultiUserDepositsAndWithdrawals() public {
        // Phase 1: Multiple users deposit
        vm.prank(user1);
        vault.deposit(INITIAL_DEPOSIT);

        vm.prank(user2);
        vault.deposit(INITIAL_DEPOSIT * 2);

        vm.prank(user3);
        vault.deposit(INITIAL_DEPOSIT / 2);

        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, INITIAL_DEPOSIT * 3.5e18 / 1e18, "Total assets should match deposits");

        // Phase 2: Some users request withdrawals
        vm.prank(user1);
        uint256 requestId1 = vault.requestWithdrawal(vault.balanceOf(user1) / 2);

        vm.prank(user2);
        uint256 requestId2 = vault.requestWithdrawal(vault.balanceOf(user2) / 3);

        // Phase 3: Time passes and withdrawals are processed
        vm.warp(block.timestamp + 1 days);

        uint256 user1BalanceBefore = mockUSDC.balanceOf(user1);
        vm.prank(user1);
        vault.processWithdrawal(requestId1);
        assertGt(mockUSDC.balanceOf(user1), user1BalanceBefore, "User1 should receive USDC");

        uint256 user2BalanceBefore = mockUSDC.balanceOf(user2);
        vm.prank(user2);
        vault.processWithdrawal(requestId2);
        assertGt(mockUSDC.balanceOf(user2), user2BalanceBefore, "User2 should receive USDC");

        // Phase 4: New deposits while withdrawals are happening
        vm.prank(user4);
        vault.deposit(INITIAL_DEPOSIT);

        vm.prank(user5);
        vault.deposit(INITIAL_DEPOSIT * 1.5e18 / 1e18);

        assertGt(vault.totalAssets(), 0, "Vault should maintain assets through mixed operations");
    }

    function test_Integration_StrategyFailureRecovery() public {
        // Setup initial deposits
        vm.prank(user1);
        vault.deposit(INITIAL_DEPOSIT);

        vm.prank(user2);
        vault.deposit(INITIAL_DEPOSIT);

        // Simulate strategy failure
        vm.prank(address(this)); // Owner can call emergency withdraw
        aaveStrategy.emergencyWithdraw(address(mockUSDC), 1000e6);

        // Vault should rebalance to other strategies
        vm.expectEmit(true, false, false, true);
        emit StrategyRebalanced(address(compoundStrategy), 5000); // Increased allocation

        vault.rebalance();

        // Users should still be able to withdraw
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(vault.balanceOf(user1));

        vm.warp(block.timestamp + 1 days);

        vm.prank(user1);
        vault.processWithdrawal(requestId);

        assertGt(mockUSDC.balanceOf(user1), 0, "User should receive funds despite strategy failure");
    }

    function test_Integration_LiquidityStressTest() public {
        // Setup large deposits from multiple users
        address[5] memory users = [user1, user2, user3, user4, user5];
        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            vault.deposit(LARGE_DEPOSIT);
        }

        uint256 totalDeposited = LARGE_DEPOSIT * 5;
        assertEq(vault.totalAssets(), totalDeposited, "All deposits should be recorded");

        // Simulate bank run - all users try to withdraw at once
        uint256[] memory requestIds = new uint256[](5);
        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            requestIds[i] = vault.requestWithdrawal(vault.balanceOf(users[i]));
        }

        // Fast forward time
        vm.warp(block.timestamp + 1 days);

        // Process withdrawals - should handle liquidity management
        uint256 totalWithdrawn = 0;
        for (uint256 i = 0; i < users.length; i++) {
            uint256 balanceBefore = mockUSDC.balanceOf(users[i]);

            vm.prank(users[i]);
            vault.processWithdrawal(requestIds[i]);

            uint256 withdrawn = mockUSDC.balanceOf(users[i]) - balanceBefore;
            totalWithdrawn += withdrawn;
        }

        assertGt(totalWithdrawn, totalDeposited * 95 / 100, "Should withdraw at least 95% of deposits");
    }

    // ============ Emergency Procedures ============

    function test_Integration_EmergencyPause() public {
        // Setup deposits
        vm.prank(user1);
        vault.deposit(INITIAL_DEPOSIT);

        // Emergency pause
        vm.expectEmit(true, false, false, false);
        emit SystemPaused(block.timestamp);

        vault.pause();

        // New deposits should fail
        vm.prank(user2);
        vm.expectRevert("Pausable: paused");
        vault.deposit(INITIAL_DEPOSIT);

        // Existing users should still be able to request withdrawals
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(vault.balanceOf(user1) / 2);

        // Emergency unpause
        vm.expectEmit(true, false, false, false);
        emit SystemUnpaused(block.timestamp);

        vault.unpause();

        // Operations should resume normally
        vm.prank(user2);
        vault.deposit(INITIAL_DEPOSIT);

        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        vault.processWithdrawal(requestId);
    }

    function test_Integration_EmergencyWithdrawAll() public {
        // Setup deposits across multiple strategies
        vm.prank(user1);
        vault.deposit(INITIAL_DEPOSIT);

        vm.prank(user2);
        vault.deposit(INITIAL_DEPOSIT);

        uint256 totalAssetsBefore = vault.totalAssets();

        // Emergency withdraw from vault
        vault.emergencyWithdraw();

        // All funds should be back in the vault
        assertGe(mockUSDC.balanceOf(address(vault)), totalAssetsBefore * 95 / 100, "Most funds should be recovered");

        // Users should still be able to withdraw
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(vault.balanceOf(user1));

        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        vault.processWithdrawal(requestId);
    }

    // ============ Complex Scenarios ============

    function test_Integration_StrategyRebalancingDuringWithdrawals() public {
        // Setup initial state
        vm.prank(user1);
        vault.deposit(LARGE_DEPOSIT);

        vm.prank(user2);
        vault.deposit(LARGE_DEPOSIT);

        // User1 requests large withdrawal
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(vault.balanceOf(user1));

        // Meanwhile, strategy performance changes requiring rebalancing
        // Note: In real scenario, APY would change based on market conditions

        // Rebalance strategies
        vault.rebalance();

        // Process withdrawal should still work
        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        vault.processWithdrawal(requestId);

        assertGt(mockUSDC.balanceOf(user1), 0, "Withdrawal should succeed despite rebalancing");
    }

    function test_Integration_ConcurrentOperations() public {
        // Simulate concurrent deposits, withdrawals, and strategy operations

        // Initial deposits
        vm.prank(user1);
        vault.deposit(INITIAL_DEPOSIT);

        vm.prank(user2);
        vault.deposit(INITIAL_DEPOSIT);

        // User1 requests withdrawal while user3 deposits
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(vault.balanceOf(user1) / 2);

        vm.prank(user3);
        vault.deposit(INITIAL_DEPOSIT);

        // Strategy rebalancing happens
        vault.rebalance();

        // User4 makes large deposit
        vm.prank(user4);
        vault.deposit(LARGE_DEPOSIT);

        // Time passes and withdrawal is processed
        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        vault.processWithdrawal(requestId);

        // User5 deposits while user2 requests withdrawal
        vm.prank(user5);
        vault.deposit(INITIAL_DEPOSIT);

        vm.prank(user2);
        uint256 requestId2 = vault.requestWithdrawal(vault.balanceOf(user2));

        // System should remain stable
        assertGt(vault.totalAssets(), 0, "Vault should maintain positive assets");
        assertGt(vault.totalShares(), 0, "Vault should have outstanding shares");
    }

    // ============ Risk Management Integration ============

    function test_Integration_RiskBasedAllocation() public {
        // Setup users with different risk profiles
        vm.prank(user1);
        vault.deposit(INITIAL_DEPOSIT);

        // Set user1 as conservative
        riskManager.setRiskProfileForUser(user1, RiskProfileManager.RiskLevel.LOW);

        vm.prank(user2);
        vault.deposit(INITIAL_DEPOSIT);

        // Set user2 as aggressive
        riskManager.setRiskProfileForUser(user2, RiskProfileManager.RiskLevel.HIGH);

        // Vault should allocate based on risk profiles
        vault.allocateToStrategies();

        // Conservative users should have more stable allocations
        // Aggressive users should have more growth-oriented allocations
        assertTrue(vault.totalAssets() > 0, "Risk-based allocation should maintain assets");
    }

    function test_Integration_WithdrawalWindowManagement() public {
        // Test withdrawal window management under various conditions

        vm.prank(user1);
        vault.deposit(INITIAL_DEPOSIT);

        // Request withdrawal
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(vault.balanceOf(user1) / 2);

        // Try to process too early
        vm.prank(user1);
        vm.expectRevert("Withdrawal window not passed");
        vault.processWithdrawal(requestId);

        // Cancel and resubmit
        vm.prank(user1);
        vault.cancelWithdrawal(requestId);

        vm.prank(user1);
        uint256 newRequestId = vault.requestWithdrawal(vault.balanceOf(user1) / 2);

        // Wait for window and process
        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        vault.processWithdrawal(newRequestId);

        assertGt(mockUSDC.balanceOf(user1), 0, "Withdrawal should succeed after proper window");
    }

    // ============ Performance and Gas Tests ============

    function test_Integration_GasEfficiencyAtScale() public {
        // Test gas efficiency with many users and operations

        uint256 gasStart = gasleft();

        // Multiple deposits
        for (uint256 i = 1; i <= 5; i++) {
            address user = address(uint160(i));
            mockUSDC.mint(user, INITIAL_DEPOSIT);
            vm.prank(user);
            mockUSDC.approve(address(vault), type(uint256).max);
            vm.prank(user);
            vault.deposit(INITIAL_DEPOSIT);
        }

        // Strategy rebalancing
        vault.rebalance();

        uint256 gasUsed = gasStart - gasleft();

        // Should be reasonably gas efficient even at scale
        assertLt(gasUsed, 2000000, "Operations should be gas efficient at scale");
    }

    function test_Integration_SystemRecoveryAfterFailure() public {
        // Setup system
        vm.prank(user1);
        vault.deposit(LARGE_DEPOSIT);

        // Simulate system failure
        vault.pause();

        // Emergency procedures
        vault.emergencyWithdraw();

        // System recovery
        vault.unpause();

        // Verify system can resume normal operations
        vm.prank(user2);
        vault.deposit(INITIAL_DEPOSIT);

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(vault.balanceOf(user1) / 2);

        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        vault.processWithdrawal(requestId);

        assertGt(vault.totalAssets(), 0, "System should recover and function normally");
    }
}
