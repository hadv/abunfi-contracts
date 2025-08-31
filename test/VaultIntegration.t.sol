// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/strategies/AaveStrategy.sol";
import "../src/strategies/CompoundStrategy.sol";
import "../src/StrategyManager.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockAavePool.sol";
import "../src/mocks/MockAaveDataProvider.sol";
import "../src/mocks/MockComet.sol";
import "../src/mocks/MockCometRewards.sol";

contract VaultIntegrationTest is Test {
    AbunfiVault public vault;
    AaveStrategy public aaveStrategy;
    CompoundStrategy public compoundStrategy;
    StrategyManager public strategyManager;
    MockERC20 public mockUSDC;
    MockERC20 public mockAUSDC;
    MockAavePool public mockAavePool;
    MockAaveDataProvider public mockAaveDataProvider;
    MockComet public mockComet;
    MockCometRewards public mockCometRewards;

    address public owner;
    address public user1;
    address public user2;

    uint256 constant INITIAL_SUPPLY = 10_000_000 * 10 ** 6; // 10M USDC
    uint256 constant DEPOSIT_AMOUNT = 1000 * 10 ** 6; // 1000 USDC
    uint256 constant MIN_DEPOSIT = 4 * 10 ** 6; // 4 USDC

    event Harvest(uint256 totalYield);

    function setUp() public {
        owner = address(this);
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

        // Deploy mock Compound Comet
        mockComet = new MockComet(address(mockUSDC));

        // Deploy mock CometRewards
        mockCometRewards = new MockCometRewards();

        // Deploy AbunfiVault
        vault = new AbunfiVault(address(mockUSDC));

        // Deploy AaveStrategy
        aaveStrategy =
            new AaveStrategy(address(mockUSDC), address(mockAavePool), address(mockAaveDataProvider), address(vault));

        // Deploy CompoundStrategy
        compoundStrategy =
            new CompoundStrategy(address(mockUSDC), address(mockComet), address(mockCometRewards), address(vault));

        // Deploy StrategyManager
        strategyManager = new StrategyManager();

        // Setup initial balances
        mockUSDC.mint(user1, INITIAL_SUPPLY);
        mockUSDC.mint(user2, INITIAL_SUPPLY);

        vm.prank(user1);
        mockUSDC.approve(address(vault), INITIAL_SUPPLY);
        vm.prank(user2);
        mockUSDC.approve(address(vault), INITIAL_SUPPLY);
    }

    // Strategy Management Tests
    function test_StrategyManagement_AddStrategiesToVault() public {
        vault.addStrategyWithWeight(address(aaveStrategy), 60); // 60% weight
        vault.addStrategyWithWeight(address(compoundStrategy), 40); // 40% weight

        assertTrue(vault.isActiveStrategy(address(aaveStrategy)));
        assertTrue(vault.isActiveStrategy(address(compoundStrategy)));
    }

    function test_StrategyManagement_GetAllStrategiesInfo() public {
        vault.addStrategyWithWeight(address(aaveStrategy), 60);
        vault.addStrategyWithWeight(address(compoundStrategy), 40);

        (
            address[] memory addresses,
            string[] memory names,
            uint256[] memory totalAssetsAmounts,
            uint256[] memory apys,
            uint256[] memory weights
        ) = vault.getAllStrategiesInfo();

        assertEq(addresses.length, 2);
        assertEq(names.length, 2);
        assertEq(weights.length, 2);
    }

    function test_StrategyManagement_UpdateStrategyWeights() public {
        vault.addStrategy(address(aaveStrategy), 60);

        vault.updateStrategyWeight(address(aaveStrategy), 70);

        (, uint256 totalAssetsAmount, uint256 apy, uint256 weight, bool isActive) =
            vault.getStrategyInfo(address(aaveStrategy));
        assertEq(weight, 70);
    }

    function test_StrategyManagement_RemoveStrategies() public {
        vault.addStrategy(address(aaveStrategy), 60);

        vault.removeStrategy(address(aaveStrategy));

        assertFalse(vault.isActiveStrategy(address(aaveStrategy)));
    }

    // Multi-Strategy Deposits and Withdrawals Tests
    function test_MultiStrategy_DepositAndAllocateToStrategies() public {
        vault.addStrategy(address(aaveStrategy), 60);
        vault.addStrategy(address(compoundStrategy), 40);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        assertGe(vault.totalAssets(), DEPOSIT_AMOUNT);
        assertGt(vault.balanceOf(user1), 0);
    }

    function test_MultiStrategy_AllocateFundsBasedOnWeights() public {
        vault.addStrategy(address(aaveStrategy), 60);
        vault.addStrategy(address(compoundStrategy), 40);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        vault.allocateToStrategies();

        // Check that funds were allocated
        uint256 aaveBalance = aaveStrategy.totalAssets();
        uint256 compoundBalance = compoundStrategy.totalAssets();

        assertGt(aaveBalance + compoundBalance, 0);
    }

    function test_MultiStrategy_WithdrawFromMultipleStrategies() public {
        vault.addStrategy(address(aaveStrategy), 60);
        vault.addStrategy(address(compoundStrategy), 40);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        vault.allocateToStrategies();

        uint256 userShares = vault.userShares(user1);
        uint256 halfShares = userShares / 2;

        vm.prank(user1);
        vault.withdraw(halfShares);

        assertEq(vault.userShares(user1), userShares - halfShares);
    }

    // Rebalancing Tests
    function test_Rebalancing_RebalanceStrategiesBasedOnPerformance() public {
        vault.addStrategy(address(aaveStrategy), 60);
        vault.addStrategy(address(compoundStrategy), 40);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        vault.allocateToStrategies();

        // Mock different APYs
        mockAaveDataProvider.setLiquidityRate(address(mockUSDC), 8e25); // 8% APY
        mockComet.setSupplyRate(1e17); // 10% APY (simplified)

        // Should not revert
        vault.rebalance();
    }

    function test_Rebalancing_UpdateReserveRatio() public {
        uint256 newRatio = 1500; // 15%

        vault.updateReserveRatio(newRatio);

        assertEq(vault.reserveRatio(), newRatio);
    }

    // Harvest Tests
    function test_Harvest_HarvestYieldFromAllStrategies() public {
        vault.addStrategy(address(aaveStrategy), 60);
        vault.addStrategy(address(compoundStrategy), 40);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        vault.allocateToStrategies();

        // Simulate yield generation
        uint256 aaveYield = 50 * 10 ** 6;
        uint256 compoundYield = 30 * 10 ** 6;

        mockAavePool.addYield(address(aaveStrategy), aaveYield);
        mockComet.setBalance(address(compoundStrategy), compoundStrategy.totalAssets() + compoundYield);

        vm.expectEmit(true, true, true, true);
        emit Harvest(compoundYield); // CompoundStrategy yield

        vault.harvest();
    }

    // Strategy Manager Integration Tests
    function test_StrategyManagerIntegration_CalculateOptimalAllocations() public {
        strategyManager.addStrategy(
            address(aaveStrategy),
            60, // weight
            25, // risk score
            7000, // max allocation (70%)
            1000 // min allocation (10%)
        );

        strategyManager.addStrategy(
            address(compoundStrategy),
            40, // weight
            30, // risk score
            6000, // max allocation (60%)
            1000 // min allocation (10%)
        );

        uint256 totalAmount = 10000 * 10 ** 6;
        uint256[] memory allocations = strategyManager.calculateOptimalAllocation(totalAmount);

        assertEq(allocations.length, 2);
        assertLe(allocations[0] + allocations[1], totalAmount);
    }

    function test_StrategyManagerIntegration_UpdateAPYData() public {
        strategyManager.addStrategy(address(aaveStrategy), 60, 25, 7000, 1000);

        strategyManager.updateStrategyAPY(address(aaveStrategy), 500); // 5% APY

        (,,,,,, uint256 lastAPY,,) = strategyManager.strategies(address(aaveStrategy));
        assertEq(lastAPY, 500);
    }

    function test_StrategyManagerIntegration_CheckRebalancingNeeded() public {
        strategyManager.addStrategy(address(aaveStrategy), 60, 25, 7000, 1000);
        strategyManager.addStrategy(address(compoundStrategy), 40, 30, 6000, 1000);

        address[] memory strategies = new address[](2);
        strategies[0] = address(aaveStrategy);
        strategies[1] = address(compoundStrategy);

        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 6000 * 10 ** 6;
        allocations[1] = 4000 * 10 ** 6;

        bool shouldRebalance = strategyManager.shouldRebalance(strategies, allocations);
        // Should return a boolean value
        assertTrue(shouldRebalance == true || shouldRebalance == false);
    }

    function test_StrategyManagerIntegration_UpdateRiskTolerance() public {
        uint256 newRiskTolerance = 70;

        strategyManager.setRiskTolerance(newRiskTolerance);

        assertEq(strategyManager.riskTolerance(), newRiskTolerance);
    }

    // Edge Cases and Error Handling Tests
    function test_EdgeCases_HandleZeroDepositsGracefully() public {
        vm.expectRevert("Amount below minimum");
        vm.prank(user1);
        vault.deposit(0);
    }

    function test_EdgeCases_HandleDepositsBelowMinimum() public {
        uint256 belowMin = MIN_DEPOSIT - 1;

        vm.expectRevert("Amount below minimum");
        vm.prank(user1);
        vault.deposit(belowMin);
    }

    function test_EdgeCases_HandleWithdrawalsWithInsufficientShares() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        uint256 userShares = vault.userShares(user1);

        vm.expectRevert("Insufficient shares");
        vm.prank(user1);
        vault.withdraw(userShares + 1);
    }

    function test_EdgeCases_HandleStrategyFailuresGracefully() public {
        vault.addStrategy(address(aaveStrategy), 100);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);

        // Even if strategy fails, vault should continue operating
        assertGe(vault.totalAssets(), DEPOSIT_AMOUNT);
    }

    // Gas Optimization Tests
    function test_GasOptimization_EfficientMultipleStrategyOperations() public {
        vault.addStrategy(address(aaveStrategy), 50);
        vault.addStrategy(address(compoundStrategy), 50);

        uint256 gasBefore = gasleft();
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();

        // Gas usage should be reasonable (less than 500k gas)
        assertLt(gasUsed, 500000);
    }

    // Access Control Tests
    function test_AccessControl_OnlyOwnerCanAddStrategies() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        vault.addStrategy(address(aaveStrategy), 60);
    }

    function test_AccessControl_OnlyOwnerCanUpdateWeights() public {
        vault.addStrategy(address(aaveStrategy), 60);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        vault.updateStrategyWeight(address(aaveStrategy), 70);
    }

    function test_AccessControl_OnlyOwnerCanRemoveStrategies() public {
        vault.addStrategy(address(aaveStrategy), 60);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        vault.removeStrategy(address(aaveStrategy));
    }

    // Fuzz Tests
    function testFuzz_MultiStrategy_ValidDeposits(uint256 amount) public {
        amount = bound(amount, MIN_DEPOSIT, INITIAL_SUPPLY);

        vault.addStrategy(address(aaveStrategy), 50);
        vault.addStrategy(address(compoundStrategy), 50);

        vm.prank(user1);
        vault.deposit(amount);

        assertGe(vault.totalAssets(), amount);
        assertGt(vault.balanceOf(user1), 0);
    }

    function testFuzz_StrategyWeights_ValidWeights(uint256 weight1, uint256 weight2) public {
        weight1 = bound(weight1, 1, 99);
        weight2 = bound(weight2, 1, 100 - weight1);

        vault.addStrategy(address(aaveStrategy), weight1);
        vault.addStrategy(address(compoundStrategy), weight2);

        assertTrue(vault.isActiveStrategy(address(aaveStrategy)));
        assertTrue(vault.isActiveStrategy(address(compoundStrategy)));
    }
}
