/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Fuzz_Test } from "../../Fuzz.t.sol";
import { StepComputations, SwapState } from "../../../../src/vaults/types/SwapState.sol";
import { SwapStateLibExtension } from "../../../utils/extensions/SwapStateLibExtension.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Common logic needed by all "SwapStateLib" fuzz tests.
 */
// forge-lint: disable-next-item(unsafe-typecast)
abstract contract SwapStateLib_Fuzz_Test is Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    SwapStateLibExtension internal swapStateLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();
        swapStateLib = new SwapStateLibExtension();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function givenValidStep(SwapState memory state, StepComputations memory step, bool zeroForOne, bool shortOfNext)
        internal
        pure
    {
        // And: A next tick in the curve, a target up to it, amounts in a uint128.
        step.tickNext = int24(bound(step.tickNext, TickMath.MIN_TICK + 1, TickMath.MAX_TICK - 1));
        step.sqrtPriceNextX96 = TickMath.getSqrtPriceAtTick(step.tickNext);
        uint160 gap = shortOfNext ? 1 : 0;
        state.sqrtPriceX96 = zeroForOne
            ? uint160(bound(state.sqrtPriceX96, step.sqrtPriceNextX96 + gap, TickMath.MAX_SQRT_PRICE - 1))
            : uint160(bound(state.sqrtPriceX96, TickMath.MIN_SQRT_PRICE + 1, step.sqrtPriceNextX96 - gap));
        step.sqrtPriceTargetX96 = zeroForOne
            ? uint160(bound(step.sqrtPriceTargetX96, step.sqrtPriceNextX96 + gap, state.sqrtPriceX96))
            : uint160(bound(step.sqrtPriceTargetX96, state.sqrtPriceX96, step.sqrtPriceNextX96 - gap));
        state.position.sqrtPriceBound = zeroForOne ? TickMath.MIN_SQRT_PRICE : TickMath.MAX_SQRT_PRICE;
        step.amountIn = bound(step.amountIn, 0, type(uint128).max);
        step.feeAmount = bound(step.feeAmount, 0, type(uint128).max);
        step.amountOut = bound(step.amountOut, 0, type(uint128).max);
        state.amountIn = bound(state.amountIn, 0, type(uint128).max);
        state.amountOut = bound(state.amountOut, 0, type(uint128).max);
    }
}
