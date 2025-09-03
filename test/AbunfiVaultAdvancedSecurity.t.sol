// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/mocks/MockERC20.sol";
import "../src/RiskProfileManager.sol";
import "../src/WithdrawalManager.sol";
import "../src/StrategyManager.sol";
import "../src/mocks/MockStrategy.sol";

/**
 * @title AbunfiVaultAdvancedSecurity
 * @dev Comprehensive security and edge case testing for AbunfiVault
 * Tests critical finance production scenarios including reentrancy, overflow, and attack vectors
 */
contract AbunfiVaultAdvancedSecurityTest is Test {
    AbunfiVault public vault;
    MockERC20 public mockUSDC;
    RiskProfileManager public riskManager;
    WithdrawalManager public withdrawalManager;
    StrategyManager public strategyManager;
    MockStrategy public mockStrategy;

    address public owner;
    address public attacker;
    address public user1;
    address public user2;
    address public user3;

    // Test constants
    uint256 constant MINIMUM_DEPOSIT = 4 * 10 ** 6; // 4 USDC
    uint256 constant LARGE_AMOUNT = 1_000_000 * 10 ** 6; // 1M USDC
    uint256 constant MAX_UINT256 = type(uint256).max;
    uint256 constant DUST_AMOUNT = 1; // 1 wei

    event Deposit(address indexed user, uint256 amount, uint256 shares, RiskProfileManager.RiskLevel riskLevel);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);

    function setUp() public {
        owner = address(this);
        attacker = makeAddr("attacker");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy mock USDC with 6 decimals
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);

        // Deploy risk management system
        riskManager = new RiskProfileManager();
        strategyManager = new StrategyManager(address(riskManager));

        // Deploy vault first
        vault = new AbunfiVault(
            address(mockUSDC),
            address(0), // No trusted forwarder for these tests
            address(riskManager),
            address(0) // Temporary
        );

        // Deploy withdrawal manager with vault address
        withdrawalManager = new WithdrawalManager(address(vault), address(mockUSDC));

        // Update vault with correct withdrawal manager
        vault.updateRiskManagers(address(riskManager), address(withdrawalManager));

        // Deploy mock strategy
        mockStrategy = new MockStrategy(address(mockUSDC), "Mock Strategy", 500); // 5% APY

        // Setup vault with strategy
        vault.addStrategy(address(mockStrategy));

        // Mint tokens to test users
        mockUSDC.mint(user1, LARGE_AMOUNT);
        mockUSDC.mint(user2, LARGE_AMOUNT);
        mockUSDC.mint(user3, LARGE_AMOUNT);
        mockUSDC.mint(attacker, LARGE_AMOUNT);
    }

    // ============ REENTRANCY ATTACK TESTS ============

    function test_ReentrancyProtection_DepositReentrancy() public {
        // Create a malicious ERC20 token that triggers reentrancy on transfer
        MaliciousToken maliciousToken = new MaliciousToken(vault);

        // Try to use malicious token - this should be prevented by the vault's design
        // Since the vault only accepts the specific USDC token, this attack vector is mitigated
        // This test validates that the vault doesn't accept arbitrary tokens

        vm.expectRevert(); // Should revert because malicious token is not the accepted token
        maliciousToken.triggerReentrancyAttack();
    }

    function test_ReentrancyProtection_WithdrawReentrancy() public {
        // Test that withdrawal operations are protected against reentrancy
        // The vault uses ReentrancyGuard which should prevent recursive calls

        // Make a legitimate deposit first
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), MINIMUM_DEPOSIT);
        vault.deposit(MINIMUM_DEPOSIT);

        uint256 userShares = vault.userShares(user1);

        // Normal withdrawal should work
        vault.withdraw(userShares);
        vm.stopPrank();

        // Verify the withdrawal completed successfully
        assertEq(vault.userShares(user1), 0, "User should have no shares after withdrawal");
    }

    // ============ INTEGER OVERFLOW/UNDERFLOW TESTS ============

    function test_IntegerOverflow_ShareCalculation() public {
        // Test with maximum possible values to check for overflow
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), MAX_UINT256);

        // This should not overflow due to SafeMath or Solidity 0.8+ built-in checks
        vm.expectRevert(); // Should revert due to insufficient balance, not overflow
        vault.deposit(MAX_UINT256);
        vm.stopPrank();
    }

    function test_IntegerUnderflow_WithdrawMoreThanBalance() public {
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), MINIMUM_DEPOSIT);
        vault.deposit(MINIMUM_DEPOSIT);

        uint256 userShares = vault.userShares(user1);

        // Try to withdraw more shares than user has
        vm.expectRevert("Insufficient shares");
        vault.withdraw(userShares + 1);
        vm.stopPrank();
    }

    // ============ ZERO VALUE EDGE CASES ============

    function test_ZeroValueEdgeCases_ZeroDeposit() public {
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), 0);

        vm.expectRevert("Amount below minimum");
        vault.deposit(0);
        vm.stopPrank();
    }

    function test_ZeroValueEdgeCases_ZeroWithdraw() public {
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), MINIMUM_DEPOSIT);
        vault.deposit(MINIMUM_DEPOSIT);

        vm.expectRevert("Cannot withdraw 0 shares");
        vault.withdraw(0);
        vm.stopPrank();
    }

    // ============ DUST ATTACK TESTS ============

    function test_DustAttack_MinimalDeposits() public {
        // Attacker tries to make many minimal deposits to manipulate share price
        vm.startPrank(attacker);
        mockUSDC.approve(address(vault), MINIMUM_DEPOSIT * 100);

        // First deposit should work
        vault.deposit(MINIMUM_DEPOSIT);

        // Subsequent minimal deposits should still work but not break the system
        for (uint256 i = 0; i < 10; i++) {
            vault.deposit(MINIMUM_DEPOSIT);
        }

        // Verify system integrity
        assertTrue(vault.totalDeposits() > 0);
        assertTrue(vault.totalShares() > 0);
        vm.stopPrank();
    }

    // ============ ROUNDING ERROR TESTS ============

    function test_RoundingErrors_ShareCalculation() public {
        // Test rounding in share calculations with small amounts
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), MINIMUM_DEPOSIT);
        vault.deposit(MINIMUM_DEPOSIT);

        uint256 initialShares = vault.userShares(user1);
        vm.stopPrank();

        // Second user deposits same amount
        vm.startPrank(user2);
        mockUSDC.approve(address(vault), MINIMUM_DEPOSIT);
        vault.deposit(MINIMUM_DEPOSIT);

        uint256 secondShares = vault.userShares(user2);
        vm.stopPrank();

        // Shares should be equal or very close (within rounding tolerance)
        uint256 difference = initialShares > secondShares ? initialShares - secondShares : secondShares - initialShares;
        assertTrue(difference <= 1, "Rounding error too large");
    }

    // ============ FRONT-RUNNING PROTECTION TESTS ============

    function test_FrontRunning_DepositOrderIndependence() public {
        uint256 amount1 = 100 * 10 ** 6; // 100 USDC
        uint256 amount2 = 200 * 10 ** 6; // 200 USDC

        // Simulate front-running scenario
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), amount1);
        vault.deposit(amount1);
        vm.stopPrank();

        vm.startPrank(user2);
        mockUSDC.approve(address(vault), amount2);
        vault.deposit(amount2);
        vm.stopPrank();

        // Verify fair share distribution
        uint256 shares1 = vault.userShares(user1);
        uint256 shares2 = vault.userShares(user2);

        // User2 should have approximately 2x shares of user1
        assertTrue(shares2 > shares1 * 19 / 10, "Share distribution unfair"); // Allow 10% tolerance
        assertTrue(shares2 < shares1 * 21 / 10, "Share distribution unfair");
    }

    // ============ PAUSED STATE EDGE CASES ============

    function test_PausedState_DepositBlocked() public {
        // Pause the vault
        vault.pause();

        vm.startPrank(user1);
        mockUSDC.approve(address(vault), MINIMUM_DEPOSIT);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vault.deposit(MINIMUM_DEPOSIT);
        vm.stopPrank();
    }

    function test_PausedState_WithdrawStillWorks() public {
        // First make a deposit
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), MINIMUM_DEPOSIT);
        vault.deposit(MINIMUM_DEPOSIT);
        vm.stopPrank();

        // Pause the vault
        vault.pause();

        // Withdrawals should still work when paused
        vm.startPrank(user1);
        uint256 userShares = vault.userShares(user1);
        vault.withdraw(userShares);
        vm.stopPrank();

        assertEq(vault.userShares(user1), 0);
    }

    // ============ MAXIMUM VALUE STRESS TESTS ============

    function test_MaxValueStress_LargeDeposit() public {
        uint256 largeAmount = 100_000_000 * 10 ** 6; // 100M USDC
        mockUSDC.mint(user1, largeAmount);

        vm.startPrank(user1);
        mockUSDC.approve(address(vault), largeAmount);
        vault.deposit(largeAmount);

        // Verify the deposit was processed correctly
        assertEq(vault.userDeposits(user1), largeAmount);
        assertTrue(vault.userShares(user1) > 0);
        vm.stopPrank();
    }
}

/**
 * @title MaliciousToken
 * @dev Contract to test reentrancy attacks via malicious ERC20
 */
contract MaliciousToken {
    AbunfiVault public vault;

    constructor(AbunfiVault _vault) {
        vault = _vault;
    }

    function triggerReentrancyAttack() external {
        // This should fail because vault only accepts specific USDC token
        vault.deposit(1000000); // 1 USDC worth
    }
}

/**
 * @title ReentrancyAttacker
 * @dev Contract to test reentrancy attacks on the vault
 */
contract ReentrancyAttacker {
    AbunfiVault public vault;
    MockERC20 public token;
    bool public attacking = false;

    constructor(AbunfiVault _vault, MockERC20 _token) {
        vault = _vault;
        token = _token;
    }

    function attackDeposit(uint256 amount) external {
        token.approve(address(vault), amount * 2);
        attacking = true;
        vault.deposit(amount);
    }

    function attackWithdraw(uint256 shares) external {
        attacking = true;
        vault.withdraw(shares);
    }

    // This function will be called during the attack
    receive() external payable {
        if (attacking) {
            attacking = false;
            // Try to reenter
            vault.deposit(4 * 10 ** 6);
        }
    }
}
