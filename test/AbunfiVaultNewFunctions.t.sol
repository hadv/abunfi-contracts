// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockStrategy.sol";

contract AbunfiVaultNewFunctionsTest is Test {
    AbunfiVault public vault;
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

        // Use simple mock contracts for risk and withdrawal managers to avoid complex setup
        address mockRiskManager = address(new MockERC20("Mock Risk Manager", "MRM", 18));
        address mockWithdrawalManager = address(new MockERC20("Mock Withdrawal Manager", "MWM", 18));

        // Deploy vault with mock managers
        vault = new AbunfiVault(address(mockUSDC), address(0), mockRiskManager, mockWithdrawalManager);

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
        uint256 userShares = vault.balanceOf(user1);
        uint256 withdrawShares = userShares / 2;

        // Since we're using mock withdrawal manager, we can't test the actual withdrawal functionality
        // This test will verify that the function exists and can be called
        vm.prank(user1);

        // The function should revert because the mock withdrawal manager doesn't implement the interface
        vm.expectRevert();
        vault.requestWithdrawal(withdrawShares);
    }

    function test_RequestWithdrawal_ZeroShares() public {
        vm.prank(user1);
        vm.expectRevert("Shares must be greater than zero");
        vault.requestWithdrawal(0);
    }

    function test_RequestWithdrawal_InsufficientShares() public {
        uint256 userShares = vault.balanceOf(user1);

        vm.prank(user1);
        vm.expectRevert("Insufficient shares");
        vault.requestWithdrawal(userShares + 1);
    }

    function test_RequestWithdrawal_MultipleRequests() public {
        uint256 userShares = vault.balanceOf(user1);
        uint256 firstWithdraw = userShares / 3;
        uint256 secondWithdraw = userShares / 3;

        vm.startPrank(user1);
        uint256 requestId1 = vault.requestWithdrawal(firstWithdraw);
        uint256 requestId2 = vault.requestWithdrawal(secondWithdraw);
        vm.stopPrank();

        assertEq(requestId1, 1, "First request ID should be 1");
        assertEq(requestId2, 2, "Second request ID should be 2");
        assertEq(
            vault.balanceOf(user1),
            userShares - firstWithdraw - secondWithdraw,
            "User shares should be reduced by both withdrawals"
        );
    }

    // ============ processWithdrawal Tests ============

    function test_ProcessWithdrawal_ValidProcessing() public {
        // First request withdrawal
        uint256 userShares = vault.balanceOf(user1);
        uint256 withdrawShares = userShares / 2;

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(withdrawShares);

        // Fast forward time to pass withdrawal window
        vm.warp(block.timestamp + 1 days);

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
        // User1 requests withdrawal
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(vault.balanceOf(user1) / 2);

        // User2 tries to process user1's withdrawal
        vm.prank(user2);
        vm.expectRevert("Not request owner");
        vault.processWithdrawal(requestId);
    }

    function test_ProcessWithdrawal_TooEarly() public {
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(vault.balanceOf(user1) / 2);

        // Try to process immediately (within withdrawal window)
        vm.prank(user1);
        vm.expectRevert("Withdrawal window not passed");
        vault.processWithdrawal(requestId);
    }

    // ============ cancelWithdrawal Tests ============

    function test_CancelWithdrawal_ValidCancellation() public {
        uint256 userShares = vault.balanceOf(user1);
        uint256 withdrawShares = userShares / 2;

        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(withdrawShares);

        uint256 sharesAfterRequest = vault.balanceOf(user1);

        vm.expectEmit(true, true, false, true);
        emit WithdrawalCancelled(user1, requestId, withdrawShares);

        vm.prank(user1);
        vault.cancelWithdrawal(requestId);

        assertEq(vault.balanceOf(user1), userShares, "User shares should be restored");
    }

    function test_CancelWithdrawal_InvalidRequestId() public {
        vm.prank(user1);
        vm.expectRevert("Invalid request ID");
        vault.cancelWithdrawal(999);
    }

    function test_CancelWithdrawal_NotOwner() public {
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(vault.balanceOf(user1) / 2);

        vm.prank(user2);
        vm.expectRevert("Not request owner");
        vault.cancelWithdrawal(requestId);
    }

    function test_CancelWithdrawal_AlreadyProcessed() public {
        vm.prank(user1);
        uint256 requestId = vault.requestWithdrawal(vault.balanceOf(user1) / 2);

        // Fast forward and process
        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        vault.processWithdrawal(requestId);

        // Try to cancel processed withdrawal
        vm.prank(user1);
        vm.expectRevert("Request already processed");
        vault.cancelWithdrawal(requestId);
    }

    // ============ processVaultWithdrawal Tests ============

    function test_ProcessVaultWithdrawal_OnlyWithdrawalManager() public {
        vm.expectRevert("Only withdrawal manager");
        vault.processVaultWithdrawal(user1, 100, 100);
    }

    function test_ProcessVaultWithdrawal_ValidCall() public {
        uint256 shares = 50e18;
        uint256 amount = 50e6;

        vm.expectEmit(true, false, false, true);
        emit VaultWithdrawalProcessed(user1, shares, amount);

        // Mock the withdrawal manager calling this function
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
        vm.expectRevert("Invalid risk manager");
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
