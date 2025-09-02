// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RiskProfileManager
 * @dev Manages user risk profiles and strategy allocation mappings
 */
contract RiskProfileManager is Ownable, ReentrancyGuard {
    
    // Risk levels
    enum RiskLevel { LOW, MEDIUM, HIGH }
    
    // Risk profile structure
    struct RiskProfile {
        RiskLevel level;
        uint256 lastUpdated;
        bool isActive;
    }
    
    // Strategy allocation for each risk level
    struct RiskAllocation {
        address[] strategies;
        uint256[] allocations; // Basis points (10000 = 100%)
        uint256 maxRiskScore; // Maximum risk score for strategies in this profile
        string description;
    }
    
    // State variables
    mapping(address => RiskProfile) public userRiskProfiles;
    mapping(RiskLevel => RiskAllocation) public riskAllocations;
    
    // Configuration
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public riskUpdateCooldown = 24 hours; // Prevent frequent risk changes
    
    // Events
    event RiskProfileUpdated(address indexed user, RiskLevel oldLevel, RiskLevel newLevel);
    event RiskAllocationUpdated(RiskLevel level, address[] strategies, uint256[] allocations);
    event RiskUpdateCooldownChanged(uint256 oldCooldown, uint256 newCooldown);
    
    constructor() Ownable(msg.sender) {
        _initializeDefaultAllocations();
    }
    
    /**
     * @dev Set user's risk profile
     * @param level Risk level to set
     */
    function setRiskProfile(RiskLevel level) external nonReentrant {
        address user = msg.sender;
        RiskProfile storage profile = userRiskProfiles[user];
        
        // Check cooldown period
        if (profile.isActive) {
            require(
                block.timestamp >= profile.lastUpdated + riskUpdateCooldown,
                "Risk update cooldown not met"
            );
        }
        
        RiskLevel oldLevel = profile.level;
        
        // Update profile
        profile.level = level;
        profile.lastUpdated = block.timestamp;
        profile.isActive = true;
        
        emit RiskProfileUpdated(user, oldLevel, level);
    }
    
    /**
     * @dev Get user's current risk profile
     * @param user User address
     * @return Risk profile
     */
    function getUserRiskProfile(address user) external view returns (RiskProfile memory) {
        return userRiskProfiles[user];
    }
    
    /**
     * @dev Get user's risk level (defaults to MEDIUM if not set)
     * @param user User address
     * @return Risk level
     */
    function getUserRiskLevel(address user) external view returns (RiskLevel) {
        if (!userRiskProfiles[user].isActive) {
            return RiskLevel.MEDIUM; // Default to medium risk
        }
        return userRiskProfiles[user].level;
    }
    
    /**
     * @dev Get allocation for a specific risk level
     * @param level Risk level
     * @return Risk allocation structure
     */
    function getRiskAllocation(RiskLevel level) external view returns (RiskAllocation memory) {
        return riskAllocations[level];
    }
    
    /**
     * @dev Get strategy allocations for user's risk level
     * @param user User address
     * @return strategies Array of strategy addresses
     * @return allocations Array of allocation percentages in basis points
     */
    function getUserAllocations(address user) external view returns (address[] memory strategies, uint256[] memory allocations) {
        RiskLevel level = this.getUserRiskLevel(user);
        RiskAllocation memory allocation = riskAllocations[level];
        return (allocation.strategies, allocation.allocations);
    }
    
    /**
     * @dev Check if user can update risk profile (cooldown check)
     * @param user User address
     * @return True if user can update
     */
    function canUpdateRiskProfile(address user) external view returns (bool) {
        RiskProfile memory profile = userRiskProfiles[user];
        if (!profile.isActive) {
            return true;
        }
        return block.timestamp >= profile.lastUpdated + riskUpdateCooldown;
    }
    
    // Admin functions
    
    /**
     * @dev Update risk allocation for a specific level
     * @param level Risk level to update
     * @param strategies Array of strategy addresses
     * @param allocations Array of allocation percentages in basis points
     * @param maxRiskScore Maximum risk score for strategies
     * @param description Description of the risk profile
     */
    function updateRiskAllocation(
        RiskLevel level,
        address[] calldata strategies,
        uint256[] calldata allocations,
        uint256 maxRiskScore,
        string calldata description
    ) external onlyOwner {
        require(strategies.length == allocations.length, "Arrays length mismatch");
        require(strategies.length > 0, "Empty strategies array");
        
        // Validate total allocation equals 100%
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            totalAllocation += allocations[i];
        }
        require(totalAllocation == BASIS_POINTS, "Total allocation must equal 100%");
        
        // Update allocation
        riskAllocations[level] = RiskAllocation({
            strategies: strategies,
            allocations: allocations,
            maxRiskScore: maxRiskScore,
            description: description
        });
        
        emit RiskAllocationUpdated(level, strategies, allocations);
    }
    
    /**
     * @dev Set risk profile on behalf of user (for vault integration)
     * @param user User address
     * @param level Risk level to set
     */
    function setRiskProfileForUser(address user, RiskLevel level) external {
        // Only allow trusted contracts (like vault) to set risk profiles
        // For now, we'll allow any caller but in production this should be restricted
        RiskProfile storage profile = userRiskProfiles[user];

        // Check cooldown period
        if (profile.isActive) {
            require(
                block.timestamp >= profile.lastUpdated + riskUpdateCooldown,
                "Risk update cooldown not met"
            );
        }

        RiskLevel oldLevel = profile.level;

        // Update profile
        profile.level = level;
        profile.lastUpdated = block.timestamp;
        profile.isActive = true;

        emit RiskProfileUpdated(user, oldLevel, level);
    }

    /**
     * @dev Update risk update cooldown period
     * @param newCooldown New cooldown period in seconds
     */
    function updateRiskUpdateCooldown(uint256 newCooldown) external onlyOwner {
        require(newCooldown <= 7 days, "Cooldown too long");
        uint256 oldCooldown = riskUpdateCooldown;
        riskUpdateCooldown = newCooldown;
        emit RiskUpdateCooldownChanged(oldCooldown, newCooldown);
    }
    
    /**
     * @dev Initialize default risk allocations
     */
    function _initializeDefaultAllocations() internal {
        // LOW RISK: Conservative allocation
        address[] memory lowRiskStrategies = new address[](0);
        uint256[] memory lowRiskAllocations = new uint256[](0);
        
        riskAllocations[RiskLevel.LOW] = RiskAllocation({
            strategies: lowRiskStrategies,
            allocations: lowRiskAllocations,
            maxRiskScore: 30,
            description: "Conservative: Focus on stable, low-risk yield strategies"
        });
        
        // MEDIUM RISK: Balanced allocation
        address[] memory mediumRiskStrategies = new address[](0);
        uint256[] memory mediumRiskAllocations = new uint256[](0);
        
        riskAllocations[RiskLevel.MEDIUM] = RiskAllocation({
            strategies: mediumRiskStrategies,
            allocations: mediumRiskAllocations,
            maxRiskScore: 60,
            description: "Balanced: Mix of stable and moderate yield strategies"
        });
        
        // HIGH RISK: Aggressive allocation
        address[] memory highRiskStrategies = new address[](0);
        uint256[] memory highRiskAllocations = new uint256[](0);
        
        riskAllocations[RiskLevel.HIGH] = RiskAllocation({
            strategies: highRiskStrategies,
            allocations: highRiskAllocations,
            maxRiskScore: 90,
            description: "Aggressive: Higher yield strategies with increased risk"
        });
    }
    
    /**
     * @dev Get risk level as string
     * @param level Risk level enum
     * @return String representation
     */
    function getRiskLevelString(RiskLevel level) external pure returns (string memory) {
        if (level == RiskLevel.LOW) return "LOW";
        if (level == RiskLevel.MEDIUM) return "MEDIUM";
        if (level == RiskLevel.HIGH) return "HIGH";
        return "UNKNOWN";
    }
}
