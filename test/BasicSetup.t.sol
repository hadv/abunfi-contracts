// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/mocks/MockERC20.sol";
import "../src/RiskProfileManager.sol";
import "../src/mocks/MockAavePool.sol";
import "../src/mocks/MockComet.sol";

contract BasicSetupTest is Test {
    event Deposit(address indexed user, uint256 amount, uint256 shares, RiskProfileManager.RiskLevel riskLevel);

    MockERC20 public mockUSDC;
    AbunfiVault public vault;

    address public owner;
    address public user1;

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

    function test_MockUSDC_DeploySuccessfully() public {
        assertEq(mockUSDC.name(), "Mock USDC");
        assertEq(mockUSDC.symbol(), "USDC");
        assertEq(mockUSDC.decimals(), 6);
    }

    function test_MockUSDC_MintTokensCorrectly() public {
        uint256 balance = mockUSDC.balanceOf(user1);
        assertEq(balance, 1000 * 10 ** 6);
    }

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

        assertEq(vault.balanceOf(user1), depositAmount);
    }

    function test_AbunfiVault_RejectDepositsBelowMinimum() public {
        uint256 depositAmount = 3 * 10 ** 6; // 3 USDC (below minimum)

        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);
        vm.expectRevert("Amount below minimum");
        vault.deposit(depositAmount);
        vm.stopPrank();
    }

    function test_MockAavePool_DeploySuccessfully() public {
        MockAavePool mockAavePool = new MockAavePool(address(mockUSDC));
        assertTrue(address(mockAavePool) != address(0));
    }

    function test_MockComet_DeploySuccessfully() public {
        MockComet mockComet = new MockComet(address(mockUSDC));
        assertTrue(address(mockComet) != address(0));
    }

    function testFuzz_Deposit_ValidAmounts(uint256 amount) public {
        // Bound the amount to reasonable values (minimum to 1M USDC)
        amount = bound(amount, vault.MINIMUM_DEPOSIT(), 1_000_000 * 10 ** 6);

        // Mint enough tokens to user
        mockUSDC.mint(user1, amount);

        vm.startPrank(user1);
        mockUSDC.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), amount);
    }

    function test_RevertWhen_DepositBelowMinimum() public {
        uint256 depositAmount = vault.MINIMUM_DEPOSIT() - 1;

        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);
        vm.expectRevert("Amount below minimum");
        vault.deposit(depositAmount);
        vm.stopPrank();
    }
}
