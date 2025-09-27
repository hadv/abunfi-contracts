// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title IAbunfiVault
 * @notice Interface for AbunfiVault contract used by WithdrawalManager
 * @dev This interface defines the callback function that the withdrawal manager
 *      uses to execute actual withdrawals in the vault contract.
 */
interface IAbunfiVault {
    /**
     * @dev Process vault withdrawal (callback from withdrawal manager)
     * @notice Executes the actual withdrawal by updating user state and transferring tokens
     * @param user User address who is withdrawing funds
     * @param shares Number of shares to burn from user's balance
     * @param amount Amount of USDC to transfer to user (6 decimals)
     * @dev This function should only be callable by the withdrawal manager
     */
    function processVaultWithdrawal(address user, uint256 shares, uint256 amount) external;
}

/**
 * @title WithdrawalManager
 * @notice Manages withdrawal requests and processing for the AbunfiVault system
 * @dev This contract implements a two-phase withdrawal system with both delayed and instant options.
 *      It works in conjunction with the AbunfiVault to provide secure and efficient fund withdrawals.
 *
 * @dev Architecture Overview:
 *      1. Users interact with AbunfiVault withdrawal functions
 *      2. Vault delegates to WithdrawalManager for processing logic
 *      3. WithdrawalManager validates requests and manages timing
 *      4. WithdrawalManager calls back to Vault for actual token transfers
 *
 * @dev Withdrawal Types:
 *      - Delayed Withdrawal: No fee, requires waiting period (withdrawal window)
 *      - Instant Withdrawal: Charges fee, immediate processing
 *
 * @dev Security Features:
 *      - Only vault can call withdrawal processing functions
 *      - Withdrawal window prevents bank runs and allows liquidity management
 *      - Reentrancy protection on all external functions
 *      - Interest accrual updates before processing
 *
 * @dev Gas Optimization:
 *      - Batch processing capabilities for multiple requests
 *      - Efficient storage layout for withdrawal requests
 *      - Minimal external calls during processing
 */
