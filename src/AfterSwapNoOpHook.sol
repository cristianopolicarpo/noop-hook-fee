// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

contract AfterSwapNoOpHook is BaseHook {
    using CurrencyLibrary for Currency;
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
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: true,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        int128 hookDeltaUnspecified = params.zeroForOne
            ? delta.amount1()
            : delta.amount0();

        Currency currency = params.zeroForOne ? key.currency1 : key.currency0;

        // -------------------------------------------------------
        // IF YOU ARE MINTING CLAIM TOKENS IN THE HOOK
        // -------------------------------------------------------

        // poolManager.mint(
        //     address(this),
        //     currency.toId(),
        //     uint256(int256(hookDeltaUnspecified))
        // );

        // -------------------------------------------------------
        // IF YOU ARE TAKING ACTUAL TOKENS IN THE HOOK
        // -------------------------------------------------------
        poolManager.take(
            currency,
            address(this),
            uint256(int256(hookDeltaUnspecified))
        );

        return (this.afterSwap.selector, hookDeltaUnspecified);
    }
}
