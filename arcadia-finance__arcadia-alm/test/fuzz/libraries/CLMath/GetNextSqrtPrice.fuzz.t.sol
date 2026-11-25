/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CLMath_Fuzz_Test } from "./_CLMath.fuzz.t.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getNextSqrtPrice" of library "CLMath".
 */
contract GetNextSqrtPrice_CLMath_Fuzz_Test is CLMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getNextSqrtPrice_BetweenSpotAndTheBound(
        uint256 sqrtPriceOld,
        uint256 sqrtPriceBound,
        uint256 sqrtPriceDelta,
        bool zeroForOne
    ) public view {
        // Given: A price, and a bound in the move's direction.
        sqrtPriceOld = bound(sqrtPriceOld, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE);
        sqrtPriceBound = zeroForOne
            ? bound(sqrtPriceBound, TickMath.MIN_SQRT_PRICE, sqrtPriceOld)
            : bound(sqrtPriceBound, sqrtPriceOld, TickMath.MAX_SQRT_PRICE);

        // When: Moving the price by any relative amount.
        uint256 sqrtPriceNew = clMath.getNextSqrtPrice(zeroForOne, sqrtPriceOld, sqrtPriceBound, sqrtPriceDelta);

        // Then: It lies between the price and the bound.
        if (zeroForOne) {
            assertLe(sqrtPriceNew, sqrtPriceOld);
            assertGe(sqrtPriceNew, sqrtPriceBound);
        } else {
            assertGe(sqrtPriceNew, sqrtPriceOld);
            assertLe(sqrtPriceNew, sqrtPriceBound);
        }
    }

    function testFuzz_Success_getNextSqrtPrice_TheBoundForAMovePastIt(
        uint256 sqrtPriceOld,
        uint256 sqrtPriceBound,
        uint256 sqrtPriceDelta,
        bool zeroForOne
    ) public view {
        // Given: A price, and a bound in the move's direction.
        sqrtPriceOld = bound(sqrtPriceOld, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE);
        sqrtPriceBound = zeroForOne
            ? bound(sqrtPriceBound, TickMath.MIN_SQRT_PRICE, sqrtPriceOld)
            : bound(sqrtPriceBound, sqrtPriceOld, TickMath.MAX_SQRT_PRICE);

        // And: A relative move at least the one to the bound.
        sqrtPriceDelta = bound(
            sqrtPriceDelta,
            zeroForOne
                ? FixedPointMathLib.fullMulDivUp(sqrtPriceOld - sqrtPriceBound, 1 << 192, sqrtPriceOld)
                : FixedPointMathLib.fullMulDivUp(sqrtPriceBound - sqrtPriceOld, 1 << 192, sqrtPriceBound),
            type(uint256).max
        );

        // When: Moving the price.
        uint256 sqrtPriceNew = clMath.getNextSqrtPrice(zeroForOne, sqrtPriceOld, sqrtPriceBound, sqrtPriceDelta);

        // Then: It is the bound.
        assertEq(sqrtPriceNew, sqrtPriceBound);
    }

    function testFuzz_Success_getNextSqrtPrice_TheSamePriceWithoutAMove(
        uint256 sqrtPriceOld,
        uint256 sqrtPriceBound,
        bool zeroForOne
    ) public view {
        // Given: A price, and a bound in the move's direction.
        sqrtPriceOld = bound(sqrtPriceOld, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE);
        sqrtPriceBound = zeroForOne
            ? bound(sqrtPriceBound, TickMath.MIN_SQRT_PRICE, sqrtPriceOld)
            : bound(sqrtPriceBound, sqrtPriceOld, TickMath.MAX_SQRT_PRICE);

        // When: Moving the price by zero.
        uint256 sqrtPriceNew = clMath.getNextSqrtPrice(zeroForOne, sqrtPriceOld, sqrtPriceBound, 0);

        // Then: It is the price.
        assertEq(sqrtPriceNew, sqrtPriceOld);
    }

    function testFuzz_Success_getNextSqrtPrice_TheBoundForAMoveOfExactlyItsDistance(
        uint256 sqrtPriceOld,
        uint256 sqrtPriceBound,
        bool zeroForOne
    ) public view {
        // Given: A price, and a bound in the move's direction.
        sqrtPriceOld = bound(sqrtPriceOld, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE);
        sqrtPriceBound = zeroForOne
            ? bound(sqrtPriceBound, TickMath.MIN_SQRT_PRICE, sqrtPriceOld)
            : bound(sqrtPriceBound, sqrtPriceOld, TickMath.MAX_SQRT_PRICE);

        // When: Moving the price by the bound's distance, rounded down.
        uint256 sqrtPriceNew = clMath.getNextSqrtPrice(
            zeroForOne,
            sqrtPriceOld,
            sqrtPriceBound,
            zeroForOne
                ? FixedPointMathLib.fullMulDiv(sqrtPriceOld - sqrtPriceBound, 1 << 192, sqrtPriceOld)
                : FixedPointMathLib.fullMulDiv(sqrtPriceBound - sqrtPriceOld, 1 << 192, sqrtPriceBound)
        );

        // Then: It is the bound.
        assertEq(sqrtPriceNew, sqrtPriceBound);
    }

    function testFuzz_Success_getNextSqrtPrice_TheRelativeMoveShortOfTheBound(
        uint256 sqrtPriceOld,
        uint256 sqrtPriceBound,
        uint256 sqrtPriceDelta,
        bool zeroForOne
    ) public view {
        // Given: A price, and a bound in the move's direction, apart from it.
        sqrtPriceOld = bound(sqrtPriceOld, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE - 1);
        sqrtPriceBound = zeroForOne
            ? bound(sqrtPriceBound, TickMath.MIN_SQRT_PRICE, sqrtPriceOld - 1)
            : bound(sqrtPriceBound, sqrtPriceOld + 1, TickMath.MAX_SQRT_PRICE);

        // And: A relative move short of the bound's distance.
        sqrtPriceDelta = bound(
            sqrtPriceDelta,
            0,
            (zeroForOne
                        ? FixedPointMathLib.fullMulDiv(sqrtPriceOld - sqrtPriceBound, 1 << 192, sqrtPriceOld)
                        : FixedPointMathLib.fullMulDiv(sqrtPriceBound - sqrtPriceOld, 1 << 192, sqrtPriceBound)) - 1
        );

        // When: Moving the price.
        uint256 sqrtPriceNew = clMath.getNextSqrtPrice(zeroForOne, sqrtPriceOld, sqrtPriceBound, sqrtPriceDelta);

        // Then: Token0 sold lowers it by s0 * delta, token1 lifts it to s0 / (1 - delta).
        assertEq(
            sqrtPriceNew,
            zeroForOne
                ? sqrtPriceOld - FullMath.mulDiv(sqrtPriceOld, sqrtPriceDelta, 1 << 192)
                : FullMath.mulDiv(sqrtPriceOld, 1 << 192, (1 << 192) - sqrtPriceDelta)
        );
    }
}
