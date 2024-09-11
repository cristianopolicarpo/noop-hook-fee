// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {AfterSwapNoOpHook} from "../src/AfterSwapNoOpHook.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import "forge-std/console.sol";
contract AfterSwapNoOpHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;
    AfterSwapNoOpHook hook;

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        address hookAddress = address(
            uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG)
        );
        deployCodeTo("AfterSwapNoOpHook.sol", abi.encode(manager), hookAddress);
        hook = AfterSwapNoOpHook(hookAddress);

        (key, ) = initPoolAndAddLiquidity(
            currency0,
            currency1,
            hook,
            3000,
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );
    }

    function test_sanity() public {
        uint256 token0BalanceBefore = currency0.balanceOfSelf();
        uint256 token1BalanceBefore = currency1.balanceOfSelf();

        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );

        uint256 token0BalanceAfter = currency0.balanceOfSelf();
        uint256 token1BalanceAfter = currency1.balanceOfSelf();

        // Input token has been deducted
        assertEq(token0BalanceAfter, token0BalanceBefore - 0.001 ether);

        // Didn't get output tokens back to user
        assertEq(token1BalanceAfter, token1BalanceBefore);

        // -------------------------------------------------------
        // IF YOU ARE MINTING CLAIM TOKENS IN THE HOOK
        // -------------------------------------------------------

        // Hook should have received claim tokens for output token
        // uint256 token1ClaimTokenId = currency1.toId();
        // uint256 hookClaimTokenBalance = manager.balanceOf(
        //     address(hook),
        //     token1ClaimTokenId
        // );
        // assertGt(hookClaimTokenBalance, 0);

        // -------------------------------------------------------
        // IF YOU ARE TAKING ACTUAL TOKENS IN THE HOOK
        // -------------------------------------------------------

        // Hook should have received the output token
        uint256 hookToken1Balance = currency1.balanceOf(address(hook));
        console.log("Hook Token1 Balance: ", hookToken1Balance);
        assertGt(hookToken1Balance, 0);
    }
}
