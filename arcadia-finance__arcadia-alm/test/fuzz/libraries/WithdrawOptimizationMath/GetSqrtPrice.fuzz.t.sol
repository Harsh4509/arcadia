/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../../utils/Constants.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { RedeemOptimizationMath_Fuzz_Test } from "../RedeemOptimizationMath/_RedeemOptimizationMath.fuzz.t.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { StepComputations, SwapState } from "../../../../src/vaults/types/SwapState.sol";

/**
 * @notice Fuzz tests for the function "getSqrtPrice" of library "WithdrawOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetSqrtPrice_WithdrawOptimizationMath_Fuzz_Test is RedeemOptimizationMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getSqrtPrice_PastTheStartAndAtMostTheTarget(
        SwapState memory state,
        StepComputations memory step,
        uint256 rangeCount,
        bool zeroForOne,
        uint256[4] memory amounts
    ) public view {
        // Given: n ranges, a step in the band, the pool, and the core's part W of it.
        Snapshot memory snapshot;
        snapshot.ranges = new PricedRange[](bound(rangeCount, 1, ConfigLib.MAX_RANGE_CAP));
        givenValidStep(state, step, zeroForOne);

        // And: Holdings B and A of 1 to 2^64 at 2^96, C up to B, a up to A.
        amounts[1] = bound(amounts[1], 1 << 96, Constants.MAX_SOLVER_HOLDINGS);
        amounts[2] = bound(amounts[2], 1 << 96, Constants.MAX_SOLVER_HOLDINGS);
        amounts[3] = bound(amounts[3], 0, amounts[1]);
        amounts[0] = bound(amounts[0], 0, amounts[2]);

        // When: Calculating the price where the cost starts to set the shares.
        uint160 sqrtPriceNew = withdrawMath.getSqrtPrice(
            snapshot, zeroForOne, amounts[0], amounts[1], amounts[2], state, step, amounts[3]
        );

        // Then: It is past the step's start and at most its target.
        if (zeroForOne) {
            assertLt(sqrtPriceNew, state.sqrtPriceX96);
            assertGe(sqrtPriceNew, step.sqrtPriceTargetX96);
        } else {
            assertGt(sqrtPriceNew, state.sqrtPriceX96);
            assertLe(sqrtPriceNew, step.sqrtPriceTargetX96);
        }
    }

    function testFuzz_Success_getSqrtPrice_TheFirstPricePastTheStartWithNothingLeftToPay(
        SwapState memory state,
        StepComputations memory step,
        uint256 rangeCount,
        bool zeroForOne,
        uint256 holdingsIn,
        uint256 holdingsOut,
        uint256 amountIn
    ) public view {
        // Given: n ranges, a step in the band, the pool, and the core's part W of it.
        Snapshot memory snapshot;
        snapshot.ranges = new PricedRange[](bound(rangeCount, 1, ConfigLib.MAX_RANGE_CAP));
        givenValidStep(state, step, zeroForOne);

        // And: Holdings B and A of 1 to 2^64 at 2^96, C up to B, nothing left to pay.
        holdingsIn = bound(holdingsIn, 1 << 96, Constants.MAX_SOLVER_HOLDINGS);
        holdingsOut = bound(holdingsOut, 1 << 96, Constants.MAX_SOLVER_HOLDINGS);
        amountIn = bound(amountIn, 0, holdingsIn);

        // When: Calculating the price where the cost starts to set the shares.
        uint160 sqrtPriceNew =
            withdrawMath.getSqrtPrice(snapshot, zeroForOne, 0, holdingsIn, holdingsOut, state, step, amountIn);

        // Then: The cost sets the shares from the start, at the first price past it.
        assertEq(sqrtPriceNew, zeroForOne ? state.sqrtPriceX96 - 1 : state.sqrtPriceX96 + 1);
    }
}
