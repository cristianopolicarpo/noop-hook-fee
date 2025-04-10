// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

contract NoOpHookFee is BaseHook {
    using CurrencyLibrary for Currency;

    // Define fee in basis points (for example, 50 bp = 0.5%)
    uint256 public constant FEE_BP = 50;

    constructor(IPoolManager poolManager) BaseHook(poolManager) {}

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: true,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // beforeSwap: Charges fees on the input token for exact input swaps (when params.amountSpecified < 0)
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        // If amountSpecified is negative, we have an exact input swap.
        if (params.amountSpecified < 0) {
            // Calculate fee as a percentage of the absolute value of amountSpecified.
            // (-params.amountSpecified) converts the negative value to positive.
            int256 hookFee256 = (-params.amountSpecified * int256(FEE_BP)) /
                10000;
            // Fee amount converted for BeforeSwapDelta must be int128.
            int128 hookFee = int128(hookFee256);

            // Create the BeforeSwapDelta with fee for the input token.
            BeforeSwapDelta bsd = toBeforeSwapDelta(hookFee, 0);

            // For an exact input swap, the input token is:
            // If zeroForOne is true, input = token0; otherwise, input = token1.
            Currency token = params.zeroForOne ? key.currency0 : key.currency1;

            // Withdraw ("take") the fee from the pool.
            // Directly casting hookFee256 (guaranteed to be non-negative) to uint256.
            poolManager.take(token, address(this), uint256(hookFee256));

            return (this.beforeSwap.selector, bsd, 0);
        }
        // If not an exact input swap, no hook fee is charged at this stage.
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    // afterSwap: Charges fees on the input token for exact output swaps (when params.amountSpecified > 0)
    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4, int128) {
        // If amountSpecified is positive, we have an exact output swap.
        if (params.amountSpecified > 0) {
            // For exact output swaps, fee is charged on the input token.
            // Determine the input token delta:
            // If zeroForOne is true, input token is token0 (using delta.amount0()); otherwise, token1.
            int128 inputDelta = params.zeroForOne
                ? delta.amount0()
                : delta.amount1();

            // Since inputDelta should be negative (indicating funds leaving), take its absolute value.
            int256 hookFee256 = (-inputDelta * int256(FEE_BP)) / 10000;

            // Identify the input token.
            Currency token = params.zeroForOne ? key.currency0 : key.currency1;

            // Withdraw ("take") the fee from the pool, converting hookFee256 to uint256 directly.
            poolManager.take(token, address(this), uint256(hookFee256));

            return (this.afterSwap.selector, int128(hookFee256));
        }
        // If not an exact output swap, no hook fee is charged.
        return (this.afterSwap.selector, 0);
    }
}
