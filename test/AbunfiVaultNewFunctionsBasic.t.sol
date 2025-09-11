// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/RiskProfileManager.sol";
import "../src/WithdrawalManager.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockStrategy.sol";

/**
 * @title AbunfiVaultNewFunctionsBasicTest
 * @dev Basic test cases for newly added AbunfiVault functions:
 * - requestWithdrawal(uint256 shares)
 * - processWithdrawal(uint256 requestId)
 * - cancelWithdrawal(uint256 requestId)
 * - processVaultWithdrawal(address user, uint256 shares, uint256 amount)
 * - updateRiskManagers(address _riskProfileManager, address _withdrawalManager)
 */
contract AbunfiVaultNewFunctionsBasicTest is Test {
    AbunfiVault public vault;
    RiskProfileManager public riskManager;
    WithdrawalManager public withdrawalManager;
    MockERC20 public mockUSDC;
    MockStrategy public mockStrategy;

    address public owner = address(this);
    address public user1 = address(0x1001);
    address public user2 = address(0x1002);

    uint256 public constant DEPOSIT_AMOUNT = 100e6; // 100 USDC

    function setUp() public {
        // Deploy mock USDC
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);

        // Deploy risk manager first
        riskManager = new RiskProfileManager();

        // Deploy withdrawal manager placeholder (will be updated later)
        withdrawalManager = new WithdrawalManager(
            address(0x1), // temporary vault address
            address(mockUSDC) // asset address
        );

        // Deploy vault with correct constructor
        vault = new AbunfiVault(
            address(mockUSDC),
            address(this), // trusted forwarder
            address(riskManager),
            address(withdrawalManager)
        );

        // Deploy new withdrawal manager with correct vault address
        withdrawalManager = new WithdrawalManager(
            address(vault),
            address(mockUSDC) // asset address
        );

        // Deploy mock strategy
        mockStrategy = new MockStrategy(address(mockUSDC), "Mock Strategy", 500); // 5% APY

        // Set up vault
        vault.updateRiskManagers(address(riskManager), address(withdrawalManager));
        vault.addStrategy(address(mockStrategy), 10000); // 100% weight

        // Mint tokens to users
        mockUSDC.mint(user1, 1000e6);
        mockUSDC.mint(user2, 1000e6);

        // Users approve vault
        vm.prank(user1);
        mockUSDC.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        mockUSDC.approve(address(vault), type(uint256).max);

        // Users deposit
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT);
    }

    // ============ REQUEST WITHDRAWAL TESTS ============

    function test_RequestWithdrawal_ValidRequest() public {
        uint256 userShares = vault.userShares(user1);
        
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(userShares);
        
        assertEq(requestId, 1, "Request ID should be 1");
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

    // ============ PROCESS WITHDRAWAL TESTS ============

    function test_ProcessWithdrawal_ValidProcessing() public {
        uint256 userShares = vault.userShares(user1);
        uint256 balanceBefore = mockUSDC.balanceOf(user1);

        // Request withdrawal
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(userShares);

        // Fast forward past withdrawal window
        vm.warp(block.timestamp + 8 days);

        // Process withdrawal
        vm.prank(user1);
        vault.processWithdrawal(requestId);

        uint256 balanceAfter = mockUSDC.balanceOf(user1);
        assertTrue(balanceAfter > balanceBefore, "User should receive tokens");
        assertEq(vault.userShares(user1), 0, "User shares should be zero");
    }

    // ============ CANCEL WITHDRAWAL TESTS ============

    function test_CancelWithdrawal_ValidCancellation() public {
        uint256 userShares = vault.userShares(user1);

        // Request withdrawal
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(userShares);

        // Cancel withdrawal
        vm.prank(user1);
        vault.cancelWithdrawal(requestId);

        // User should still have shares
        assertEq(vault.userShares(user1), userShares, "User should still have shares");
    }

    // ============ PROCESS VAULT WITHDRAWAL TESTS ============

    function test_ProcessVaultWithdrawal_OnlyWithdrawalManager() public {
        uint256 userShares = vault.userShares(user1);

        vm.expectRevert("Only withdrawal manager can call");
        vault.processVaultWithdrawal(user1, userShares, DEPOSIT_AMOUNT);
    }

    // ============ UPDATE RISK MANAGERS TESTS ============

    function test_UpdateRiskManagers_ValidUpdate() public {
        RiskProfileManager newRiskManager = new RiskProfileManager();
        WithdrawalManager newWithdrawalManager = new WithdrawalManager(
            address(vault),
            address(mockUSDC) // asset address
        );

        vault.updateRiskManagers(address(newRiskManager), address(newWithdrawalManager));

        // Verify the update worked by checking the new managers are set
        assertTrue(address(vault.riskProfileManager()) == address(newRiskManager), "Risk manager should be updated");
        assertTrue(address(vault.withdrawalManager()) == address(newWithdrawalManager), "Withdrawal manager should be updated");
    }

    function test_UpdateRiskManagers_ZeroAddresses() public {
        vm.expectRevert("Invalid risk profile manager");
        vault.updateRiskManagers(address(0), address(withdrawalManager));

        vm.expectRevert("Invalid withdrawal manager");
        vault.updateRiskManagers(address(riskManager), address(0));
    }

    function test_UpdateRiskManagers_OnlyOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        vault.updateRiskManagers(address(riskManager), address(withdrawalManager));
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

        // 4. Verify results
        uint256 balanceAfter = mockUSDC.balanceOf(user1);
        assertTrue(balanceAfter > balanceBefore, "User should receive tokens");
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
}
