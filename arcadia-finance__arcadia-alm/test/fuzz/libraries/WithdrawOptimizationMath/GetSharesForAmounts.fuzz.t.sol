/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { RedeemOptimizationMath_Fuzz_Test } from "../RedeemOptimizationMath/_RedeemOptimizationMath.fuzz.t.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { StepComputations, SwapState } from "../../../../src/vaults/types/SwapState.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getSharesForAmounts" of library "WithdrawOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetSharesForAmounts_WithdrawOptimizationMath_Fuzz_Test is RedeemOptimizationMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getSharesForAmounts_TheStepsCostAndOutputAndTheSharesPayingBoth(
        uint256 rangeCount,
        uint256 supply,
        SwapState memory state,
        StepComputations memory step,
        bool zeroForOne,
        uint256 amountOut,
        uint256 holdingsIn,
        uint256 holdingsOut,
        uint256 amountIn
    ) public view {
        // Given: n ranges, a supply, a price in the band, a target on the sale's side.
        Snapshot memory snapshot;
        snapshot.ranges = new PricedRange[](bound(rangeCount, 1, ConfigLib.MAX_RANGE_CAP));
        snapshot.supply = bound(supply, 1, Constants.MAX_FUZZED_AMOUNT);
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

        // And: The pool's liquidity and fee, the core's part W, and the sale so far.
        state.liquidity = uint128(bound(state.liquidity, 1, Constants.MAX_SOLVER_LIQUIDITY));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));
        state.position.liquidity = bound(state.position.liquidity, 0, state.liquidity);
        amountIn = bound(amountIn, 0, Constants.MAX_SOLVER_HOLDINGS);
        state.amountOut = bound(state.amountOut, 0, Constants.MAX_SOLVER_HOLDINGS);

        // And: The holdings B and A, and the amount with its rounding, each 160 bits.
        holdingsIn = bound(holdingsIn, 1, Constants.MAX_SOLVER_HOLDINGS);
        holdingsOut = bound(holdingsOut, 0, Constants.MAX_SOLVER_HOLDINGS);
        amountOut = bound(amountOut, 0, Constants.MAX_SOLVER_HOLDINGS);

        // When: Calculating the shares for the step.
        bytes memory result = abi.encodeCall(
            withdrawMath.getSharesForAmounts,
            (snapshot, zeroForOne, amountOut, holdingsIn, holdingsOut, state, step, amountIn)
        );
        (, result) = address(withdrawMath).staticcall(result);

        // Then: The step's cost at L + n with fee, rounded up, and its output at L, down.
        uint256 holdingsInDelta;
        uint256 holdingsOutDelta;
        {
            uint256 liquidityCost = (uint256(state.liquidity) + snapshot.ranges.length) * 1e6;
            if (zeroForOne) {
                step.amountIn = FullMath.mulDivRoundingUp(
                    liquidityCost, 1 << 192, uint256(step.sqrtPriceTargetX96) * (1e6 - uint256(state.fee))
                ) - FullMath.mulDiv(liquidityCost, 1 << 192, uint256(state.sqrtPriceX96) * (1e6 - uint256(state.fee)));
                step.amountOut = uint256(state.liquidity) * (state.sqrtPriceX96 - step.sqrtPriceTargetX96);
            } else {
                step.amountIn = FullMath.mulDivRoundingUp(
                    liquidityCost, step.sqrtPriceTargetX96 - state.sqrtPriceX96, 1e6 - uint256(state.fee)
                );
                step.amountOut = FixedPointMathLib.zeroFloorSub(
                    FullMath.mulDiv(state.liquidity, 1 << 192, state.sqrtPriceX96),
                    FullMath.mulDivRoundingUp(state.liquidity, 1 << 192, step.sqrtPriceTargetX96)
                );
            }

            // And: The core's part: its cost less 2 rounded down, its output plus 2 up.
            holdingsInDelta = FullMath.mulDiv(
                FixedPointMathLib.zeroFloorSub(step.amountIn, 2), state.position.liquidity * 1e6, liquidityCost
            );
            holdingsOutDelta = FullMath.mulDivRoundingUp(step.amountOut + 2, state.position.liquidity, state.liquidity);
        }

        // And: The cost binds when the output pays the rest or the funding shares do.
        amountIn += step.amountIn;
        amountOut = FixedPointMathLib.zeroFloorSub(amountOut, state.amountOut + step.amountOut);
        (holdingsIn, holdingsOut) =
        (holdingsIn + holdingsInDelta, FixedPointMathLib.zeroFloorSub(holdingsOut, holdingsOutDelta));
        bool binds = amountOut == 0 || holdingsOut > 0
            && (amountIn > holdingsIn || FullMath.mulDiv(amountIn, holdingsOut, holdingsIn) >= amountOut);

        // And: The shares fund the cost or pay the rest, none past the holdings.
        bytes memory expected = abi.encode(
            binds
                ? (amountIn > holdingsIn
                        ? type(uint256).max
                        : FullMath.mulDivRoundingUp(amountIn, snapshot.supply, holdingsIn))
                : (holdingsOut == 0 || amountOut > holdingsOut
                        ? type(uint256).max
                        : FullMath.mulDivRoundingUp(amountOut, snapshot.supply, holdingsOut)),
            binds,
            holdingsInDelta,
            holdingsOutDelta,
            step
        );
        assertEq(result, expected);
    }

    function testFuzz_Success_getSharesForAmounts_NoneWhenTheWholeTokenInLeavesTheRestUnpaid(
        uint256 rangeCount,
        uint256 supply,
        SwapState memory state,
        StepComputations memory step,
        uint256 holdingsIn,
        uint256 holdingsOut
    ) public view {
        // Given: n ranges, a supply, a price in the band, and a target below it.
        Snapshot memory snapshot;
        snapshot.ranges = new PricedRange[](bound(rangeCount, 1, ConfigLib.MAX_RANGE_CAP));
        snapshot.supply = bound(supply, 1, Constants.MAX_FUZZED_AMOUNT);
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

        // And: The pool's liquidity and fee, the core's part W, and the output so far.
        state.liquidity = uint128(bound(state.liquidity, 1, Constants.MAX_SOLVER_LIQUIDITY));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));
        state.position.liquidity = bound(state.position.liquidity, 0, state.liquidity);
        state.amountOut = bound(state.amountOut, 0, Constants.MAX_SOLVER_HOLDINGS);

        uint256 amountOut;
        {
            // And: The step's cost and output, and the core's part of both.
            uint256 liquidityCost = (uint256(state.liquidity) + snapshot.ranges.length) * 1e6;
            uint256 stepIn = FullMath.mulDivRoundingUp(
                liquidityCost, 1 << 192, uint256(step.sqrtPriceTargetX96) * (1e6 - uint256(state.fee))
            ) - FullMath.mulDiv(liquidityCost, 1 << 192, uint256(state.sqrtPriceX96) * (1e6 - uint256(state.fee)));
            uint256 stepOut = uint256(state.liquidity) * (state.sqrtPriceX96 - step.sqrtPriceTargetX96);
            uint256 holdingsInAfter = FullMath.mulDiv(
                FixedPointMathLib.zeroFloorSub(stepIn, 2), state.position.liquidity * 1e6, liquidityCost
            );
            uint256 holdingsOutDelta = FullMath.mulDivRoundingUp(stepOut + 2, state.position.liquidity, state.liquidity);

            // And: TokenIn holdings whose part the sale's cost takes in full.
            holdingsIn = bound(holdingsIn, stepIn + 1, stepIn + Constants.MAX_SOLVER_HOLDINGS);
            holdingsInAfter += holdingsIn;
            state.amountIn = holdingsInAfter - stepIn;

            // And: An amount whose rest is a wei more than the tokenOut holdings left.
            holdingsOut = bound(holdingsOut, holdingsOutDelta + 1, holdingsOutDelta + Constants.MAX_SOLVER_HOLDINGS);
            amountOut = state.amountOut + stepOut + (holdingsOut - holdingsOutDelta) + 1;
        }

        // When: Calculating the shares for the step.
        bytes memory result = abi.encodeCall(
            withdrawMath.getSharesForAmounts,
            (snapshot, true, amountOut, holdingsIn, holdingsOut, state, step, state.amountIn)
        );
        (, result) = address(withdrawMath).staticcall(result);
        (uint256 shares, bool costBinds) = abi.decode(result, (uint256, bool));

        // Then: The cost does not bind, and no shares pay the rest.
        assertEq(costBinds, false);
        assertEq(shares, type(uint256).max);
    }

    function testFuzz_Success_getSharesForAmounts_TheSupplyWhenTheWholeTokenInPaysTheRestExactly(
        uint256 rangeCount,
        uint256 supply,
        SwapState memory state,
        StepComputations memory step,
        uint256 holdingsIn,
        uint256 holdingsOut
    ) public view {
        // Given: n ranges, a supply, a price in the band, and a target below it.
        Snapshot memory snapshot;
        snapshot.ranges = new PricedRange[](bound(rangeCount, 1, ConfigLib.MAX_RANGE_CAP));
        snapshot.supply = bound(supply, 1, Constants.MAX_FUZZED_AMOUNT);
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

        // And: The pool's liquidity and fee, the core's part W, and the output so far.
        state.liquidity = uint128(bound(state.liquidity, 1, Constants.MAX_SOLVER_LIQUIDITY));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));
        state.position.liquidity = bound(state.position.liquidity, 0, state.liquidity);
        state.amountOut = bound(state.amountOut, 0, Constants.MAX_SOLVER_HOLDINGS);

        uint256 amountOut;
        {
            // And: The step's cost and output, and the core's part of both.
            uint256 liquidityCost = (uint256(state.liquidity) + snapshot.ranges.length) * 1e6;
            uint256 stepIn = FullMath.mulDivRoundingUp(
                liquidityCost, 1 << 192, uint256(step.sqrtPriceTargetX96) * (1e6 - uint256(state.fee))
            ) - FullMath.mulDiv(liquidityCost, 1 << 192, uint256(state.sqrtPriceX96) * (1e6 - uint256(state.fee)));
            uint256 stepOut = uint256(state.liquidity) * (state.sqrtPriceX96 - step.sqrtPriceTargetX96);
            uint256 holdingsInAfter = FullMath.mulDiv(
                FixedPointMathLib.zeroFloorSub(stepIn, 2), state.position.liquidity * 1e6, liquidityCost
            );
            uint256 holdingsOutDelta = FullMath.mulDivRoundingUp(stepOut + 2, state.position.liquidity, state.liquidity);

            // And: TokenIn holdings whose part the sale's cost takes in full.
            holdingsIn = bound(holdingsIn, stepIn + 1, stepIn + Constants.MAX_SOLVER_HOLDINGS);
            holdingsInAfter += holdingsIn;
            state.amountIn = holdingsInAfter - stepIn;

            // And: An amount whose rest is exactly the tokenOut holdings left.
            holdingsOut = bound(holdingsOut, holdingsOutDelta + 1, holdingsOutDelta + Constants.MAX_SOLVER_HOLDINGS);
            amountOut = state.amountOut + stepOut + (holdingsOut - holdingsOutDelta);
        }

        // When: Calculating the shares for the step.
        bytes memory result = abi.encodeCall(
            withdrawMath.getSharesForAmounts,
            (snapshot, true, amountOut, holdingsIn, holdingsOut, state, step, state.amountIn)
        );
        (, result) = address(withdrawMath).staticcall(result);
        (uint256 shares, bool costBinds) = abi.decode(result, (uint256, bool));

        // Then: The cost binds, at the whole supply.
        assertEq(costBinds, true);
        assertEq(shares, snapshot.supply);
    }

    function testFuzz_Success_getSharesForAmounts_TheSupplyWhenTheTokenOutIsTheRestExactly(
        uint256 rangeCount,
        uint256 supply,
        SwapState memory state,
        StepComputations memory step,
        uint256 holdingsIn,
        uint256 holdingsOut
    ) public view {
        // Given: n ranges, a supply, a price in the band, and a target below it.
        Snapshot memory snapshot;
        snapshot.ranges = new PricedRange[](bound(rangeCount, 1, ConfigLib.MAX_RANGE_CAP));
        snapshot.supply = bound(supply, 1, Constants.MAX_FUZZED_AMOUNT);
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

        // And: The pool's liquidity and fee, the core's part W, and the output so far.
        state.liquidity = uint128(bound(state.liquidity, 1, Constants.MAX_SOLVER_LIQUIDITY));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));
        state.position.liquidity = bound(state.position.liquidity, 0, state.liquidity);
        state.amountOut = bound(state.amountOut, 0, Constants.MAX_SOLVER_HOLDINGS);

        uint256 amountOut;
        {
            // And: The step's cost and output, and the core's part of both.
            uint256 liquidityCost = (uint256(state.liquidity) + snapshot.ranges.length) * 1e6;
            uint256 stepIn = FullMath.mulDivRoundingUp(
                liquidityCost, 1 << 192, uint256(step.sqrtPriceTargetX96) * (1e6 - uint256(state.fee))
            ) - FullMath.mulDiv(liquidityCost, 1 << 192, uint256(state.sqrtPriceX96) * (1e6 - uint256(state.fee)));
            uint256 stepOut = uint256(state.liquidity) * (state.sqrtPriceX96 - step.sqrtPriceTargetX96);
            uint256 holdingsInAfter = FullMath.mulDiv(
                FixedPointMathLib.zeroFloorSub(stepIn, 2), state.position.liquidity * 1e6, liquidityCost
            );
            uint256 holdingsOutDelta = FullMath.mulDivRoundingUp(stepOut + 2, state.position.liquidity, state.liquidity);

            // And: TokenIn holdings a wei above the sale's cost.
            holdingsIn = bound(holdingsIn, stepIn + 1, stepIn + Constants.MAX_SOLVER_HOLDINGS);
            holdingsInAfter += holdingsIn;
            state.amountIn = holdingsInAfter - stepIn - 1;

            // And: An amount whose rest is exactly the tokenOut holdings left.
            holdingsOut = bound(holdingsOut, holdingsOutDelta + 1, holdingsOutDelta + Constants.MAX_SOLVER_HOLDINGS);
            amountOut = state.amountOut + stepOut + (holdingsOut - holdingsOutDelta);
        }

        // When: Calculating the shares for the step.
        bytes memory result = abi.encodeCall(
            withdrawMath.getSharesForAmounts,
            (snapshot, true, amountOut, holdingsIn, holdingsOut, state, step, state.amountIn)
        );
        (, result) = address(withdrawMath).staticcall(result);
        (uint256 shares, bool costBinds) = abi.decode(result, (uint256, bool));

        // Then: The cost does not bind, and the whole supply pays the rest.
        assertEq(costBinds, false);
        assertEq(shares, snapshot.supply);
    }
}
