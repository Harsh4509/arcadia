/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { MetadexSwapMath } from "../../../../src/shared/libraries/vendored/MetadexSwapMath.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { StepComputations, SwapState } from "../../../../src/vaults/types/SwapState.sol";
import { SwapStateLib_Fuzz_Test } from "./_SwapStateLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "computeSwapStep" of library "SwapStateLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract ComputeSwapStep_SwapStateLib_Fuzz_Test is SwapStateLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_computeSwapStep_AsThePoolsStepToItsTarget(
        SwapState memory state,
        StepComputations memory step,
        bool zeroForOne
    ) public view {
        // Given: A price, a target in the swap's direction, a liquidity and a fee.
        state.sqrtPriceX96 =
            uint160(bound(state.sqrtPriceX96, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE - 1));
        step.sqrtPriceTargetX96 = zeroForOne
            ? uint160(bound(step.sqrtPriceTargetX96, TickMath.MIN_SQRT_PRICE, state.sqrtPriceX96))
            : uint160(bound(step.sqrtPriceTargetX96, state.sqrtPriceX96, TickMath.MAX_SQRT_PRICE));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));

        // When: Calling computeSwapStep(), rounding as the pool does.
        step = swapStateLib.computeSwapStep(state, step, zeroForOne, true);

        // Then: It takes and pays what the pool's exact input step to the target does.
        (uint160 sqrtPriceNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) = MetadexSwapMath.computeSwapStep(
            state.sqrtPriceX96, step.sqrtPriceTargetX96, state.liquidity, type(int256).max, state.fee
        );
        assertEq(sqrtPriceNextX96, step.sqrtPriceTargetX96);
        assertEq(step.amountIn, amountIn);
        assertEq(step.amountOut, amountOut);
        assertEq(step.feeAmount, feeAmount);
    }

    function testFuzz_Success_computeSwapStep_RoundedDownAsThePoolMath(
        SwapState memory state,
        StepComputations memory step,
        bool zeroForOne
    ) public view {
        // Given: A price, a target in the swap's direction, a liquidity and a fee.
        state.sqrtPriceX96 =
            uint160(bound(state.sqrtPriceX96, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE - 1));
        step.sqrtPriceTargetX96 = zeroForOne
            ? uint160(bound(step.sqrtPriceTargetX96, TickMath.MIN_SQRT_PRICE, state.sqrtPriceX96))
            : uint160(bound(step.sqrtPriceTargetX96, state.sqrtPriceX96, TickMath.MAX_SQRT_PRICE));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));

        // When: Calling computeSwapStep(), rounding down.
        step = swapStateLib.computeSwapStep(state, step, zeroForOne, false);

        // Then: The input is the price move's amount, and the fee on it, rounded down.
        uint256 amountIn = zeroForOne
            ? SqrtPriceMath.getAmount0Delta(step.sqrtPriceTargetX96, state.sqrtPriceX96, state.liquidity, false)
            : SqrtPriceMath.getAmount1Delta(state.sqrtPriceX96, step.sqrtPriceTargetX96, state.liquidity, false);
        assertEq(step.amountIn, amountIn);
        assertEq(step.feeAmount, FullMath.mulDiv(amountIn, state.fee, 1e6 - state.fee));

        // And: The output is the price move's other amount rounded down.
        assertEq(
            step.amountOut,
            zeroForOne
                ? SqrtPriceMath.getAmount1Delta(step.sqrtPriceTargetX96, state.sqrtPriceX96, state.liquidity, false)
                : SqrtPriceMath.getAmount0Delta(state.sqrtPriceX96, step.sqrtPriceTargetX96, state.liquidity, false)
        );
    }
}
