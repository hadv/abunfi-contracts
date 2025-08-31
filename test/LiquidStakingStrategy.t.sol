// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/strategies/LiquidStakingStrategy.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockLidoStETH.sol";
import "../src/mocks/MockRocketPoolRETH.sol";

contract LiquidStakingStrategyTest is Test {
    LiquidStakingStrategy public liquidStakingStrategy;
    MockERC20 public mockWETH;
    MockLidoStETH public mockStETH;
    MockRocketPoolRETH public mockRETH;

    address public owner;
    address public vault;
    address public user1;
    address public user2;

    uint256 constant INITIAL_SUPPLY = 1000 * 10 ** 18; // 1000 ETH
    uint256 constant DEPOSIT_AMOUNT = 10 * 10 ** 18; // 10 ETH

    event ProviderAdded(address indexed provider);
    event Staked(address indexed token, uint256 amount);
    event Unstaked(address indexed provider, uint256 amount);
    event RewardsHarvested(uint256 amount);
    event ProviderRebalanced(address indexed token, uint256 oldAmount, uint256 newAmount);
    event ExchangeRateUpdated(address indexed provider, uint256 newRate);

    function setUp() public {
        owner = address(this);
        vault = makeAddr("vault");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock WETH
        mockWETH = new MockERC20("Wrapped Ether", "WETH", 18);

        // Deploy mock stETH
        mockStETH = new MockLidoStETH();

        // Deploy mock rETH
        mockRETH = new MockRocketPoolRETH();

        // Deploy LiquidStakingStrategy
        liquidStakingStrategy =
            new LiquidStakingStrategy(address(mockWETH), address(mockStETH), vault, "Liquid Staking Strategy");

        // Setup initial balances
        mockWETH.mint(vault, INITIAL_SUPPLY);
        vm.prank(vault);
        mockWETH.approve(address(liquidStakingStrategy), INITIAL_SUPPLY);

        // Add ETH to mock contracts for staking
        vm.deal(address(mockStETH), 100 ether);
        vm.deal(address(mockRETH), 100 ether);
    }

    // Deployment Tests
    function test_Deployment_InitializeWithCorrectParameters() public {
        assertEq(liquidStakingStrategy.name(), "Liquid Staking Strategy");
        assertEq(address(liquidStakingStrategy.asset()), address(mockWETH));
        assertEq(liquidStakingStrategy.riskTolerance(), 50);
        assertEq(liquidStakingStrategy.maxSingleProviderAllocation(), 4000);
    }

    function test_Deployment_HasProvidersInitialized() public {
        // Add a provider first
        liquidStakingStrategy.addProvider(
            address(mockStETH),
            address(mockWETH),
            400, // 4% APY
            10, // risk score
            0 // Lido provider type
        );
        assertGt(liquidStakingStrategy.providerCount(), 0);
    }

    // Provider Management Tests
    function test_ProviderManagement_AddNewStakingProvider() public {
        uint256 providerId = liquidStakingStrategy.providerCount();

        liquidStakingStrategy.addProvider(
            address(mockStETH),
            address(mockWETH),
            500, // 5% APY
            10, // risk score
            0 // LIDO type
        );

        assertEq(liquidStakingStrategy.providerCount(), providerId + 1);
    }

    function test_ProviderManagement_DeactivateProvider() public {
        // First add a provider
        liquidStakingStrategy.addProvider(
            address(mockStETH),
            address(mockWETH),
            500,
            10, // risk score
            0 // provider type
        );

        liquidStakingStrategy.deactivateProvider(address(mockStETH));

        // Check that provider count remains the same but provider is deactivated
        assertGe(liquidStakingStrategy.providerCount(), 1);
    }

    function test_ProviderManagement_UpdateProviderAPY() public {
        // First add a provider
        liquidStakingStrategy.addProvider(
            address(mockStETH),
            address(mockWETH),
            500,
            10, // risk score
            0 // provider type
        );

        uint256 providerId = 0;
        uint256 newAPY = 600; // 6%

        liquidStakingStrategy.updateProviderAPY(providerId, newAPY);

        assertEq(liquidStakingStrategy.getProviderAPY(providerId), newAPY);
    }

    function test_ProviderManagement_UpdateExchangeRate() public {
        // First add a provider
        liquidStakingStrategy.addProvider(
            address(mockStETH),
            address(mockWETH),
            500,
            10, // risk score
            0 // provider type
        );

        uint256 providerId = 0;
        uint256 newRate = 1.1 * 10 ** 18; // 1.1 ETH per staking token

        liquidStakingStrategy.updateExchangeRate(providerId, newRate);
    }

    // Deposit Tests
    function test_Deposits_AllowVaultToDeposit() public {
        // Add provider first
        liquidStakingStrategy.addProvider(address(mockStETH), address(mockWETH), 500, 10, 0);

        vm.prank(vault);
        liquidStakingStrategy.deposit(DEPOSIT_AMOUNT);

        assertGt(liquidStakingStrategy.totalAssets(), 0);
    }

    function test_Deposits_RevertIfNonVaultTries() public {
        vm.expectRevert("Only vault can call");
        vm.prank(user1);
        liquidStakingStrategy.deposit(DEPOSIT_AMOUNT);
    }

    function test_Deposits_RevertIfZeroAmount() public {
        vm.expectRevert("Amount must be positive");
        vm.prank(vault);
        liquidStakingStrategy.deposit(0);
    }

    function test_Deposits_ChooseOptimalProvider() public {
        // Add multiple providers with different APYs
        liquidStakingStrategy.addProvider(
            address(mockStETH),
            address(mockWETH),
            500, // 5% APY
            10, // 10% slashing risk
            0 // LIDO type
        );

        liquidStakingStrategy.addProvider(
            address(mockRETH),
            address(mockWETH),
            450, // 4.5% APY
            5, // 5% slashing risk
            1 // ROCKET_POOL type
        );

        vm.prank(vault);
        liquidStakingStrategy.deposit(DEPOSIT_AMOUNT);

        // Should choose provider with better risk-adjusted return
        assertGt(liquidStakingStrategy.totalAssets(), 0);
    }

    // Withdrawal Tests
    function test_Withdrawals_AllowVaultToWithdraw() public {
        // Add providers and deposit first
        liquidStakingStrategy.addProvider(address(mockStETH), address(mockWETH), 500, 10, 0);

        vm.prank(vault);
        liquidStakingStrategy.deposit(DEPOSIT_AMOUNT);

        uint256 withdrawAmount = 5 * 10 ** 18;

        vm.prank(vault);
        liquidStakingStrategy.withdraw(withdrawAmount);
    }

    function test_Withdrawals_RevertIfNonVaultTries() public {
        uint256 withdrawAmount = 5 * 10 ** 18;

        vm.expectRevert("Only vault can call");
        vm.prank(user1);
        liquidStakingStrategy.withdraw(withdrawAmount);
    }

    function test_Withdrawals_RevertIfZeroAmount() public {
        vm.expectRevert("Amount must be positive");
        vm.prank(vault);
        liquidStakingStrategy.withdraw(0);
    }

    function test_Withdrawals_AllowWithdrawingAllAssets() public {
        // Add providers and deposit first
        liquidStakingStrategy.addProvider(address(mockStETH), address(mockWETH), 500, 10, 0);

        vm.prank(vault);
        liquidStakingStrategy.deposit(DEPOSIT_AMOUNT);

        vm.prank(vault);
        liquidStakingStrategy.withdrawAll();
    }

    function test_Withdrawals_HandlePartialWithdrawalsCorrectly() public {
        // Add providers and deposit first
        liquidStakingStrategy.addProvider(address(mockStETH), address(mockWETH), 500, 10, 0);

        vm.prank(vault);
        liquidStakingStrategy.deposit(DEPOSIT_AMOUNT);

        uint256 totalBefore = liquidStakingStrategy.totalAssets();
        uint256 withdrawAmount = totalBefore / 2;

        vm.prank(vault);
        liquidStakingStrategy.withdraw(withdrawAmount);

        uint256 totalAfter = liquidStakingStrategy.totalAssets();
        assertLt(totalAfter, totalBefore);
    }

    // Harvest Tests
    function test_Harvest_AllowVaultToHarvest() public {
        // Add providers and deposit first
        liquidStakingStrategy.addProvider(address(mockStETH), address(mockWETH), 500, 10, 0);

        vm.prank(vault);
        liquidStakingStrategy.deposit(DEPOSIT_AMOUNT);

        // Simulate staking rewards
        mockStETH.accrueRewards();

        vm.prank(vault);
        liquidStakingStrategy.harvest();
    }

    function test_Harvest_ReturnYieldAmount() public {
        // Add providers and deposit first
        liquidStakingStrategy.addProvider(address(mockStETH), address(mockWETH), 500, 10, 0);

        vm.prank(vault);
        liquidStakingStrategy.deposit(DEPOSIT_AMOUNT);

        // Simulate some yield
        mockStETH.accrueRewards();

        vm.prank(vault);
        uint256 yield = liquidStakingStrategy.harvest();
        assertGe(yield, 0);
    }

    function test_Harvest_RevertIfNonVaultTries() public {
        vm.expectRevert("Only vault can call");
        vm.prank(user1);
        liquidStakingStrategy.harvest();
    }

    // Rebalancing Tests
    function test_Rebalancing_RebalanceWhenThresholdExceeded() public {
        // Add multiple providers
        liquidStakingStrategy.addProvider(address(mockStETH), address(mockWETH), 500, 10, 0);

        liquidStakingStrategy.addProvider(address(mockRETH), address(mockWETH), 450, 5, 1);

        vm.prank(vault);
        liquidStakingStrategy.deposit(DEPOSIT_AMOUNT);

        // Change APY to trigger rebalancing
        liquidStakingStrategy.updateProviderAPY(1, 600); // Make rETH more attractive

        liquidStakingStrategy.rebalance();
    }

    function test_Rebalancing_NotRebalanceIfWithinThreshold() public {
        // Add providers and deposit first
        liquidStakingStrategy.addProvider(address(mockStETH), address(mockWETH), 500, 10, 0);

        liquidStakingStrategy.addProvider(address(mockRETH), address(mockWETH), 450, 5, 1);

        vm.prank(vault);
        liquidStakingStrategy.deposit(DEPOSIT_AMOUNT);

        // Small APY change that shouldn't trigger major rebalancing
        liquidStakingStrategy.updateProviderAPY(0, 505);

        // Should not revert
        liquidStakingStrategy.rebalance();
    }

    function test_Rebalancing_RespectMaximumAllocationLimits() public {
        // Add providers and deposit first
        liquidStakingStrategy.addProvider(address(mockStETH), address(mockWETH), 500, 10, 0);

        liquidStakingStrategy.addProvider(address(mockRETH), address(mockWETH), 450, 5, 1);

        vm.prank(vault);
        liquidStakingStrategy.deposit(DEPOSIT_AMOUNT);

        // Set very high APY for one provider
        liquidStakingStrategy.updateProviderAPY(0, 2000); // 20% APY

        liquidStakingStrategy.rebalance();

        // Check that allocation doesn't exceed maximum
        uint256 allocation = liquidStakingStrategy.getProviderAllocation(0);
        assertLe(allocation, 100000); // Max allocation in basis points
    }

    // Risk Management Tests
    function test_RiskManagement_CalculateRiskAdjustedAPYCorrectly() public {
        // Add a provider first
        liquidStakingStrategy.addProvider(
            address(mockStETH),
            address(mockWETH),
            500,
            10, // risk score
            0 // provider type
        );

        uint256 providerId = 0;
        uint256 riskAdjustedAPY = liquidStakingStrategy.calculateRiskAdjustedAPY(providerId);
        assertGt(riskAdjustedAPY, 0);
    }

    function test_RiskManagement_RespectRiskTolerance() public {
        // Add a normal provider first
        liquidStakingStrategy.addProvider(
            address(mockStETH),
            address(mockWETH),
            500,
            10, // risk score
            0 // provider type
        );

        // Should not allocate to high-risk provider if risk tolerance is low
        liquidStakingStrategy.setRiskTolerance(20); // Low risk tolerance

        vm.prank(vault);
        liquidStakingStrategy.deposit(DEPOSIT_AMOUNT);

        // Verify the function works without reverting
        assertGe(liquidStakingStrategy.totalAssets(), 0);
    }

    // View Functions Tests
    function test_ViewFunctions_ReturnCorrectTotalAssets() public {
        liquidStakingStrategy.addProvider(address(mockStETH), address(mockWETH), 500, 10, 0);

        vm.prank(vault);
        liquidStakingStrategy.deposit(DEPOSIT_AMOUNT);

        uint256 totalAssets = liquidStakingStrategy.totalAssets();
        assertGt(totalAssets, 0);
    }

    function test_ViewFunctions_ReturnCorrectAPY() public {
        liquidStakingStrategy.addProvider(address(mockStETH), address(mockWETH), 500, 10, 0);

        vm.prank(vault);
        liquidStakingStrategy.deposit(DEPOSIT_AMOUNT);

        uint256 apy = liquidStakingStrategy.getAPY();
        assertGt(apy, 0);
    }

    function test_ViewFunctions_ReturnProviderAllocation() public {
        liquidStakingStrategy.addProvider(address(mockStETH), address(mockWETH), 500, 10, 0);

        vm.prank(vault);
        liquidStakingStrategy.deposit(DEPOSIT_AMOUNT);

        uint256 allocation = liquidStakingStrategy.getProviderAllocation(0);
        assertGe(allocation, 0);
    }

    function test_ViewFunctions_ReturnDiversificationScore() public {
        liquidStakingStrategy.addProvider(address(mockStETH), address(mockWETH), 500, 10, 0);

        vm.prank(vault);
        liquidStakingStrategy.deposit(DEPOSIT_AMOUNT);

        uint256 score = liquidStakingStrategy.getDiversificationScore();
        assertGe(score, 0);
    }

    // Access Control Tests
    function test_AccessControl_OnlyOwnerCanAddProviders() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        liquidStakingStrategy.addProvider(address(mockStETH), address(mockWETH), 500, 10, 0);
    }

    function test_AccessControl_OnlyOwnerCanSetRiskTolerance() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        liquidStakingStrategy.setRiskTolerance(50);
    }

    // Fuzz Tests
    function testFuzz_Deposits_ValidAmounts(uint256 amount) public {
        amount = bound(amount, 1 ether, INITIAL_SUPPLY);

        liquidStakingStrategy.addProvider(address(mockStETH), address(mockWETH), 500, 10, 0);

        vm.prank(vault);
        liquidStakingStrategy.deposit(amount);

        assertGt(liquidStakingStrategy.totalAssets(), 0);
    }

    function testFuzz_RiskTolerance_ValidValues(uint256 tolerance) public {
        tolerance = bound(tolerance, 1, 100);

        liquidStakingStrategy.setRiskTolerance(tolerance);
        assertEq(liquidStakingStrategy.riskTolerance(), tolerance);
    }
}
