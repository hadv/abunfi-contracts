// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockStrategy.sol";
import "../src/RiskProfileManager.sol";
import "../src/WithdrawalManager.sol";

/**
 * @title EconomicAttackVectors
 * @dev Tests for economic attacks, MEV extraction, and financial manipulation
 * Critical for production DeFi applications to resist economic exploitation
 */
contract EconomicAttackVectorsTest is Test {
    AbunfiVault public vault;
    MockERC20 public mockUSDC;
    MockStrategy public mockStrategy;
    RiskProfileManager public riskManager;
    WithdrawalManager public withdrawalManager;

    address public owner;
    address public attacker;
    address public victim;
    address public mevBot;
    address public frontRunner;

    uint256 constant LARGE_AMOUNT = 1_000_000 * 10**6; // 1M USDC
    uint256 constant VICTIM_AMOUNT = 100_000 * 10**6; // 100k USDC
    uint256 constant ATTACK_AMOUNT = 10_000_000 * 10**6; // 10M USDC

    event SandwichAttackDetected(address indexed attacker, uint256 frontRunAmount, uint256 backRunAmount);
    event MEVExtracted(address indexed bot, uint256 extractedValue);

    function setUp() public {
        owner = address(this);
        attacker = makeAddr("attacker");
        victim = makeAddr("victim");
        mevBot = makeAddr("mevBot");
        frontRunner = makeAddr("frontRunner");

        // Deploy mock USDC
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);

        // Deploy risk management
        riskManager = new RiskProfileManager();

        // Deploy vault first
        vault = new AbunfiVault(
            address(mockUSDC),
            address(0),
            address(riskManager),
            address(0) // Temporary
        );

        // Deploy withdrawal manager with vault address
        withdrawalManager = new WithdrawalManager(address(vault), address(mockUSDC));

        // Update vault with correct withdrawal manager
        vault.updateRiskManagers(address(riskManager), address(withdrawalManager));

        // Deploy and add strategy
        mockStrategy = new MockStrategy(address(mockUSDC), "Mock Strategy", 500); // 5% APY
        vault.addStrategy(address(mockStrategy));

        // Mint tokens to participants
        mockUSDC.mint(attacker, ATTACK_AMOUNT);
        mockUSDC.mint(victim, VICTIM_AMOUNT);
        mockUSDC.mint(mevBot, ATTACK_AMOUNT);
        mockUSDC.mint(frontRunner, ATTACK_AMOUNT);
    }

    // ============ SANDWICH ATTACK TESTS ============

    function test_SandwichAttack_DepositManipulation() public {
        // Attacker front-runs victim's deposit to manipulate share price
        
        // 1. Attacker deposits large amount first (front-run)
        vm.startPrank(attacker);
        mockUSDC.approve(address(vault), LARGE_AMOUNT);
        vault.deposit(LARGE_AMOUNT);
        vm.stopPrank();

        uint256 attackerSharesBefore = vault.userShares(attacker);
        
        // 2. Victim deposits (the transaction being sandwiched)
        vm.startPrank(victim);
        mockUSDC.approve(address(vault), VICTIM_AMOUNT);
        vault.deposit(VICTIM_AMOUNT);
        vm.stopPrank();

        uint256 victimShares = vault.userShares(victim);
        
        // 3. Attacker withdraws (back-run)
        vm.startPrank(attacker);
        vault.withdraw(attackerSharesBefore);
        vm.stopPrank();

        // Verify victim didn't get unfairly diluted
        // In a fair system, victim should get proportional shares
        uint256 expectedVictimShares = VICTIM_AMOUNT * vault.SHARES_MULTIPLIER() / 1e6;
        uint256 tolerance = expectedVictimShares / 100; // 1% tolerance
        
        assertTrue(
            victimShares >= expectedVictimShares - tolerance,
            "Victim shares should not be significantly diluted"
        );
    }

    function test_SandwichAttack_WithdrawalManipulation() public {
        // Setup: Both attacker and victim have deposits
        vm.startPrank(attacker);
        mockUSDC.approve(address(vault), LARGE_AMOUNT);
        vault.deposit(LARGE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(victim);
        mockUSDC.approve(address(vault), VICTIM_AMOUNT);
        vault.deposit(VICTIM_AMOUNT);
        vm.stopPrank();

        // Add some yield to make the attack more profitable
        mockStrategy.addYield(50_000 * 10**6); // 50k USDC yield

        uint256 victimBalanceBefore = mockUSDC.balanceOf(victim);
        uint256 attackerBalanceBefore = mockUSDC.balanceOf(attacker);

        // Attacker tries to extract MEV from victim's withdrawal
        uint256 victimShares = vault.userShares(victim);
        uint256 attackerShares = vault.userShares(attacker);

        // 1. Attacker front-runs victim's withdrawal
        vm.startPrank(attacker);
        vault.withdraw(attackerShares / 2); // Partial withdrawal
        vm.stopPrank();

        // 2. Victim withdraws
        vm.startPrank(victim);
        vault.withdraw(victimShares);
        vm.stopPrank();

        // 3. Attacker back-runs
        vm.startPrank(attacker);
        vault.withdraw(vault.userShares(attacker)); // Withdraw remaining
        vm.stopPrank();

        uint256 victimBalanceAfter = mockUSDC.balanceOf(victim);
        uint256 attackerBalanceAfter = mockUSDC.balanceOf(attacker);

        uint256 victimProfit = victimBalanceAfter - victimBalanceBefore;
        uint256 attackerProfit = attackerBalanceAfter - attackerBalanceBefore;

        // Victim should still get reasonable returns despite sandwich attack
        assertTrue(victimProfit >= VICTIM_AMOUNT, "Victim should at least get principal back");
    }

    // ============ FLASH LOAN ATTACK SIMULATION ============

    function test_FlashLoanAttack_SharePriceManipulation() public {
        FlashLoanAttacker attackContract = new FlashLoanAttacker(vault, mockUSDC);
        
        // Fund the attack contract
        mockUSDC.mint(address(attackContract), ATTACK_AMOUNT);
        
        // Victim makes initial deposit
        vm.startPrank(victim);
        mockUSDC.approve(address(vault), VICTIM_AMOUNT);
        vault.deposit(VICTIM_AMOUNT);
        vm.stopPrank();

        uint256 victimSharesBefore = vault.userShares(victim);
        
        // Execute flash loan attack
        attackContract.executeFlashLoanAttack(ATTACK_AMOUNT);
        
        uint256 victimSharesAfter = vault.userShares(victim);
        
        // Victim's shares should not be significantly affected
        assertApproxEqRel(
            victimSharesAfter,
            victimSharesBefore,
            0.05e18, // 5% tolerance
            "Flash loan attack should not significantly affect existing users"
        );
    }

    // ============ FRONT-RUNNING TESTS ============

    function test_FrontRunning_DepositOrdering() public {
        // Simulate front-running scenario where attacker sees victim's transaction
        // and tries to profit by front-running it
        
        uint256 frontRunAmount = VICTIM_AMOUNT * 10; // 10x victim's amount
        
        // Front-runner deposits first
        vm.startPrank(frontRunner);
        mockUSDC.approve(address(vault), frontRunAmount);
        vault.deposit(frontRunAmount);
        vm.stopPrank();

        uint256 frontRunnerShares = vault.userShares(frontRunner);
        
        // Victim deposits after
        vm.startPrank(victim);
        mockUSDC.approve(address(vault), VICTIM_AMOUNT);
        vault.deposit(VICTIM_AMOUNT);
        vm.stopPrank();

        uint256 victimShares = vault.userShares(victim);
        
        // Check if front-running provided unfair advantage
        uint256 frontRunnerSharesPerUSDC = frontRunnerShares * 1e18 / frontRunAmount;
        uint256 victimSharesPerUSDC = victimShares * 1e18 / VICTIM_AMOUNT;
        
        // Shares per USDC should be approximately equal (fair pricing)
        assertApproxEqRel(
            frontRunnerSharesPerUSDC,
            victimSharesPerUSDC,
            0.01e18, // 1% tolerance
            "Front-running should not provide unfair share pricing advantage"
        );
    }

    // ============ ECONOMIC GRIEFING ATTACKS ============

    function test_EconomicGriefing_DustAttack() public {
        // Attacker makes many tiny deposits to increase gas costs for other operations
        uint256 dustAmount = vault.MINIMUM_DEPOSIT(); // Minimum possible deposit
        uint256 numDustDeposits = 100;
        
        vm.startPrank(attacker);
        mockUSDC.approve(address(vault), dustAmount * numDustDeposits);
        
        for (uint256 i = 0; i < numDustDeposits; i++) {
            vault.deposit(dustAmount);
        }
        vm.stopPrank();

        // Verify system still functions efficiently for normal users
        uint256 gasStart = gasleft();
        
        vm.startPrank(victim);
        mockUSDC.approve(address(vault), VICTIM_AMOUNT);
        vault.deposit(VICTIM_AMOUNT);
        vm.stopPrank();
        
        uint256 gasUsed = gasStart - gasleft();
        
        // Gas usage should still be reasonable despite dust attack
        assertTrue(gasUsed < 500_000, "Dust attack should not significantly increase gas costs");
    }

    function test_EconomicGriefing_WithdrawalSpam() public {
        // Setup: Attacker has many small positions
        uint256 smallAmount = vault.MINIMUM_DEPOSIT();
        uint256 numPositions = 50;
        
        vm.startPrank(attacker);
        mockUSDC.approve(address(vault), smallAmount * numPositions);
        
        for (uint256 i = 0; i < numPositions; i++) {
            vault.deposit(smallAmount);
        }
        vm.stopPrank();

        // Attacker spams withdrawal requests
        vm.startPrank(attacker);
        uint256 attackerShares = vault.userShares(attacker);
        uint256 sharesPerRequest = attackerShares / numPositions;
        
        for (uint256 i = 0; i < numPositions; i++) {
            vault.requestWithdrawal(sharesPerRequest);
        }
        vm.stopPrank();

        // System should still function for legitimate users
        vm.startPrank(victim);
        mockUSDC.approve(address(vault), VICTIM_AMOUNT);
        vault.deposit(VICTIM_AMOUNT);
        
        uint256 victimShares = vault.userShares(victim);
        vault.requestWithdrawal(victimShares);
        vm.stopPrank();
        
        assertTrue(victimShares > 0, "Legitimate users should not be affected by withdrawal spam");
    }

    // ============ SHARE PRICE MANIPULATION TESTS ============

    function test_SharePriceManipulation_InflationAttack() public {
        // Attacker tries to inflate share price to harm future depositors
        
        // 1. Attacker makes initial deposit
        vm.startPrank(attacker);
        mockUSDC.approve(address(vault), LARGE_AMOUNT);
        vault.deposit(LARGE_AMOUNT);
        vm.stopPrank();

        // 2. Attacker directly transfers tokens to vault to inflate share price
        // This simulates donating to the vault to manipulate share calculations
        mockUSDC.mint(address(vault), LARGE_AMOUNT);

        // 3. Victim tries to deposit
        vm.startPrank(victim);
        mockUSDC.approve(address(vault), VICTIM_AMOUNT);
        vault.deposit(VICTIM_AMOUNT);
        vm.stopPrank();

        uint256 victimShares = vault.userShares(victim);
        
        // Victim should still receive reasonable shares despite manipulation attempt
        assertTrue(victimShares > 0, "Victim should receive shares despite inflation attack");
        
        // The share calculation should be protected against extreme manipulation
        uint256 minExpectedShares = VICTIM_AMOUNT / 2; // At least 50% of expected shares
        assertTrue(victimShares >= minExpectedShares, "Share inflation attack should be mitigated");
    }

    // ============ MEV EXTRACTION TESTS ============

    function test_MEVExtraction_ArbitrageOpportunity() public {
        // Setup different yield rates to create arbitrage opportunity
        mockStrategy.addYield(100_000 * 10**6); // Add significant yield
        
        // MEV bot tries to extract value from yield distribution
        vm.startPrank(mevBot);
        mockUSDC.approve(address(vault), LARGE_AMOUNT);
        
        // Bot deposits right before harvest
        vault.deposit(LARGE_AMOUNT);
        
        // Trigger harvest
        vm.prank(address(vault));
        mockStrategy.harvest();
        
        // Bot immediately withdraws to capture yield
        uint256 botShares = vault.userShares(mevBot);
        vault.withdraw(botShares);
        vm.stopPrank();

        // Verify MEV extraction was limited
        uint256 botBalance = mockUSDC.balanceOf(mevBot);
        uint256 profit = botBalance > LARGE_AMOUNT ? botBalance - LARGE_AMOUNT : 0;
        
        // Profit should be reasonable, not excessive
        assertTrue(profit < LARGE_AMOUNT / 100, "MEV extraction should be limited"); // Less than 1% profit
    }

    // ============ GOVERNANCE ATTACK SIMULATION ============

    function test_GovernanceAttack_OwnershipManipulation() public {
        // Test that ownership cannot be manipulated through economic attacks
        
        // Attacker becomes largest depositor
        vm.startPrank(attacker);
        mockUSDC.approve(address(vault), ATTACK_AMOUNT);
        vault.deposit(ATTACK_AMOUNT);
        vm.stopPrank();

        // Verify attacker cannot gain unauthorized control
        vm.startPrank(attacker);
        vm.expectRevert();
        vault.transferOwnership(attacker);
        vm.stopPrank();

        // Owner should still be the original owner
        assertEq(vault.owner(), owner, "Ownership should not be transferable by large depositors");
    }

    // ============ LIQUIDITY MANIPULATION TESTS ============

    function test_LiquidityManipulation_DrainAttack() public {
        // Setup: Multiple users deposit
        vm.startPrank(victim);
        mockUSDC.approve(address(vault), VICTIM_AMOUNT);
        vault.deposit(VICTIM_AMOUNT);
        vm.stopPrank();

        // Attacker tries to drain liquidity
        vm.startPrank(attacker);
        mockUSDC.approve(address(vault), ATTACK_AMOUNT);
        vault.deposit(ATTACK_AMOUNT);
        
        // Immediately try to withdraw everything
        uint256 attackerShares = vault.userShares(attacker);
        vault.withdraw(attackerShares);
        vm.stopPrank();

        // Victim should still be able to withdraw
        vm.startPrank(victim);
        uint256 victimShares = vault.userShares(victim);
        vault.withdraw(victimShares);
        vm.stopPrank();

        uint256 victimFinalBalance = mockUSDC.balanceOf(victim);
        assertTrue(victimFinalBalance >= VICTIM_AMOUNT * 95 / 100, "Victim should recover most funds");
    }
}

/**
 * @title FlashLoanAttacker
 * @dev Contract to simulate flash loan attacks
 */
contract FlashLoanAttacker {
    AbunfiVault public vault;
    MockERC20 public token;
    
    constructor(AbunfiVault _vault, MockERC20 _token) {
        vault = _vault;
        token = _token;
    }
    
    function executeFlashLoanAttack(uint256 amount) external {
        // Simulate flash loan by using pre-funded tokens
        token.approve(address(vault), amount);
        
        // 1. Deposit large amount to manipulate share price
        vault.deposit(amount);
        
        // 2. Immediately withdraw to extract value
        uint256 shares = vault.userShares(address(this));
        vault.withdraw(shares);
        
        // In a real flash loan, we would repay the loan here
        // For simulation, we just keep the tokens
    }
}
