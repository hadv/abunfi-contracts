// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPoolManager
 * @dev Interface for Uniswap V4 Pool Manager
 */
interface IPoolManager {
    /**
     * @dev Parameters for modifying liquidity
     */
    struct ModifyLiquidityParams {
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
        bytes32 salt;
    }

    /**
     * @dev Parameters for swapping
     */
    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    /**
     * @dev Initialize a pool
     */
    function initialize(
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        bytes calldata hookData
    ) external returns (int24 tick);

    /**
     * @dev Modify liquidity in a pool
     */
    function modifyLiquidity(
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external returns (BalanceDelta memory callerDelta, BalanceDelta memory feesAccrued);

    /**
     * @dev Swap tokens in a pool
     */
    function swap(
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external returns (BalanceDelta memory);

    /**
     * @dev Donate to a pool
     */
    function donate(
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external returns (BalanceDelta memory);

    /**
     * @dev Get pool slot0 data
     */
    function getSlot0(PoolKey calldata key)
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee
        );

    /**
     * @dev Get pool liquidity
     */
    function getLiquidity(PoolKey calldata key) external view returns (uint128);

    /**
     * @dev Get position info
     */
    function getPosition(
        PoolKey calldata key,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) external view returns (uint128 liquidity);

    /**
     * @dev Take tokens from the pool manager
     */
    function take(address currency, address to, uint256 amount) external;

    /**
     * @dev Settle tokens to the pool manager
     */
    function settle(address currency) external returns (uint256 paid);

    /**
     * @dev Clear tokens (for flash accounting)
     */
    function clear(address currency, uint256 amount) external;

    /**
     * @dev Sync reserves
     */
    function sync(address currency) external;
}

/**
 * @dev Pool key structure (imported from IUniswapV4Hook)
 */
struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

/**
 * @dev Balance delta structure (imported from IUniswapV4Hook)
 */
struct BalanceDelta {
    int128 amount0;
    int128 amount1;
}
