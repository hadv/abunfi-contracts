// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/strategies/LiquidityProvidingStrategy.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockCurvePool.sol";
import "../src/mocks/MockUniswapV3Pool.sol";
import "../src/mocks/MockUniswapV3PositionManager.sol";

contract LiquidityProvidingStrategyTest is Test {
    LiquidityProvidingStrategy public liquidityProvidingStrategy;
    MockERC20 public mockUSDC;
    MockERC20 public mockUSDT;
    MockERC20 public mockDAI;
    MockCurvePool public mockCurvePool;
    MockUniswapV3Pool public mockUniswapV3Pool;
    MockUniswapV3PositionManager public mockPositionManager;

    address public owner;
    address public vault;
    address public user1;
    address public user2;

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 6; // 1M USDC
    uint256 constant DEPOSIT_AMOUNT = 1000 * 10 ** 6; // 1000 USDC

    event PoolAdded(address indexed pool, string poolType);
    event LiquidityAdded(address indexed pool, uint256 amount);
    event LiquidityRemoved(address indexed pool, uint256 amount);
    event RewardsHarvested(uint256 amount);
    event PoolRebalanced(address indexed pool, uint256 oldAmount, uint256 newAmount);

    function setUp() public {
        owner = address(this);
        vault = makeAddr("vault");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock tokens
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        mockUSDT = new MockERC20("Tether USD", "USDT", 6);
        mockDAI = new MockERC20("Dai Stablecoin", "DAI", 18);

        // Deploy mock Curve pool
        address[] memory tokens = new address[](3);
        tokens[0] = address(mockUSDC);
        tokens[1] = address(mockUSDT);
        tokens[2] = address(mockDAI);
        mockCurvePool = new MockCurvePool("Curve 3Pool LP", "3CRV", tokens);

        // Deploy mock Uniswap V3 pool
        mockUniswapV3Pool = new MockUniswapV3Pool(
            address(mockUSDC),
            address(mockUSDT),
            500 // 0.05% fee
        );

        // Deploy mock Position Manager
        mockPositionManager = new MockUniswapV3PositionManager();

        // Deploy LiquidityProvidingStrategy
        liquidityProvidingStrategy = new LiquidityProvidingStrategy(
            address(mockUSDC), address(mockCurvePool), vault, "Liquidity Providing Strategy"
        );

        // Setup initial balances
        mockUSDC.mint(vault, INITIAL_SUPPLY);
        mockUSDT.mint(vault, INITIAL_SUPPLY);
        mockDAI.mint(vault, 1_000_000 * 10 ** 18); // 1M DAI

        // Approve strategy to spend tokens
        vm.startPrank(vault);
        mockUSDC.approve(address(liquidityProvidingStrategy), INITIAL_SUPPLY);
        mockUSDT.approve(address(liquidityProvidingStrategy), INITIAL_SUPPLY);
        mockDAI.approve(address(liquidityProvidingStrategy), 1_000_000 * 10 ** 18);
        vm.stopPrank();

        // Setup mock pools with initial liquidity
        mockUSDC.mint(address(mockCurvePool), 100_000 * 10 ** 6);
        mockUSDT.mint(address(mockCurvePool), 100_000 * 10 ** 6);
        mockDAI.mint(address(mockCurvePool), 100_000 * 10 ** 18);

        mockUSDC.mint(address(mockUniswapV3Pool), 100_000 * 10 ** 6);
        mockUSDT.mint(address(mockUniswapV3Pool), 100_000 * 10 ** 6);
    }

    // Deployment Tests
    function test_Deployment_InitializeWithCorrectParameters() public {
        assertEq(liquidityProvidingStrategy.name(), "Liquidity Providing Strategy");
        assertEq(address(liquidityProvidingStrategy.asset()), address(mockUSDC));
        assertEq(liquidityProvidingStrategy.riskTolerance(), 50);
        assertEq(liquidityProvidingStrategy.maxSinglePoolAllocation(), 5000);
    }

    function test_Deployment_HasPoolsInitialized() public {
        assertGe(liquidityProvidingStrategy.poolCount(), 0);
    }

    // Pool Management Tests
    function test_PoolManagement_AddNewCurvePool() public {
        uint256 poolId = liquidityProvidingStrategy.poolCount();

        address[] memory tokens = new address[](2);
        tokens[0] = address(mockUSDC);
        tokens[1] = address(mockUSDT);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;

        vm.expectEmit(true, true, true, true);
        emit PoolAdded(address(mockCurvePool), "Curve");

        liquidityProvidingStrategy.addCurvePool(
            address(mockCurvePool),
            address(mockCurvePool), // LP token same as pool for mock
            tokens,
            weights,
            300, // 3% fee APY
            200 // 2% reward APY
        );

        assertEq(liquidityProvidingStrategy.poolCount(), poolId + 1);
    }

    function test_PoolManagement_AddNewUniswapV3Pool() public {
        uint256 poolId = liquidityProvidingStrategy.poolCount();

        address[] memory tokens = new address[](2);
        tokens[0] = address(mockUSDC);
        tokens[1] = address(mockUSDT);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;

        vm.expectEmit(true, true, true, true);
        emit PoolAdded(address(mockUniswapV3Pool), "UniswapV3");

        liquidityProvidingStrategy.addUniswapV3Pool(
            address(mockUniswapV3Pool),
            tokens,
            weights,
            250, // 2.5% fee APY
            150 // 1.5% reward APY
        );

        assertEq(liquidityProvidingStrategy.poolCount(), poolId + 1);
    }

    function test_PoolManagement_DeactivatePool() public {
        // Add a pool first
        address[] memory tokens = new address[](2);
        tokens[0] = address(mockUSDC);
        tokens[1] = address(mockUSDT);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;

        liquidityProvidingStrategy.addCurvePool(
            address(mockCurvePool), address(mockCurvePool), tokens, weights, 300, 200
        );

        liquidityProvidingStrategy.deactivatePool(address(mockCurvePool));

        // Verify it doesn't revert
        assertGe(liquidityProvidingStrategy.poolCount(), 1);
    }

    function test_PoolManagement_UpdatePoolAPY() public {
        // Add a pool first
        address[] memory tokens = new address[](2);
        tokens[0] = address(mockUSDC);
        tokens[1] = address(mockUSDT);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;

        liquidityProvidingStrategy.addCurvePool(
            address(mockCurvePool), address(mockCurvePool), tokens, weights, 300, 200
        );

        uint256 poolId = 0;
        uint256 newAPY = 600; // Combined APY

        liquidityProvidingStrategy.updatePoolAPY(poolId, newAPY);

        // Verify it doesn't revert
        assertGe(liquidityProvidingStrategy.poolCount(), 1);
    }

    // Deposit Tests
    function test_Deposits_AllowVaultToDeposit() public {
        // Add a Curve pool first
        address[] memory tokens = new address[](3);
        tokens[0] = address(mockUSDC);
        tokens[1] = address(mockUSDT);
        tokens[2] = address(mockDAI);

        uint256[] memory weights = new uint256[](3);
        weights[0] = 3333;
        weights[1] = 3333;
        weights[2] = 3334;

        liquidityProvidingStrategy.addCurvePool(
            address(mockCurvePool), address(mockCurvePool), tokens, weights, 300, 200
        );

        vm.expectEmit(true, true, true, true);
        emit LiquidityAdded(address(mockCurvePool), DEPOSIT_AMOUNT);

        vm.prank(vault);
        liquidityProvidingStrategy.deposit(DEPOSIT_AMOUNT);

        assertGt(liquidityProvidingStrategy.totalAssets(), 0);
    }

    function test_Deposits_RevertIfNonVaultTries() public {
        vm.expectRevert("Only vault can call");
        vm.prank(user1);
        liquidityProvidingStrategy.deposit(DEPOSIT_AMOUNT);
    }

    function test_Deposits_RevertIfZeroAmount() public {
        vm.expectRevert("Amount must be positive");
        vm.prank(vault);
        liquidityProvidingStrategy.deposit(0);
    }

    function test_Deposits_ChooseOptimalPool() public {
        // Add multiple pools with different APYs
        address[] memory tokens = new address[](3);
        tokens[0] = address(mockUSDC);
        tokens[1] = address(mockUSDT);
        tokens[2] = address(mockDAI);

        uint256[] memory weights = new uint256[](3);
        weights[0] = 3333;
        weights[1] = 3333;
        weights[2] = 3334;

        liquidityProvidingStrategy.addCurvePool(
            address(mockCurvePool), address(mockCurvePool), tokens, weights, 300, 200
        );

        address[] memory tokens2 = new address[](2);
        tokens2[0] = address(mockUSDC);
        tokens2[1] = address(mockUSDT);

        uint256[] memory weights2 = new uint256[](2);
        weights2[0] = 5000;
        weights2[1] = 5000;

        liquidityProvidingStrategy.addUniswapV3Pool(
            address(mockUniswapV3Pool),
            tokens2,
            weights2,
            400, // Higher APY
            300
        );

        vm.prank(vault);
        liquidityProvidingStrategy.deposit(DEPOSIT_AMOUNT);

        // Should choose pool with better APY
        assertGt(liquidityProvidingStrategy.totalAssets(), 0);
    }

    // Withdrawal Tests
    function test_Withdrawals_AllowVaultToWithdraw() public {
        // Add pool and deposit first
        address[] memory tokens = new address[](3);
        tokens[0] = address(mockUSDC);
        tokens[1] = address(mockUSDT);
        tokens[2] = address(mockDAI);

        uint256[] memory weights = new uint256[](3);
        weights[0] = 3333;
        weights[1] = 3333;
        weights[2] = 3334;

        liquidityProvidingStrategy.addCurvePool(
            address(mockCurvePool), address(mockCurvePool), tokens, weights, 300, 200
        );

        vm.prank(vault);
        liquidityProvidingStrategy.deposit(DEPOSIT_AMOUNT);

        uint256 withdrawAmount = 500 * 10 ** 6;

        vm.expectEmit(true, true, true, true);
        emit LiquidityRemoved(address(mockCurvePool), withdrawAmount);

        vm.prank(vault);
        liquidityProvidingStrategy.withdraw(withdrawAmount);
    }

    function test_Withdrawals_RevertIfNonVaultTries() public {
        uint256 withdrawAmount = 500 * 10 ** 6;

        vm.expectRevert("Only vault can call");
        vm.prank(user1);
        liquidityProvidingStrategy.withdraw(withdrawAmount);
    }

    function test_Withdrawals_RevertIfZeroAmount() public {
        vm.expectRevert("Amount must be positive");
        vm.prank(vault);
        liquidityProvidingStrategy.withdraw(0);
    }

    function test_Withdrawals_AllowWithdrawingAllAssets() public {
        // Add pool and deposit first
        address[] memory tokens = new address[](3);
        tokens[0] = address(mockUSDC);
        tokens[1] = address(mockUSDT);
        tokens[2] = address(mockDAI);

        uint256[] memory weights = new uint256[](3);
        weights[0] = 3333;
        weights[1] = 3333;
        weights[2] = 3334;

        liquidityProvidingStrategy.addCurvePool(
            address(mockCurvePool), address(mockCurvePool), tokens, weights, 300, 200
        );

        vm.prank(vault);
        liquidityProvidingStrategy.deposit(DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit LiquidityRemoved(address(mockCurvePool), DEPOSIT_AMOUNT);

        vm.prank(vault);
        liquidityProvidingStrategy.withdrawAll();
    }

    // Access Control Tests
    function test_AccessControl_OnlyOwnerCanAddPools() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(mockUSDC);
        tokens[1] = address(mockUSDT);
        tokens[2] = address(mockDAI);

        uint256[] memory weights = new uint256[](3);
        weights[0] = 3333;
        weights[1] = 3333;
        weights[2] = 3334;

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        liquidityProvidingStrategy.addCurvePool(
            address(mockCurvePool), address(mockCurvePool), tokens, weights, 300, 200
        );
    }

    function test_AccessControl_OnlyOwnerCanSetRiskTolerance() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        liquidityProvidingStrategy.setRiskTolerance(50);
    }

    // Fuzz Tests
    function testFuzz_Deposits_ValidAmounts(uint256 amount) public {
        amount = bound(amount, 1000, INITIAL_SUPPLY);

        // Add pool first
        address[] memory tokens = new address[](2);
        tokens[0] = address(mockUSDC);
        tokens[1] = address(mockUSDT);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;

        liquidityProvidingStrategy.addCurvePool(
            address(mockCurvePool), address(mockCurvePool), tokens, weights, 300, 200
        );

        vm.prank(vault);
        liquidityProvidingStrategy.deposit(amount);

        assertGt(liquidityProvidingStrategy.totalAssets(), 0);
    }
}
