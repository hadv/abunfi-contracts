// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/strategies/AaveStrategy.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockAavePool.sol";
import "../src/mocks/MockAaveDataProvider.sol";

contract AaveStrategyTest is Test {
    AaveStrategy public aaveStrategy;
    MockAavePool public mockAavePool;
    MockAaveDataProvider public mockAaveDataProvider;
    MockERC20 public mockUSDC;
    MockERC20 public mockAUSDC;

    address public owner;
    address public vault;
    address public user1;
    address public user2;

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 6; // 1M USDC
    uint256 constant DEPOSIT_AMOUNT = 1000 * 10 ** 6; // 1000 USDC

    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event Harvested(uint256 yield);

    function setUp() public {
        owner = address(this);
        vault = makeAddr("vault");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock USDC
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);

        // Deploy mock aUSDC
        mockAUSDC = new MockERC20("Aave interest bearing USDC", "aUSDC", 6);

        // Deploy mock Aave Pool
        mockAavePool = new MockAavePool(address(mockUSDC));

        // Deploy mock Aave Data Provider
        mockAaveDataProvider = new MockAaveDataProvider();

        // Setup mock configurations BEFORE deploying strategy
        mockAavePool.setAToken(address(mockUSDC), address(mockAUSDC));
        mockAaveDataProvider.setReserveTokens(address(mockUSDC), address(mockAUSDC), address(0), address(0));
        mockAaveDataProvider.setLiquidityRate(address(mockUSDC), 5e25); // 5% APY

        // Deploy AaveStrategy
        aaveStrategy = new AaveStrategy(address(mockUSDC), address(mockAavePool), address(mockAaveDataProvider), vault);

        // Setup initial balances
        mockUSDC.mint(vault, INITIAL_SUPPLY);
        vm.prank(vault);
        mockUSDC.approve(address(aaveStrategy), INITIAL_SUPPLY);
    }

    // Deployment Tests
    function test_Deployment_SetsCorrectAsset() public {
        assertEq(address(aaveStrategy.asset()), address(mockUSDC));
    }

    function test_Deployment_SetsCorrectVault() public {
        assertEq(aaveStrategy.vault(), vault);
    }

    function test_Deployment_SetsCorrectAavePool() public {
        assertEq(address(aaveStrategy.aavePool()), address(mockAavePool));
    }

    function test_Deployment_SetsCorrectDataProvider() public {
        assertEq(address(aaveStrategy.dataProvider()), address(mockAaveDataProvider));
    }

    function test_Deployment_HasCorrectName() public {
        assertEq(aaveStrategy.name(), "Aave USDC Lending Strategy");
    }

    function test_Deployment_SetsCorrectAToken() public {
        assertEq(address(aaveStrategy.aToken()), address(mockAUSDC));
    }

    // Deposit Tests
    function test_Deposits_AllowVaultToDeposit() public {
        // Transfer tokens to strategy (simulating vault transfer)
        vm.prank(vault);
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit Deposited(DEPOSIT_AMOUNT);

        vm.prank(vault);
        aaveStrategy.deposit(DEPOSIT_AMOUNT);

        assertEq(aaveStrategy.totalDeposited(), DEPOSIT_AMOUNT);
    }

    function test_Deposits_RevertIfNonVaultTries() public {
        vm.expectRevert("Only vault can call");
        vm.prank(user1);
        aaveStrategy.deposit(DEPOSIT_AMOUNT);
    }

    function test_Deposits_RevertIfZeroAmount() public {
        vm.expectRevert("Cannot deposit 0");
        vm.prank(vault);
        aaveStrategy.deposit(0);
    }

    function test_Deposits_UpdateTotalAssetsAfterDeposit() public {
        vm.prank(vault);
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);

        vm.prank(vault);
        aaveStrategy.deposit(DEPOSIT_AMOUNT);

        assertEq(aaveStrategy.totalAssets(), DEPOSIT_AMOUNT);
    }

    function test_Deposits_SupplyTokensToAavePool() public {
        vm.prank(vault);
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);

        vm.prank(vault);
        aaveStrategy.deposit(DEPOSIT_AMOUNT);

        assertEq(mockAUSDC.balanceOf(address(aaveStrategy)), DEPOSIT_AMOUNT);
    }

    // Withdrawal Tests
    function test_Withdrawals_AllowVaultToWithdraw() public {
        // First deposit
        vm.prank(vault);
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        aaveStrategy.deposit(DEPOSIT_AMOUNT);

        // Then withdraw
        uint256 withdrawAmount = 500 * 10 ** 6;

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(withdrawAmount);

        vm.prank(vault);
        aaveStrategy.withdraw(withdrawAmount);
    }

    function test_Withdrawals_RevertIfNonVaultTries() public {
        uint256 withdrawAmount = 500 * 10 ** 6;

        vm.expectRevert("Only vault can call");
        vm.prank(user1);
        aaveStrategy.withdraw(withdrawAmount);
    }

    function test_Withdrawals_RevertIfZeroAmount() public {
        vm.expectRevert("Cannot withdraw 0");
        vm.prank(vault);
        aaveStrategy.withdraw(0);
    }

    function test_Withdrawals_RevertIfInsufficientBalance() public {
        uint256 excessiveAmount = DEPOSIT_AMOUNT + 1 * 10 ** 6;

        vm.expectRevert("Insufficient balance");
        vm.prank(vault);
        aaveStrategy.withdraw(excessiveAmount);
    }

    function test_Withdrawals_AllowWithdrawingAllAssets() public {
        // First deposit
        vm.prank(vault);
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        aaveStrategy.deposit(DEPOSIT_AMOUNT);

        // Then withdraw all
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(DEPOSIT_AMOUNT);

        vm.prank(vault);
        aaveStrategy.withdrawAll();

        assertEq(aaveStrategy.totalDeposited(), 0);
    }

    function test_Withdrawals_TransferCorrectAmountToVault() public {
        // First deposit
        vm.prank(vault);
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        aaveStrategy.deposit(DEPOSIT_AMOUNT);

        uint256 withdrawAmount = 500 * 10 ** 6;
        uint256 vaultBalanceBefore = mockUSDC.balanceOf(vault);

        vm.prank(vault);
        aaveStrategy.withdraw(withdrawAmount);

        uint256 vaultBalanceAfter = mockUSDC.balanceOf(vault);
        assertEq(vaultBalanceAfter - vaultBalanceBefore, withdrawAmount);
    }

    // Harvest Tests
    function test_Harvest_AllowVaultToHarvest() public {
        // First deposit
        vm.prank(vault);
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        aaveStrategy.deposit(DEPOSIT_AMOUNT);

        // Simulate yield
        uint256 yieldAmount = 50 * 10 ** 6;
        mockAUSDC.mint(address(aaveStrategy), yieldAmount);

        vm.expectEmit(true, true, true, true);
        emit Harvested(yieldAmount);

        vm.prank(vault);
        aaveStrategy.harvest();
    }

    function test_Harvest_ReturnCorrectYieldAmount() public {
        // First deposit
        vm.prank(vault);
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        aaveStrategy.deposit(DEPOSIT_AMOUNT);

        uint256 yieldAmount = 50 * 10 ** 6;
        mockAUSDC.mint(address(aaveStrategy), yieldAmount);

        vm.prank(vault);
        uint256 harvestResult = aaveStrategy.harvest();
        assertEq(harvestResult, yieldAmount);
    }

    function test_Harvest_UpdateTotalDepositedAfterHarvest() public {
        // First deposit
        vm.prank(vault);
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        aaveStrategy.deposit(DEPOSIT_AMOUNT);

        uint256 yieldAmount = 50 * 10 ** 6;
        mockAUSDC.mint(address(aaveStrategy), yieldAmount);

        vm.prank(vault);
        aaveStrategy.harvest();

        assertEq(aaveStrategy.totalDeposited(), DEPOSIT_AMOUNT + yieldAmount);
    }

    function test_Harvest_ReturnZeroWhenNoYield() public {
        // First deposit
        vm.prank(vault);
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        aaveStrategy.deposit(DEPOSIT_AMOUNT);

        vm.prank(vault);
        uint256 harvestResult = aaveStrategy.harvest();
        assertEq(harvestResult, 0);
    }

    function test_Harvest_RevertIfNonVaultTries() public {
        vm.expectRevert("Only vault can call");
        vm.prank(user1);
        aaveStrategy.harvest();
    }

    // APY Tests
    function test_APY_ReturnCorrectAPY() public {
        uint256 apy = aaveStrategy.getAPY();
        assertGt(apy, 0);
    }

    function test_APY_ReturnCurrentLendingRate() public {
        uint256 rate = aaveStrategy.getCurrentLendingRate();
        assertEq(rate, 5e25); // 5% APY
    }

    // View Function Tests
    function test_ViewFunctions_ReturnCorrectTotalAssets() public {
        vm.prank(vault);
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        aaveStrategy.deposit(DEPOSIT_AMOUNT);

        assertEq(aaveStrategy.totalAssets(), DEPOSIT_AMOUNT);
    }

    function test_ViewFunctions_ReturnCorrectTotalAssetsWithYield() public {
        vm.prank(vault);
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        aaveStrategy.deposit(DEPOSIT_AMOUNT);

        uint256 yieldAmount = 25 * 10 ** 6;
        mockAUSDC.mint(address(aaveStrategy), yieldAmount);

        assertEq(aaveStrategy.totalAssets(), DEPOSIT_AMOUNT + yieldAmount);
    }

    // Access Control Tests
    function test_AccessControl_OnlyOwnerCanTransferOwnership() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        aaveStrategy.transferOwnership(user1);
    }

    // Fuzz Tests
    function testFuzz_Deposits_ValidAmounts(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_SUPPLY);

        vm.prank(vault);
        mockUSDC.transfer(address(aaveStrategy), amount);

        vm.prank(vault);
        aaveStrategy.deposit(amount);

        assertEq(aaveStrategy.totalDeposited(), amount);
        assertEq(aaveStrategy.totalAssets(), amount);
    }

    function testFuzz_Withdrawals_ValidAmounts(uint256 depositAmount, uint256 withdrawRatio) public {
        depositAmount = bound(depositAmount, 1000, INITIAL_SUPPLY);
        withdrawRatio = bound(withdrawRatio, 1, 100);

        // Deposit first
        vm.prank(vault);
        mockUSDC.transfer(address(aaveStrategy), depositAmount);
        vm.prank(vault);
        aaveStrategy.deposit(depositAmount);

        // Calculate withdraw amount
        uint256 withdrawAmount = (depositAmount * withdrawRatio) / 100;

        if (withdrawAmount > 0) {
            vm.prank(vault);
            aaveStrategy.withdraw(withdrawAmount);

            assertEq(aaveStrategy.totalDeposited(), depositAmount - withdrawAmount);
        }
    }
}
