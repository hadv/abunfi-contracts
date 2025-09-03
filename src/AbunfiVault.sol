// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "./interfaces/IAbunfiStrategy.sol";
import "./RiskProfileManager.sol";
import "./WithdrawalManager.sol";
import "forge-std/console.sol";

/**
 * @title AbunfiVault
 * @dev Main vault contract for Abunfi micro-savings platform
 * Manages user deposits and allocates funds to yield-generating strategies
 * Supports gasless transactions via ERC-2771 meta-transactions
 */
contract AbunfiVault is Ownable, ReentrancyGuard, Pausable, ERC2771Context {
    using SafeERC20 for IERC20;

    // State variables
    IERC20 public immutable asset; // USDC token
    mapping(address => uint256) public userDeposits;
    mapping(address => uint256) public userShares;
    mapping(address => uint256) public lastDepositTime;

    // Risk-based tracking
    mapping(address => uint256) public userLastInterestUpdate;
    mapping(address => uint256) public userAccruedInterest;
    mapping(address => uint256) public userTotalInterestEarned;

    uint256 public totalDeposits;
    uint256 public totalShares;
    uint256 public constant MINIMUM_DEPOSIT = 4e6; // ~$4 USDC (6 decimals)
    uint256 public constant SHARES_MULTIPLIER = 1e18;

    // Risk management contracts
    RiskProfileManager public riskProfileManager;
    WithdrawalManager public withdrawalManager;

    // Strategy management
    IAbunfiStrategy[] public strategies;
    mapping(address => bool) public isActiveStrategy;
    mapping(address => uint256) public strategyAllocations; // Target allocation percentage (basis points)
    mapping(address => uint256) public strategyWeights; // Weight for APY-based allocation
    uint256 public totalAllocated;
    uint256 public reserveRatio = 1000; // 10% reserve in basis points
    uint256 public constant MAX_STRATEGIES = 10;
    uint256 public constant BASIS_POINTS = 10000;

    // Events
    event Deposit(address indexed user, uint256 amount, uint256 shares, RiskProfileManager.RiskLevel riskLevel);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);
    event RiskBasedDeposit(address indexed user, uint256 amount, RiskProfileManager.RiskLevel riskLevel);
    event InterestAccrued(address indexed user, uint256 amount);
    event StrategyAdded(address indexed strategy);
    event StrategyAdded(address indexed strategy, uint256 weight);
    event StrategyRemoved(address indexed strategy);
    event StrategyWeightUpdated(address indexed strategy, uint256 oldWeight, uint256 newWeight);
    event Harvest(uint256 totalYield);
    event Rebalanced(uint256 totalRebalanced);
    event RiskManagersUpdated(address riskProfileManager, address withdrawalManager);
    event ReserveRatioUpdated(uint256 oldRatio, uint256 newRatio);

    constructor(address _asset, address _trustedForwarder, address _riskProfileManager, address _withdrawalManager)
        Ownable(msg.sender)
        ERC2771Context(_trustedForwarder)
    {
        asset = IERC20(_asset);
        riskProfileManager = RiskProfileManager(_riskProfileManager);
        withdrawalManager = WithdrawalManager(_withdrawalManager);
    }

    /**
     * @dev Override required by ERC2771Context to support meta-transactions
     */
    function _msgSender() internal view override(Context, ERC2771Context) returns (address) {
        return ERC2771Context._msgSender();
    }

    /**
     * @dev Override required by ERC2771Context to support meta-transactions
     */
    function _msgData() internal view override(Context, ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    /**
     * @dev Override required by ERC2771Context to support meta-transactions
     */
    function _contextSuffixLength() internal view override(Context, ERC2771Context) returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }

    /**
     * @dev Deposit USDC to start earning yield with risk-based allocation
     * @param amount Amount of USDC to deposit
     */
    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        require(amount >= MINIMUM_DEPOSIT, "Amount below minimum");
        require(amount > 0, "Cannot deposit 0");

        address sender = _msgSender();

        // Update user's accrued interest before new deposit
        _updateUserInterest(sender);

        // Calculate shares to mint
        uint256 shares = totalShares == 0 ? amount * SHARES_MULTIPLIER / 1e6 : amount * totalShares / totalAssets();

        // Update user state
        userDeposits[sender] += amount;
        userShares[sender] += shares;
        lastDepositTime[sender] = block.timestamp;
        userLastInterestUpdate[sender] = block.timestamp;

        // Update global state
        totalDeposits += amount;
        totalShares += shares;

        // Transfer tokens
        asset.safeTransferFrom(sender, address(this), amount);

        // Get user's risk level for allocation (with fallback)
        RiskProfileManager.RiskLevel riskLevel;
        try riskProfileManager.getUserRiskLevel(sender) returns (RiskProfileManager.RiskLevel level) {
            riskLevel = level;
        } catch {
            // Fallback to MEDIUM risk if risk manager call fails
            riskLevel = RiskProfileManager.RiskLevel.MEDIUM;
        }

        // Trigger risk-based allocation
        _allocateBasedOnRisk(amount, riskLevel);

        emit Deposit(sender, amount, shares, riskLevel);
        emit RiskBasedDeposit(sender, amount, riskLevel);
    }

    /**
     * @dev Deposit with specific risk level (allows user to set risk during deposit)
     * @param amount Amount of USDC to deposit
     * @param riskLevel Risk level for this deposit
     */
    function depositWithRiskLevel(uint256 amount, RiskProfileManager.RiskLevel riskLevel)
        external
        nonReentrant
        whenNotPaused
    {
        require(amount >= MINIMUM_DEPOSIT, "Amount below minimum");
        require(amount > 0, "Cannot deposit 0");

        address sender = _msgSender();

        // Set user's risk profile if they can update it (with fallback)
        try riskProfileManager.canUpdateRiskProfile(sender) returns (bool canUpdate) {
            if (canUpdate) {
                try riskProfileManager.setRiskProfileForUser(sender, riskLevel) {
                    // Risk profile updated successfully
                } catch {
                    // Risk profile update failed, continue with deposit
                }
            }
        } catch {
            // Risk manager call failed, continue with deposit
        }

        // Update user's accrued interest before new deposit
        _updateUserInterest(sender);

        // Calculate shares to mint
        uint256 shares = totalShares == 0 ? amount * SHARES_MULTIPLIER / 1e6 : amount * totalShares / totalAssets();

        // Update user state
        userDeposits[sender] += amount;
        userShares[sender] += shares;
        lastDepositTime[sender] = block.timestamp;
        userLastInterestUpdate[sender] = block.timestamp;

        // Update global state
        totalDeposits += amount;
        totalShares += shares;

        // Transfer tokens
        asset.safeTransferFrom(sender, address(this), amount);

        // Trigger risk-based allocation
        _allocateBasedOnRisk(amount, riskLevel);

        emit Deposit(sender, amount, shares, riskLevel);
        emit RiskBasedDeposit(sender, amount, riskLevel);
    }

    /**
     * @dev Request withdrawal with window period (recommended)
     * @notice Creates a withdrawal request that must wait for the withdrawal window before processing.
     *         This is the recommended withdrawal method as it doesn't charge fees.
     * @param shares Number of shares to redeem - must be > 0 and <= user's available shares
     * @return requestId ID of the withdrawal request that can be used later to process the withdrawal
     * @dev Process:
     *      1. Validates user has sufficient shares
     *      2. Updates user's accrued interest
     *      3. Delegates to withdrawal manager to create the request
     *      4. Returns request ID for future processing
     * @dev Usage:
     *      - Call this function to initiate withdrawal
     *      - Wait for withdrawal window period (typically 24-48 hours)
     *      - Call processWithdrawal(requestId) to complete the withdrawal
     * @dev Benefits:
     *      - No withdrawal fees (unlike instant withdrawal)
     *      - Helps vault manage liquidity efficiently
     *      - Prevents bank run scenarios
     */
    function requestWithdrawal(uint256 shares) external nonReentrant returns (uint256 requestId) {
        require(shares > 0, "Cannot withdraw 0 shares");
        address sender = _msgSender();
        require(userShares[sender] >= shares, "Insufficient shares");

        // Update user's accrued interest
        _updateUserInterest(sender);

        // Delegate to withdrawal manager with sender address
        return withdrawalManager.requestWithdrawalForUser(sender, shares);
    }

    /**
     * @dev Process withdrawal request after window period
     * @notice Completes a withdrawal request that was created earlier and has passed the required waiting period.
     * @param requestId ID of the withdrawal request (obtained from requestWithdrawal)
     * @dev Requirements:
     *      - Request must exist and belong to the caller
     *      - Withdrawal window period must have elapsed
     *      - Request must not be already processed or cancelled
     * @dev Process:
     *      1. Updates user's accrued interest
     *      2. Delegates to withdrawal manager for validation and processing
     *      3. Withdrawal manager calls back to processVaultWithdrawal
     *      4. Vault ensures liquidity and transfers tokens to user
     * @dev Gas Optimization:
     *      - Consider processing multiple requests in batch if you have many
     *      - Interest is updated automatically during processing
     */
    function processWithdrawal(uint256 requestId) external nonReentrant {
        address sender = _msgSender();

        // Update user's accrued interest
        _updateUserInterest(sender);

        // Delegate to withdrawal manager with user address
        withdrawalManager.processWithdrawalForUser(sender, requestId);
    }

    /**
     * @dev Instant withdrawal with fee (legacy function for compatibility)
     * @param shares Number of shares to redeem
     */
    function withdraw(uint256 shares) external nonReentrant {
        require(shares > 0, "Cannot withdraw 0 shares");

        address sender = _msgSender();
        require(userShares[sender] >= shares, "Insufficient shares");

        // Update user's accrued interest
        _updateUserInterest(sender);

        // Calculate withdrawal amount including accrued interest
        uint256 amount = _calculateWithdrawalAmount(sender, shares);

        // Update user state
        userShares[sender] -= shares;
        if (userShares[sender] == 0) {
            userDeposits[sender] = 0;
            userAccruedInterest[sender] = 0;
        } else {
            // Proportionally reduce deposits and accrued interest
            uint256 remainingRatio = userShares[sender] * 1e18 / (userShares[sender] + shares);
            userDeposits[sender] = userDeposits[sender] * remainingRatio / 1e18;
            userAccruedInterest[sender] = userAccruedInterest[sender] * remainingRatio / 1e18;
        }

        // Update global state
        totalShares -= shares;
        if (amount > totalDeposits) {
            totalDeposits = 0;
        } else {
            totalDeposits -= amount;
        }

        // Ensure we have enough liquidity by withdrawing from strategies if needed
        _ensureLiquidity(amount);

        // Transfer tokens
        asset.safeTransfer(sender, amount);

        emit Withdraw(sender, amount, shares);
    }

    /**
     * @dev Instant withdrawal with fee
     * @notice Allows immediate withdrawal of funds by paying a fee, bypassing the withdrawal window.
     * @param shares Number of shares to redeem instantly - must be > 0 and <= user's available shares
     * @dev Trade-offs:
     *      - Pros: Immediate access to funds, no waiting period
     *      - Cons: Charges a fee (typically 0.5-2% of withdrawal amount)
     * @dev Process:
     *      1. Validates user has sufficient shares
     *      2. Updates user's accrued interest
     *      3. Delegates to withdrawal manager for fee calculation and processing
     *      4. Withdrawal manager calls back to processVaultWithdrawal
     *      5. User receives net amount (withdrawal amount - fee)
     * @dev Fee Structure:
     *      - Fee percentage is configurable by admin
     *      - Fee remains in vault as protocol revenue
     *      - Net amount = gross_amount * (1 - fee_percentage)
     * @dev Use Cases:
     *      - Emergency fund access
     *      - Time-sensitive opportunities
     *      - Users who prefer convenience over cost
     */
    function instantWithdrawal(uint256 shares) external nonReentrant {
        require(shares > 0, "Cannot withdraw 0 shares");
        address sender = _msgSender();
        require(userShares[sender] >= shares, "Insufficient shares");

        // Update user's accrued interest
        _updateUserInterest(sender);

        // Delegate to withdrawal manager with user address
        withdrawalManager.instantWithdrawalForUser(sender, shares);
    }

    /**
     * @dev Cancel withdrawal request
     * @param requestId ID of the withdrawal request to cancel
     */
    function cancelWithdrawal(uint256 requestId) external nonReentrant {
        withdrawalManager.cancelWithdrawalForUser(_msgSender(), requestId);
    }

    /**
     * @dev Process vault withdrawal (called by withdrawal manager)
     * @notice This function is called by the withdrawal manager to execute the actual withdrawal.
     *         It handles the core vault operations: updating user state, ensuring liquidity, and transferring tokens.
     * @param user User address who is withdrawing funds
     * @param shares Number of shares to burn/withdraw from user's balance
     * @param amount Amount of USDC to transfer to the user (in 6 decimals)
     * @dev Requirements:
     *      - Can only be called by the withdrawal manager contract
     *      - User must have sufficient shares to withdraw
     *      - Vault must have sufficient liquidity (will withdraw from strategies if needed)
     * @dev Effects:
     *      - Reduces user's share balance by specified amount
     *      - Reduces total shares in the vault
     *      - Ensures sufficient liquidity by withdrawing from strategies if necessary
     *      - Transfers USDC tokens directly to the user
     *      - Emits Withdraw event for tracking
     * @dev Security:
     *      - Only withdrawal manager can call this function
     *      - Validates user has sufficient shares before processing
     *      - Uses SafeERC20 for secure token transfers
     */
    function processVaultWithdrawal(address user, uint256 shares, uint256 amount) external {
        require(msg.sender == address(withdrawalManager), "Only withdrawal manager can call");
        require(userShares[user] >= shares, "Insufficient shares");

        // Update user state
        userShares[user] -= shares;
        totalShares -= shares;

        // Ensure we have enough liquidity
        _ensureLiquidity(amount);

        // Transfer tokens to user
        asset.safeTransfer(user, amount);

        emit Withdraw(user, amount, shares);
    }

    /**
     * @dev Get total assets under management (including deployed to strategies)
     */
    function totalAssets() public view returns (uint256) {
        uint256 idle = asset.balanceOf(address(this));
        uint256 deployed = 0;

        for (uint256 i = 0; i < strategies.length; i++) {
            if (isActiveStrategy[address(strategies[i])]) {
                deployed += strategies[i].totalAssets();
            }
        }

        return idle + deployed;
    }

    /**
     * @dev Get user's current balance including yield
     */
    function balanceOf(address user) external view returns (uint256) {
        if (totalShares == 0) return 0;
        return userShares[user] * totalAssets() / totalShares;
    }

    /**
     * @dev Get user's earned yield
     */
    function earnedYield(address user) external view returns (uint256) {
        uint256 currentBalance = this.balanceOf(user);
        return currentBalance > userDeposits[user] ? currentBalance - userDeposits[user] : 0;
    }

    /**
     * @dev Update accrued interest for user (public function)
     * @param user User address
     */
    function updateAccruedInterest(address user) external {
        _updateUserInterest(user);
    }

    // Strategy management functions (onlyOwner)
    function addStrategy(address strategy, uint256 weight) external onlyOwner {
        require(strategy != address(0), "Invalid strategy");
        require(!isActiveStrategy[strategy], "Strategy already active");
        require(strategies.length < MAX_STRATEGIES, "Too many strategies");
        require(weight > 0, "Weight must be positive");

        strategies.push(IAbunfiStrategy(strategy));
        isActiveStrategy[strategy] = true;
        strategyWeights[strategy] = weight;

        emit StrategyAdded(strategy, weight);
    }

    function removeStrategy(address strategy) external onlyOwner {
        require(isActiveStrategy[strategy], "Strategy not active");

        // Withdraw all funds from strategy
        IAbunfiStrategy(strategy).withdrawAll();
        isActiveStrategy[strategy] = false;
        strategyWeights[strategy] = 0;
        strategyAllocations[strategy] = 0;

        emit StrategyRemoved(strategy);
    }

    /**
     * @dev Update strategy weight for allocation
     */
    function updateStrategyWeight(address strategy, uint256 newWeight) external onlyOwner {
        require(isActiveStrategy[strategy], "Strategy not active");
        require(newWeight > 0, "Weight must be positive");

        uint256 oldWeight = strategyWeights[strategy];
        strategyWeights[strategy] = newWeight;

        emit StrategyWeightUpdated(strategy, oldWeight, newWeight);
    }

    /**
     * @dev Update reserve ratio
     */
    function updateReserveRatio(uint256 newRatio) external onlyOwner {
        require(newRatio <= 5000, "Reserve ratio too high"); // Max 50%

        uint256 oldRatio = reserveRatio;
        reserveRatio = newRatio;

        emit ReserveRatioUpdated(oldRatio, newRatio);
    }

    /**
     * @dev Allocate idle funds to strategies based on weights and APY
     */
    function allocateToStrategies() external onlyOwner {
        uint256 totalAssets_ = totalAssets();
        uint256 idle = asset.balanceOf(address(this));
        uint256 reserve = (totalAssets_ * reserveRatio) / BASIS_POINTS;

        if (idle > reserve) {
            uint256 toAllocate = idle - reserve;
            _allocateByWeight(toAllocate);
        }
    }

    /**
     * @dev Smart rebalancing based on APY performance
     */
    function rebalance() external onlyOwner {
        uint256 totalRebalanced = 0;

        // Calculate optimal allocation based on current APYs
        uint256[] memory targetAllocations = _calculateOptimalAllocations();

        for (uint256 i = 0; i < strategies.length; i++) {
            if (isActiveStrategy[address(strategies[i])]) {
                uint256 currentBalance = strategies[i].totalAssets();
                uint256 targetBalance = targetAllocations[i];

                if (currentBalance > targetBalance) {
                    // Withdraw excess
                    uint256 excess = currentBalance - targetBalance;
                    strategies[i].withdraw(excess);
                    totalRebalanced += excess;
                } else if (targetBalance > currentBalance) {
                    // Allocate more if we have idle funds
                    uint256 needed = targetBalance - currentBalance;
                    uint256 available = asset.balanceOf(address(this));
                    uint256 toAllocate = needed > available ? available : needed;

                    if (toAllocate > 0) {
                        asset.safeTransfer(address(strategies[i]), toAllocate);
                        strategies[i].deposit(toAllocate);
                        totalRebalanced += toAllocate;
                    }
                }
            }
        }

        emit Rebalanced(totalRebalanced);
    }

    /**
     * @dev Harvest yield from all strategies
     */
    function harvest() external onlyOwner {
        uint256 totalYield = 0;

        for (uint256 i = 0; i < strategies.length; i++) {
            if (isActiveStrategy[address(strategies[i])]) {
                totalYield += strategies[i].harvest();
            }
        }

        emit Harvest(totalYield);
    }

    /**
     * @dev Get strategy information including APY
     */
    function getStrategyInfo(address strategy)
        external
        view
        returns (string memory name, uint256 totalAssetsAmount, uint256 apy, uint256 weight, bool isActive)
    {
        if (isActiveStrategy[strategy]) {
            IAbunfiStrategy strategyContract = IAbunfiStrategy(strategy);
            return (
                strategyContract.name(),
                strategyContract.totalAssets(),
                strategyContract.getAPY(),
                strategyWeights[strategy],
                true
            );
        }
        return ("", 0, 0, 0, false);
    }

    /**
     * @dev Get all active strategies info
     */
    function getAllStrategiesInfo()
        external
        view
        returns (
            address[] memory addresses,
            string[] memory names,
            uint256[] memory totalAssetsAmounts,
            uint256[] memory apys,
            uint256[] memory weights
        )
    {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < strategies.length; i++) {
            if (isActiveStrategy[address(strategies[i])]) {
                activeCount++;
            }
        }

        addresses = new address[](activeCount);
        names = new string[](activeCount);
        totalAssetsAmounts = new uint256[](activeCount);
        apys = new uint256[](activeCount);
        weights = new uint256[](activeCount);

        uint256 index = 0;
        for (uint256 i = 0; i < strategies.length; i++) {
            if (isActiveStrategy[address(strategies[i])]) {
                addresses[index] = address(strategies[i]);
                names[index] = strategies[i].name();
                totalAssetsAmounts[index] = strategies[i].totalAssets();
                apys[index] = strategies[i].getAPY();
                weights[index] = strategyWeights[address(strategies[i])];
                index++;
            }
        }
    }

    /**
     * @dev Ensure sufficient liquidity for withdrawal
     */
    function _ensureLiquidity(uint256 amount) internal {
        uint256 idle = asset.balanceOf(address(this));

        if (idle < amount) {
            uint256 needed = amount - idle;

            // Withdraw from strategies starting with lowest APY
            uint256[] memory apys = new uint256[](strategies.length);
            uint256[] memory indices = new uint256[](strategies.length);

            // Get APYs and create index array
            for (uint256 i = 0; i < strategies.length; i++) {
                if (isActiveStrategy[address(strategies[i])]) {
                    apys[i] = strategies[i].getAPY();
                } else {
                    apys[i] = 0;
                }
                indices[i] = i;
            }

            // Simple bubble sort by APY (ascending)
            for (uint256 i = 0; i < strategies.length - 1; i++) {
                for (uint256 j = 0; j < strategies.length - i - 1; j++) {
                    if (apys[indices[j]] > apys[indices[j + 1]]) {
                        uint256 temp = indices[j];
                        indices[j] = indices[j + 1];
                        indices[j + 1] = temp;
                    }
                }
            }

            // Withdraw from strategies with lowest APY first
            for (uint256 i = 0; i < strategies.length && needed > 0; i++) {
                uint256 strategyIndex = indices[i];
                if (isActiveStrategy[address(strategies[strategyIndex])]) {
                    uint256 available = strategies[strategyIndex].totalAssets();
                    uint256 toWithdraw = needed > available ? available : needed;

                    if (toWithdraw > 0) {
                        strategies[strategyIndex].withdraw(toWithdraw);
                        needed -= toWithdraw;
                    }
                }
            }
        }
    }

    /**
     * @dev Allocate funds based on strategy weights
     */
    function _allocateByWeight(uint256 amount) internal {
        uint256 totalWeight = 0;

        // Calculate total weight
        for (uint256 i = 0; i < strategies.length; i++) {
            if (isActiveStrategy[address(strategies[i])]) {
                totalWeight += strategyWeights[address(strategies[i])];
            }
        }

        if (totalWeight > 0) {
            for (uint256 i = 0; i < strategies.length; i++) {
                if (isActiveStrategy[address(strategies[i])]) {
                    uint256 allocation = (amount * strategyWeights[address(strategies[i])]) / totalWeight;
                    if (allocation > 0) {
                        asset.safeTransfer(address(strategies[i]), allocation);
                        strategies[i].deposit(allocation);
                    }
                }
            }
        }
    }

    /**
     * @dev Calculate optimal allocations based on APY and weights
     */
    function _calculateOptimalAllocations() internal view returns (uint256[] memory) {
        uint256[] memory allocations = new uint256[](strategies.length);
        uint256 totalAssets_ = totalAssets();
        uint256 reserve = (totalAssets_ * reserveRatio) / BASIS_POINTS;
        uint256 deployable = totalAssets_ > reserve ? totalAssets_ - reserve : 0;

        uint256 totalWeightedAPY = 0;
        uint256[] memory weightedAPYs = new uint256[](strategies.length);

        // Calculate weighted APYs
        for (uint256 i = 0; i < strategies.length; i++) {
            if (isActiveStrategy[address(strategies[i])]) {
                uint256 apy = strategies[i].getAPY();
                uint256 weight = strategyWeights[address(strategies[i])];
                weightedAPYs[i] = apy * weight;
                totalWeightedAPY += weightedAPYs[i];
            }
        }

        // Allocate based on weighted APY
        if (totalWeightedAPY > 0) {
            for (uint256 i = 0; i < strategies.length; i++) {
                if (isActiveStrategy[address(strategies[i])]) {
                    allocations[i] = (deployable * weightedAPYs[i]) / totalWeightedAPY;
                }
            }
        }

        return allocations;
    }

    // Emergency functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Additional strategy management
    address[] public strategyList;

    /**
     * @dev Add a strategy with weight
     */
    function addStrategyWithWeight(address _strategy, uint256 _weight) external onlyOwner {
        require(_strategy != address(0), "Invalid strategy address");
        require(!isActiveStrategy[_strategy], "Strategy already active");
        require(_weight > 0, "Weight must be positive");

        isActiveStrategy[_strategy] = true;
        strategyWeights[_strategy] = _weight;
        strategies.push(IAbunfiStrategy(_strategy));
        strategyList.push(_strategy);

        emit StrategyAdded(_strategy);
    }

    /**
     * @dev Add a strategy (single parameter version for compatibility)
     */
    function addStrategy(address _strategy) external onlyOwner {
        require(_strategy != address(0), "Invalid strategy address");
        require(!isActiveStrategy[_strategy], "Strategy already active");

        isActiveStrategy[_strategy] = true;
        strategyWeights[_strategy] = 100; // Default weight
        strategyList.push(_strategy);

        emit StrategyAdded(_strategy);
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 balance = asset.balanceOf(address(this));
        asset.safeTransfer(owner(), balance);
    }

    // Risk-based and interest tracking functions

    /**
     * @dev Update user's accrued interest
     * @param user User address
     */
    function _updateUserInterest(address user) internal {
        if (userLastInterestUpdate[user] == 0) {
            userLastInterestUpdate[user] = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - userLastInterestUpdate[user];
        if (timeElapsed == 0) return;

        // Calculate interest based on user's share of total assets
        uint256 userBalance = userShares[user] * totalAssets() / totalShares;
        uint256 principal = userDeposits[user];

        if (userBalance > principal) {
            uint256 newInterest = userBalance - principal - userAccruedInterest[user];
            userAccruedInterest[user] += newInterest;
            userTotalInterestEarned[user] += newInterest;

            if (newInterest > 0) {
                emit InterestAccrued(user, newInterest);
            }
        }

        userLastInterestUpdate[user] = block.timestamp;
    }

    /**
     * @dev Calculate withdrawal amount including accrued interest
     * @param user User address
     * @param shares Number of shares to withdraw
     * @return Withdrawal amount
     */
    function _calculateWithdrawalAmount(address user, uint256 shares) internal view returns (uint256) {
        if (totalShares == 0) return 0;

        // Base amount from shares
        uint256 baseAmount = shares * totalAssets() / totalShares;

        // Add proportional accrued interest
        uint256 userTotalShares = userShares[user];
        if (userTotalShares > 0) {
            uint256 proportionalInterest = userAccruedInterest[user] * shares / userTotalShares;
            return baseAmount + proportionalInterest;
        }

        return baseAmount;
    }

    /**
     * @dev Allocate funds based on user's risk profile
     * @param amount Amount to allocate
     * @param riskLevel User's risk level
     */
    function _allocateBasedOnRisk(uint256 amount, RiskProfileManager.RiskLevel riskLevel) internal {
        // Get risk-based allocation from risk profile manager (with fallback)
        address[] memory riskStrategies;
        uint256[] memory allocations;

        try riskProfileManager.getUserAllocations(msg.sender) returns (
            address[] memory riskStrats, uint256[] memory allocs
        ) {
            riskStrategies = riskStrats;
            allocations = allocs;
        } catch {
            // Fallback to default allocation if risk manager call fails
            _allocateByWeight(amount);
            return;
        }

        if (riskStrategies.length == 0) {
            // Fallback to default allocation if no risk-specific strategies
            _allocateByWeight(amount);
            return;
        }

        // Allocate based on risk profile
        for (uint256 i = 0; i < riskStrategies.length; i++) {
            if (isActiveStrategy[riskStrategies[i]]) {
                uint256 allocation = (amount * allocations[i]) / BASIS_POINTS;
                if (allocation > 0) {
                    asset.safeTransfer(riskStrategies[i], allocation);
                    IAbunfiStrategy(riskStrategies[i]).deposit(allocation);
                }
            }
        }
    }

    /**
     * @dev Update risk management contracts
     * @param _riskProfileManager New risk profile manager address
     * @param _withdrawalManager New withdrawal manager address
     */
    function updateRiskManagers(address _riskProfileManager, address _withdrawalManager) external onlyOwner {
        require(_riskProfileManager != address(0), "Invalid risk profile manager");
        require(_withdrawalManager != address(0), "Invalid withdrawal manager");

        riskProfileManager = RiskProfileManager(_riskProfileManager);
        withdrawalManager = WithdrawalManager(_withdrawalManager);

        emit RiskManagersUpdated(_riskProfileManager, _withdrawalManager);
    }

    /**
     * @dev Get user's current balance including accrued interest
     * @param user User address
     * @return Total balance including interest
     */
    function getBalanceWithInterest(address user) external view returns (uint256) {
        if (totalShares == 0) return 0;
        uint256 baseBalance = userShares[user] * totalAssets() / totalShares;
        return baseBalance + userAccruedInterest[user];
    }

    /**
     * @dev Get user's accrued interest
     * @param user User address
     * @return Accrued interest amount
     */
    function getUserAccruedInterest(address user) external view returns (uint256) {
        return userAccruedInterest[user];
    }

    /**
     * @dev Get user's total interest earned over time
     * @param user User address
     * @return Total interest earned
     */
    function getUserTotalInterestEarned(address user) external view returns (uint256) {
        return userTotalInterestEarned[user];
    }
}
