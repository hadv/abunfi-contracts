// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAbunfiStrategy
 * @dev Interface for yield-generating strategies
 */
interface IAbunfiStrategy {
    /**
     * @dev Deposit assets into the strategy
     * @param amount Amount to deposit
     */
    function deposit(uint256 amount) external;

    /**
     * @dev Withdraw specific amount from strategy
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external;

    /**
     * @dev Withdraw all assets from strategy
     */
    function withdrawAll() external;

    /**
     * @dev Harvest yield and compound
     * @return yield Amount of yield harvested
     */
    function harvest() external returns (uint256 yield);

    /**
     * @dev Get total assets managed by strategy
     * @return Total assets in strategy
     */
    function totalAssets() external view returns (uint256);

    /**
     * @dev Get the underlying asset address
     * @return Asset token address
     */
    function asset() external view returns (address);

    /**
     * @dev Get strategy name
     * @return Strategy name
     */
    function name() external view returns (string memory);

    /**
     * @dev Get current APY (Annual Percentage Yield)
     * @return APY in basis points (10000 = 100%)
     */
    function getAPY() external view returns (uint256);
}
