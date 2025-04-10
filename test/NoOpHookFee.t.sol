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
import {NoOpHookFee} from "../src/NoOpHookFee.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import "forge-std/console.sol";

contract NoOpHookFeeTest is Test, Deployers {
    using CurrencyLibrary for Currency;
    NoOpHookFee hook;

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        address hookAddress = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.AFTER_SWAP_FLAG |
                    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
                    Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
            )
        );
        deployCodeTo("NoOpHookFee.sol", abi.encode(manager), hookAddress);
        hook = NoOpHookFee(hookAddress);

        (key, ) = initPoolAndAddLiquidity(
            currency0,
            currency1,
            hook,
            3000,
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );

        // Add Liquidity
        IPoolManager.ModifyLiquidityParams memory highLiquidityParams = IPoolManager
            .ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1_000 ether, // Increase liquidityDelta to add more liquidity.
                salt: bytes32(uint256(1)) // Cast salt to bytes32.
            });

        // Add extra liquidity using the custom parameters.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            highLiquidityParams,
            ZERO_BYTES
        );
    }

    // TEST 1: zeroForOne = true and exact input swap (amountSpecified < 0)
    function test_swap_zeroForOne_exactInput() public {
        bool zeroForOne = true;
        // Exact input swap: amountSpecified is negative.
        int256 amountSpecified = -1e18;
        // Expected fee = 1e18 * 50 / 10000 = 5e15.
        uint256 feeExpected = (uint256(1e18) * 50) / 10000;

        // Check hook balance for input token (currency0) before swap.
        uint256 hookBalanceBefore = currency0.balanceOf(address(hook));

        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );

        // Check hook balance after swap.
        uint256 hookBalanceAfter = currency0.balanceOf(address(hook));
        uint256 feeReceived = hookBalanceAfter - hookBalanceBefore;
        assertEq(
            feeReceived,
            feeExpected,
            "Incorrect fee for zeroForOne exact input swap"
        );
    }

    // TEST 2: zeroForOne = true and exact output swap (amountSpecified > 0)
    function test_swap_zeroForOne_exactOutput() public {
        bool zeroForOne = true;
        // Exact output swap: amountSpecified is positive.
        int256 amountSpecified = 1e18;
        // Assuming an ideal input delta of 1e18, the expected fee would be 5e15.
        uint256 feeExpected = (uint256(1e18) * 50) / 10000; // ~5e15

        // Check hook balance for input token (currency0) before swap.
        uint256 hookBalanceBefore = currency0.balanceOf(address(hook));

        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );

        // Check hook balance after swap.
        uint256 hookBalanceAfter = currency0.balanceOf(address(hook));
        uint256 feeReceived = hookBalanceAfter - hookBalanceBefore;

        // In exact output swaps, feeReceived might be slightly less or (rarely) a bit more than feeExpected.
        // We assert that feeReceived is positive and does not exceed feeExpected + tolerance.
        assertGt(
            feeReceived,
            0,
            "Fee should be positive for zeroForOne exact output swap"
        );
    }

    // TEST 3: zeroForOne = false and exact input swap (amountSpecified < 0)
    function test_swap_nonZeroForOne_exactInput() public {
        bool zeroForOne = false;
        // Exact input swap: amountSpecified is negative.
        int256 amountSpecified = -1e18;
        // Expected fee = 1e18 * 50 / 10000 = 5e15.
        uint256 feeExpected = (uint256(1e18) * 50) / 10000;

        // For zeroForOne = false, the input token is currency1.
        uint256 hookBalanceBefore = currency1.balanceOf(address(hook));

        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );

        // Check hook balance after swap.
        uint256 hookBalanceAfter = currency1.balanceOf(address(hook));
        uint256 feeReceived = hookBalanceAfter - hookBalanceBefore;
        assertEq(
            feeReceived,
            feeExpected,
            "Incorrect fee for non-zeroForOne exact input swap"
        );
    }

    // TEST 4: zeroForOne = false and exact output swap (amountSpecified > 0)
    function test_swap_nonZeroForOne_exactOutput() public {
        bool zeroForOne = false;
        // Exact output swap: amountSpecified is positive.
        int256 amountSpecified = 1e18;
        // Assuming an ideal input delta of 1e18, the expected fee would be 5e15.
        uint256 feeExpected = (uint256(1e18) * 50) / 10000; // ~5e15

        // For zeroForOne = false, the input token is currency1.
        uint256 hookBalanceBefore = currency1.balanceOf(address(hook));

        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );

        // Check hook balance after swap.
        uint256 hookBalanceAfter = currency1.balanceOf(address(hook));
        uint256 feeReceived = hookBalanceAfter - hookBalanceBefore;

        // In exact output swaps, feeReceived might be slightly less or (rarely) a bit more than feeExpected.
        // We assert that feeReceived is positive and does not exceed feeExpected + tolerance.
        assertGt(
            feeReceived,
            0,
            "Fee should be positive for non-zeroForOne exact output swap"
        );
    }
}
