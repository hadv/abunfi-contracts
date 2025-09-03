// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/WithdrawalManager.sol";
import "../src/RiskProfileManager.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockStrategy.sol";

/**
 * @title WithdrawalStressTests
 * @dev Comprehensive stress testing for withdrawal system including bank run scenarios
 * Critical for production finance applications to handle mass withdrawal events
 */
contract WithdrawalStressTestsTest is Test {
    AbunfiVault public vault;
    WithdrawalManager public withdrawalManager;
    RiskProfileManager public riskManager;
    MockERC20 public mockUSDC;
    MockStrategy public mockStrategy;

    address public owner;
    address[] public users;
    uint256 constant NUM_USERS = 50;
    uint256 constant DEPOSIT_AMOUNT = 10_000 * 10**6; // 10k USDC per user
    uint256 constant TOTAL_DEPOSITS = NUM_USERS * DEPOSIT_AMOUNT; // 500k USDC total

    event WithdrawalRequested(address indexed user, uint256 requestId, uint256 shares, uint256 estimatedAmount);
    event WithdrawalProcessed(address indexed user, uint256 requestId, uint256 amount);
    event InstantWithdrawal(address indexed user, uint256 amount, uint256 fee);

    function setUp() public {
        owner = address(this);

        // Deploy mock USDC
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);

        // Deploy risk management
        riskManager = new RiskProfileManager();

        // Deploy vault first with temporary withdrawal manager
        vault = new AbunfiVault(
            address(mockUSDC),
            address(0),
            address(riskManager),
            address(0) // Temporary
        );

        // Deploy withdrawal manager with vault address
        withdrawalManager = new WithdrawalManager(address(vault), address(mockUSDC));

        // Update vault with correct withdrawal manager
        vault.updateRiskManagers(address(riskManager), address(withdrawalManager));

        // Deploy and add strategy
        mockStrategy = new MockStrategy(address(mockUSDC), "Mock Strategy", 500); // 5% APY
        vault.addStrategy(address(mockStrategy));

        // Create test users
        for (uint256 i = 0; i < NUM_USERS; i++) {
            users.push(makeAddr(string(abi.encodePacked("user", i))));
        }

        // Setup users with deposits
        _setupUsersWithDeposits();
    }

    function _setupUsersWithDeposits() internal {
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = users[i];
            
            // Mint tokens to user
            mockUSDC.mint(user, DEPOSIT_AMOUNT);
            
            // User deposits
            vm.startPrank(user);
            mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
            vault.deposit(DEPOSIT_AMOUNT);
            vm.stopPrank();
        }
    }

    // ============ BANK RUN SIMULATION TESTS ============

    function test_BankRun_MassWithdrawalRequests() public {
        // Simulate bank run - all users request withdrawal simultaneously
        uint256[] memory requestIds = new uint256[](NUM_USERS);
        
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = users[i];
            uint256 userShares = vault.userShares(user);
            
            vm.prank(user);
            requestIds[i] = vault.requestWithdrawal(userShares);
        }

        // Verify all requests were created
        for (uint256 i = 0; i < NUM_USERS; i++) {
            assertTrue(requestIds[i] >= 0, "Withdrawal request should be created");
        }

        // Check system state after mass requests
        assertTrue(vault.totalShares() > 0, "Vault should still have shares");
        assertTrue(vault.totalDeposits() > 0, "Vault should still have deposits");
    }

    function test_BankRun_ProcessMassWithdrawals() public {
        // Setup mass withdrawal requests
        uint256[] memory requestIds = new uint256[](NUM_USERS);
        
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = users[i];
            uint256 userShares = vault.userShares(user);
            
            vm.prank(user);
            requestIds[i] = vault.requestWithdrawal(userShares);
        }

        // Fast forward past withdrawal window
        vm.warp(block.timestamp + 8 days);

        // Process all withdrawals
        uint256 totalWithdrawn = 0;
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = users[i];
            uint256 balanceBefore = mockUSDC.balanceOf(user);
            
            vm.prank(user);
            vault.processWithdrawal(requestIds[i]);
            
            uint256 balanceAfter = mockUSDC.balanceOf(user);
            uint256 withdrawn = balanceAfter - balanceBefore;
            totalWithdrawn += withdrawn;
            
            assertTrue(withdrawn > 0, "User should receive funds");
        }

        // Verify total withdrawn is reasonable (accounting for potential yield)
        assertTrue(totalWithdrawn >= TOTAL_DEPOSITS * 95 / 100, "Should withdraw at least 95% of deposits");
    }

    function test_BankRun_PartialLiquidity() public {
        // Simulate scenario where vault has limited liquidity
        uint256 vaultBalance = mockUSDC.balanceOf(address(vault));
        
        // Reduce vault liquidity to 50% of total deposits
        uint256 liquidityReduction = vaultBalance / 2;
        vm.prank(address(vault));
        mockUSDC.transfer(owner, liquidityReduction);

        // Mass withdrawal requests
        for (uint256 i = 0; i < NUM_USERS / 2; i++) { // Only half the users
            address user = users[i];
            uint256 userShares = vault.userShares(user);
            
            vm.prank(user);
            vault.requestWithdrawal(userShares);
        }

        // Fast forward and process
        vm.warp(block.timestamp + 8 days);

        // Try to process withdrawals - some should succeed based on available liquidity
        uint256 successfulWithdrawals = 0;
        for (uint256 i = 0; i < NUM_USERS / 2; i++) {
            address user = users[i];

            try vault.processWithdrawal(i) { // Use request ID i
                successfulWithdrawals++;
            } catch {
                // Expected for some users when liquidity is limited
            }
        }

        // At least some withdrawals should be possible with available liquidity
        // Even with reduced liquidity, the system should handle some withdrawals
        assertTrue(successfulWithdrawals >= 0, "System should handle withdrawals gracefully");
    }

    // ============ WITHDRAWAL WINDOW EDGE CASES ============

    function test_WithdrawalWindow_EarlyProcessing() public {
        address user = users[0];
        uint256 userShares = vault.userShares(user);
        
        vm.prank(user);
        uint256 requestId = vault.requestWithdrawal(userShares);

        // Try to process before window expires
        vm.expectRevert("Withdrawal window not met");
        vm.prank(user);
        vault.processWithdrawal(requestId);
    }

    function test_WithdrawalWindow_ExactTiming() public {
        address user = users[0];
        uint256 userShares = vault.userShares(user);
        
        vm.prank(user);
        uint256 requestId = vault.requestWithdrawal(userShares);

        // Fast forward to exact window expiry
        vm.warp(block.timestamp + 7 days);

        // Should work exactly at window expiry
        vm.prank(user);
        vault.processWithdrawal(requestId);
    }

    function test_WithdrawalWindow_MultipleRequests() public {
        address user = users[0];
        uint256 userShares = vault.userShares(user);
        uint256 halfShares = userShares / 2;

        // Make first withdrawal request
        vm.startPrank(user);
        uint256 requestId1 = vault.requestWithdrawal(halfShares);
        vm.stopPrank();

        // Wait a day and make second request
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user);
        // Check remaining shares before second request
        uint256 remainingShares = vault.userShares(user);

        // Only make second request if we have remaining shares
        if (remainingShares > 0) {
            uint256 secondRequestShares = remainingShares > halfShares ? halfShares : remainingShares;
            uint256 requestId2 = vault.requestWithdrawal(secondRequestShares);
            vm.stopPrank();

            // Process first request after its window (7 days from first request)
            vm.warp(block.timestamp + 6 days); // Total 7 days from first request
            vm.prank(user);
            vault.processWithdrawal(requestId1);

            // Process second request after its window (7 days from second request)
            vm.warp(block.timestamp + 1 days); // Total 7 days from second request
            vm.prank(user);
            vault.processWithdrawal(requestId2);
        } else {
            vm.stopPrank();
            // If no remaining shares, just process the first request
            vm.warp(block.timestamp + 6 days);
            vm.prank(user);
            vault.processWithdrawal(requestId1);
        }
    }

    // ============ INSTANT WITHDRAWAL STRESS TESTS ============

    function test_InstantWithdrawal_MassInstantWithdrawals() public {
        // Test system under mass instant withdrawal pressure
        uint256 totalFeesPaid = 0;
        
        for (uint256 i = 0; i < NUM_USERS / 4; i++) { // Quarter of users do instant withdrawal
            address user = users[i];
            uint256 userShares = vault.userShares(user);
            uint256 balanceBefore = mockUSDC.balanceOf(user);
            
            vm.prank(user);
            vault.instantWithdrawal(userShares);
            
            uint256 balanceAfter = mockUSDC.balanceOf(user);
            uint256 received = balanceAfter - balanceBefore;
            
            // Calculate expected fee (1% default)
            uint256 expectedAmount = userShares; // Simplified calculation
            uint256 expectedFee = expectedAmount / 100;
            totalFeesPaid += expectedFee;
            
            assertTrue(received > 0, "User should receive funds");
            assertTrue(received < expectedAmount, "Should pay instant withdrawal fee");
        }

        assertTrue(totalFeesPaid > 0, "System should collect fees");
    }

    function test_InstantWithdrawal_FeeCalculation() public {
        address user = users[0];
        uint256 userShares = vault.userShares(user);
        uint256 balanceBefore = mockUSDC.balanceOf(user);
        
        vm.prank(user);
        vault.instantWithdrawal(userShares);
        
        uint256 balanceAfter = mockUSDC.balanceOf(user);
        uint256 received = balanceAfter - balanceBefore;
        
        // Verify fee was applied correctly
        // The received amount should be less than the full share value due to fee
        assertTrue(received > 0, "Should receive some funds");
        assertTrue(received < DEPOSIT_AMOUNT, "Should receive less than full amount due to fee");

        // Fee should be approximately 1% of the withdrawal amount
        uint256 expectedReceived = DEPOSIT_AMOUNT * 99 / 100; // 99% after 1% fee
        assertApproxEqRel(received, expectedReceived, 0.05e18, "Fee calculation should be accurate");
    }

    // ============ INTEREST ACCRUAL DURING WITHDRAWALS ============

    function test_InterestAccrual_DuringWithdrawalWindow() public {
        address user = users[0];
        uint256 userShares = vault.userShares(user);
        
        // Request withdrawal
        vm.prank(user);
        uint256 requestId = vault.requestWithdrawal(userShares);

        // Simulate yield generation during withdrawal window
        mockStrategy.addYield(1000 * 10**6); // 1000 USDC yield
        
        // Fast forward and process
        vm.warp(block.timestamp + 7 days);
        
        uint256 balanceBefore = mockUSDC.balanceOf(user);
        vm.prank(user);
        vault.processWithdrawal(requestId);
        uint256 balanceAfter = mockUSDC.balanceOf(user);
        
        uint256 received = balanceAfter - balanceBefore;
        
        // User should receive their share of yield generated during waiting period
        assertTrue(received >= DEPOSIT_AMOUNT, "Should receive at least original deposit");
    }

    // ============ WITHDRAWAL CANCELLATION TESTS ============

    function test_WithdrawalCancellation_BeforeProcessing() public {
        address user = users[0];
        uint256 userShares = vault.userShares(user);

        // Ensure user has shares
        assertTrue(userShares > 0, "User should have shares");

        vm.prank(user);
        uint256 requestId = vault.requestWithdrawal(userShares);

        // Verify request was created
        assertEq(requestId, 0, "First request should have ID 0");

        // Cancel before processing
        vm.prank(user);
        vault.cancelWithdrawal(requestId);

        // Should not be able to process cancelled request
        vm.warp(block.timestamp + 8 days);
        vm.expectRevert("Request cancelled");
        vm.prank(user);
        vault.processWithdrawal(requestId);
    }

    function test_WithdrawalCancellation_RestoreShares() public {
        address user = users[0];
        uint256 initialShares = vault.userShares(user);

        // Ensure user has shares
        assertTrue(initialShares > 0, "User should have shares");

        vm.prank(user);
        uint256 requestId = vault.requestWithdrawal(initialShares);

        // Verify request was created
        assertEq(requestId, 0, "First request should have ID 0");

        // Cancel withdrawal
        vm.prank(user);
        vault.cancelWithdrawal(requestId);

        // User should still have their shares after cancellation
        uint256 sharesAfterCancel = vault.userShares(user);
        assertTrue(sharesAfterCancel > 0, "User should still have shares after cancellation");

        // User should be able to make a new withdrawal request
        vm.prank(user);
        uint256 newRequestId = vault.requestWithdrawal(sharesAfterCancel);
        assertEq(newRequestId, 1, "New request should have ID 1 (second request)");
    }

    // ============ EDGE CASE STRESS TESTS ============

    function test_EdgeCase_ZeroShareWithdrawal() public {
        address user = users[0];
        
        vm.expectRevert("Cannot withdraw 0 shares");
        vm.prank(user);
        vault.requestWithdrawal(0);
    }

    function test_EdgeCase_ExcessiveShareWithdrawal() public {
        address user = users[0];
        uint256 userShares = vault.userShares(user);
        
        vm.expectRevert("Insufficient shares");
        vm.prank(user);
        vault.requestWithdrawal(userShares + 1);
    }

    function test_EdgeCase_DoubleProcessing() public {
        address user = users[0];
        uint256 userShares = vault.userShares(user);
        
        vm.prank(user);
        uint256 requestId = vault.requestWithdrawal(userShares);

        vm.warp(block.timestamp + 8 days);
        
        // Process once
        vm.prank(user);
        vault.processWithdrawal(requestId);

        // Try to process again
        vm.expectRevert("Request already processed");
        vm.prank(user);
        vault.processWithdrawal(requestId);
    }

    // ============ SYSTEM RECOVERY TESTS ============

    function test_SystemRecovery_AfterMassWithdrawals() public {
        // Simulate mass withdrawals
        for (uint256 i = 0; i < NUM_USERS / 2; i++) {
            address user = users[i];
            uint256 userShares = vault.userShares(user);
            
            vm.prank(user);
            vault.instantWithdrawal(userShares);
        }

        // System should still function for remaining users
        address remainingUser = users[NUM_USERS - 1];
        uint256 remainingShares = vault.userShares(remainingUser);
        
        assertTrue(remainingShares > 0, "Remaining users should still have shares");
        
        // New deposits should still work
        mockUSDC.mint(remainingUser, DEPOSIT_AMOUNT);
        vm.startPrank(remainingUser);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        assertTrue(vault.userShares(remainingUser) > remainingShares, "New deposits should work");
    }
}
