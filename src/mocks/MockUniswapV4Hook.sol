// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IUniswapV4Hook.sol";

/**
 * @title MockUniswapV4Hook
 * @dev Mock implementation of Uniswap V4 Hook for testing
 */
contract MockUniswapV4Hook is IUniswapV4Hook {
    
    // Hook call tracking
    mapping(bytes4 => uint256) public hookCallCounts;
    mapping(bytes4 => bool) public hookEnabled;
    
    // Events for testing
    event HookCalled(bytes4 selector, address sender);
    event BeforeInitializeCalled(address sender, PoolKey key, uint160 sqrtPriceX96);
    event AfterInitializeCalled(address sender, PoolKey key, uint160 sqrtPriceX96, int24 tick);
    event BeforeAddLiquidityCalled(address sender, PoolKey key);
    event AfterAddLiquidityCalled(address sender, PoolKey key, BalanceDelta delta);
    event BeforeRemoveLiquidityCalled(address sender, PoolKey key);
    event AfterRemoveLiquidityCalled(address sender, PoolKey key, BalanceDelta delta);
    event BeforeSwapCalled(address sender, PoolKey key);
    event AfterSwapCalled(address sender, PoolKey key, BalanceDelta delta);
    event BeforeDonateCalled(address sender, PoolKey key, uint256 amount0, uint256 amount1);
    event AfterDonateCalled(address sender, PoolKey key, uint256 amount0, uint256 amount1);
    
    constructor() {
        // Enable all hooks by default
        hookEnabled[IUniswapV4Hook.beforeInitialize.selector] = true;
        hookEnabled[IUniswapV4Hook.afterInitialize.selector] = true;
        hookEnabled[IUniswapV4Hook.beforeAddLiquidity.selector] = true;
        hookEnabled[IUniswapV4Hook.afterAddLiquidity.selector] = true;
        hookEnabled[IUniswapV4Hook.beforeRemoveLiquidity.selector] = true;
        hookEnabled[IUniswapV4Hook.afterRemoveLiquidity.selector] = true;
        hookEnabled[IUniswapV4Hook.beforeSwap.selector] = true;
        hookEnabled[IUniswapV4Hook.afterSwap.selector] = true;
        hookEnabled[IUniswapV4Hook.beforeDonate.selector] = true;
        hookEnabled[IUniswapV4Hook.afterDonate.selector] = true;
    }
    
    /**
     * @dev Called before pool initialization
     */
    function beforeInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        bytes calldata hookData
    ) external override returns (bytes4) {
        if (!hookEnabled[this.beforeInitialize.selector]) {
            return bytes4(0);
        }
        
        hookCallCounts[this.beforeInitialize.selector]++;
        emit HookCalled(this.beforeInitialize.selector, sender);
        emit BeforeInitializeCalled(sender, key, sqrtPriceX96);
        
        return this.beforeInitialize.selector;
    }
    
    /**
     * @dev Called after pool initialization
     */
    function afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick,
        bytes calldata hookData
    ) external override returns (bytes4) {
        if (!hookEnabled[this.afterInitialize.selector]) {
            return bytes4(0);
        }
        
        hookCallCounts[this.afterInitialize.selector]++;
        emit HookCalled(this.afterInitialize.selector, sender);
        emit AfterInitializeCalled(sender, key, sqrtPriceX96, tick);
        
        return this.afterInitialize.selector;
    }
    
    /**
     * @dev Called before adding liquidity
     */
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        if (!hookEnabled[this.beforeAddLiquidity.selector]) {
            return bytes4(0);
        }
        
        hookCallCounts[this.beforeAddLiquidity.selector]++;
        emit HookCalled(this.beforeAddLiquidity.selector, sender);
        emit BeforeAddLiquidityCalled(sender, key);
        
        return this.beforeAddLiquidity.selector;
    }
    
    /**
     * @dev Called after adding liquidity
     */
    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta calldata delta,
        bytes calldata hookData
    ) external override returns (bytes4) {
        if (!hookEnabled[this.afterAddLiquidity.selector]) {
            return bytes4(0);
        }
        
        hookCallCounts[this.afterAddLiquidity.selector]++;
        emit HookCalled(this.afterAddLiquidity.selector, sender);
        emit AfterAddLiquidityCalled(sender, key, delta);
        
        return this.afterAddLiquidity.selector;
    }
    
    /**
     * @dev Called before removing liquidity
     */
    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        if (!hookEnabled[this.beforeRemoveLiquidity.selector]) {
            return bytes4(0);
        }
        
        hookCallCounts[this.beforeRemoveLiquidity.selector]++;
        emit HookCalled(this.beforeRemoveLiquidity.selector, sender);
        emit BeforeRemoveLiquidityCalled(sender, key);
        
        return this.beforeRemoveLiquidity.selector;
    }
    
    /**
     * @dev Called after removing liquidity
     */
    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta calldata delta,
        bytes calldata hookData
    ) external override returns (bytes4) {
        if (!hookEnabled[this.afterRemoveLiquidity.selector]) {
            return bytes4(0);
        }
        
        hookCallCounts[this.afterRemoveLiquidity.selector]++;
        emit HookCalled(this.afterRemoveLiquidity.selector, sender);
        emit AfterRemoveLiquidityCalled(sender, key, delta);
        
        return this.afterRemoveLiquidity.selector;
    }
    
    /**
     * @dev Called before swap
     */
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        if (!hookEnabled[this.beforeSwap.selector]) {
            return bytes4(0);
        }
        
        hookCallCounts[this.beforeSwap.selector]++;
        emit HookCalled(this.beforeSwap.selector, sender);
        emit BeforeSwapCalled(sender, key);
        
        return this.beforeSwap.selector;
    }
    
    /**
     * @dev Called after swap
     */
    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta calldata delta,
        bytes calldata hookData
    ) external override returns (bytes4) {
        if (!hookEnabled[this.afterSwap.selector]) {
            return bytes4(0);
        }
        
        hookCallCounts[this.afterSwap.selector]++;
        emit HookCalled(this.afterSwap.selector, sender);
        emit AfterSwapCalled(sender, key, delta);
        
        return this.afterSwap.selector;
    }
    
    /**
     * @dev Called before donate
     */
    function beforeDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external override returns (bytes4) {
        if (!hookEnabled[this.beforeDonate.selector]) {
            return bytes4(0);
        }
        
        hookCallCounts[this.beforeDonate.selector]++;
        emit HookCalled(this.beforeDonate.selector, sender);
        emit BeforeDonateCalled(sender, key, amount0, amount1);
        
        return this.beforeDonate.selector;
    }
    
    /**
     * @dev Called after donate
     */
    function afterDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external override returns (bytes4) {
        if (!hookEnabled[this.afterDonate.selector]) {
            return bytes4(0);
        }
        
        hookCallCounts[this.afterDonate.selector]++;
        emit HookCalled(this.afterDonate.selector, sender);
        emit AfterDonateCalled(sender, key, amount0, amount1);
        
        return this.afterDonate.selector;
    }
    
    // ============ TEST HELPERS ============
    
    /**
     * @dev Enable or disable a specific hook
     */
    function setHookEnabled(bytes4 selector, bool enabled) external {
        hookEnabled[selector] = enabled;
    }
    
    /**
     * @dev Get the number of times a hook was called
     */
    function getHookCallCount(bytes4 selector) external view returns (uint256) {
        return hookCallCounts[selector];
    }
    
    /**
     * @dev Reset hook call counts
     */
    function resetHookCallCounts() external {
        hookCallCounts[this.beforeInitialize.selector] = 0;
        hookCallCounts[this.afterInitialize.selector] = 0;
        hookCallCounts[this.beforeAddLiquidity.selector] = 0;
        hookCallCounts[this.afterAddLiquidity.selector] = 0;
        hookCallCounts[this.beforeRemoveLiquidity.selector] = 0;
        hookCallCounts[this.afterRemoveLiquidity.selector] = 0;
        hookCallCounts[this.beforeSwap.selector] = 0;
        hookCallCounts[this.afterSwap.selector] = 0;
        hookCallCounts[this.beforeDonate.selector] = 0;
        hookCallCounts[this.afterDonate.selector] = 0;
    }
    
    /**
     * @dev Check if a hook is enabled
     */
    function isHookEnabled(bytes4 selector) external view returns (bool) {
        return hookEnabled[selector];
    }
}
