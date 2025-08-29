// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockAaveDataProvider
 * @dev Mock implementation of Aave Protocol Data Provider for testing
 */
contract MockAaveDataProvider {
    struct ReserveTokens {
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
    }
    
    mapping(address => ReserveTokens) private reserveTokens;
    mapping(address => uint256) private liquidityRates;
    
    /**
     * @dev Set reserve tokens for an asset
     */
    function setReserveTokens(
        address asset,
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress
    ) external {
        reserveTokens[asset] = ReserveTokens({
            aTokenAddress: aTokenAddress,
            stableDebtTokenAddress: stableDebtTokenAddress,
            variableDebtTokenAddress: variableDebtTokenAddress
        });
    }
    
    /**
     * @dev Set liquidity rate for an asset
     */
    function setLiquidityRate(address asset, uint256 liquidityRate) external {
        liquidityRates[asset] = liquidityRate;
    }
    
    /**
     * @dev Get reserve tokens addresses
     */
    function getReserveTokensAddresses(address asset) external view returns (
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress
    ) {
        ReserveTokens memory tokens = reserveTokens[asset];
        return (
            tokens.aTokenAddress,
            tokens.stableDebtTokenAddress,
            tokens.variableDebtTokenAddress
        );
    }
    
    /**
     * @dev Get reserve data
     */
    function getReserveData(address asset) external view returns (
        uint256 unbacked,
        uint256 accruedToTreasuryScaled,
        uint256 totalAToken,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 liquidityRate,
        uint256 variableBorrowRate,
        uint256 stableBorrowRate,
        uint256 averageStableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex,
        uint40 lastUpdateTimestamp
    ) {
        uint256 rate = liquidityRates[asset];
        uint256 rayUnit = 1e27;
        uint40 timestamp = uint40(block.timestamp);

        return (
            0, // unbacked
            0, // accruedToTreasuryScaled
            0, // totalAToken
            0, // totalStableDebt
            0, // totalVariableDebt
            rate, // liquidityRate
            0, // variableBorrowRate
            0, // stableBorrowRate
            0, // averageStableBorrowRate
            rayUnit, // liquidityIndex (ray format)
            rayUnit, // variableBorrowIndex (ray format)
            timestamp // lastUpdateTimestamp
        );
    }
    
    /**
     * @dev Get user reserve data
     */
    function getUserReserveData(address asset, address /* user */) external view returns (
        uint256 currentATokenBalance,
        uint256 currentStableDebt,
        uint256 currentVariableDebt,
        uint256 principalStableDebt,
        uint256 scaledVariableDebt,
        uint256 stableBorrowRate,
        uint256 liquidityRate,
        uint40 stableRateLastUpdated,
        bool usageAsCollateralEnabled
    ) {
        uint256 rate = liquidityRates[asset];
        // Mock implementation - return default values
        return (
            0, // currentATokenBalance
            0, // currentStableDebt
            0, // currentVariableDebt
            0, // principalStableDebt
            0, // scaledVariableDebt
            0, // stableBorrowRate
            rate, // liquidityRate
            uint40(block.timestamp), // stableRateLastUpdated
            true // usageAsCollateralEnabled
        );
    }
    
    /**
     * @dev Get all reserve tokens
     */
    function getAllReservesTokens() external pure returns (
        address[] memory,
        string[] memory
    ) {
        // Mock implementation - return empty arrays
        address[] memory addresses = new address[](0);
        string[] memory symbols = new string[](0);
        return (addresses, symbols);
    }
    
    /**
     * @dev Get all aTokens
     */
    function getAllATokens() external pure returns (
        address[] memory,
        string[] memory
    ) {
        // Mock implementation - return empty arrays
        address[] memory addresses = new address[](0);
        string[] memory symbols = new string[](0);
        return (addresses, symbols);
    }
}
