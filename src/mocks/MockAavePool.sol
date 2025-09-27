// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MockERC20.sol";
import "../interfaces/IAaveTypes.sol";

struct MockReserveData {
    uint256 configuration;
    uint128 liquidityIndex;
    uint128 currentLiquidityRate;
    uint128 variableBorrowIndex;
    uint128 currentVariableBorrowRate;
    uint128 currentStableBorrowRate;
    uint40 lastUpdateTimestamp;
    uint16 id;
    address aTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    address interestRateStrategyAddress;
    uint128 accruedToTreasury;
    uint128 unbacked;
    uint128 isolationModeTotalDebt;
}

/**
 * @title MockAavePool
 * @dev Mock implementation of Aave V3 Pool for testing
 */
contract MockAavePool {
    IERC20 public asset;
    mapping(address => uint256) public balances;
    mapping(address => address) public aTokens;
    uint256 public liquidityRate = 80000000000000000000000000; // ~8% APY in ray format

    event Supply(address indexed asset, uint256 amount, address indexed onBehalfOf, uint16 referralCode);
    event Withdraw(address indexed asset, uint256 amount, address indexed to);

    constructor(address _asset) {
        asset = IERC20(_asset);
    }

    /**
     * @dev Set aToken address for testing
     */
    function setAToken(address _asset, address _aToken) external {
        aTokens[_asset] = _aToken;
    }

    /**
     * @dev Supply assets to the pool
     */
    function supply(address _asset, uint256 _amount, address _onBehalfOf, uint16 _referralCode) external {
        require(_amount > 0, "Amount must be positive");

        // Transfer tokens from sender
        IERC20(_asset).transferFrom(msg.sender, address(this), _amount);

        // Track balance for the strategy (onBehalfOf)
        balances[_onBehalfOf] += _amount;

        // Also track in aToken balance if aToken exists
        if (aTokens[_asset] != address(0)) {
            // Mint aTokens to the strategy
            MockERC20(aTokens[_asset]).mint(_onBehalfOf, _amount);
        }

        emit Supply(_asset, _amount, _onBehalfOf, _referralCode);
    }

    /**
     * @dev Withdraw assets from the pool
     */
    function withdraw(address _asset, uint256 _amount, address _to) external returns (uint256) {
        require(_amount > 0, "Amount must be positive");
        require(balances[msg.sender] >= _amount, "Insufficient balance");
        require(!liquidityCrisis, "Insufficient liquidity");

        // Update balance
        balances[msg.sender] -= _amount;

        // Transfer tokens back
        IERC20(_asset).transfer(_to, _amount);

        emit Withdraw(_asset, _amount, _to);
        return _amount;
    }

    /**
     * @dev Get reserve data
     */
    function getReserveData(address _asset) external view returns (MockReserveData memory) {
        return MockReserveData({
            configuration: 0,
            liquidityIndex: 1e27, // 1 in ray format
            currentLiquidityRate: uint128(liquidityRate),
            variableBorrowIndex: 1e27,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate: 0,
            lastUpdateTimestamp: uint40(block.timestamp),
            id: 0,
            aTokenAddress: aTokens[_asset],
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(0),
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });
    }

    function getUserReserveData(address _asset, address /* user */)
        external
        view
        returns (
            uint256 currentATokenBalance,
            uint256 currentStableDebt,
            uint256 currentVariableDebt,
            uint256 principalStableDebt,
            uint256 scaledVariableDebt,
            uint256 stableBorrowRate,
            uint256 _liquidityRate,
            uint40 stableRateLastUpdated,
            bool usageAsCollateralEnabled
        )
    {
        return (0, 0, 0, 0, 0, 0, liquidityRate, 0, false);
    }

    // Test helper functions
    function setBalance(address account, uint256 amount) external {
        balances[account] = amount;
    }

    function setLiquidityRate(uint256 _liquidityRate) external {
        liquidityRate = _liquidityRate;
    }

    function addYield(address account, uint256 yieldAmount) external {
        balances[account] += yieldAmount;
    }

    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }

    // Additional test helper for crisis simulation
    bool public liquidityCrisis = false;

    function setLiquidityCrisis(bool _crisis) external {
        liquidityCrisis = _crisis;
    }
}
