// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title FeeOptimizer
 * @dev Library for optimizing fees in Uniswap V4 stablecoin pools
 */
library FeeOptimizer {
    using Math for uint256;

    // Fee constants (in hundredths of basis points)
    uint24 private constant MIN_FEE = 100; // 0.01%
    uint24 private constant MAX_FEE = 10000; // 1.00%
    uint24 private constant DEFAULT_FEE = 500; // 0.05%

    // Volatility thresholds
    uint256 private constant LOW_VOLATILITY = 10; // 0.1%
    uint256 private constant HIGH_VOLATILITY = 100; // 1.0%

    struct FeeConfig {
        uint24 baseFee; // Base fee rate
        uint24 volatilityMultiplier; // Multiplier for volatility adjustment
        uint256 volumeThreshold; // Volume threshold for fee reduction
        uint256 updateFrequency; // How often to update fees (in seconds)
        bool dynamicEnabled; // Whether dynamic fees are enabled
    }

    struct MarketConditions {
        uint256 volatility; // Price volatility (basis points)
        uint256 volume24h; // 24h trading volume
        uint256 spread; // Current bid-ask spread
        uint256 liquidity; // Total pool liquidity
        uint256 timestamp; // Last update timestamp
    }

    /**
     * @dev Calculate optimal fee based on market conditions
     * @param conditions Current market conditions
     * @param config Fee configuration
     * @return optimalFee Optimal fee rate
     */
    function calculateOptimalFee(MarketConditions memory conditions, FeeConfig memory config)
        internal
        pure
        returns (uint24 optimalFee)
    {
        if (!config.dynamicEnabled) {
            return config.baseFee;
        }

        uint24 adjustedFee = config.baseFee;

        // Volatility adjustment
        if (conditions.volatility > HIGH_VOLATILITY) {
            // High volatility: increase fees to compensate for IL risk
            adjustedFee = uint24((uint256(adjustedFee) * (100 + config.volatilityMultiplier)) / 100);
        } else if (conditions.volatility < LOW_VOLATILITY) {
            // Low volatility: reduce fees to attract more volume
            adjustedFee = uint24((uint256(adjustedFee) * (100 - config.volatilityMultiplier / 2)) / 100);
        }

        // Volume adjustment
        if (conditions.volume24h > config.volumeThreshold) {
            // High volume: can afford to reduce fees slightly
            adjustedFee = uint24((uint256(adjustedFee) * 95) / 100);
        }

        // Liquidity adjustment
        if (conditions.liquidity < 1000000e6) {
            // Less than 1M USDC
            // Low liquidity: increase fees to compensate LPs
            adjustedFee = uint24((uint256(adjustedFee) * 110) / 100);
        }

        // Spread adjustment
        if (conditions.spread > 50) {
            // > 0.5% spread
            // Wide spread: increase fees
            adjustedFee = uint24((uint256(adjustedFee) * 105) / 100);
        }

        // Ensure fee is within bounds
        if (adjustedFee < MIN_FEE) adjustedFee = MIN_FEE;
        if (adjustedFee > MAX_FEE) adjustedFee = MAX_FEE;

        return adjustedFee;
    }

    /**
     * @dev Calculate fee revenue for a given period
     * @param volume Trading volume
     * @param feeRate Fee rate (in hundredths of basis points)
     * @return feeRevenue Total fee revenue
     */
    function calculateFeeRevenue(uint256 volume, uint24 feeRate) internal pure returns (uint256 feeRevenue) {
        return (volume * feeRate) / 1000000; // Convert from hundredths of basis points
    }

    /**
     * @dev Estimate APY based on current conditions
     * @param conditions Market conditions
     * @param feeRate Current fee rate
     * @param liquidityShare LP's share of total liquidity (basis points)
     * @return estimatedAPY Estimated APY in basis points
     */
    function estimateAPY(MarketConditions memory conditions, uint24 feeRate, uint256 liquidityShare)
        internal
        pure
        returns (uint256 estimatedAPY)
    {
        // Calculate daily fee revenue
        uint256 dailyVolume = conditions.volume24h;
        uint256 dailyFees = calculateFeeRevenue(dailyVolume, feeRate);

        // Calculate LP's share of fees
        uint256 lpDailyFees = (dailyFees * liquidityShare) / 10000;

        // Annualize (365 days) and convert to APY basis points
        uint256 annualFees = lpDailyFees * 365;

        // Calculate APY as percentage of liquidity
        if (conditions.liquidity > 0) {
            estimatedAPY = (annualFees * 10000) / conditions.liquidity;
        }

        // Cap at reasonable maximum
        if (estimatedAPY > 10000) estimatedAPY = 10000; // 100% max
    }

    /**
     * @dev Get recommended fee configuration for stablecoins
     * @param pairType Type of stablecoin pair (0: major, 1: minor, 2: exotic)
     * @return config Recommended fee configuration
     */
    function getRecommendedFeeConfig(uint8 pairType) internal pure returns (FeeConfig memory config) {
        if (pairType == 0) {
            // Major pairs (USDC/USDT, DAI/USDC)
            config = FeeConfig({
                baseFee: 100, // 0.01%
                volatilityMultiplier: 50, // 50% adjustment
                volumeThreshold: 1000000e6, // 1M USDC
                updateFrequency: 3600, // 1 hour
                dynamicEnabled: true
            });
        } else if (pairType == 1) {
            // Minor pairs (FRAX/USDC, LUSD/DAI)
            config = FeeConfig({
                baseFee: 300, // 0.03%
                volatilityMultiplier: 75, // 75% adjustment
                volumeThreshold: 100000e6, // 100K USDC
                updateFrequency: 1800, // 30 minutes
                dynamicEnabled: true
            });
        } else {
            // Exotic pairs
            config = FeeConfig({
                baseFee: 500, // 0.05%
                volatilityMultiplier: 100, // 100% adjustment
                volumeThreshold: 10000e6, // 10K USDC
                updateFrequency: 900, // 15 minutes
                dynamicEnabled: true
            });
        }
    }

    /**
     * @dev Calculate impermanent loss for stablecoin pair
     * @param priceRatio Current price ratio (token1/token0)
     * @param initialRatio Initial price ratio
     * @return impermanentLoss IL in basis points
     */
    function calculateImpermanentLoss(uint256 priceRatio, uint256 initialRatio)
        internal
        pure
        returns (uint256 impermanentLoss)
    {
        if (priceRatio == initialRatio) {
            return 0;
        }

        // Simplified IL calculation for small price movements
        // IL ≈ (price_ratio - 1)² / 8 for small deviations
        uint256 deviation = priceRatio > initialRatio ? priceRatio - initialRatio : initialRatio - priceRatio;

        uint256 relativeDeviation = (deviation * 10000) / initialRatio;

        // IL = deviation² / 8 (in basis points)
        impermanentLoss = (relativeDeviation * relativeDeviation) / (8 * 10000);

        // Cap at reasonable maximum for stablecoins
        if (impermanentLoss > 100) impermanentLoss = 100; // 1% max
    }

    /**
     * @dev Check if fee update is needed
     * @param lastUpdate Last fee update timestamp
     * @param updateFrequency Update frequency in seconds
     * @param conditions Current market conditions
     * @param currentFee Current fee rate
     * @param config Fee configuration
     * @return needsUpdate Whether fee update is needed
     */
    function needsFeeUpdate(
        uint256 lastUpdate,
        uint256 updateFrequency,
        MarketConditions memory conditions,
        uint24 currentFee,
        FeeConfig memory config
    ) internal view returns (bool needsUpdate) {
        // Check time-based update
        if (block.timestamp >= lastUpdate + updateFrequency) {
            return true;
        }

        // Check condition-based update
        uint24 optimalFee = calculateOptimalFee(conditions, config);

        // Update if fee difference is significant (>10%)
        uint256 feeDifference = currentFee > optimalFee ? currentFee - optimalFee : optimalFee - currentFee;

        return (feeDifference * 100) / currentFee > 10;
    }

    /**
     * @dev Calculate gas-adjusted profit for fee update
     * @param feeIncrease Expected fee revenue increase
     * @param gasPrice Current gas price
     * @param gasUsed Gas used for fee update
     * @return profitable Whether update is profitable
     */
    function isUpdateProfitable(uint256 feeIncrease, uint256 gasPrice, uint256 gasUsed)
        internal
        pure
        returns (bool profitable)
    {
        uint256 gasCost = gasPrice * gasUsed;

        // Update is profitable if fee increase covers gas cost with 20% margin
        return feeIncrease > (gasCost * 120) / 100;
    }
}
