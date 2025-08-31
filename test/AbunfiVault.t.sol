// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/mocks/MockERC20.sol";

contract AbunfiVaultTest is Test {
    AbunfiVault public vault;
    MockERC20 public mockUSDC;

    address public owner;
    address public user1;
    address public user2;

    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock USDC
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);

        // Deploy vault
        vault = new AbunfiVault(address(mockUSDC), address(0));

        // Mint USDC to users
        mockUSDC.mint(user1, 1000 * 10 ** 6); // 1000 USDC
        mockUSDC.mint(user2, 1000 * 10 ** 6); // 1000 USDC
    }

    // Deployment Tests
    function test_Deployment_SetsCorrectAsset() public {
        assertEq(address(vault.asset()), address(mockUSDC));
    }

    function test_Deployment_SetsCorrectMinimumDeposit() public {
        assertEq(vault.MINIMUM_DEPOSIT(), 4 * 10 ** 6); // 4 USDC
    }

    // Deposit Tests
    function test_Deposits_AllowDepositsAboveMinimum() public {
        uint256 depositAmount = 10 * 10 ** 6; // 10 USDC

        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);

        vm.expectEmit(true, true, true, true);
        emit Deposit(user1, depositAmount, depositAmount * 1e12);

        vault.deposit(depositAmount);
        vm.stopPrank();

        assertEq(vault.userDeposits(user1), depositAmount);
        assertEq(vault.balanceOf(user1), depositAmount);
    }

    function test_Deposits_RejectDepositsBelowMinimum() public {
        uint256 depositAmount = 3 * 10 ** 6; // 3 USDC (below minimum)

        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);

        vm.expectRevert("Amount below minimum");
        vault.deposit(depositAmount);
        vm.stopPrank();
    }

    function test_Deposits_UpdateUserBalancesCorrectly() public {
        uint256 depositAmount = 10 * 10 ** 6; // 10 USDC

        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();

        assertEq(vault.userDeposits(user1), depositAmount);
        assertEq(vault.balanceOf(user1), depositAmount);
    }

    // Withdrawal Tests
    function test_Withdrawals_AllowWithdrawals() public {
        // First deposit
        uint256 depositAmount = 100 * 10 ** 6; // 100 USDC
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        // Then withdraw half
        uint256 userShares = vault.userShares(user1);
        uint256 withdrawShares = userShares / 2;

        vm.expectEmit(true, true, true, true);
        emit Withdraw(user1, withdrawShares / 1e12, withdrawShares);

        vault.withdraw(withdrawShares);
        vm.stopPrank();

        assertEq(vault.userShares(user1), userShares - withdrawShares);
    }

    function test_Withdrawals_RejectExcessiveWithdrawals() public {
        // First deposit
        uint256 depositAmount = 100 * 10 ** 6; // 100 USDC
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        // Try to withdraw more than balance
        uint256 userShares = vault.userShares(user1);
        uint256 excessiveShares = userShares + 1;

        vm.expectRevert("Insufficient shares");
        vault.withdraw(excessiveShares);
        vm.stopPrank();
    }

    // Multiple Users Tests
    function test_MultipleUsers_HandleMultipleUsersCorrectly() public {
        uint256 deposit1 = 50 * 10 ** 6; // 50 USDC
        uint256 deposit2 = 100 * 10 ** 6; // 100 USDC

        // User 1 deposits
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), deposit1);
        vault.deposit(deposit1);
        vm.stopPrank();

        // User 2 deposits
        vm.startPrank(user2);
        mockUSDC.approve(address(vault), deposit2);
        vault.deposit(deposit2);
        vm.stopPrank();

        assertEq(vault.totalDeposits(), deposit1 + deposit2);
        assertEq(vault.balanceOf(user1), deposit1);
        assertEq(vault.balanceOf(user2), deposit2);
    }

    // Access Control Tests
    function test_AccessControl_OnlyOwnerCanAddStrategies() public {
        address mockStrategy = makeAddr("mockStrategy");

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vault.addStrategy(mockStrategy);
        vm.stopPrank();
    }

    function test_AccessControl_OnlyOwnerCanPause() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vault.pause();
        vm.stopPrank();
    }

    // Fuzz Tests
    function testFuzz_Deposits_ValidAmounts(uint256 amount) public {
        amount = bound(amount, vault.MINIMUM_DEPOSIT(), 1_000_000 * 10 ** 6);

        mockUSDC.mint(user1, amount);

        vm.startPrank(user1);
        mockUSDC.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), amount);
    }

    function testFuzz_Withdrawals_ValidAmounts(uint256 depositAmount, uint256 withdrawRatio) public {
        depositAmount = bound(depositAmount, vault.MINIMUM_DEPOSIT(), 1_000_000 * 10 ** 6);
        withdrawRatio = bound(withdrawRatio, 1, 100);

        mockUSDC.mint(user1, depositAmount);

        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        uint256 userShares = vault.userShares(user1);
        uint256 withdrawShares = (userShares * withdrawRatio) / 100;

        if (withdrawShares > 0) {
            vault.withdraw(withdrawShares);
            assertEq(vault.userShares(user1), userShares - withdrawShares);
        }
        vm.stopPrank();
    }
}
