/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { RedeemOptimizationMath_Fuzz_Test } from "../RedeemOptimizationMath/_RedeemOptimizationMath.fuzz.t.sol";
import { StepComputations, SwapState } from "../../../../src/vaults/types/SwapState.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getNextSqrtPrice" of library "WithdrawOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetNextSqrtPrice_WithdrawOptimizationMath_Fuzz_Test is RedeemOptimizationMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getNextSqrtPrice_TheTargetForAMoveReachingIt(
        SwapState memory state,
        StepComputations memory step,
        bool zeroForOne,
        uint256 sqrtPriceDelta
    ) public view {
        // Given: A price in the band, and a target on the move's side within the band.
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 1),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 1)
            )
        );
        step.sqrtPriceTargetX96 = zeroForOne
            ? uint160(
                bound(
                    step.sqrtPriceTargetX96, TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK), state.sqrtPriceX96 - 1
                )
            )
            : uint160(
                bound(
                    step.sqrtPriceTargetX96, state.sqrtPriceX96 + 1, TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
                )
            );

        // And: A relative move of at least |target - s0| / max(s0, target).
        uint256 reach = zeroForOne
            ? FullMath.mulDiv(state.sqrtPriceX96 - step.sqrtPriceTargetX96, 1 << 192, state.sqrtPriceX96)
            : FullMath.mulDiv(step.sqrtPriceTargetX96 - state.sqrtPriceX96, 1 << 192, step.sqrtPriceTargetX96);
        sqrtPriceDelta = bound(sqrtPriceDelta, reach, (1 << 192) - 1);

        // When: Moving the price.
        uint160 sqrtPriceNew = withdrawMath.getNextSqrtPrice(zeroForOne, state, step, sqrtPriceDelta);

        // Then: It stops at the target.
        assertEq(sqrtPriceNew, step.sqrtPriceTargetX96);
    }

    function testFuzz_Success_getNextSqrtPrice_ZeroForOne_TheMoveRoundedToNearest(
        SwapState memory state,
        StepComputations memory step,
        uint256 sqrtPriceDelta
    ) public view {
        // Given: A price in the band, and a target below it within the band.
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 1),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 1)
            )
        );
        step.sqrtPriceTargetX96 = uint160(
            bound(step.sqrtPriceTargetX96, TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK), state.sqrtPriceX96 - 1)
        );

        // And: A relative move short of the target's distance.
        uint256 reach = FullMath.mulDiv(state.sqrtPriceX96 - step.sqrtPriceTargetX96, 1 << 192, state.sqrtPriceX96);
        sqrtPriceDelta = bound(sqrtPriceDelta, 0, reach - 1);

        // When: Moving the price down.
        uint160 sqrtPriceNew = withdrawMath.getNextSqrtPrice(true, state, step, sqrtPriceDelta);

        // Then: s0 less s0 * delta / 2^192 to nearest, past s0, at most to the target.
        uint256 moved = state.sqrtPriceX96 - ((FullMath.mulDiv(state.sqrtPriceX96, sqrtPriceDelta, 1 << 191) + 1) >> 1);
        assertEq(
            sqrtPriceNew,
            FixedPointMathLib.min(FixedPointMathLib.max(moved, step.sqrtPriceTargetX96), state.sqrtPriceX96 - 1)
        );
    }

    function testFuzz_Success_getNextSqrtPrice_OneForZero_TheMoveRoundedToNearest(
        SwapState memory state,
        StepComputations memory step,
        uint256 sqrtPriceDelta
    ) public view {
        // Given: A price in the band, and a target above it within the band.
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 1),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 1)
            )
        );
        step.sqrtPriceTargetX96 = uint160(
            bound(step.sqrtPriceTargetX96, state.sqrtPriceX96 + 1, TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK))
        );

        // And: A relative move short of the target's distance.
        uint256 reach = FullMath.mulDiv(step.sqrtPriceTargetX96 - state.sqrtPriceX96, 1 << 192, step.sqrtPriceTargetX96);
        sqrtPriceDelta = bound(sqrtPriceDelta, 0, reach - 1);

        // When: Moving the price up.
        uint160 sqrtPriceNew = withdrawMath.getNextSqrtPrice(false, state, step, sqrtPriceDelta);

        // Then: s0 / (1 - delta / 2^192) to nearest, past s0, at most to the target.
        uint256 moved = (FullMath.mulDiv(state.sqrtPriceX96, 1 << 193, (1 << 192) - sqrtPriceDelta) + 1) >> 1;
        assertEq(
            sqrtPriceNew,
            FixedPointMathLib.max(FixedPointMathLib.min(moved, step.sqrtPriceTargetX96), state.sqrtPriceX96 + 1)
        );
    }

    function testFuzz_Success_getNextSqrtPrice_TheTargetForAMoveOfExactlyItsDistance(
        SwapState memory state,
        StepComputations memory step,
        bool zeroForOne
    ) public view {
        // Given: A price in the band, and a target on the move's side within the band.
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 1),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 1)
            )
        );
        step.sqrtPriceTargetX96 = zeroForOne
            ? uint160(
                bound(
                    step.sqrtPriceTargetX96, TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK), state.sqrtPriceX96 - 1
                )
            )
            : uint160(
                bound(
                    step.sqrtPriceTargetX96, state.sqrtPriceX96 + 1, TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
                )
            );

        // When: Moving the price by |target - s0| / max(s0, target).
        uint160 sqrtPriceNew = withdrawMath.getNextSqrtPrice(
            zeroForOne,
            state,
            step,
            zeroForOne
                ? FullMath.mulDiv(state.sqrtPriceX96 - step.sqrtPriceTargetX96, 1 << 192, state.sqrtPriceX96)
                : FullMath.mulDiv(step.sqrtPriceTargetX96 - state.sqrtPriceX96, 1 << 192, step.sqrtPriceTargetX96)
        );

        // Then: It stops at the target.
        assertEq(sqrtPriceNew, step.sqrtPriceTargetX96);
    }

    function testFuzz_Success_getNextSqrtPrice_TheTargetForAMoveOfOne(
        SwapState memory state,
        StepComputations memory step,
        bool zeroForOne
    ) public view {
        // Given: A price in the band, and a target on the move's side within the band.
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 1),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 1)
            )
        );
        step.sqrtPriceTargetX96 = zeroForOne
            ? uint160(
                bound(
                    step.sqrtPriceTargetX96, TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK), state.sqrtPriceX96 - 1
                )
            )
            : uint160(
                bound(
                    step.sqrtPriceTargetX96, state.sqrtPriceX96 + 1, TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
                )
            );

        // When: Moving the price by one, the root getRoot returns without a real root.
        uint160 sqrtPriceNew = withdrawMath.getNextSqrtPrice(zeroForOne, state, step, 1 << 192);

        // Then: It stops at the target.
        assertEq(sqrtPriceNew, step.sqrtPriceTargetX96);
    }

    function testFuzz_Success_getNextSqrtPrice_OneForZero_TheTargetAcrossTheBandForItsDistance(
        SwapState memory state,
        StepComputations memory step
    ) public view {
        // Given: A price at the band's lowest tick, and a target at its highest.
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 1),
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 2)
            )
        );
        step.sqrtPriceTargetX96 = uint160(
            bound(
                step.sqrtPriceTargetX96,
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 1),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );

        // When: Moving the price up by the target's distance, (target - s0) / target.
        uint160 sqrtPriceNew = withdrawMath.getNextSqrtPrice(
            false,
            state,
            step,
            FullMath.mulDiv(step.sqrtPriceTargetX96 - state.sqrtPriceX96, 1 << 192, step.sqrtPriceTargetX96)
        );

        // Then: It stops at the target.
        assertEq(sqrtPriceNew, step.sqrtPriceTargetX96);
    }
}