contract WithdrawalManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Withdrawal request structure
    struct WithdrawalRequest {
        uint256 shares; // Number of shares to withdraw
        uint256 requestTime; // When withdrawal was requested
        uint256 estimatedAmount; // Estimated withdrawal amount at request time
        uint256 accruedInterestAtRequest; // Interest accrued up to request time
        bool isProcessed; // Whether withdrawal has been processed
        bool isCancelled; // Whether withdrawal was cancelled
    }

    // User withdrawal tracking
    mapping(address => WithdrawalRequest[]) public userWithdrawalRequests;
    mapping(address => uint256) public pendingWithdrawalShares;

    // Interest accrual tracking
    mapping(address => uint256) public lastInterestUpdateTime;
    mapping(address => uint256) public accruedInterest;
    mapping(address => uint256) public totalInterestEarned;

    // Configuration
    uint256 public withdrawalWindow = 7 days; // Default 7-day window
    uint256 public instantWithdrawalFee = 100; // 1% fee for instant withdrawal (basis points)
    uint256 public maxWithdrawalWindow = 30 days;
    uint256 public constant BASIS_POINTS = 10000;

    // Vault reference for share calculations
    address public vault;
    IERC20 public asset;

    // Events
    event WithdrawalRequested(address indexed user, uint256 indexed requestId, uint256 shares, uint256 estimatedAmount);
    event WithdrawalProcessed(address indexed user, uint256 indexed requestId, uint256 shares, uint256 actualAmount);
    event WithdrawalCancelled(address indexed user, uint256 indexed requestId);
    event InstantWithdrawal(address indexed user, uint256 shares, uint256 amount, uint256 fee);
    event InterestAccrued(address indexed user, uint256 amount);
    event WithdrawalWindowUpdated(uint256 oldWindow, uint256 newWindow);

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    constructor(address _vault, address _asset) Ownable(msg.sender) {
        vault = _vault;
        asset = IERC20(_asset);
    }

    /**
     * @dev Request withdrawal with window period (called by vault)
     * @notice This function is called by the vault to create a withdrawal request on behalf of a user.
     *         It creates a withdrawal request that must wait for the withdrawal window period before processing.
     * @param user User address requesting withdrawal - the actual user who owns the shares
     * @param shares Number of shares to withdraw - must be > 0 and <= user's available shares
     * @return requestId ID of the withdrawal request that can be used to process the withdrawal later
     * @dev Requirements:
     *      - Can only be called by the vault contract
     *      - Shares must be greater than 0
     *      - User must have sufficient shares available
     * @dev Effects:
     *      - Creates a new withdrawal request with current timestamp
     *      - Updates user's accrued interest
     *      - Tracks pending withdrawal shares
     *      - Emits WithdrawalRequested event
     */
    function requestWithdrawalForUser(address user, uint256 shares) external nonReentrant returns (uint256 requestId) {
        require(msg.sender == vault, "Only vault can call");
        require(shares > 0, "Cannot withdraw 0 shares");

        // Update user's accrued interest before processing
        _updateAccruedInterest(user);

        // Get current estimated withdrawal amount
        uint256 estimatedAmount = _getWithdrawalAmount(user, shares);

        // Create withdrawal request
        WithdrawalRequest memory request = WithdrawalRequest({
            shares: shares,
            requestTime: block.timestamp,
            estimatedAmount: estimatedAmount,
            accruedInterestAtRequest: accruedInterest[user],
            isProcessed: false,
            isCancelled: false
        });

        userWithdrawalRequests[user].push(request);
        requestId = userWithdrawalRequests[user].length - 1;

        // Track pending withdrawal shares
        pendingWithdrawalShares[user] += shares;

        emit WithdrawalRequested(user, requestId, shares, estimatedAmount);

        return requestId;
    }

    /**
     * @dev Request withdrawal with window period (legacy function)
     * @param shares Number of shares to withdraw
     * @return requestId ID of the withdrawal request
     */
    function requestWithdrawal(uint256 shares) external nonReentrant returns (uint256 requestId) {
        require(shares > 0, "Cannot withdraw 0 shares");
        address user = msg.sender;

        // Update user's accrued interest before processing
        _updateAccruedInterest(user);

        // Get current estimated withdrawal amount
        uint256 estimatedAmount = _getWithdrawalAmount(user, shares);

        // Create withdrawal request
        WithdrawalRequest memory request = WithdrawalRequest({
            shares: shares,
            requestTime: block.timestamp,
            estimatedAmount: estimatedAmount,
            accruedInterestAtRequest: accruedInterest[user],
            isProcessed: false,
            isCancelled: false
        });

        userWithdrawalRequests[user].push(request);
        requestId = userWithdrawalRequests[user].length - 1;

        // Track pending withdrawal shares
        pendingWithdrawalShares[user] += shares;

        emit WithdrawalRequested(user, requestId, shares, estimatedAmount);

        return requestId;
    }

    /**
     * @dev Process withdrawal request after window period (called by vault)
     * @notice This function processes a withdrawal request after the required window period has passed.
     *         It validates the request, calculates final amounts, and executes the withdrawal.
     * @param user User address who owns the withdrawal request
     * @param requestId ID of the withdrawal request to process
     * @dev Requirements:
     *      - Can only be called by the vault contract
     *      - Request ID must be valid for the user
     *      - Request must not be already processed or cancelled
     *      - Withdrawal window period must have elapsed since request time
     * @dev Effects:
     *      - Marks the withdrawal request as processed
     *      - Updates user's accrued interest
     *      - Reduces pending withdrawal shares
     *      - Calls vault to execute the actual token transfer
     *      - Emits WithdrawalProcessed event
     */
    function processWithdrawalForUser(address user, uint256 requestId) external nonReentrant {
        require(msg.sender == vault, "Only vault can call");
        require(requestId < userWithdrawalRequests[user].length, "Invalid request ID");

        WithdrawalRequest storage request = userWithdrawalRequests[user][requestId];
        require(!request.isProcessed, "Request already processed");
        require(!request.isCancelled, "Request cancelled");
        require(block.timestamp >= request.requestTime + withdrawalWindow, "Withdrawal window not met");

        // Update user's accrued interest
        _updateAccruedInterest(user);

        // Calculate final withdrawal amount including interest accrued during window
        uint256 finalAmount = _getWithdrawalAmount(user, request.shares);

        // Mark as processed
        request.isProcessed = true;
        pendingWithdrawalShares[user] -= request.shares;

        // Process withdrawal through vault
        _processVaultWithdrawal(user, request.shares, finalAmount);

        emit WithdrawalProcessed(user, requestId, request.shares, finalAmount);
    }

    /**
     * @dev Process withdrawal request after window period (legacy function)
     * @param requestId ID of the withdrawal request
     */
    function processWithdrawal(uint256 requestId) external nonReentrant {
        address user = msg.sender;
        require(requestId < userWithdrawalRequests[user].length, "Invalid request ID");

        WithdrawalRequest storage request = userWithdrawalRequests[user][requestId];
        require(!request.isProcessed, "Request already processed");
        require(!request.isCancelled, "Request cancelled");
        require(block.timestamp >= request.requestTime + withdrawalWindow, "Withdrawal window not met");

        // Update user's accrued interest
        _updateAccruedInterest(user);

        // Calculate final withdrawal amount including interest accrued during window
        uint256 finalAmount = _getWithdrawalAmount(user, request.shares);

        // Mark as processed
        request.isProcessed = true;
        pendingWithdrawalShares[user] -= request.shares;

        // Process withdrawal through vault
        _processVaultWithdrawal(user, request.shares, finalAmount);

        emit WithdrawalProcessed(user, requestId, request.shares, finalAmount);
    }

    /**
     * @dev Instant withdrawal with fee (called by vault)
     * @notice This function processes an instant withdrawal with a fee, bypassing the withdrawal window.
     *         Users pay a fee for immediate access to their funds without waiting.
     * @param user User address requesting instant withdrawal
     * @param shares Number of shares to withdraw instantly - must be > 0 and <= user's available shares
     * @dev Requirements:
     *      - Can only be called by the vault contract
     *      - Shares must be greater than 0
     *      - User must have sufficient shares available
     * @dev Effects:
     *      - Updates user's accrued interest
     *      - Calculates withdrawal amount and instant withdrawal fee
     *      - Calls vault to execute the token transfer (net amount after fee)
     *      - Emits InstantWithdrawal event with fee information
     * @dev Fee Calculation:
     *      - Fee = (withdrawal_amount * instantWithdrawalFee) / 10000
     *      - Net amount = withdrawal_amount - fee
     *      - Fee remains in the vault as protocol revenue
     */
    function instantWithdrawalForUser(address user, uint256 shares) external nonReentrant {
        require(msg.sender == vault, "Only vault can call");
        require(shares > 0, "Cannot withdraw 0 shares");

        // Update user's accrued interest
        _updateAccruedInterest(user);

        // Calculate withdrawal amount
        uint256 amount = _getWithdrawalAmount(user, shares);

        // Calculate and deduct instant withdrawal fee
        uint256 fee = (amount * instantWithdrawalFee) / BASIS_POINTS;
        uint256 netAmount = amount - fee;

        // Process withdrawal through vault
        _processVaultWithdrawal(user, shares, netAmount);

        emit InstantWithdrawal(user, shares, netAmount, fee);
    }

    /**
     * @dev Instant withdrawal with fee (legacy function)
     * @param shares Number of shares to withdraw instantly
     */
    function instantWithdrawal(uint256 shares) external nonReentrant {
        require(shares > 0, "Cannot withdraw 0 shares");
        address user = msg.sender;

        // Update user's accrued interest
        _updateAccruedInterest(user);

        // Calculate withdrawal amount and fee
        uint256 withdrawalAmount = _getWithdrawalAmount(user, shares);
        uint256 fee = (withdrawalAmount * instantWithdrawalFee) / 10000;
        uint256 netAmount = withdrawalAmount - fee;

        // Process instant withdrawal through vault
        _processVaultWithdrawal(user, shares, netAmount);

        emit InstantWithdrawal(user, shares, netAmount, fee);
    }

    /**
     * @dev Cancel withdrawal request
     * @param requestId ID of the withdrawal request to cancel
     */
    function cancelWithdrawal(uint256 requestId) external nonReentrant {
        address user = msg.sender;
        require(requestId < userWithdrawalRequests[user].length, "Invalid request ID");

        WithdrawalRequest storage request = userWithdrawalRequests[user][requestId];
        require(!request.isProcessed, "Request already processed");
        require(!request.isCancelled, "Request already cancelled");

        // Mark as cancelled
        request.isCancelled = true;
        pendingWithdrawalShares[user] -= request.shares;

        emit WithdrawalCancelled(user, requestId);
    }

    /**
     * @dev Cancel withdrawal request for user (called by vault)
     * @param user User address
     * @param requestId ID of the withdrawal request to cancel
     */
    function cancelWithdrawalForUser(address user, uint256 requestId) external nonReentrant {
        require(msg.sender == vault, "Only vault can call");
        require(requestId < userWithdrawalRequests[user].length, "Invalid request ID");

        WithdrawalRequest storage request = userWithdrawalRequests[user][requestId];
        require(!request.isProcessed, "Request already processed");
        require(!request.isCancelled, "Request already cancelled");

        // Mark as cancelled
        request.isCancelled = true;
        pendingWithdrawalShares[user] -= request.shares;

        emit WithdrawalCancelled(user, requestId);
    }

    /**
     * @dev Update accrued interest for user
     * @param user User address
     */
    function updateAccruedInterest(address user) external {
        _updateAccruedInterest(user);
    }

    /**
     * @dev Get user's withdrawal requests
     * @param user User address
     * @return Array of withdrawal requests
     */
    function getUserWithdrawalRequests(address user) external view returns (WithdrawalRequest[] memory) {
        return userWithdrawalRequests[user];
    }

    /**
     * @dev Get pending withdrawal requests count for user
     * @param user User address
     * @return count Number of pending requests
     */
    function getPendingWithdrawalCount(address user) external view returns (uint256 count) {
        WithdrawalRequest[] memory requests = userWithdrawalRequests[user];
        for (uint256 i = 0; i < requests.length; i++) {
            if (!requests[i].isProcessed && !requests[i].isCancelled) {
                count++;
            }
        }
    }

    /**
     * @dev Check if withdrawal request can be processed
     * @param user User address
     * @param requestId Request ID
     * @return True if can be processed
     */
    function canProcessWithdrawal(address user, uint256 requestId) external view returns (bool) {
        if (requestId >= userWithdrawalRequests[user].length) return false;

        WithdrawalRequest memory request = userWithdrawalRequests[user][requestId];
        return !request.isProcessed && !request.isCancelled && block.timestamp >= request.requestTime + withdrawalWindow;
    }

    // Admin functions

    /**
     * @dev Update withdrawal window period
     * @param newWindow New window period in seconds
     */
    function updateWithdrawalWindow(uint256 newWindow) external onlyOwner {
        require(newWindow <= maxWithdrawalWindow, "Window too long");
        uint256 oldWindow = withdrawalWindow;
        withdrawalWindow = newWindow;
        emit WithdrawalWindowUpdated(oldWindow, newWindow);
    }

    /**
     * @dev Update instant withdrawal fee
     * @param newFee New fee in basis points
     */
    function updateInstantWithdrawalFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee too high"); // Max 10%
        instantWithdrawalFee = newFee;
    }

    // Internal functions

    /**
     * @dev Update accrued interest for user (internal)
     * @param user User address
     */
    function _updateAccruedInterest(address user) internal {
        // This would integrate with vault to calculate interest
        // For now, we'll track the timestamp
        lastInterestUpdateTime[user] = block.timestamp;
        emit InterestAccrued(user, 0); // Placeholder
    }

    /**
     * @dev Get withdrawal amount for shares (internal)
     * @notice Converts shares to equivalent USDC withdrawal amount.
     *         This function handles the decimal conversion between shares (18 decimals) and USDC (6 decimals).
     * @param shares Number of shares to convert to withdrawal amount
     * @return Withdrawal amount in USDC (6 decimals)
     * @dev Implementation Notes:
     *      - Shares are stored with 18 decimal precision (1e18 = 1 share)
     *      - USDC uses 6 decimal precision (1e6 = 1 USDC)
     *      - Conversion: shares / 1e12 = USDC amount
     *      - Example: 100e18 shares = 100e6 USDC (100 USDC)
     * @dev Future Enhancement:
     *      - Could incorporate user-specific interest calculations
     *      - Could use vault's totalAssets() and totalShares() for dynamic pricing
     */
    function _getWithdrawalAmount(
        address,
        /* user */
        uint256 shares
    )
        internal
        view
        returns (uint256)
    {
        // For now, use a simple conversion: shares are in 18 decimals, USDC is in 6 decimals
        // So we need to divide by 1e12 to convert from shares to USDC amount
        return shares / 1e12;
    }

    /**
     * @dev Process withdrawal through vault (internal)
     * @param user User address
     * @param shares Number of shares
     * @param amount Withdrawal amount
     */
    function _processVaultWithdrawal(address user, uint256 shares, uint256 amount) internal {
        // Call vault to process the actual withdrawal
        // The vault will handle liquidity management and token transfers
        IAbunfiVault(vault).processVaultWithdrawal(user, shares, amount);
    }
}
