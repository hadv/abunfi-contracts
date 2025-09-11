// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/strategies/UniswapV4FairFlowStablecoinStrategy.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockUniswapV4Pool.sol";

contract UniswapV4StrategyEdgeCasesTest is Test {
    UniswapV4FairFlowStablecoinStrategy public strategy;
    MockERC20 public mockUSDC;
    MockERC20 public mockUSDT;
    MockUniswapV4Pool public mockPool;

    address public vault = address(0x1);
    address public manager = address(0x2);
    address public attacker = address(0x3);

    uint256 public constant INITIAL_DEPOSIT = 1000e6;
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
        mockPool = new MockUniswapV4Pool(address(mockUSDC), address(mockUSDT));

        // Deploy strategy
        strategy = new UniswapV4FairFlowStablecoinStrategy(
            address(mockUSDC),
            address(mockPool),
            vault,
            "UniswapV4 Stablecoin Strategy"
        );

        // Setup initial balances
        mockUSDC.mint(vault, INITIAL_DEPOSIT);
        mockUSDC.mint(address(strategy), INITIAL_DEPOSIT);
        mockUSDT.mint(address(mockPool), INITIAL_DEPOSIT);

        // Setup approvals
        vm.prank(vault);
        mockUSDC.approve(address(strategy), type(uint256).max);
    }

    // ============ Position Management Edge Cases ============

    function test_EdgeCase_ZeroLiquidityPosition() public {
        vm.prank(vault);
        vm.expectRevert("Insufficient liquidity");
        strategy.deposit(0);
    }

    function test_EdgeCase_MinimumLiquidityThreshold() public {
        vm.prank(vault);
        uint256 shares = strategy.deposit(MIN_LIQUIDITY);
        
        assertGt(shares, 0, "Should receive shares for minimum liquidity");
        assertGe(strategy.totalAssets(), MIN_LIQUIDITY, "Total assets should meet minimum");
    }

    function test_EdgeCase_MaximumPositionSize() public {
        uint256 maxDeposit = strategy.maxDeposit(vault);
        
        vm.prank(vault);
        uint256 shares = strategy.deposit(maxDeposit);
        
        assertGt(shares, 0, "Should handle maximum deposit");
        
        // Try to deposit more than maximum
        vm.prank(vault);
        vm.expectRevert("Exceeds maximum deposit");
        strategy.deposit(1);
    }

    function test_EdgeCase_PositionRebalancingAtBounds() public {
        // Deposit initial liquidity
        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        // Simulate price movement to edge of range
        mockPool.setPrice(1050000); // 5% above peg

        vm.expectEmit(true, true, false, true);
        emit PositionRebalanced(-60, 60, 0); // New range around current price

        vm.prank(manager);
        strategy.rebalancePosition();
    }

    function test_EdgeCase_RebalanceWithZeroLiquidity() public {
        // Try to rebalance without any position
        vm.prank(manager);
        vm.expectRevert("No position to rebalance");
        strategy.rebalancePosition();
    }

    // ============ Fee Collection Edge Cases ============

    function test_EdgeCase_CollectFeesWithNoPosition() public {
        vm.prank(manager);
        vm.expectRevert("No fees to collect");
        strategy.collectFees();
    }

    function test_EdgeCase_CollectMinimalFees() public {
        // Deposit and generate minimal fees
        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        // Simulate minimal fee generation
        mockPool.addFees(1, 1); // 1 wei of each token

        vm.expectEmit(true, true, false, false);
        emit FeesCollected(1, 1);

        vm.prank(manager);
        strategy.collectFees();
    }

    function test_EdgeCase_CollectLargeFees() public {
        // Deposit and generate large fees
        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        // Simulate large fee generation
        uint256 largeFees = 100e6;
        mockUSDC.mint(address(mockPool), largeFees);
        mockUSDT.mint(address(mockPool), largeFees);
        mockPool.addFees(largeFees, largeFees);

        vm.expectEmit(true, true, false, false);
        emit FeesCollected(largeFees, largeFees);

        vm.prank(manager);
        strategy.collectFees();

        assertGt(strategy.totalAssets(), INITIAL_DEPOSIT, "Total assets should increase with fees");
    }

    // ============ Slippage Protection Edge Cases ============

    function test_EdgeCase_ExactSlippageLimit() public {
        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        // Set price change exactly at slippage limit
        uint256 newPrice = 1000000 * (10000 + MAX_SLIPPAGE) / 10000; // Exactly 5% slippage
        mockPool.setPrice(newPrice);

        // Should succeed at exact limit
        vm.prank(manager);
        strategy.rebalancePosition();
    }

    function test_EdgeCase_SlippageExceeded() public {
        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        // Set price change beyond slippage limit
        uint256 newPrice = 1000000 * (10000 + MAX_SLIPPAGE + 1) / 10000; // 5.01% slippage
        mockPool.setPrice(newPrice);

        vm.expectEmit(true, true, false, false);
        emit SlippageExceeded(1000000, newPrice);

        vm.prank(manager);
        vm.expectRevert("Slippage exceeded");
        strategy.rebalancePosition();
    }

    function test_EdgeCase_NegativeSlippage() public {
        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        // Set price change in opposite direction
        uint256 newPrice = 1000000 * (10000 - MAX_SLIPPAGE - 1) / 10000; // -5.01% slippage
        mockPool.setPrice(newPrice);

        vm.expectEmit(true, true, false, false);
        emit SlippageExceeded(1000000, newPrice);

        vm.prank(manager);
        vm.expectRevert("Slippage exceeded");
        strategy.rebalancePosition();
    }

    // ============ Emergency Scenarios ============

    function test_EdgeCase_EmergencyWithdrawal() public {
        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        uint256 totalAssets = strategy.totalAssets();

        vm.expectEmit(true, false, false, false);
        emit EmergencyWithdrawal(totalAssets);

        vm.prank(manager);
        strategy.emergencyWithdraw();

        assertEq(strategy.totalAssets(), 0, "All assets should be withdrawn");
        assertGt(mockUSDC.balanceOf(vault), 0, "Vault should receive withdrawn assets");
    }

    function test_EdgeCase_EmergencyWithdrawWithoutPosition() public {
        vm.prank(manager);
        vm.expectRevert("No position to withdraw");
        strategy.emergencyWithdraw();
    }

    function test_EdgeCase_PausedStrategy() public {
        vm.prank(manager);
        strategy.pause();

        vm.prank(vault);
        vm.expectRevert("Strategy is paused");
        strategy.deposit(INITIAL_DEPOSIT);
    }

    function test_EdgeCase_UnpauseStrategy() public {
        vm.prank(manager);
        strategy.pause();

        vm.prank(manager);
        strategy.unpause();

        vm.prank(vault);
        uint256 shares = strategy.deposit(INITIAL_DEPOSIT);
        assertGt(shares, 0, "Should work after unpause");
    }

    // ============ Access Control Edge Cases ============

    function test_EdgeCase_UnauthorizedRebalance() public {
        vm.prank(attacker);
        vm.expectRevert("Unauthorized");
        strategy.rebalancePosition();
    }

    function test_EdgeCase_UnauthorizedFeeCollection() public {
        vm.prank(attacker);
        vm.expectRevert("Unauthorized");
        strategy.collectFees();
    }

    function test_EdgeCase_UnauthorizedEmergencyWithdraw() public {
        vm.prank(attacker);
        vm.expectRevert("Unauthorized");
        strategy.emergencyWithdraw();
    }

    function test_EdgeCase_UnauthorizedPause() public {
        vm.prank(attacker);
        vm.expectRevert("Unauthorized");
        strategy.pause();
    }

    // ============ Market Condition Edge Cases ============

    function test_EdgeCase_ExtremeVolatility() public {
        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        // Simulate extreme price volatility
        uint256[] memory prices = new uint256[](5);
        prices[0] = 950000; // -5%
        prices[1] = 1100000; // +10%
        prices[2] = 900000; // -10%
        prices[3] = 1050000; // +5%
        prices[4] = 1000000; // Back to peg

        for (uint256 i = 0; i < prices.length; i++) {
            mockPool.setPrice(prices[i]);
            
            if (i < 2) { // First two should trigger rebalance
                vm.prank(manager);
                strategy.rebalancePosition();
            } else { // Later ones might exceed slippage
                vm.prank(manager);
                try strategy.rebalancePosition() {
                    // Rebalance succeeded
                } catch {
                    // Rebalance failed due to slippage - this is expected
                }
            }
        }

        assertGt(strategy.totalAssets(), 0, "Strategy should maintain assets through volatility");
    }

    function test_EdgeCase_ZeroLiquidityPool() public {
        // Simulate pool with zero liquidity
        mockPool.setLiquidity(0);

        vm.prank(vault);
        vm.expectRevert("Insufficient pool liquidity");
        strategy.deposit(INITIAL_DEPOSIT);
    }

    function test_EdgeCase_PoolPriceManipulation() public {
        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        // Simulate price manipulation attack
        uint256 manipulatedPrice = 2000000; // 100% price increase
        mockPool.setPrice(manipulatedPrice);

        // Strategy should detect and reject the manipulation
        vm.prank(manager);
        vm.expectRevert("Price manipulation detected");
        strategy.rebalancePosition();
    }

    // ============ Gas Optimization Edge Cases ============

    function test_EdgeCase_GasOptimizedRebalance() public {
        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        uint256 gasStart = gasleft();
        
        vm.prank(manager);
        strategy.rebalancePosition();
        
        uint256 gasUsed = gasStart - gasleft();
        
        // Ensure gas usage is within reasonable bounds
        assertLt(gasUsed, 500000, "Rebalance should be gas efficient");
    }

    function test_EdgeCase_BatchOperations() public {
        vm.prank(vault);
        strategy.deposit(INITIAL_DEPOSIT);

        // Simulate batch operations for gas efficiency
        vm.prank(manager);
        strategy.batchOperations(
            true, // collect fees
            true, // rebalance
            false // emergency withdraw
        );

        assertGt(strategy.totalAssets(), INITIAL_DEPOSIT, "Batch operations should increase assets");
    }
}
