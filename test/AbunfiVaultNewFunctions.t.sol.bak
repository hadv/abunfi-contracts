// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/RiskProfileManager.sol";
import "../src/WithdrawalManager.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockStrategy.sol";

/**
 * @title AbunfiVaultNewFunctionsTest
 * @dev Comprehensive test cases for newly added AbunfiVault functions:
 * - requestWithdrawal()
 * - processWithdrawal()
 * - cancelWithdrawal()
 * - processVaultWithdrawal()
 * - updateRiskManagers()
 * - Batching system functions
 */
contract AbunfiVaultNewFunctionsTest is Test {
    AbunfiVault public vault;
    RiskProfileManager public riskManager;
    WithdrawalManager public withdrawalManager;
    MockERC20 public mockUSDC;
    MockStrategy public mockStrategy;

    address public owner = address(this);
    address public user1 = address(0x1001);
    address public user2 = address(0x1002);
    address public user3 = address(0x1003);
    address public attacker = address(0x1004);

    uint256 public constant MINIMUM_DEPOSIT = 4e6; // 4 USDC
    uint256 public constant DEPOSIT_AMOUNT = 100e6; // 100 USDC
    uint256 public constant LARGE_DEPOSIT = 10000e6; // 10,000 USDC

    // Events to test
    event WithdrawalRequested(address indexed user, uint256 requestId, uint256 shares, uint256 estimatedAmount);
    event WithdrawalProcessed(address indexed user, uint256 requestId, uint256 amount);
    event WithdrawalCancelled(address indexed user, uint256 requestId);
    event RiskManagersUpdated(address indexed riskProfileManager, address indexed withdrawalManager);
    event BatchAllocationExecuted(uint256 amount, uint256 timestamp);

    function setUp() public {
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

        // Update vault with withdrawal manager
        vault.updateRiskManagers(address(riskManager), address(withdrawalManager));

        // Deploy and add mock strategy
        mockStrategy = new MockStrategy(address(mockUSDC), "Mock Strategy", 500);
        vault.addStrategy(address(mockStrategy), 5000); // 50% weight

        // Mint tokens to users
        mockUSDC.mint(user1, LARGE_DEPOSIT);
        mockUSDC.mint(user2, LARGE_DEPOSIT);
        mockUSDC.mint(user3, LARGE_DEPOSIT);
        mockUSDC.mint(attacker, LARGE_DEPOSIT);

        // Setup initial deposits for testing
        _setupUserDeposits();
    }

    function _setupUserDeposits() internal {
        // User1: Large deposit
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // User2: Medium deposit
        vm.startPrank(user2);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT / 2);
        vault.deposit(DEPOSIT_AMOUNT / 2);
        vm.stopPrank();

        // User3: Minimum deposit
        vm.startPrank(user3);
        mockUSDC.approve(address(vault), MINIMUM_DEPOSIT);
        vault.deposit(MINIMUM_DEPOSIT);
        vm.stopPrank();
    }

    // ============ REQUEST WITHDRAWAL TESTS ============

    function test_RequestWithdrawal_ValidRequest() public {
        uint256 userShares = vault.userShares(user1);
        assertTrue(userShares > 0, "User should have shares");

        vm.expectEmit(true, true, true, false);
        emit WithdrawalRequested(user1, 0, userShares, userShares);

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(userShares);

        assertEq(requestId, 0, "First request should have ID 0");
    }

    function test_RequestWithdrawal_ZeroShares() public {
        vm.expectRevert("Cannot withdraw 0 shares");
        vm.prank(user1);
        vault.requestWithdrawal(0);
    }

    function test_RequestWithdrawal_InsufficientShares() public {
        uint256 userShares = vault.userShares(user1);
        
        vm.expectRevert("Insufficient shares");
        vm.prank(user1);
        vault.requestWithdrawal(userShares + 1);
    }

    function test_RequestWithdrawal_MultipleRequests() public {
        uint256 userShares = vault.userShares(user1);
        uint256 halfShares = userShares / 2;

        // First request
        vm.prank(user1);
        uint256 requestId1 = vault.requestWithdrawal(halfShares);
        assertEq(requestId1, 0);

        // Second request with remaining shares
        uint256 remainingShares = vault.userShares(user1);
        vm.prank(user1);
        uint256 requestId2 = vault.requestWithdrawal(remainingShares);
        assertEq(requestId2, 1);
    }

    function test_RequestWithdrawal_UpdatesInterest() public {
        // Add some yield to generate interest
        mockStrategy.addYield(1000e6);
        
        // Fast forward time to accrue interest
        vm.warp(block.timestamp + 30 days);

        uint256 userShares = vault.userShares(user1);
        uint256 interestBefore = vault.userAccruedInterest(user1);

        vm.prank(user1);
        vault.requestWithdrawal(userShares);

        uint256 interestAfter = vault.userAccruedInterest(user1);
        assertTrue(interestAfter >= interestBefore, "Interest should be updated");
    }

    // ============ PROCESS WITHDRAWAL TESTS ============

    function test_ProcessWithdrawal_ValidProcessing() public {
        uint256 userShares = vault.userShares(user1);
        uint256 balanceBefore = mockUSDC.balanceOf(user1);

        // Request withdrawal
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(userShares);

        // Fast forward past withdrawal window
        vm.warp(block.timestamp + 8 days);

        vm.expectEmit(true, true, true, false);
        emit WithdrawalProcessed(user1, requestId, userShares);

        // Process withdrawal
        vm.prank(user1);
        vault.processWithdrawal(requestId);

        uint256 balanceAfter = mockUSDC.balanceOf(user1);
        assertTrue(balanceAfter > balanceBefore, "User should receive tokens");
        assertEq(vault.userShares(user1), 0, "User shares should be zero");
    }

    function test_ProcessWithdrawal_BeforeWindow() public {
        uint256 userShares = vault.userShares(user1);

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(userShares);

        // Try to process immediately (before window)
        vm.expectRevert("Withdrawal window not met");
        vm.prank(user1);
        vault.processWithdrawal(requestId);
    }

    function test_ProcessWithdrawal_AlreadyProcessed() public {
        uint256 userShares = vault.userShares(user1);

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(userShares);

        vm.warp(block.timestamp + 8 days);

        // Process once
        vm.prank(user1);
        vault.processWithdrawal(requestId);

        // Try to process again
        vm.expectRevert("Request already processed");
        vm.prank(user1);
        vault.processWithdrawal(requestId);
    }

    function test_ProcessWithdrawal_WrongUser() public {
        uint256 userShares = vault.userShares(user1);

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(userShares);

        vm.warp(block.timestamp + 8 days);

        // Try to process with different user
        vm.expectRevert("Invalid request ID");
        vm.prank(user2);
        vault.processWithdrawal(requestId);
    }

    // ============ CANCEL WITHDRAWAL TESTS ============

    function test_CancelWithdrawal_ValidCancellation() public {
        uint256 userShares = vault.userShares(user1);

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(userShares);

        vm.expectEmit(true, true, true, true);
        emit WithdrawalCancelled(user1, requestId);

        vm.prank(user1);
        vault.cancelWithdrawal(requestId);

        // Should not be able to process cancelled request
        vm.warp(block.timestamp + 8 days);
        vm.expectRevert("Request cancelled");
        vm.prank(user1);
        vault.processWithdrawal(requestId);
    }

    function test_CancelWithdrawal_AlreadyCancelled() public {
        uint256 userShares = vault.userShares(user1);

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(userShares);

        vm.prank(user1);
        vault.cancelWithdrawal(requestId);

        // Try to cancel again
        vm.expectRevert("Request already cancelled");
        vm.prank(user1);
        vault.cancelWithdrawal(requestId);
    }

    function test_CancelWithdrawal_AlreadyProcessed() public {
        uint256 userShares = vault.userShares(user1);

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(userShares);

        vm.warp(block.timestamp + 8 days);

        // Process first
        vm.prank(user1);
        vault.processWithdrawal(requestId);

        // Try to cancel processed request
        vm.expectRevert("Request already processed");
        vm.prank(user1);
        vault.cancelWithdrawal(requestId);
    }

    function test_CancelWithdrawal_RestoresPendingShares() public {
        uint256 userShares = vault.userShares(user1);

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(userShares);

        // Cancel withdrawal
        vm.prank(user1);
        vault.cancelWithdrawal(requestId);

        // User should be able to make new withdrawal request
        vm.prank(user1);
        uint256 newRequestId = vault.requestWithdrawal(userShares);
        assertEq(newRequestId, 1, "Should be able to make new request");
    }

    // ============ PROCESS VAULT WITHDRAWAL TESTS ============

    function test_ProcessVaultWithdrawal_OnlyWithdrawalManager() public {
        uint256 userShares = vault.userShares(user1);

        // Try to call directly (not from withdrawal manager)
        vm.expectRevert("Only withdrawal manager can call");
        vm.prank(user1);
        vault.processVaultWithdrawal(user1, userShares, DEPOSIT_AMOUNT);
    }

    function test_ProcessVaultWithdrawal_InsufficientShares() public {
        uint256 userShares = vault.userShares(user1);

        // Mock call from withdrawal manager with excessive shares
        vm.prank(address(withdrawalManager));
        vm.expectRevert("Insufficient shares");
        vault.processVaultWithdrawal(user1, userShares + 1, DEPOSIT_AMOUNT);
    }

    function test_ProcessVaultWithdrawal_ValidExecution() public {
        uint256 userShares = vault.userShares(user1);
        uint256 balanceBefore = mockUSDC.balanceOf(user1);
        uint256 totalSharesBefore = vault.totalShares();

        // Mock call from withdrawal manager
        vm.prank(address(withdrawalManager));
        vault.processVaultWithdrawal(user1, userShares, DEPOSIT_AMOUNT);

        uint256 balanceAfter = mockUSDC.balanceOf(user1);
        uint256 totalSharesAfter = vault.totalShares();

        assertEq(balanceAfter - balanceBefore, DEPOSIT_AMOUNT, "User should receive correct amount");
        assertEq(vault.userShares(user1), 0, "User shares should be zero");
        assertEq(totalSharesAfter, totalSharesBefore - userShares, "Total shares should decrease");
    }

    // ============ UPDATE RISK MANAGERS TESTS ============

    function test_UpdateRiskManagers_ValidUpdate() public {
        RiskProfileManager newRiskManager = new RiskProfileManager();
        WithdrawalManager newWithdrawalManager = new WithdrawalManager(address(vault), address(mockUSDC));

        vm.expectEmit(true, true, true, true);
        emit RiskManagersUpdated(address(newRiskManager), address(newWithdrawalManager));

        vault.updateRiskManagers(address(newRiskManager), address(newWithdrawalManager));

        assertEq(address(vault.riskProfileManager()), address(newRiskManager));
        assertEq(address(vault.withdrawalManager()), address(newWithdrawalManager));
    }

    function test_UpdateRiskManagers_ZeroAddressRiskManager() public {
        vm.expectRevert("Invalid risk profile manager");
        vault.updateRiskManagers(address(0), address(withdrawalManager));
    }

    function test_UpdateRiskManagers_ZeroAddressWithdrawalManager() public {
        vm.expectRevert("Invalid withdrawal manager");
        vault.updateRiskManagers(address(riskManager), address(0));
    }

    function test_UpdateRiskManagers_OnlyOwner() public {
        RiskProfileManager newRiskManager = new RiskProfileManager();
        WithdrawalManager newWithdrawalManager = new WithdrawalManager(address(vault), address(mockUSDC));

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        vault.updateRiskManagers(address(newRiskManager), address(newWithdrawalManager));
    }

    // ============ BATCHING SYSTEM TESTS ============

    function test_BatchingSystem_AllocationThreshold() public {
        // Check initial threshold
        assertEq(vault.allocationThreshold(), 1000e6, "Default threshold should be $1000");

        // Update threshold
        uint256 newThreshold = 2000e6;
        vault.updateAllocationThreshold(newThreshold);
        assertEq(vault.allocationThreshold(), newThreshold);
    }

    function test_BatchingSystem_AllocationInterval() public {
        // Check initial interval
        assertEq(vault.allocationInterval(), 4 hours, "Default interval should be 4 hours");

        // Update interval
        uint256 newInterval = 6 hours;
        vault.updateAllocationInterval(newInterval);
        assertEq(vault.allocationInterval(), newInterval);
    }

    function test_BatchingSystem_EmergencyThreshold() public {
        // Check initial emergency threshold
        assertEq(vault.emergencyAllocationThreshold(), 5000e6, "Default emergency threshold should be $5000");

        // Update emergency threshold
        uint256 newThreshold = 10000e6;
        vault.updateEmergencyAllocationThreshold(newThreshold);
        assertEq(vault.emergencyAllocationThreshold(), newThreshold);
    }

    function test_BatchingSystem_ThresholdValidation() public {
        // Test minimum threshold
        vm.expectRevert("Threshold too low");
        vault.updateAllocationThreshold(50e6); // Below $100 minimum

        // Test maximum threshold
        vm.expectRevert("Threshold too high");
        vault.updateAllocationThreshold(15000e6); // Above $10k maximum
    }

    function test_BatchingSystem_IntervalValidation() public {
        // Test minimum interval
        vm.expectRevert("Interval too short");
        vault.updateAllocationInterval(30 minutes); // Below 1 hour minimum

        // Test maximum interval
        vm.expectRevert("Interval too long");
        vault.updateAllocationInterval(25 hours); // Above 24 hours maximum
    }

    function test_BatchingSystem_EmergencyThresholdValidation() public {
        // Test emergency threshold below regular threshold
        vm.expectRevert("Emergency threshold must be >= regular threshold");
        vault.updateEmergencyAllocationThreshold(500e6); // Below regular threshold

        // Test maximum emergency threshold
        vm.expectRevert("Emergency threshold too high");
        vault.updateEmergencyAllocationThreshold(60000e6); // Above $50k maximum
    }

    function test_BatchingSystem_OnlyOwnerCanUpdate() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        vault.updateAllocationThreshold(2000e6);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        vault.updateAllocationInterval(6 hours);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        vault.updateEmergencyAllocationThreshold(10000e6);
    }

    // ============ INTEGRATION TESTS ============

    function test_Integration_FullWithdrawalFlow() public {
        uint256 userShares = vault.userShares(user1);
        uint256 balanceBefore = mockUSDC.balanceOf(user1);

        // 1. Request withdrawal
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(userShares);

        // 2. Wait for withdrawal window
        vm.warp(block.timestamp + 8 days);

        // 3. Process withdrawal
        vm.prank(user1);
        vault.processWithdrawal(requestId);

        uint256 balanceAfter = mockUSDC.balanceOf(user1);
        assertTrue(balanceAfter > balanceBefore, "User should receive funds");
        assertEq(vault.userShares(user1), 0, "User should have no shares");
    }

    function test_Integration_CancelAndResubmit() public {
        uint256 userShares = vault.userShares(user1);

        // 1. Request withdrawal
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(userShares);

        // 2. Cancel withdrawal
        vm.prank(user1);
        vault.cancelWithdrawal(requestId);

        // 3. Submit new withdrawal request
        vm.prank(user1);
        uint256 newRequestId = vault.requestWithdrawal(userShares);

        // 4. Process new request
        vm.warp(block.timestamp + 8 days);
        vm.prank(user1);
        vault.processWithdrawal(newRequestId);

        assertEq(vault.userShares(user1), 0, "User should have no shares after processing");
    }

    function test_Integration_MultipleUsersWithdrawals() public {
        // All users request withdrawal
        vm.prank(user1);
        uint256 requestId1 = vault.requestWithdrawal(vault.userShares(user1));

        vm.prank(user2);
        uint256 requestId2 = vault.requestWithdrawal(vault.userShares(user2));

        vm.prank(user3);
        uint256 requestId3 = vault.requestWithdrawal(vault.userShares(user3));

        // Wait for withdrawal window
        vm.warp(block.timestamp + 8 days);

        // Process all withdrawals
        vm.prank(user1);
        vault.processWithdrawal(requestId1);

        vm.prank(user2);
        vault.processWithdrawal(requestId2);

        vm.prank(user3);
        vault.processWithdrawal(requestId3);

        // Verify all users have no shares
        assertEq(vault.userShares(user1), 0);
        assertEq(vault.userShares(user2), 0);
        assertEq(vault.userShares(user3), 0);
    }

    // ============ EDGE CASE TESTS ============

    function test_EdgeCase_WithdrawalWithYield() public {
        uint256 userShares = vault.userShares(user1);

        // Add yield to strategy
        mockStrategy.addYield(1000e6);

        // Request withdrawal
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(userShares);

        // Add more yield during withdrawal window
        mockStrategy.addYield(500e6);

        vm.warp(block.timestamp + 8 days);

        uint256 balanceBefore = mockUSDC.balanceOf(user1);
        vm.prank(user1);
        vault.processWithdrawal(requestId);
        uint256 balanceAfter = mockUSDC.balanceOf(user1);

        // User should receive more than original deposit due to yield
        assertTrue(balanceAfter > balanceBefore, "User should receive funds including yield");
    }

    function test_EdgeCase_WithdrawalDuringLowLiquidity() public {
        // Allocate most funds to strategy
        vault.allocateToStrategies();

        uint256 userShares = vault.userShares(user1);

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(userShares);

        vm.warp(block.timestamp + 8 days);

        // Should still work - vault should withdraw from strategy if needed
        vm.prank(user1);
        vault.processWithdrawal(requestId);

        assertEq(vault.userShares(user1), 0, "Withdrawal should succeed even with low liquidity");
    }
}
