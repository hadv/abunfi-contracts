// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/RiskProfileManager.sol";
import "../src/WithdrawalManager.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockStrategy.sol";

contract AbunfiVaultNewFunctionsTest is Test {
    AbunfiVault public vault;
    RiskProfileManager public riskManager;
    WithdrawalManager public withdrawalManager;
    MockERC20 public mockUSDC;
    MockStrategy public mockStrategy;

    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);

    uint256 public constant DEPOSIT_AMOUNT = 100e6; // 100 USDC

    event WithdrawalRequested(address indexed user, uint256 indexed requestId, uint256 shares, uint256 estimatedAmount);
    event WithdrawalProcessed(address indexed user, uint256 indexed requestId, uint256 shares, uint256 amount);
    event WithdrawalCancelled(address indexed user, uint256 indexed requestId, uint256 shares);
    event VaultWithdrawalProcessed(address indexed user, uint256 shares, uint256 amount);
    event RiskManagersUpdated(address indexed riskProfileManager, address indexed withdrawalManager);

    function setUp() public {
        // Deploy mock USDC
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);

        // Deploy real risk manager
        riskManager = new RiskProfileManager();

        // Deploy withdrawal manager with temporary vault address
        withdrawalManager = new WithdrawalManager(
            address(0x1), // temporary vault address
            address(mockUSDC)
        );

        // Deploy vault with real managers
        vault = new AbunfiVault(address(mockUSDC), address(0), address(riskManager), address(withdrawalManager));

        // Deploy new withdrawal manager with correct vault address
        withdrawalManager = new WithdrawalManager(
            address(vault),
            address(mockUSDC)
        );

        // Update vault to use the correct withdrawal manager
        vault.updateRiskManagers(address(riskManager), address(withdrawalManager));

        // Deploy mock strategy
        mockStrategy = new MockStrategy(address(mockUSDC), "Mock Strategy", 500); // 5% APY

        // Mint tokens to users
        mockUSDC.mint(user1, 1000e6);
        mockUSDC.mint(user2, 1000e6);
        mockUSDC.mint(user3, 1000e6);

        // Users approve vault
        vm.prank(user1);
        mockUSDC.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        mockUSDC.approve(address(vault), type(uint256).max);
        vm.prank(user3);
        mockUSDC.approve(address(vault), type(uint256).max);

        // Users deposit
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.prank(user3);
        vault.deposit(DEPOSIT_AMOUNT);
    }

    // ============ requestWithdrawal Tests ============

    function test_RequestWithdrawal_ValidRequest() public {
        // First, user1 needs to deposit to have shares
        vm.prank(user1);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        uint256 userShares = vault.userShares(user1);
        uint256 withdrawShares = userShares / 2;

        vm.expectEmit(true, true, false, true);
        emit WithdrawalRequested(user1, 0, withdrawShares, withdrawShares / 1e12); // Assuming simple conversion

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(withdrawShares);

        assertEq(requestId, 0, "First request should have ID 0");
        assertEq(vault.userShares(user1), userShares - withdrawShares, "User shares should be reduced");
    }

    function test_RequestWithdrawal_ZeroShares() public {
        vm.prank(user1);
        vm.expectRevert("Cannot withdraw 0 shares");
        vault.requestWithdrawal(0);
    }

    function test_RequestWithdrawal_InsufficientShares() public {
        // First, user1 needs to deposit to have shares
        vm.prank(user1);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        uint256 userShares = vault.userShares(user1);

        vm.prank(user1);
        vm.expectRevert("Insufficient shares");
        vault.requestWithdrawal(userShares + 1);
    }

    function test_RequestWithdrawal_MultipleRequests() public {
        // First, user1 needs to deposit to have shares
        vm.prank(user1);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        uint256 userShares = vault.userShares(user1);
        // For 100 USDC deposit, user gets 100e18 shares
        assertEq(userShares, 100e18, "User should have 100e18 shares");

        uint256 firstWithdraw = userShares / 3;  // 33.333... e18
        uint256 secondWithdraw = userShares / 3; // 33.333... e18

        vm.startPrank(user1);
        uint256 requestId1 = vault.requestWithdrawal(firstWithdraw);
        uint256 requestId2 = vault.requestWithdrawal(secondWithdraw);
        vm.stopPrank();

        assertEq(requestId1, 0, "First request ID should be 0");
        assertEq(requestId2, 1, "Second request ID should be 1");

        // Verify user shares are reduced
        uint256 finalShares = vault.userShares(user1);
        uint256 expectedFinalShares = userShares - firstWithdraw - secondWithdraw;
        assertEq(finalShares, expectedFinalShares, "User shares should be reduced");
    }

    // ============ processWithdrawal Tests ============

    function test_ProcessWithdrawal_ValidProcessing() public {
        // First, user1 needs to deposit to have shares
        vm.prank(user1);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        // First request withdrawal
        uint256 userShares = vault.userShares(user1);
        uint256 withdrawShares = userShares / 2;

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(withdrawShares);

        // Fast forward time to pass withdrawal window
        vm.warp(block.timestamp + 8 days); // Use 8 days to be safe

        uint256 initialBalance = mockUSDC.balanceOf(user1);

        vm.expectEmit(true, true, false, true);
        emit WithdrawalProcessed(user1, requestId, withdrawShares, withdrawShares); // Assuming 1:1 ratio

        vm.prank(user1);
        vault.processWithdrawal(requestId);

        assertGt(mockUSDC.balanceOf(user1), initialBalance, "User should receive USDC");
    }

    function test_ProcessWithdrawal_InvalidRequestId() public {
        vm.prank(user1);
        vm.expectRevert("Invalid request ID");
        vault.processWithdrawal(999);
    }

    function test_ProcessWithdrawal_NotOwner() public {
        // First, user1 needs to deposit to have shares
        vm.prank(user1);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        // User1 requests withdrawal
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(vault.userShares(user1) / 2);

        // User2 tries to process user1's withdrawal
        vm.prank(user2);
        vm.expectRevert("Not request owner");
        vault.processWithdrawal(requestId);
    }

    function test_ProcessWithdrawal_TooEarly() public {
        // First, user1 needs to deposit to have shares
        vm.prank(user1);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(vault.userShares(user1) / 2);

        // Try to process immediately (within withdrawal window)
        vm.prank(user1);
        vm.expectRevert("Withdrawal window not passed");
        vault.processWithdrawal(requestId);
    }

    // ============ cancelWithdrawal Tests ============

    function test_CancelWithdrawal_ValidCancellation() public {
        // First, user1 needs to deposit to have shares
        vm.prank(user1);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        uint256 userShares = vault.userShares(user1);
        uint256 withdrawShares = userShares / 2;

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(withdrawShares);

        uint256 sharesAfterRequest = vault.userShares(user1);

        vm.expectEmit(true, true, false, true);
        emit WithdrawalCancelled(user1, requestId, withdrawShares);

        vm.prank(user1);
        vault.cancelWithdrawal(requestId);

        assertEq(vault.userShares(user1), userShares, "User shares should be restored");
    }

    function test_CancelWithdrawal_InvalidRequestId() public {
        vm.prank(user1);
        vm.expectRevert("Invalid request ID");
        vault.cancelWithdrawal(999);
    }

    function test_CancelWithdrawal_NotOwner() public {
        // First, user1 needs to deposit to have shares
        vm.prank(user1);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(vault.userShares(user1) / 2);

        vm.prank(user2);
        vm.expectRevert("Not request owner");
        vault.cancelWithdrawal(requestId);
    }

    function test_CancelWithdrawal_AlreadyProcessed() public {
        // First, user1 needs to deposit to have shares
        vm.prank(user1);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(vault.userShares(user1) / 2);

        // Fast forward and process
        vm.warp(block.timestamp + 8 days);
        vm.prank(user1);
        vault.processWithdrawal(requestId);

        // Try to cancel processed withdrawal
        vm.prank(user1);
        vm.expectRevert("Request already processed");
        vault.cancelWithdrawal(requestId);
    }

    // ============ processVaultWithdrawal Tests ============

    function test_ProcessVaultWithdrawal_OnlyWithdrawalManager() public {
        vm.expectRevert("Only withdrawal manager can call");
        vault.processVaultWithdrawal(user1, 100, 100);
    }

    function test_ProcessVaultWithdrawal_ValidCall() public {
        // First, user1 needs to deposit to have shares
        vm.prank(user1);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        uint256 shares = 50e18;
        uint256 amount = 50e6;

        vm.expectEmit(true, false, false, true);
        emit VaultWithdrawalProcessed(user1, shares, amount);

        // Call from withdrawal manager
        vm.prank(address(withdrawalManager));
        vault.processVaultWithdrawal(user1, shares, amount);
    }

    // ============ updateRiskManagers Tests ============

    function test_UpdateRiskManagers_ValidUpdate() public {
        RiskProfileManager newRiskManager = new RiskProfileManager();
        WithdrawalManager newWithdrawalManager = new WithdrawalManager(
            address(vault),
            address(mockUSDC) // asset address
        );

        vm.expectEmit(true, true, false, false);
        emit RiskManagersUpdated(address(newRiskManager), address(newWithdrawalManager));

        vault.updateRiskManagers(address(newRiskManager), address(newWithdrawalManager));

        // Verify the update worked by checking the new managers are set
        assertTrue(address(vault.riskProfileManager()) == address(newRiskManager), "Risk manager should be updated");
        assertTrue(
            address(vault.withdrawalManager()) == address(newWithdrawalManager), "Withdrawal manager should be updated"
        );
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
        vm.prank(user1);
        vm.expectRevert();
        vault.updateRiskManagers(address(riskManager), address(withdrawalManager));
    }

    // ============ Integration Tests ============

    function test_FullWithdrawalFlow() public {
        // 1. Request withdrawal
        uint256 userShares = vault.balanceOf(user1);
        uint256 withdrawShares = userShares / 2;
        uint256 initialUSDCBalance = mockUSDC.balanceOf(user1);

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(withdrawShares);

        // 2. Wait for withdrawal window
        vm.warp(block.timestamp + 1 days);

        // 3. Process withdrawal
        vm.prank(user1);
        vault.processWithdrawal(requestId);

        // 4. Verify final state
        assertGt(mockUSDC.balanceOf(user1), initialUSDCBalance, "User should receive USDC");
        assertEq(vault.balanceOf(user1), userShares - withdrawShares, "User shares should be reduced");
    }

    function test_CancelAndResubmitWithdrawal() public {
        // 1. Request withdrawal
        uint256 userShares = vault.balanceOf(user1);
        uint256 withdrawShares = userShares / 2;

        vm.prank(user1);
        uint256 requestId1 = vault.requestWithdrawal(withdrawShares);

        // 2. Cancel withdrawal
        vm.prank(user1);
        vault.cancelWithdrawal(requestId1);

        // 3. Resubmit withdrawal
        vm.prank(user1);
        uint256 requestId2 = vault.requestWithdrawal(withdrawShares);

        // 4. Verify state
        assertEq(vault.balanceOf(user1), userShares - withdrawShares, "User shares should be reduced again");
        assertNotEq(requestId1, requestId2, "Request IDs should be different");
    }
}
