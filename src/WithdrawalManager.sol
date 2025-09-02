// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title WithdrawalManager
 * @dev Manages withdrawal requests with window periods and interest accrual tracking
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
    event WithdrawalRequested(
        address indexed user, 
        uint256 indexed requestId, 
        uint256 shares, 
        uint256 estimatedAmount
    );
    event WithdrawalProcessed(
        address indexed user, 
        uint256 indexed requestId, 
        uint256 shares, 
        uint256 actualAmount
    );
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
     * @dev Request withdrawal with window period
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
     * @dev Process withdrawal request after window period
     * @param requestId ID of the withdrawal request
     */
    function processWithdrawal(uint256 requestId) external nonReentrant {
        address user = msg.sender;
        require(requestId < userWithdrawalRequests[user].length, "Invalid request ID");
        
        WithdrawalRequest storage request = userWithdrawalRequests[user][requestId];
        require(!request.isProcessed, "Request already processed");
        require(!request.isCancelled, "Request cancelled");
        require(
            block.timestamp >= request.requestTime + withdrawalWindow,
            "Withdrawal window not met"
        );
        
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
     * @dev Instant withdrawal with fee
     * @param shares Number of shares to withdraw instantly
     */
    function instantWithdrawal(uint256 shares) external nonReentrant {
        require(shares > 0, "Cannot withdraw 0 shares");
        address user = msg.sender;
        
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
        return !request.isProcessed && 
               !request.isCancelled && 
               block.timestamp >= request.requestTime + withdrawalWindow;
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
     * @param user User address
     * @param shares Number of shares
     * @return Withdrawal amount
     */
    function _getWithdrawalAmount(address user, uint256 shares) internal view returns (uint256) {
        // This would integrate with vault to get current share value
        // Placeholder implementation
        return shares; // 1:1 for now
    }
    
    /**
     * @dev Process withdrawal through vault (internal)
     * @param user User address
     * @param shares Number of shares
     * @param amount Withdrawal amount
     */
    function _processVaultWithdrawal(address user, uint256 shares, uint256 amount) internal {
        // This would call vault's withdrawal function
        // Placeholder implementation
        asset.safeTransfer(user, amount);
    }
}
