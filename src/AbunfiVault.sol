// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IAbunfiStrategy.sol";

/**
 * @title AbunfiVault
 * @dev Main vault contract for Abunfi micro-savings platform
 * Manages user deposits and allocates funds to yield-generating strategies
 */
contract AbunfiVault is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // State variables
    IERC20 public immutable asset; // USDC token
    mapping(address => uint256) public userDeposits;
    mapping(address => uint256) public userShares;
    mapping(address => uint256) public lastDepositTime;
    
    uint256 public totalDeposits;
    uint256 public totalShares;
    uint256 public constant MINIMUM_DEPOSIT = 4e6; // ~$4 USDC (6 decimals)
    uint256 public constant SHARES_MULTIPLIER = 1e18;
    
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
    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);
    event StrategyAdded(address indexed strategy);
    event StrategyAdded(address indexed strategy, uint256 weight);
    event StrategyRemoved(address indexed strategy);
    event StrategyWeightUpdated(address indexed strategy, uint256 oldWeight, uint256 newWeight);
    event Harvest(uint256 totalYield);
    event Rebalanced(uint256 totalRebalanced);
    event ReserveRatioUpdated(uint256 oldRatio, uint256 newRatio);

    constructor(address _asset) Ownable(msg.sender) {
        asset = IERC20(_asset);
    }

    /**
     * @dev Deposit USDC to start earning yield
     * @param amount Amount of USDC to deposit
     */
    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        require(amount >= MINIMUM_DEPOSIT, "Amount below minimum");
        require(amount > 0, "Cannot deposit 0");

        // Calculate shares to mint
        uint256 shares = totalShares == 0 ? 
            amount * SHARES_MULTIPLIER / 1e6 : 
            amount * totalShares / totalAssets();

        // Update user state
        userDeposits[msg.sender] += amount;
        userShares[msg.sender] += shares;
        lastDepositTime[msg.sender] = block.timestamp;
        
        // Update global state
        totalDeposits += amount;
        totalShares += shares;

        // Transfer tokens
        asset.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount, shares);
    }

    /**
     * @dev Withdraw USDC and earned yield
     * @param shares Number of shares to redeem
     */
    function withdraw(uint256 shares) external nonReentrant {
        require(shares > 0, "Cannot withdraw 0 shares");
        require(userShares[msg.sender] >= shares, "Insufficient shares");

        // Calculate withdrawal amount
        uint256 amount = shares * totalAssets() / totalShares;
        
        // Update user state
        userShares[msg.sender] -= shares;
        if (userShares[msg.sender] == 0) {
            userDeposits[msg.sender] = 0;
        } else {
            userDeposits[msg.sender] = userDeposits[msg.sender] * userShares[msg.sender] / (userShares[msg.sender] + shares);
        }
        
        // Update global state
        totalShares -= shares;
        if (amount > totalDeposits) {
            totalDeposits = 0;
        } else {
            totalDeposits -= amount;
        }

        // Ensure we have enough liquidity
        _ensureLiquidity(amount);

        // Transfer tokens
        asset.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount, shares);
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
    function getStrategyInfo(address strategy) external view returns (
        string memory name,
        uint256 totalAssetsAmount,
        uint256 apy,
        uint256 weight,
        bool isActive
    ) {
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
    function getAllStrategiesInfo() external view returns (
        address[] memory addresses,
        string[] memory names,
        uint256[] memory totalAssetsAmounts,
        uint256[] memory apys,
        uint256[] memory weights
    ) {
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
}
