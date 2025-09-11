// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/mocks/MockStrategy.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockUniswapV4PoolManager.sol";

contract UniswapV4StrategyEdgeCasesTest is Test {
    MockStrategy public strategy;
    MockERC20 public mockUSDC;
    MockERC20 public mockUSDT;
    MockUniswapV4PoolManager public mockPool;

    address public vault = address(0x1);
    address public manager = address(0x2);
    address public attacker = address(0x3);

    uint256 public constant INITIAL_DEPOSIT = 1000e6;
    uint256 public constant LARGE_DEPOSIT = 10000e6;
    uint256 public constant MIN_LIQUIDITY = 1e6;
    uint256 public constant MAX_SLIPPAGE = 500; // 5%

    event PositionRebalanced(int24 newLowerTick, int24 newUpperTick, uint128 liquidity);
    event FeesCollected(uint256 amount0, uint256 amount1);
    event EmergencyWithdrawal(uint256 amount);
    event SlippageExceeded(uint256 expected, uint256 actual);

    function setUp() public {
        // Deploy mock tokens
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);
        mockUSDT = new MockERC20("Mock USDT", "USDT", 6);

        // Deploy mock pool
        mockPool = new MockUniswapV4PoolManager();

        // Deploy strategy (using MockStrategy for simplicity)
        strategy = new MockStrategy(
            address(mockUSDC),
            "UniswapV4 Stablecoin Strategy",
            500 // 5% APY
        );

        // Setup initial balances
        mockUSDC.mint(vault, INITIAL_DEPOSIT);
        mockUSDC.mint(address(strategy), INITIAL_DEPOSIT);
        mockUSDT.mint(address(mockPool), INITIAL_DEPOSIT);

        // Setup approvals
        vm.prank(vault);
        mockUSDC.approve(address(strategy), type(uint256).max);
    }

    // ============ Basic Strategy Edge Cases ============

    function test_EdgeCase_ZeroDeposit() public {
        vm.prank(vault);
        vm.expectRevert("Cannot deposit 0");
        strategy.deposit(0);
    }

    function test_EdgeCase_MinimumDeposit() public {
        // Transfer tokens to strategy first
        vm.prank(vault);
        mockUSDC.transfer(address(strategy), MIN_LIQUIDITY);

        vm.prank(vault);
        strategy.deposit(MIN_LIQUIDITY);

        assertGe(strategy.totalAssets(), MIN_LIQUIDITY, "Total assets should meet minimum");
    }

    function test_EdgeCase_LargeDeposit() public {
        uint256 largeAmount = LARGE_DEPOSIT;

        // Transfer tokens to strategy first
        vm.prank(vault);
        mockUSDC.transfer(address(strategy), largeAmount);

        vm.prank(vault);
        strategy.deposit(largeAmount);

        assertGe(strategy.totalAssets(), largeAmount, "Should handle large deposit");
    }

    function test_EdgeCase_DepositFailure() public {
        // Set strategy to fail deposits
        strategy.setShouldFailDeposit(true);

        vm.prank(vault);
        vm.expectRevert("Mock: Deposit failed");
        strategy.deposit(INITIAL_DEPOSIT);
    }

    function test_EdgeCase_WithdrawWithZeroBalance() public {
        // Try to withdraw without any deposits
        vm.prank(vault);
        vm.expectRevert("Insufficient balance");
        strategy.withdraw(INITIAL_DEPOSIT);
    }

    // ============ Yield Generation Edge Cases ============

    function test_EdgeCase_HarvestWithNoDeposits() public {
        vm.prank(vault);
        uint256 yield = strategy.harvest();

        assertEq(yield, 0, "Should not generate yield without deposits");
    }

    function test_EdgeCase_HarvestMinimalYield() public {
        // Transfer tokens to strategy first
        vm.prank(vault);
        mockUSDC.transfer(address(strategy), INITIAL_DEPOSIT);

        // Deposit and generate minimal yield
        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        // Advance blocks to generate yield
        vm.roll(block.number + 1);

        vm.prank(vault);
        uint256 yield = strategy.harvest();

        assertGt(yield, 0, "Should generate some yield");
    }

    function test_EdgeCase_HarvestFailure() public {
        // Transfer tokens to strategy first
        vm.prank(vault);
        mockUSDC.transfer(address(strategy), INITIAL_DEPOSIT);

        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        // Set strategy to fail harvest
        strategy.setShouldFailHarvest(true);

        vm.prank(vault);
        vm.expectRevert("Mock: Harvest failed");
        strategy.harvest();
    }

    // ============ Withdrawal Edge Cases ============

    function test_EdgeCase_WithdrawExactBalance() public {
        // Transfer tokens to strategy first
        vm.prank(vault);
        mockUSDC.transfer(address(strategy), INITIAL_DEPOSIT);

        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        uint256 totalAssets = strategy.totalAssets();

        vm.prank(vault);
        strategy.withdraw(totalAssets);

        assertEq(strategy.totalAssets(), 0, "Should withdraw exact balance");
    }

    function test_EdgeCase_WithdrawMoreThanBalance() public {
        // Transfer tokens to strategy first
        vm.prank(vault);
        mockUSDC.transfer(address(strategy), INITIAL_DEPOSIT);

        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        vm.prank(vault);
        vm.expectRevert("Insufficient balance");
        strategy.withdraw(INITIAL_DEPOSIT * 2);
    }

    function test_EdgeCase_WithdrawFailure() public {
        // Transfer tokens to strategy first
        vm.prank(vault);
        mockUSDC.transfer(address(strategy), INITIAL_DEPOSIT);

        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        // Set strategy to fail withdrawals
        strategy.setShouldFailWithdraw(true);

        vm.prank(vault);
        vm.expectRevert("Mock: Withdraw failed");
        strategy.withdraw(INITIAL_DEPOSIT / 2);
    }

    // ============ Emergency Scenarios ============

    function test_EdgeCase_WithdrawAll() public {
        // Transfer tokens to strategy first
        vm.prank(vault);
        mockUSDC.transfer(address(strategy), INITIAL_DEPOSIT);

        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        uint256 totalAssets = strategy.totalAssets();
        uint256 vaultBalanceBefore = mockUSDC.balanceOf(vault);

        vm.prank(vault);
        strategy.withdrawAll();

        assertEq(strategy.totalAssets(), 0, "All assets should be withdrawn");
        assertEq(mockUSDC.balanceOf(vault), vaultBalanceBefore + totalAssets, "Vault should receive withdrawn assets");
    }

    function test_EdgeCase_WithdrawAllWithoutDeposits() public {
        vm.prank(vault);
        strategy.withdrawAll(); // Should not revert, just do nothing

        assertEq(strategy.totalAssets(), 0, "Should remain at zero");
    }

    function test_EdgeCase_WithdrawAllFailure() public {
        // Transfer tokens to strategy first
        vm.prank(vault);
        mockUSDC.transfer(address(strategy), INITIAL_DEPOSIT);

        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        // Set strategy to fail withdrawals
        strategy.setShouldFailWithdraw(true);

        vm.prank(vault);
        vm.expectRevert("Mock: Withdraw failed");
        strategy.withdrawAll();
    }

    // ============ Access Control Edge Cases ============

    function test_EdgeCase_UnauthorizedAPYChange() public {
        vm.prank(attacker);
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.setAPY(1000);
    }

    function test_EdgeCase_UnauthorizedYieldRateChange() public {
        vm.prank(attacker);
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.setYieldRate(200);
    }

    function test_EdgeCase_UnauthorizedFailureFlags() public {
        vm.prank(attacker);
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.setShouldFailDeposit(true);
    }

    function test_EdgeCase_OwnerCanChangeSettings() public {
        // Owner should be able to change settings
        strategy.setAPY(1000);
        strategy.setYieldRate(200);
        strategy.setShouldFailDeposit(false);

        assertEq(strategy.getAPY(), 1000, "APY should be updated");
    }

    // ============ Yield and APY Edge Cases ============

    function test_EdgeCase_VariableYieldRates() public {
        // Transfer tokens to strategy first
        vm.prank(vault);
        mockUSDC.transfer(address(strategy), INITIAL_DEPOSIT);

        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        // Test different yield rates
        uint256[] memory yieldRates = new uint256[](3);
        yieldRates[0] = 50; // Low yield
        yieldRates[1] = 200; // High yield
        yieldRates[2] = 0; // No yield

        for (uint256 i = 0; i < yieldRates.length; i++) {
            strategy.setYieldRate(yieldRates[i]);

            // Advance blocks to generate yield
            vm.roll(block.number + 10);

            vm.prank(vault);
            uint256 yield = strategy.harvest();

            if (yieldRates[i] > 0) {
                assertGt(yield, 0, "Should generate yield with positive rate");
            } else {
                assertEq(yield, 0, "Should not generate yield with zero rate");
            }
        }

        assertGt(strategy.totalAssets(), INITIAL_DEPOSIT, "Strategy should have grown");
    }

    function test_EdgeCase_APYChanges() public {
        uint256 initialAPY = strategy.getAPY();

        // Change APY
        strategy.setAPY(1500); // 15%
        assertEq(strategy.getAPY(), 1500, "APY should be updated");

        // Change back
        strategy.setAPY(initialAPY);
        assertEq(strategy.getAPY(), initialAPY, "APY should be restored");
    }

    function test_EdgeCase_ZeroAPY() public {
        strategy.setAPY(0);
        assertEq(strategy.getAPY(), 0, "APY should be zero");
    }

    // ============ Gas Optimization Edge Cases ============

    function test_EdgeCase_GasOptimizedHarvest() public {
        // Transfer tokens to strategy first
        vm.prank(vault);
        mockUSDC.transfer(address(strategy), INITIAL_DEPOSIT);

        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        // Advance blocks to generate yield
        vm.roll(block.number + 10);

        uint256 gasStart = gasleft();

        vm.prank(vault);
        strategy.harvest();

        uint256 gasUsed = gasStart - gasleft();

        // Ensure gas usage is within reasonable bounds
        assertLt(gasUsed, 100000, "Harvest should be gas efficient");
    }

    function test_EdgeCase_MultipleOperations() public {
        // Transfer tokens to strategy first
        vm.prank(vault);
        mockUSDC.transfer(address(strategy), INITIAL_DEPOSIT);

        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        // Advance blocks to generate yield
        vm.roll(block.number + 10);

        // Perform multiple operations
        vm.prank(vault);
        strategy.harvest();

        vm.prank(vault);
        strategy.withdraw(INITIAL_DEPOSIT / 4);

        vm.prank(vault);
        strategy.harvest();

        assertGt(strategy.totalAssets(), 0, "Multiple operations should work correctly");
    }
}
