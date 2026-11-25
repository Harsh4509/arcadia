/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { DepositOptimizationMath_Fuzz_Test } from "./_DepositOptimizationMath.fuzz.t.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "previewDeposit" of library "DepositOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract PreviewDeposit_DepositOptimizationMath_Fuzz_Test is DepositOptimizationMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_previewDeposit_OneForZero_TheBalanceMarginCoversTheStepsCeilings(
        MarginState memory state,
        RangeState memory range
    ) public {
        // Given: A pool of other liquidity, a spot in the band, a fee, a supply.
        state.sqrtPrice = uint160(
            bound(
                state.sqrtPrice,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + MARGIN_TICK_SPACING),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 2 * MARGIN_TICK_SPACING)
            )
        );
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));
        state.unstakedFee = uint24(bound(state.unstakedFee, 0, Constants.MAX_UNSTAKED_FEE));
        state.poolLiquidity = uint128(bound(state.poolLiquidity, Constants.MIN_FUZZED_LIQUIDITY, type(uint64).max));
        state.supply = bound(state.supply, 1, type(uint128).max);

        // And: A core holding token0 in an unstaked range above spot, and idle token1.
        int24 spaced = spacedTickBelow(TickMath.getTickAtSqrtPrice(state.sqrtPrice), MARGIN_TICK_SPACING);
        range.tickLower = int24(
                bound(range.tickLower, spaced + MARGIN_TICK_SPACING, Constants.BOUND_TICK - MARGIN_TICK_SPACING)
            ) / MARGIN_TICK_SPACING * MARGIN_TICK_SPACING;
        range.tickUpper = int24(bound(range.tickUpper, range.tickLower + MARGIN_TICK_SPACING, Constants.BOUND_TICK))
            / MARGIN_TICK_SPACING * MARGIN_TICK_SPACING;
        (range.liquidity, range.liquidityStaked) = (uint128(bound(range.liquidity, 1, type(uint64).max)), 0);
        (state.idle0, state.idle1) = (0, bound(state.idle1, 0, type(uint64).max));
        RangeState[] memory staged = new RangeState[](1);
        staged[0] = range;
        PricedRange[] memory ranges = pricedOf(staged);
        givenValidMarginDeposit(state, ranges);

        // When: Sizing the deposit's swap and its mint.
        (uint256 legIn, uint256 legOut, uint256 stranded, uint256 tolerance) = measure(state, ranges);

        // Then: The token1 kept covers the cost ratio of the token0 bought.
        assertGe(legIn, legOut);

        // And: The mint leaves at most the bound.
        assertLe(stranded, tolerance);
    }

    function testFuzz_Success_previewDeposit_OneForZero_ThePositionMarginCoversTheStepsCeilings(
        MarginState memory state,
        RangeState memory range,
        RangeState memory below,
        bool twoRanges
    ) public {
        // Given: A pool holding the core's liquidity alone, a fee and an unstaked fee.
        // And: A deposit, its step ending at the ceilings of the cost and fee share.
        PricedRange[] memory ranges = givenValidPositionMarginState(state, range, below, twoRanges);

        // When: Sizing the deposit's swap and its mint.
        (uint256 legIn, uint256 legOut, uint256 stranded, uint256 tolerance) = measure(state, ranges);

        // Then: The token1 kept covers the cost ratio of the token0 bought.
        assertGe(legIn, legOut);

        // And: The mint leaves at most the bound.
        assertLe(stranded, tolerance);
    }
}
