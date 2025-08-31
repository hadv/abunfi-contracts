// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./AbunfiSmartAccount.sol";

/**
 * @title EIP7702Paymaster
 * @dev Advanced paymaster for EIP-7702 delegated accounts
 * Sponsors gas fees for users with sophisticated policy management
 */
contract EIP7702Paymaster is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Events
    event UserOperationSponsored(
        address indexed account,
        address indexed actualGasPrice,
        uint256 actualGasCost,
        uint256 actualGasUsed
    );
    event PolicyUpdated(address indexed account, SponsorshipPolicy policy);
    event GlobalPolicyUpdated(SponsorshipPolicy policy);
    event FundsDeposited(address indexed depositor, uint256 amount);
    event FundsWithdrawn(address indexed recipient, uint256 amount);
    event AccountWhitelisted(address indexed account, bool whitelisted);

    // Structs
    struct SponsorshipPolicy {
        uint256 dailyGasLimit;        // Daily gas limit in wei
        uint256 perTxGasLimit;        // Per-transaction gas limit in wei
        uint256 dailyTxLimit;         // Daily transaction count limit
        bool requiresWhitelist;       // Whether account needs to be whitelisted
        bool isActive;                // Whether sponsorship is active
    }

    struct AccountState {
        uint256 dailyGasUsed;         // Gas used today
        uint256 dailyTxCount;         // Transactions today
        uint256 lastResetTime;        // Last time daily limits were reset
        bool isWhitelisted;           // Whether account is whitelisted
        SponsorshipPolicy customPolicy; // Custom policy for this account
    }

    struct UserOperationContext {
        address account;              // The delegated account
        uint256 maxFeePerGas;        // Maximum fee per gas
        uint256 gasLimit;            // Gas limit for the operation
        bytes signature;             // Paymaster signature (if required)
    }

    // State variables
    mapping(address => AccountState) public accountStates;
    SponsorshipPolicy public globalPolicy;
    
    // Whitelisted accounts for premium sponsorship
    mapping(address => bool) public whitelistedAccounts;
    
    // Trusted bundlers that can call this paymaster
    mapping(address => bool) public trustedBundlers;
    
    // Emergency controls
    bool public paused = false;
    uint256 public constant RESET_PERIOD = 24 hours;
    
    // Default policies
    uint256 public constant DEFAULT_DAILY_GAS_LIMIT = 0.1 ether; // ~$250 at 2500 ETH
    uint256 public constant DEFAULT_PER_TX_GAS_LIMIT = 0.01 ether; // ~$25 per tx
    uint256 public constant DEFAULT_DAILY_TX_LIMIT = 50; // 50 transactions per day

    modifier onlyTrustedBundler() {
        require(trustedBundlers[msg.sender], "Not a trusted bundler");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Paymaster is paused");
        _;
    }

    constructor() Ownable(msg.sender) {
        // Set default global policy
        globalPolicy = SponsorshipPolicy({
            dailyGasLimit: DEFAULT_DAILY_GAS_LIMIT,
            perTxGasLimit: DEFAULT_PER_TX_GAS_LIMIT,
            dailyTxLimit: DEFAULT_DAILY_TX_LIMIT,
            requiresWhitelist: false,
            isActive: true
        });
    }

    /**
     * @dev Validate and sponsor a user operation
     * @param userOp The user operation from AbunfiSmartAccount
     * @param context Additional context for sponsorship decision
     * @return success Whether the operation can be sponsored
     * @return gasPrice The gas price to use
     */
    function validateUserOperation(
        AbunfiSmartAccount.UserOperation calldata userOp,
        UserOperationContext calldata context
    ) external view returns (bool success, uint256 gasPrice) {
        if (paused) return (false, 0);
        
        // Get effective policy for this account
        SponsorshipPolicy memory policy = _getEffectivePolicy(context.account);
        
        if (!policy.isActive) return (false, 0);
        
        // Check whitelist requirement
        if (policy.requiresWhitelist && !accountStates[context.account].isWhitelisted) {
            return (false, 0);
        }
        
        // Estimate gas cost
        uint256 estimatedGasCost = userOp.gasLimit * userOp.maxFeePerGas;
        
        // Check per-transaction limit
        if (estimatedGasCost > policy.perTxGasLimit) {
            return (false, 0);
        }
        
        // Check daily limits (with potential reset)
        AccountState memory state = accountStates[context.account];
        if (block.timestamp >= state.lastResetTime + RESET_PERIOD) {
            // Reset daily counters
            state.dailyGasUsed = 0;
            state.dailyTxCount = 0;
        }
        
        // Check daily gas limit
        if (state.dailyGasUsed + estimatedGasCost > policy.dailyGasLimit) {
            return (false, 0);
        }
        
        // Check daily transaction limit
        if (state.dailyTxCount >= policy.dailyTxLimit) {
            return (false, 0);
        }
        
        // Check paymaster balance
        if (address(this).balance < estimatedGasCost) {
            return (false, 0);
        }
        
        return (true, userOp.maxFeePerGas);
    }

    /**
     * @dev Execute sponsorship for a user operation
     * @param userOp The user operation
     * @param context The operation context
     * @param actualGasUsed Actual gas used by the operation
     */
    function executeSponsorship(
        AbunfiSmartAccount.UserOperation calldata userOp,
        UserOperationContext calldata context,
        uint256 actualGasUsed
    ) external onlyTrustedBundler whenNotPaused nonReentrant {
        
        // Validate the operation can be sponsored
        (bool canSponsor, uint256 gasPrice) = this.validateUserOperation(userOp, context);
        require(canSponsor, "Operation cannot be sponsored");
        
        // Calculate actual gas cost
        uint256 actualGasCost = actualGasUsed * gasPrice;
        require(address(this).balance >= actualGasCost, "Insufficient paymaster balance");
        
        // Update account state
        _updateAccountState(context.account, actualGasCost);
        
        // Transfer gas cost to bundler
        payable(msg.sender).transfer(actualGasCost);
        
        emit UserOperationSponsored(
            context.account,
            msg.sender,
            actualGasCost,
            actualGasUsed
        );
    }

    /**
     * @dev Batch sponsor multiple operations
     * @param userOps Array of user operations
     * @param contexts Array of operation contexts
     * @param actualGasUsed Array of actual gas used for each operation
     */
    function batchExecuteSponsorship(
        AbunfiSmartAccount.UserOperation[] calldata userOps,
        UserOperationContext[] calldata contexts,
        uint256[] calldata actualGasUsed
    ) external onlyTrustedBundler whenNotPaused nonReentrant {
        require(
            userOps.length == contexts.length && contexts.length == actualGasUsed.length,
            "Array length mismatch"
        );
        
        uint256 totalGasCost = 0;
        
        // Validate all operations first
        for (uint256 i = 0; i < userOps.length; i++) {
            (bool canSponsor, uint256 gasPrice) = this.validateUserOperation(userOps[i], contexts[i]);
            require(canSponsor, "Operation cannot be sponsored");
            
            totalGasCost += actualGasUsed[i] * gasPrice;
        }
        
        require(address(this).balance >= totalGasCost, "Insufficient paymaster balance");
        
        // Execute sponsorship for all operations
        for (uint256 i = 0; i < userOps.length; i++) {
            uint256 gasCost = actualGasUsed[i] * userOps[i].maxFeePerGas;
            _updateAccountState(contexts[i].account, gasCost);
            
            emit UserOperationSponsored(
                contexts[i].account,
                msg.sender,
                gasCost,
                actualGasUsed[i]
            );
        }
        
        // Transfer total gas cost to bundler
        payable(msg.sender).transfer(totalGasCost);
    }

    /**
     * @dev Update account state after sponsorship
     */
    function _updateAccountState(address account, uint256 gasCost) internal {
        AccountState storage state = accountStates[account];
        
        // Reset daily counters if needed
        if (block.timestamp >= state.lastResetTime + RESET_PERIOD) {
            state.dailyGasUsed = 0;
            state.dailyTxCount = 0;
            state.lastResetTime = block.timestamp;
        }
        
        // Update counters
        state.dailyGasUsed += gasCost;
        state.dailyTxCount += 1;
    }

    /**
     * @dev Get effective policy for an account
     */
    function _getEffectivePolicy(address account) internal view returns (SponsorshipPolicy memory) {
        AccountState memory state = accountStates[account];
        
        // Use custom policy if set and active
        if (state.customPolicy.isActive) {
            return state.customPolicy;
        }
        
        // Use global policy
        return globalPolicy;
    }

    // Admin functions
    
    /**
     * @dev Set custom policy for an account
     */
    function setAccountPolicy(address account, SponsorshipPolicy calldata policy) external onlyOwner {
        accountStates[account].customPolicy = policy;
        emit PolicyUpdated(account, policy);
    }

    /**
     * @dev Set global sponsorship policy
     */
    function setGlobalPolicy(SponsorshipPolicy calldata policy) external onlyOwner {
        globalPolicy = policy;
        emit GlobalPolicyUpdated(policy);
    }

    /**
     * @dev Add/remove trusted bundler
     */
    function setTrustedBundler(address bundler, bool trusted) external onlyOwner {
        trustedBundlers[bundler] = trusted;
    }

    /**
     * @dev Whitelist/unwhitelist an account
     */
    function setAccountWhitelist(address account, bool whitelisted) external onlyOwner {
        accountStates[account].isWhitelisted = whitelisted;
        emit AccountWhitelisted(account, whitelisted);
    }

    /**
     * @dev Emergency pause/unpause
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    /**
     * @dev Withdraw funds from paymaster
     */
    function withdrawFunds(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        payable(owner()).transfer(amount);
        emit FundsWithdrawn(owner(), amount);
    }

    /**
     * @dev Emergency withdraw all funds
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
        emit FundsWithdrawn(owner(), balance);
    }

    // View functions
    
    function getAccountState(address account) external view returns (AccountState memory) {
        return accountStates[account];
    }

    function getEffectivePolicy(address account) external view returns (SponsorshipPolicy memory) {
        return _getEffectivePolicy(account);
    }

    function getRemainingDailyAllowance(address account) external view returns (uint256 gasAllowance, uint256 txAllowance) {
        SponsorshipPolicy memory policy = _getEffectivePolicy(account);
        AccountState memory state = accountStates[account];
        
        // Reset if needed
        if (block.timestamp >= state.lastResetTime + RESET_PERIOD) {
            gasAllowance = policy.dailyGasLimit;
            txAllowance = policy.dailyTxLimit;
        } else {
            gasAllowance = policy.dailyGasLimit > state.dailyGasUsed ? 
                policy.dailyGasLimit - state.dailyGasUsed : 0;
            txAllowance = policy.dailyTxLimit > state.dailyTxCount ? 
                policy.dailyTxLimit - state.dailyTxCount : 0;
        }
    }

    // Receive ETH for gas sponsorship
    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }
}
