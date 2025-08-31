// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPoolManager.sol";

/**
 * @title MockUniswapV4PoolManager
 * @dev Mock implementation of Uniswap V4 Pool Manager for testing
 */
contract MockUniswapV4PoolManager is IPoolManager {
    
    struct PoolState {
        uint160 sqrtPriceX96;
        int24 tick;
        uint24 protocolFee;
        uint24 lpFee;
        uint128 liquidity;
        bool initialized;
    }
    
    mapping(bytes32 => PoolState) public pools;
    mapping(bytes32 => mapping(bytes32 => uint128)) public positions;
    mapping(address => uint256) public balances;
    
    uint160 private constant INITIAL_SQRT_PRICE = 79228162514264337593543950336; // sqrt(1) * 2^96
    
    event PoolInitialized(bytes32 indexed poolId, uint160 sqrtPriceX96, int24 tick);
    event LiquidityModified(bytes32 indexed poolId, address indexed owner, int256 liquidityDelta);
    event Swap(bytes32 indexed poolId, address indexed sender, int256 amount0, int256 amount1);
    
    /**
     * @dev Initialize a pool
     */
    function initialize(
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        bytes calldata hookData
    ) external override returns (int24 tick) {
        bytes32 poolId = _getPoolId(key);
        require(!pools[poolId].initialized, "Pool already initialized");
        
        if (sqrtPriceX96 == 0) {
            sqrtPriceX96 = INITIAL_SQRT_PRICE;
        }
        
        tick = _sqrtPriceToTick(sqrtPriceX96);
        
        pools[poolId] = PoolState({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            protocolFee: 0,
            lpFee: key.fee,
            liquidity: 0,
            initialized: true
        });
        
        emit PoolInitialized(poolId, sqrtPriceX96, tick);
        return tick;
    }
    
    /**
     * @dev Modify liquidity in a pool
     */
    function modifyLiquidity(
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external override returns (BalanceDelta memory callerDelta, BalanceDelta memory feesAccrued) {
        bytes32 poolId = _getPoolId(key);
        require(pools[poolId].initialized, "Pool not initialized");
        
        bytes32 positionKey = _getPositionKey(msg.sender, params.tickLower, params.tickUpper, params.salt);
        
        if (params.liquidityDelta > 0) {
            // Adding liquidity
            uint128 liquidityToAdd = uint128(uint256(params.liquidityDelta));
            positions[poolId][positionKey] += liquidityToAdd;
            pools[poolId].liquidity += liquidityToAdd;
            
            // Calculate token amounts (simplified for stablecoins)
            uint256 amount0 = uint256(liquidityToAdd) / 2;
            uint256 amount1 = uint256(liquidityToAdd) / 2;
            
            callerDelta = BalanceDelta({
                amount0: int128(uint128(amount0)),
                amount1: int128(uint128(amount1))
            });
            
        } else if (params.liquidityDelta < 0) {
            // Removing liquidity
            uint128 liquidityToRemove = uint128(uint256(-params.liquidityDelta));
            require(positions[poolId][positionKey] >= liquidityToRemove, "Insufficient liquidity");
            
            positions[poolId][positionKey] -= liquidityToRemove;
            pools[poolId].liquidity -= liquidityToRemove;
            
            // Calculate token amounts (simplified for stablecoins)
            uint256 amount0 = uint256(liquidityToRemove) / 2;
            uint256 amount1 = uint256(liquidityToRemove) / 2;
            
            callerDelta = BalanceDelta({
                amount0: -int128(uint128(amount0)),
                amount1: -int128(uint128(amount1))
            });
            
            // Simulate fees accrued (0.1% of removed liquidity)
            feesAccrued = BalanceDelta({
                amount0: int128(uint128(amount0 / 1000)),
                amount1: int128(uint128(amount1 / 1000))
            });
        }
        
        emit LiquidityModified(poolId, msg.sender, params.liquidityDelta);
    }
    
    /**
     * @dev Swap tokens in a pool
     */
    function swap(
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (BalanceDelta memory) {
        bytes32 poolId = _getPoolId(key);
        require(pools[poolId].initialized, "Pool not initialized");

        // Simplified swap calculation for stablecoins
        uint256 amountIn = uint256(params.amountSpecified > 0 ? params.amountSpecified : -params.amountSpecified);
        uint256 fee = (amountIn * pools[poolId].lpFee) / 1000000;
        uint256 amountOut = amountIn - fee;

        BalanceDelta memory delta;
        if (params.zeroForOne) {
            delta = BalanceDelta({
                amount0: int128(uint128(amountIn)),
                amount1: -int128(uint128(amountOut))
            });
        } else {
            delta = BalanceDelta({
                amount0: -int128(uint128(amountOut)),
                amount1: int128(uint128(amountIn))
            });
        }
        
        emit Swap(poolId, msg.sender, delta.amount0, delta.amount1);
        return delta;
    }
    
    /**
     * @dev Donate to a pool
     */
    function donate(
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external override returns (BalanceDelta memory) {
        bytes32 poolId = _getPoolId(key);
        require(pools[poolId].initialized, "Pool not initialized");
        
        return BalanceDelta({
            amount0: int128(uint128(amount0)),
            amount1: int128(uint128(amount1))
        });
    }
    
    /**
     * @dev Get pool slot0 data
     */
    function getSlot0(PoolKey calldata key)
        external
        view
        override
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee
        )
    {
        bytes32 poolId = _getPoolId(key);
        PoolState memory pool = pools[poolId];
        
        return (
            pool.sqrtPriceX96,
            pool.tick,
            pool.protocolFee,
            pool.lpFee
        );
    }
    
    /**
     * @dev Get pool liquidity
     */
    function getLiquidity(PoolKey calldata key) external view override returns (uint128) {
        bytes32 poolId = _getPoolId(key);
        return pools[poolId].liquidity;
    }
    
    /**
     * @dev Get position info
     */
    function getPosition(
        PoolKey calldata key,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) external view override returns (uint128 liquidity) {
        bytes32 poolId = _getPoolId(key);
        bytes32 positionKey = _getPositionKey(owner, tickLower, tickUpper, salt);
        return positions[poolId][positionKey];
    }
    
    /**
     * @dev Take tokens from the pool manager
     */
    function take(address currency, address to, uint256 amount) external override {
        // Simplified implementation
        balances[currency] -= amount;
    }
    
    /**
     * @dev Settle tokens to the pool manager
     */
    function settle(address currency) external override returns (uint256 paid) {
        // Simplified implementation
        return 0;
    }
    
    /**
     * @dev Clear tokens (for flash accounting)
     */
    function clear(address currency, uint256 amount) external override {
        // Simplified implementation
        balances[currency] = 0;
    }
    
    /**
     * @dev Sync reserves
     */
    function sync(address currency) external override {
        // Simplified implementation - no-op
    }
    
    // ============ INTERNAL FUNCTIONS ============
    
    function _getPoolId(PoolKey calldata key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks));
    }
    
    function _getPositionKey(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(owner, tickLower, tickUpper, salt));
    }
    
    function _sqrtPriceToTick(uint160 sqrtPriceX96) internal pure returns (int24) {
        // Simplified conversion for testing
        if (sqrtPriceX96 == INITIAL_SQRT_PRICE) {
            return 0;
        }
        // For other prices, return a reasonable tick value
        return int24(int256((uint256(sqrtPriceX96) - INITIAL_SQRT_PRICE) / 1e15));
    }
    
    // ============ TEST HELPERS ============
    
    function setPoolPrice(PoolKey calldata key, uint160 sqrtPriceX96) external {
        bytes32 poolId = _getPoolId(key);
        pools[poolId].sqrtPriceX96 = sqrtPriceX96;
        pools[poolId].tick = _sqrtPriceToTick(sqrtPriceX96);
    }
    
    function setPoolLiquidity(PoolKey calldata key, uint128 liquidity) external {
        bytes32 poolId = _getPoolId(key);
        pools[poolId].liquidity = liquidity;
    }
}
