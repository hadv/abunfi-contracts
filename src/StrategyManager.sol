// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IAbunfiStrategy.sol";

/**
 * @title StrategyManager
 * @dev Advanced strategy management with risk assessment and dynamic allocation
 */
contract StrategyManager is Ownable, ReentrancyGuard {
    struct StrategyInfo {
        IAbunfiStrategy strategy;
        uint256 weight; // Base weight for allocation
        uint256 riskScore; // Risk score (0-100, lower is safer)
        uint256 maxAllocation; // Maximum allocation percentage (basis points)
        uint256 minAllocation; // Minimum allocation percentage (basis points)
        bool isActive;
        uint256 lastAPY; // Last recorded APY
        uint256 apyHistory; // Moving average of APY
        uint256 performanceScore; // Performance score based on consistency
    }

    mapping(address => StrategyInfo) public strategies;
    address[] public strategyList;

    // Configuration
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_RISK_SCORE = 100;
    uint256 public riskTolerance = 50; // Default medium risk tolerance
    uint256 public performanceWindow = 30 days; // Performance evaluation window
    uint256 public rebalanceThreshold = 500; // 5% threshold for rebalancing

    // APY tracking
    mapping(address => uint256[]) public apyHistory;
    mapping(address => uint256) public lastUpdateTime;

    // Events
    event StrategyAdded(address indexed strategy, uint256 weight, uint256 riskScore);
    event StrategyUpdated(address indexed strategy, uint256 newWeight, uint256 newRiskScore);
    event StrategyDeactivated(address indexed strategy);
    event StrategyReactivated(address indexed strategy);
    event APYUpdated(address indexed strategy, uint256 oldAPY, uint256 newAPY);
    event StrategyRemoved(address indexed strategy);
    event AllocationCalculated(address indexed strategy, uint256 allocation);
    event RiskToleranceUpdated(uint256 oldTolerance, uint256 newTolerance);
    event PerformanceUpdated(address indexed strategy, uint256 newScore);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Add a new strategy with risk assessment
     */
    function addStrategy(
        address _strategy,
        uint256 _weight,
        uint256 _riskScore,
        uint256 _maxAllocation,
        uint256 _minAllocation
    ) external onlyOwner {
        require(_strategy != address(0), "Invalid strategy address");
        require(!strategies[_strategy].isActive, "Strategy already exists");
        require(_riskScore <= MAX_RISK_SCORE, "Risk score too high");
        require(_maxAllocation <= BASIS_POINTS, "Max allocation too high");
        require(_minAllocation <= _maxAllocation, "Min allocation > max allocation");
        require(_weight > 0, "Weight must be positive");

        strategies[_strategy] = StrategyInfo({
            strategy: IAbunfiStrategy(_strategy),
            weight: _weight,
            riskScore: _riskScore,
            maxAllocation: _maxAllocation,
            minAllocation: _minAllocation,
            isActive: true,
            lastAPY: 0,
            apyHistory: 0,
            performanceScore: 50 // Start with neutral score
        });

        strategyList.push(_strategy);
        lastUpdateTime[_strategy] = block.timestamp;

        emit StrategyAdded(_strategy, _weight, _riskScore);
    }

    /**
     * @dev Update strategy parameters
     */
    function updateStrategy(
        address _strategy,
        uint256 _weight,
        uint256 _riskScore,
        uint256 _maxAllocation,
        uint256 _minAllocation
    ) external onlyOwner {
        require(strategies[_strategy].isActive, "Strategy not active");
        require(_riskScore <= MAX_RISK_SCORE, "Risk score too high");
        require(_maxAllocation <= BASIS_POINTS, "Max allocation too high");
        require(_minAllocation <= _maxAllocation, "Min allocation > max allocation");
        require(_weight > 0, "Weight must be positive");

        StrategyInfo storage info = strategies[_strategy];
        info.weight = _weight;
        info.riskScore = _riskScore;
        info.maxAllocation = _maxAllocation;
        info.minAllocation = _minAllocation;

        emit StrategyUpdated(_strategy, _weight, _riskScore);
    }

    /**
     * @dev Remove a strategy
     */
    function removeStrategy(address _strategy) external onlyOwner {
        require(strategies[_strategy].isActive, "Strategy not active");

        strategies[_strategy].isActive = false;

        // Remove from strategy list
        for (uint256 i = 0; i < strategyList.length; i++) {
            if (strategyList[i] == _strategy) {
                strategyList[i] = strategyList[strategyList.length - 1];
                strategyList.pop();
                break;
            }
        }

        emit StrategyRemoved(_strategy);
    }

    /**
     * @dev Update APY data for performance tracking
     */
    function updateAPYData() external {
        for (uint256 i = 0; i < strategyList.length; i++) {
            address strategyAddr = strategyList[i];
            if (strategies[strategyAddr].isActive) {
                uint256 currentAPY = strategies[strategyAddr].strategy.getAPY();

                // Update APY history
                apyHistory[strategyAddr].push(currentAPY);

                // Keep only last 30 data points
                if (apyHistory[strategyAddr].length > 30) {
                    // Shift array left
                    for (uint256 j = 0; j < apyHistory[strategyAddr].length - 1; j++) {
                        apyHistory[strategyAddr][j] = apyHistory[strategyAddr][j + 1];
                    }
                    apyHistory[strategyAddr].pop();
                }

                // Update moving average
                strategies[strategyAddr].apyHistory = _calculateMovingAverage(strategyAddr);
                strategies[strategyAddr].lastAPY = currentAPY;
                strategies[strategyAddr].performanceScore = _calculatePerformanceScore(strategyAddr);
                lastUpdateTime[strategyAddr] = block.timestamp;

                emit PerformanceUpdated(strategyAddr, strategies[strategyAddr].performanceScore);
            }
        }
    }

    /**
     * @dev Calculate optimal allocation for each strategy
     */
    function calculateOptimalAllocations(uint256 totalAmount) external returns (address[] memory, uint256[] memory) {
        uint256 activeStrategies = 0;
        for (uint256 i = 0; i < strategyList.length; i++) {
            if (strategies[strategyList[i]].isActive) {
                activeStrategies++;
            }
        }

        address[] memory strategyAddresses = new address[](activeStrategies);
        uint256[] memory allocations = new uint256[](activeStrategies);

        if (activeStrategies == 0) {
            return (strategyAddresses, allocations);
        }

        // Calculate risk-adjusted scores
        uint256[] memory scores = new uint256[](activeStrategies);
        uint256 totalScore = 0;
        uint256 index = 0;

        for (uint256 i = 0; i < strategyList.length; i++) {
            address strategyAddr = strategyList[i];
            if (strategies[strategyAddr].isActive) {
                strategyAddresses[index] = strategyAddr;
                scores[index] = _calculateRiskAdjustedScore(strategyAddr);
                totalScore += scores[index];
                index++;
            }
        }

        // Calculate allocations based on scores
        if (totalScore > 0) {
            for (uint256 i = 0; i < activeStrategies; i++) {
                uint256 baseAllocation = (totalAmount * scores[i]) / totalScore;

                // Apply min/max constraints
                address strategyAddr = strategyAddresses[i];
                uint256 minAmount = (totalAmount * strategies[strategyAddr].minAllocation) / BASIS_POINTS;
                uint256 maxAmount = (totalAmount * strategies[strategyAddr].maxAllocation) / BASIS_POINTS;

                if (baseAllocation < minAmount) {
                    allocations[i] = minAmount;
                } else if (baseAllocation > maxAmount) {
                    allocations[i] = maxAmount;
                } else {
                    allocations[i] = baseAllocation;
                }

                emit AllocationCalculated(strategyAddr, allocations[i]);
            }
        }

        return (strategyAddresses, allocations);
    }

    /**
     * @dev Check if rebalancing is needed
     */
    function shouldRebalance(address[] memory currentStrategies, uint256[] memory currentAllocations)
        external
        view
        returns (bool)
    {
        if (currentStrategies.length == 0) return false;

        uint256 totalCurrent = 0;
        for (uint256 i = 0; i < currentAllocations.length; i++) {
            totalCurrent += currentAllocations[i];
        }

        if (totalCurrent == 0) return false;

        // Simple check: if any strategy allocation deviates significantly from equal allocation
        uint256 expectedAllocation = totalCurrent / currentStrategies.length;

        // Check if any allocation deviates significantly from expected equal allocation
        for (uint256 i = 0; i < currentAllocations.length; i++) {
            uint256 currentAlloc = currentAllocations[i];

            // Calculate deviation percentage
            uint256 deviation = currentAlloc > expectedAllocation
                ? currentAlloc - expectedAllocation
                : expectedAllocation - currentAlloc;
            uint256 deviationBps = (deviation * BASIS_POINTS) / totalCurrent;

            if (deviationBps > rebalanceThreshold) {
                return true;
            }
        }

        return false;
    }

    /**
     * @dev Calculate risk-adjusted score for a strategy
     */
    function _calculateRiskAdjustedScore(address _strategy) internal view returns (uint256) {
        StrategyInfo memory info = strategies[_strategy];

        // Base score from weight and performance
        uint256 baseScore = info.weight * info.performanceScore;

        // Risk adjustment based on risk tolerance
        uint256 riskAdjustment = 100;
        if (info.riskScore > riskTolerance) {
            // Penalize high-risk strategies if risk tolerance is low
            uint256 riskPenalty = ((info.riskScore - riskTolerance) * 50) / MAX_RISK_SCORE;
            riskAdjustment = riskAdjustment > riskPenalty ? riskAdjustment - riskPenalty : 0;
        } else if (info.riskScore < riskTolerance) {
            // Bonus for low-risk strategies if risk tolerance is high
            uint256 riskBonus = ((riskTolerance - info.riskScore) * 20) / MAX_RISK_SCORE;
            riskAdjustment += riskBonus;
        }

        // APY factor
        uint256 apyFactor = info.lastAPY > 0 ? info.lastAPY : 100; // Default to 1% if no APY data

        return (baseScore * riskAdjustment * apyFactor) / (100 * 100);
    }

    /**
     * @dev Calculate moving average of APY
     */
    function _calculateMovingAverage(address _strategy) internal view returns (uint256) {
        uint256[] memory history = apyHistory[_strategy];
        if (history.length == 0) return 0;

        uint256 sum = 0;
        for (uint256 i = 0; i < history.length; i++) {
            sum += history[i];
        }

        return sum / history.length;
    }

    /**
     * @dev Calculate performance score based on APY consistency
     */
    function _calculatePerformanceScore(address _strategy) internal view returns (uint256) {
        uint256[] memory history = apyHistory[_strategy];
        if (history.length < 2) return 50; // Default neutral score

        // Calculate variance to measure consistency
        uint256 mean = _calculateMovingAverage(_strategy);
        uint256 variance = 0;

        for (uint256 i = 0; i < history.length; i++) {
            uint256 diff = history[i] > mean ? history[i] - mean : mean - history[i];
            variance += diff * diff;
        }
        variance = variance / history.length;

        // Convert variance to score (lower variance = higher score)
        // This is a simplified scoring mechanism
        uint256 score = variance < 100 ? 100 - variance : 0;
        return score > 100 ? 100 : score;
    }

    // Admin functions
    function setRiskTolerance(uint256 _riskTolerance) external onlyOwner {
        require(_riskTolerance <= MAX_RISK_SCORE, "Risk tolerance too high");
        uint256 oldTolerance = riskTolerance;
        riskTolerance = _riskTolerance;
        emit RiskToleranceUpdated(oldTolerance, _riskTolerance);
    }

    /**
     * @dev Deactivate a strategy
     */
    function deactivateStrategy(address _strategy) external onlyOwner {
        require(strategies[_strategy].isActive, "Strategy not active");
        strategies[_strategy].isActive = false;
        emit StrategyDeactivated(_strategy);
    }

    /**
     * @dev Reactivate a strategy
     */
    function reactivateStrategy(address _strategy) external onlyOwner {
        require(!strategies[_strategy].isActive, "Strategy already active");
        strategies[_strategy].isActive = true;
        emit StrategyReactivated(_strategy);
    }

    /**
     * @dev Update strategy APY
     */
    function updateStrategyAPY(address _strategy, uint256 _apy) external onlyOwner {
        require(strategies[_strategy].isActive, "Strategy not active");
        uint256 oldAPY = strategies[_strategy].lastAPY;
        strategies[_strategy].lastAPY = _apy;

        // Track APY history
        apyHistory[_strategy].push(_apy);

        // Update moving average
        strategies[_strategy].apyHistory = _calculateMovingAverage(_strategy);

        // Calculate performance score based on consistency
        uint256 historyLength = apyHistory[_strategy].length;
        if (historyLength >= 2) {
            // Calculate variance to measure consistency
            uint256 avgAPY = strategies[_strategy].apyHistory;
            uint256 variance = 0;
            for (uint256 i = 0; i < historyLength; i++) {
                uint256 diff = apyHistory[_strategy][i] > avgAPY
                    ? apyHistory[_strategy][i] - avgAPY
                    : avgAPY - apyHistory[_strategy][i];
                variance += diff * diff;
            }
            variance = variance / historyLength;

            // Higher score for lower variance (more consistent)
            // Score ranges from 0-100, with 100 being most consistent
            strategies[_strategy].performanceScore = variance < 100 ? 100 - variance : 0;
        } else {
            // Default score for new strategies
            strategies[_strategy].performanceScore = 50;
        }

        lastUpdateTime[_strategy] = block.timestamp;

        emit APYUpdated(_strategy, oldAPY, _apy);
    }

    /**
     * @dev Calculate optimal allocation (simplified version)
     */
    function calculateOptimalAllocation(uint256 _totalAmount) external view returns (uint256[] memory) {
        address[] memory activeStrategies = getActiveStrategies();
        uint256[] memory allocations = new uint256[](activeStrategies.length);

        if (activeStrategies.length == 0) {
            return allocations;
        }

        // Simple equal allocation for now
        uint256 allocationPerStrategy = _totalAmount / activeStrategies.length;
        uint256 remainder = _totalAmount % activeStrategies.length;

        for (uint256 i = 0; i < activeStrategies.length; i++) {
            allocations[i] = allocationPerStrategy;
            if (i < remainder) {
                allocations[i] += 1; // Distribute remainder
            }
        }

        return allocations;
    }

    /**
     * @dev Get all active strategies
     */
    function getActiveStrategies() public view returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < strategyList.length; i++) {
            if (strategies[strategyList[i]].isActive) {
                count++;
            }
        }

        address[] memory activeStrategies = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < strategyList.length; i++) {
            if (strategies[strategyList[i]].isActive) {
                activeStrategies[index] = strategyList[i];
                index++;
            }
        }

        return activeStrategies;
    }

    /**
     * @dev Get strategy count
     */
    function getStrategyCount() external view returns (uint256) {
        return strategyList.length;
    }

    /**
     * @dev Get strategy info
     */
    function getStrategyInfo(address _strategy)
        external
        view
        returns (
            uint256 weight,
            uint256 lastAPY,
            uint256 riskScore,
            uint256 maxAllocation,
            uint256 minAllocation,
            bool isActive
        )
    {
        StrategyInfo memory info = strategies[_strategy];
        return (info.weight, info.lastAPY, info.riskScore, info.maxAllocation, info.minAllocation, info.isActive);
    }

    /**
     * @dev Get portfolio summary
     */
    function getPortfolioSummary()
        external
        view
        returns (uint256 totalStrategies, uint256 activeStrategies, uint256 averageAPY, uint256 totalRiskScore)
    {
        totalStrategies = strategyList.length;

        uint256 activeCount = 0;
        uint256 totalAPY = 0;
        uint256 totalRisk = 0;

        for (uint256 i = 0; i < strategyList.length; i++) {
            StrategyInfo memory info = strategies[strategyList[i]];
            if (info.isActive) {
                activeCount++;
                totalAPY += info.lastAPY;
                totalRisk += info.riskScore;
            }
        }

        activeStrategies = activeCount;
        averageAPY = activeCount > 0 ? totalAPY / activeCount : 0;
        totalRiskScore = activeCount > 0 ? totalRisk / activeCount : 0;
    }

    /**
     * @dev Calculate risk-adjusted return (simplified)
     */
    function calculateRiskAdjustedReturn(address _strategy) external view returns (uint256) {
        StrategyInfo memory info = strategies[_strategy];
        if (!info.isActive || info.riskScore == 0) {
            return 0;
        }
        // Simple risk-adjusted return: APY / risk score
        return (info.lastAPY * 100) / info.riskScore;
    }

    /**
     * @dev Calculate rebalance amounts (simplified)
     */
    function calculateRebalanceAmounts(
        address[] memory _strategies,
        uint256[] memory _currentAmounts,
        uint256 _totalAmount
    ) external view returns (uint256[] memory) {
        // Simple equal allocation for rebalancing
        address[] memory activeStrategies = getActiveStrategies();
        uint256[] memory rebalanceAmounts = new uint256[](_strategies.length);

        if (activeStrategies.length == 0) {
            return rebalanceAmounts;
        }

        uint256 targetPerStrategy = _totalAmount / activeStrategies.length;

        for (uint256 i = 0; i < _strategies.length; i++) {
            rebalanceAmounts[i] = targetPerStrategy > _currentAmounts[i] ? targetPerStrategy - _currentAmounts[i] : 0;
        }

        return rebalanceAmounts;
    }

    /**
     * @dev Get strategy performance over time
     */
    function getStrategyPerformance(address _strategy) external view returns (uint256[] memory) {
        return apyHistory[_strategy];
    }

    /**
     * @dev Calculate moving average APY
     */
    function calculateMovingAverageAPY(address _strategy, uint256 _periods) external view returns (uint256) {
        uint256[] memory history = apyHistory[_strategy];
        if (history.length == 0) {
            return 0;
        }

        uint256 periods = _periods > history.length ? history.length : _periods;
        uint256 sum = 0;

        for (uint256 i = history.length - periods; i < history.length; i++) {
            sum += history[i];
        }

        return sum / periods;
    }

    /**
     * @dev Calculate Sharpe ratio for a strategy
     */
    function calculateSharpeRatio(address _strategy) external view returns (uint256) {
        StrategyInfo memory info = strategies[_strategy];
        if (!info.isActive || info.riskScore == 0) {
            return 0;
        }
        // Simplified Sharpe ratio: (return - risk-free rate) / volatility
        // Using APY as return and risk score as volatility proxy
        uint256 riskFreeRate = 200; // 2% risk-free rate
        if (info.lastAPY <= riskFreeRate) {
            return 0;
        }
        return ((info.lastAPY - riskFreeRate) * 100) / info.riskScore;
    }

    /**
     * @dev Pause a strategy
     */
    function pauseStrategy(address _strategy) external onlyOwner {
        require(strategies[_strategy].isActive, "Strategy not active");
        strategies[_strategy].isActive = false;
        emit StrategyUpdated(_strategy, strategies[_strategy].weight, strategies[_strategy].riskScore);
    }

    /**
     * @dev Emergency stop all strategies
     */
    function emergencyStop() external onlyOwner {
        for (uint256 i = 0; i < strategyList.length; i++) {
            if (strategies[strategyList[i]].isActive) {
                strategies[strategyList[i]].isActive = false;
                emit StrategyUpdated(
                    strategyList[i], strategies[strategyList[i]].weight, strategies[strategyList[i]].riskScore
                );
            }
        }
    }

    /**
     * @dev Get strategy allocation percentage
     */
    function getStrategyAllocation(address _strategy) external view returns (uint256) {
        if (!strategies[_strategy].isActive) {
            return 0;
        }

        uint256 totalWeight = 0;
        for (uint256 i = 0; i < strategyList.length; i++) {
            if (strategies[strategyList[i]].isActive) {
                totalWeight += strategies[strategyList[i]].weight;
            }
        }

        if (totalWeight == 0) {
            return 0;
        }

        return (strategies[_strategy].weight * BASIS_POINTS) / totalWeight;
    }

    /**
     * @dev Update strategy weight
     */
    function updateStrategyWeight(address _strategy, uint256 _newWeight) external onlyOwner {
        require(strategies[_strategy].isActive, "Strategy not active");
        require(_newWeight > 0, "Weight must be positive");

        uint256 oldWeight = strategies[_strategy].weight;
        strategies[_strategy].weight = _newWeight;

        emit StrategyUpdated(_strategy, _newWeight, strategies[_strategy].riskScore);
    }

    function setRebalanceThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold <= 2000, "Threshold too high"); // Max 20%
        rebalanceThreshold = _threshold;
    }

    // View functions
    function getActiveStrategiesCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < strategyList.length; i++) {
            if (strategies[strategyList[i]].isActive) {
                count++;
            }
        }
        return count;
    }

    function getStrategyAPYHistory(address _strategy) external view returns (uint256[] memory) {
        return apyHistory[_strategy];
    }
}
