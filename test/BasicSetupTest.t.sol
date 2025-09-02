// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/mocks/MockERC20.sol";
import "../src/RiskProfileManager.sol";
import "../src/mocks/MockAavePool.sol";
import "../src/mocks/MockComet.sol";

contract BasicSetupTestTest is Test {
    MockERC20 public mockUSDC;
    AbunfiVault public vault;

    address public owner;
    address public user1;

    event Deposit(address indexed user, uint256 amount, uint256 shares, RiskProfileManager.RiskLevel riskLevel);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");

        // Deploy mock USDC
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);

        // Deploy vault
        // Create mock risk management contracts for testing
        address mockRiskManager = address(new MockERC20("Mock Risk Manager", "MRM", 18));
        address mockWithdrawalManager = address(new MockERC20("Mock Withdrawal Manager", "MWM", 18));

        vault = new AbunfiVault(address(mockUSDC), address(0), mockRiskManager, mockWithdrawalManager);

        // Mint USDC to user
        mockUSDC.mint(user1, 1000 * 10 ** 6); // 1000 USDC
    }

    // Mock USDC Tests
    function test_MockUSDC_DeploySuccessfully() public {
        assertEq(mockUSDC.name(), "Mock USDC");
        assertEq(mockUSDC.symbol(), "USDC");
        assertEq(mockUSDC.decimals(), 6);
    }

    function test_MockUSDC_MintTokensCorrectly() public {
        uint256 balance = mockUSDC.balanceOf(user1);
        assertEq(balance, 1000 * 10 ** 6);
    }

    // AbunfiVault Tests
    function test_AbunfiVault_DeploySuccessfully() public {
        assertEq(address(vault.asset()), address(mockUSDC));
        assertEq(vault.MINIMUM_DEPOSIT(), 4 * 10 ** 6); // 4 USDC
    }

    function test_AbunfiVault_AllowDepositsAboveMinimum() public {
        uint256 depositAmount = 10 * 10 ** 6; // 10 USDC

        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);

        vm.expectEmit(true, true, true, true);
        emit Deposit(user1, depositAmount, depositAmount * 1e12, RiskProfileManager.RiskLevel.MEDIUM);

        vault.deposit(depositAmount);
        vm.stopPrank();
    }

    function test_AbunfiVault_RejectDepositsBelowMinimum() public {
        uint256 depositAmount = 3 * 10 ** 6; // 3 USDC (below minimum)

        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);

        vm.expectRevert("Amount below minimum");
        vault.deposit(depositAmount);
        vm.stopPrank();
    }

    // Mock Contracts Tests
    function test_MockContracts_DeployMockAaveContracts() public {
        MockAavePool mockAavePool = new MockAavePool(address(mockUSDC));

        assertTrue(address(mockAavePool) != address(0));
    }

    function test_MockContracts_DeployMockCompoundContracts() public {
        MockComet mockComet = new MockComet(address(mockUSDC));

        assertTrue(address(mockComet) != address(0));
    }

    // Additional Integration Tests
    function test_Integration_VaultAndTokenInteraction() public {
        uint256 depositAmount = 100 * 10 ** 6; // 100 USDC

        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), depositAmount);
        assertEq(vault.totalAssets(), depositAmount);
    }

    function test_Integration_MultipleUsersDeposit() public {
        address user2 = makeAddr("user2");
        mockUSDC.mint(user2, 500 * 10 ** 6); // 500 USDC

        uint256 deposit1 = 100 * 10 ** 6;
        uint256 deposit2 = 200 * 10 ** 6;

        // User1 deposits
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), deposit1);
        vault.deposit(deposit1);
        vm.stopPrank();

        // User2 deposits
        vm.startPrank(user2);
        mockUSDC.approve(address(vault), deposit2);
        vault.deposit(deposit2);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), deposit1);
        assertEq(vault.balanceOf(user2), deposit2);
        assertEq(vault.totalAssets(), deposit1 + deposit2);
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

    function testFuzz_MockToken_MintAmounts(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        address testUser = makeAddr("testUser");
        mockUSDC.mint(testUser, amount);

        assertEq(mockUSDC.balanceOf(testUser), amount);
    }
}
