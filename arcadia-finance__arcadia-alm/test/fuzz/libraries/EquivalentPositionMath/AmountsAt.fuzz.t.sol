/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { EquivalentPosition } from "../../../../src/vaults/types/EquivalentPosition.sol";
import { EquivalentPositionMath_Fuzz_Test } from "./_EquivalentPositionMath.fuzz.t.sol";
import { FixedPoint96 } from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "amountsAt" of library "EquivalentPositionMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract AmountsAt_EquivalentPositionMath_Fuzz_Test is EquivalentPositionMath_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(EquivalentPositionMath_Fuzz_Test) {
        EquivalentPositionMath_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_amountsAt_MatchesThePrincipalAtThePrice(
        uint160 sqrtPriceX96,
        bool zeroForOne,
        HoldingState memory state
    ) public {
        // Given: Any price, a buffer, and three ranges anywhere holding any liquidity.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        for (uint256 i; i < state.liquidities.length; ++i) {
            state.ticksLower[i] = int24(bound(state.ticksLower[i], TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
            state.ticksUpper[i] = int24(bound(state.ticksUpper[i], state.ticksLower[i] + 1, TickMath.MAX_TICK));
            pushRange(state.ticksLower[i], state.ticksUpper[i], state.liquidities[i]);
        }

        // And: The equivalent position built at the price.
        EquivalentPosition memory position =
            equivalentPositionMath.getPosition(sqrtPriceX96, zeroForOne, state.buffer0, state.buffer1);

        // When: Valuing the position at the price it was built at.
        (uint256 amountIn, uint256 amountOut) = equivalentPositionMath.amountsAt(position, sqrtPriceX96, zeroForOne);
        (uint256 amount0, uint256 amount1) = zeroForOne ? (amountIn, amountOut) : (amountOut, amountIn);

        // Then: Each token tops what the ranges and buffer hold by at most its rounding.
        assertHoldsTheRanges(state, sqrtPriceX96, sqrtPriceX96, amount0, amount1);
    }

    function testFuzz_Success_amountsAt_TracksThePrincipalAlongTheStep(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceEnd,
        bool zeroForOne,
        HoldingState memory state
    ) public {
        // Given: A price strictly inside one range, with a range below it and one above.
        sqrtPriceX96 = uint160(
            bound(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK + 2),
                TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK - 1) - 1
            )
        );
        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        state.ticksLower[0] = int24(bound(state.ticksLower[0], TickMath.MIN_TICK + 1, tick - 1));
        state.ticksUpper[0] = int24(bound(state.ticksUpper[0], tick + 1, TickMath.MAX_TICK - 1));
        state.ticksLower[1] = int24(bound(state.ticksLower[1], TickMath.MIN_TICK, state.ticksLower[0] - 1));
        state.ticksUpper[1] = int24(bound(state.ticksUpper[1], state.ticksLower[1] + 1, state.ticksLower[0]));
        state.ticksLower[2] = int24(bound(state.ticksLower[2], state.ticksUpper[0], TickMath.MAX_TICK - 1));
        state.ticksUpper[2] = int24(bound(state.ticksUpper[2], state.ticksLower[2] + 1, TickMath.MAX_TICK));
        for (uint256 i; i < state.liquidities.length; ++i) {
            pushRange(state.ticksLower[i], state.ticksUpper[i], state.liquidities[i]);
        }

        // And: A price the step ends at, in the first range, on the step's side.
        sqrtPriceEnd = zeroForOne
            ? uint160(bound(sqrtPriceEnd, TickMath.getSqrtPriceAtTick(state.ticksLower[0]), sqrtPriceX96))
            : uint160(bound(sqrtPriceEnd, sqrtPriceX96, TickMath.getSqrtPriceAtTick(state.ticksUpper[0])));

        // And: The equivalent position built at the price.
        EquivalentPosition memory position =
            equivalentPositionMath.getPosition(sqrtPriceX96, zeroForOne, state.buffer0, state.buffer1);

        // When: Valuing the position built at the price, at the price the step ends at.
        (uint256 amountIn, uint256 amountOut) = equivalentPositionMath.amountsAt(position, sqrtPriceEnd, zeroForOne);
        (uint256 amount0, uint256 amount1) = zeroForOne ? (amountIn, amountOut) : (amountOut, amountIn);

        // Then: Each token exceeds what is held there by the build's rounding at most.
        assertHoldsTheRanges(state, sqrtPriceX96, sqrtPriceEnd, amount0, amount1);
    }

    function testFuzz_Success_amountsAt_FloorsANegativeAmountAtZero(
        uint160 sqrtPriceX96,
        bool zeroForOne,
        uint128 liquidity,
        uint128 excess0,
        uint128 excess1
    ) public view {
        // Given: A position whose constants exceed its liquidity's amounts in both.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        int256 constant0 =
            int256(uint256(liquidity).fullMulDiv(FixedPoint96.Q96, sqrtPriceX96)) + int256(uint256(excess0)) + 1;
        int256 constant1 =
            int256(uint256(liquidity).fullMulDiv(sqrtPriceX96, FixedPoint96.Q96)) + int256(uint256(excess1)) + 1;

        EquivalentPosition memory position = EquivalentPosition({
            liquidity: liquidity,
            unstakedLiquidity: liquidity,
            constant0: constant0,
            constant1: constant1,
            sqrtPriceBound: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        // When: Valuing it at that price.
        (uint256 amountIn, uint256 amountOut) = equivalentPositionMath.amountsAt(position, sqrtPriceX96, zeroForOne);

        // Then: Both amounts are zero instead of negative.
        assertEq(amountIn, 0);
        assertEq(amountOut, 0);
    }
}
