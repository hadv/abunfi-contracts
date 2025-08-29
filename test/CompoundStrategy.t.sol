// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/strategies/CompoundStrategy.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockComet.sol";
import "../src/mocks/MockCometRewards.sol";

contract CompoundStrategyTest is Test {
    CompoundStrategy public compoundStrategy;
    MockComet public mockComet;
    MockCometRewards public mockCometRewards;
    MockERC20 public mockUSDC;
    
    address public owner;
    address public vault;
    address public user1;
    address public user2;
    
    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10**6; // 1M USDC
    uint256 constant DEPOSIT_AMOUNT = 1000 * 10**6; // 1000 USDC
    
    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event Harvested(uint256 yield);
    event RewardsClaimed(uint256 amount);
    
    function setUp() public {
        owner = address(this);
        vault = makeAddr("vault");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Deploy mock USDC
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        
        // Deploy mock Comet
        mockComet = new MockComet(address(mockUSDC));
        
        // Deploy mock CometRewards
        mockCometRewards = new MockCometRewards();
        
        // Deploy CompoundStrategy
        compoundStrategy = new CompoundStrategy(
            address(mockUSDC),
            address(mockComet),
            address(mockCometRewards),
            vault
        );
        
        // Setup initial balances
        mockUSDC.mint(vault, INITIAL_SUPPLY);
        vm.prank(vault);
        mockUSDC.approve(address(compoundStrategy), INITIAL_SUPPLY);
    }
    
    // Deployment Tests
    function test_Deployment_SetsCorrectAsset() public {
        assertEq(address(compoundStrategy.asset()), address(mockUSDC));
    }
    
    function test_Deployment_SetsCorrectVault() public {
        assertEq(compoundStrategy.vault(), vault);
    }
    
    function test_Deployment_SetsCorrectComet() public {
        assertEq(address(compoundStrategy.comet()), address(mockComet));
    }
    
    function test_Deployment_HasCorrectName() public {
        assertEq(compoundStrategy.name(), "Compound V3 USDC Lending Strategy");
    }
    
    // Deposit Tests
    function test_Deposits_AllowVaultToDeposit() public {
        // Transfer tokens to strategy (simulating vault transfer)
        vm.prank(vault);
        mockUSDC.transfer(address(compoundStrategy), DEPOSIT_AMOUNT);
        
        vm.expectEmit(true, true, true, true);
        emit Deposited(DEPOSIT_AMOUNT);
        
        vm.prank(vault);
        compoundStrategy.deposit(DEPOSIT_AMOUNT);
        
        assertEq(compoundStrategy.totalDeposited(), DEPOSIT_AMOUNT);
    }
    
    function test_Deposits_RevertIfNonVaultTries() public {
        vm.expectRevert("Only vault can call");
        vm.prank(user1);
        compoundStrategy.deposit(DEPOSIT_AMOUNT);
    }
    
    function test_Deposits_RevertIfZeroAmount() public {
        vm.expectRevert("Cannot deposit 0");
        vm.prank(vault);
        compoundStrategy.deposit(0);
    }
    
    function test_Deposits_UpdateTotalAssetsAfterDeposit() public {
        vm.prank(vault);
        mockUSDC.transfer(address(compoundStrategy), DEPOSIT_AMOUNT);
        
        vm.prank(vault);
        compoundStrategy.deposit(DEPOSIT_AMOUNT);
        
        assertGt(compoundStrategy.totalAssets(), 0);
    }
    
    // Withdrawal Tests
    function test_Withdrawals_AllowVaultToWithdraw() public {
        // First deposit
        vm.prank(vault);
        mockUSDC.transfer(address(compoundStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        compoundStrategy.deposit(DEPOSIT_AMOUNT);
        
        // Then withdraw
        uint256 withdrawAmount = 500 * 10**6;
        
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(withdrawAmount);
        
        vm.prank(vault);
        compoundStrategy.withdraw(withdrawAmount);
    }
    
    function test_Withdrawals_RevertIfNonVaultTries() public {
        uint256 withdrawAmount = 500 * 10**6;
        
        vm.expectRevert("Only vault can call");
        vm.prank(user1);
        compoundStrategy.withdraw(withdrawAmount);
    }
    
    function test_Withdrawals_RevertIfZeroAmount() public {
        vm.expectRevert("Cannot withdraw 0");
        vm.prank(vault);
        compoundStrategy.withdraw(0);
    }
    
    function test_Withdrawals_AllowWithdrawingAllAssets() public {
        // First deposit
        vm.prank(vault);
        mockUSDC.transfer(address(compoundStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        compoundStrategy.deposit(DEPOSIT_AMOUNT);
        
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(DEPOSIT_AMOUNT);
        
        vm.prank(vault);
        compoundStrategy.withdrawAll();
        
        assertEq(compoundStrategy.totalDeposited(), 0);
    }
    
    // Harvest Tests
    function test_Harvest_AllowVaultToHarvest() public {
        // First deposit
        vm.prank(vault);
        mockUSDC.transfer(address(compoundStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        compoundStrategy.deposit(DEPOSIT_AMOUNT);
        
        // Simulate yield by increasing comet balance
        uint256 yieldAmount = 50 * 10**6;
        mockComet.setBalance(address(compoundStrategy), DEPOSIT_AMOUNT + yieldAmount);
        
        vm.expectEmit(true, true, true, true);
        emit Harvested(yieldAmount);
        
        vm.prank(vault);
        compoundStrategy.harvest();
    }
    
    function test_Harvest_ReturnCorrectYieldAmount() public {
        // First deposit
        vm.prank(vault);
        mockUSDC.transfer(address(compoundStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        compoundStrategy.deposit(DEPOSIT_AMOUNT);
        
        uint256 yieldAmount = 50 * 10**6;
        mockComet.setBalance(address(compoundStrategy), DEPOSIT_AMOUNT + yieldAmount);
        
        vm.prank(vault);
        uint256 harvestResult = compoundStrategy.harvest();
        assertEq(harvestResult, yieldAmount);
    }
    
    function test_Harvest_UpdateTotalDepositedAfterHarvest() public {
        // First deposit
        vm.prank(vault);
        mockUSDC.transfer(address(compoundStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        compoundStrategy.deposit(DEPOSIT_AMOUNT);
        
        uint256 yieldAmount = 50 * 10**6;
        uint256 newBalance = DEPOSIT_AMOUNT + yieldAmount;
        mockComet.setBalance(address(compoundStrategy), newBalance);
        
        vm.prank(vault);
        compoundStrategy.harvest();
        
        assertEq(compoundStrategy.totalDeposited(), newBalance);
    }
    
    function test_Harvest_RevertIfNonVaultTries() public {
        vm.expectRevert("Only vault can call");
        vm.prank(user1);
        compoundStrategy.harvest();
    }
    
    // APY Calculation Tests
    function test_APYCalculation_ReturnCorrectAPY() public {
        // Mock supply rate (5% APY)
        uint64 supplyRate = 158548959919; // Simplified 5% APY rate // 5% per year in per-second rate
        mockComet.setSupplyRate(supplyRate);
        
        uint256 apy = compoundStrategy.getAPY();
        assertGt(apy, 0);
    }
    
    function test_APYCalculation_ReturnCurrentSupplyRate() public {
        uint64 supplyRate = 158548959919; // Simplified 5% APY rate
        mockComet.setSupplyRate(supplyRate);
        
        uint256 currentRate = compoundStrategy.getCurrentSupplyRate();
        assertEq(currentRate, supplyRate);
    }
    
    // Rewards Tests
    function test_Rewards_ReturnPendingRewards() public {
        uint256 rewardAmount = 10 * 10**18; // 10 COMP
        mockCometRewards.setRewardOwed(address(mockComet), address(compoundStrategy), rewardAmount);
        
        uint256 pendingRewards = compoundStrategy.getPendingRewards();
        assertEq(pendingRewards, rewardAmount);
    }
    
    function test_Rewards_AllowOwnerToClaimRewards() public {
        uint256 rewardAmount = 10 * 10**18;
        mockCometRewards.setRewardOwed(address(mockComet), address(compoundStrategy), rewardAmount);
        
        vm.expectEmit(true, true, true, true);
        emit RewardsClaimed(rewardAmount);
        
        compoundStrategy.claimRewards();
    }
    
    function test_Rewards_RevertIfNonOwnerTriesToClaimRewards() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        compoundStrategy.claimRewards();
    }
    
    // Utilization Tests
    function test_Utilization_ReturnMarketUtilization() public {
        uint256 utilization = 8000; // 80%
        mockComet.setUtilization(utilization);
        
        uint256 currentUtilization = compoundStrategy.getUtilization();
        assertEq(currentUtilization, utilization);
    }
    
    // Emergency Functions Tests
    function test_EmergencyFunctions_AllowOwnerToEmergencyWithdraw() public {
        uint256 emergencyAmount = 100 * 10**6;
        mockUSDC.mint(address(compoundStrategy), emergencyAmount);
        
        uint256 ownerBalanceBefore = mockUSDC.balanceOf(owner);
        compoundStrategy.emergencyWithdraw(address(mockUSDC), emergencyAmount);
        uint256 ownerBalanceAfter = mockUSDC.balanceOf(owner);
        
        assertEq(ownerBalanceAfter - ownerBalanceBefore, emergencyAmount);
    }
    
    function test_EmergencyFunctions_RevertIfNonOwnerTriesEmergencyWithdraw() public {
        uint256 emergencyAmount = 100 * 10**6;
        
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        compoundStrategy.emergencyWithdraw(address(mockUSDC), emergencyAmount);
    }
    
    // View Functions Tests
    function test_ViewFunctions_ReturnCorrectAccruedYield() public {
        // First deposit
        vm.prank(vault);
        mockUSDC.transfer(address(compoundStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        compoundStrategy.deposit(DEPOSIT_AMOUNT);
        
        uint256 yieldAmount = 25 * 10**6;
        mockComet.setBalance(address(compoundStrategy), DEPOSIT_AMOUNT + yieldAmount);
        
        uint256 accruedYield = compoundStrategy.getAccruedYield();
        assertEq(accruedYield, yieldAmount);
    }
    
    function test_ViewFunctions_ReturnZeroAccruedYieldWhenNoYield() public {
        // First deposit
        vm.prank(vault);
        mockUSDC.transfer(address(compoundStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        compoundStrategy.deposit(DEPOSIT_AMOUNT);
        
        uint256 accruedYield = compoundStrategy.getAccruedYield();
        assertEq(accruedYield, 0);
    }
    
    function test_ViewFunctions_ReturnCorrectTotalAssets() public {
        vm.prank(vault);
        mockUSDC.transfer(address(compoundStrategy), DEPOSIT_AMOUNT);
        vm.prank(vault);
        compoundStrategy.deposit(DEPOSIT_AMOUNT);
        
        assertEq(compoundStrategy.totalAssets(), DEPOSIT_AMOUNT);
    }
    
    // Access Control Tests
    function test_AccessControl_OnlyOwnerCanTransferOwnership() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        compoundStrategy.transferOwnership(user1);
    }
    
    // Fuzz Tests
    function testFuzz_Deposits_ValidAmounts(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_SUPPLY);
        
        vm.prank(vault);
        mockUSDC.transfer(address(compoundStrategy), amount);
        
        vm.prank(vault);
        compoundStrategy.deposit(amount);
        
        assertEq(compoundStrategy.totalDeposited(), amount);
        assertEq(compoundStrategy.totalAssets(), amount);
    }
    
    function testFuzz_Withdrawals_ValidAmounts(uint256 depositAmount, uint256 withdrawRatio) public {
        depositAmount = bound(depositAmount, 1000, INITIAL_SUPPLY);
        withdrawRatio = bound(withdrawRatio, 1, 100);
        
        // Deposit first
        vm.prank(vault);
        mockUSDC.transfer(address(compoundStrategy), depositAmount);
        vm.prank(vault);
        compoundStrategy.deposit(depositAmount);
        
        // Calculate withdraw amount
        uint256 withdrawAmount = (depositAmount * withdrawRatio) / 100;
        
        if (withdrawAmount > 0) {
            vm.prank(vault);
            compoundStrategy.withdraw(withdrawAmount);
            
            assertEq(compoundStrategy.totalDeposited(), depositAmount - withdrawAmount);
        }
    }
}
