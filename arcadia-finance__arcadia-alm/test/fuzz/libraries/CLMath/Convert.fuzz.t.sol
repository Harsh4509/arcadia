/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CLMath_Fuzz_Test } from "./_CLMath.fuzz.t.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "convert" of library "CLMath".
 */
// forge-lint: disable-next-item(unused-return)
contract Convert_CLMath_Fuzz_Test is CLMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_convert_PriceWithinUint128(uint256 sqrtPriceX96, bool zeroForOne, uint256 amount)
        public
        view
    {
        // Given: A price whose square fits uint256.
        sqrtPriceX96 = bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, type(uint128).max);

        // And: An amount within uint128.
        amount = bound(amount, 0, type(uint128).max);

        // When: Converting the amount.
        uint256 converted = clMath.convert(sqrtPriceX96, zeroForOne, amount, false);

        // Then: It is the amount at the squared price.
        uint256 priceX192 = sqrtPriceX96 * sqrtPriceX96;
        uint256 expected = zeroForOne
            ? FixedPointMathLib.fullMulDiv(amount, priceX192, 1 << 192)
            : FixedPointMathLib.fullMulDiv(amount, 1 << 192, priceX192);
        assertEq(converted, expected);
    }

    function testFuzz_Success_convert_PriceWithinUint128_RoundsUp(uint256 sqrtPriceX96, bool zeroForOne, uint256 amount)
        public
        view
    {
        // Given: A price whose square fits uint256.
        sqrtPriceX96 = bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, type(uint128).max);

        // And: An amount within uint128.
        amount = bound(amount, 0, type(uint128).max);

        // When: Converting the amount, rounding up.
        uint256 converted = clMath.convert(sqrtPriceX96, zeroForOne, amount, true);

        // Then: It is the amount at the squared price, rounded up.
        uint256 priceX192 = sqrtPriceX96 * sqrtPriceX96;
        uint256 expected = zeroForOne
            ? FixedPointMathLib.fullMulDivUp(amount, priceX192, 1 << 192)
            : FixedPointMathLib.fullMulDivUp(amount, 1 << 192, priceX192);
        assertEq(converted, expected);

        // And: The amount rounded down, or one above it.
        assertLe(converted - clMath.convert(sqrtPriceX96, zeroForOne, amount, false), 1);
    }

    function testFuzz_Success_convert_ExactAtTheUint128Edge(uint256 k) public view {
        // Given: The largest price whose square fits uint256.
        uint256 sqrtPriceX96 = type(uint128).max;

        // And: An amount where a two-step floor at that price can lose a unit.
        k = bound(k, (1 << 96) - (1 << 64) + 1, (1 << 96) - 1);
        uint256 amount = FixedPointMathLib.fullMulDivUp((k << 32) - 1, sqrtPriceX96, 1 << 96);

        // When: Converting token1 into token0.
        uint256 converted = clMath.convert(sqrtPriceX96, false, amount, false);

        // Then: It is the exact floor of amount * 2^192 / sqrtPriceX96^2.
        assertEq(converted, FixedPointMathLib.fullMulDiv(amount, 1 << 192, sqrtPriceX96 * sqrtPriceX96));
    }

    function testFuzz_Success_convert_PriceAboveUint128_ZeroForOne(uint256 sqrtPriceX96, uint256 amount) public view {
        // Given: A price whose square overflows uint256.
        sqrtPriceX96 = bound(sqrtPriceX96, uint256(type(uint128).max) + 1, type(uint160).max);

        // And: An amount within uint128.
        amount = bound(amount, 0, type(uint128).max);

        // When: Converting token0 into token1.
        uint256 converted = clMath.convert(sqrtPriceX96, true, amount, false);

        // Then: It is the amount at the squared price, taken in 128-bit precision.
        uint256 priceX128 = FixedPointMathLib.fullMulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64);
        assertEq(converted, FixedPointMathLib.fullMulDiv(amount, priceX128, 1 << 128));
    }

    function testFuzz_Success_convert_PriceAboveUint128_OneForZero(uint256 sqrtPriceX96, uint256 amount) public view {
        // Given: A price whose square overflows uint256.
        sqrtPriceX96 = bound(sqrtPriceX96, uint256(type(uint128).max) + 1, type(uint160).max);

        // And: An amount within uint128.
        amount = bound(amount, 0, type(uint128).max);

        // When: Converting token1 into token0.
        uint256 converted = clMath.convert(sqrtPriceX96, false, amount, false);

        // Then: It is the amount divided by the price twice, each step floored.
        assertEq(
            converted,
            FixedPointMathLib.fullMulDiv(
                FixedPointMathLib.fullMulDiv(amount, 1 << 96, sqrtPriceX96), 1 << 96, sqrtPriceX96
            )
        );
    }

    function testFuzz_Success_convert_PriceAboveUint128_ZeroForOne_RoundsUp(uint256 sqrtPriceX96, uint256 amount)
        public
        view
    {
        // Given: A price whose square overflows uint256.
        sqrtPriceX96 = bound(sqrtPriceX96, uint256(type(uint128).max) + 1, type(uint160).max);

        // And: An amount within uint128.
        amount = bound(amount, 0, type(uint128).max);

        // When: Converting token0 into token1, rounding up.
        uint256 converted = clMath.convert(sqrtPriceX96, true, amount, true);

        // Then: The amount at the squared price in 128 bits, each step rounded up.
        uint256 priceX128 = FixedPointMathLib.fullMulDivUp(sqrtPriceX96, sqrtPriceX96, 1 << 64);
        assertEq(converted, FixedPointMathLib.fullMulDivUp(amount, priceX128, 1 << 128));
    }

    function testFuzz_Success_convert_PriceAboveUint128_OneForZero_RoundsUp(uint256 sqrtPriceX96, uint256 amount)
        public
        view
    {
        // Given: A price whose square overflows uint256.
        sqrtPriceX96 = bound(sqrtPriceX96, uint256(type(uint128).max) + 1, type(uint160).max);

        // And: An amount within uint128.
        amount = bound(amount, 0, type(uint128).max);

        // When: Converting token1 into token0, rounding up.
        uint256 converted = clMath.convert(sqrtPriceX96, false, amount, true);

        // Then: It is the amount divided by the price twice, each step rounded up.
        assertEq(
            converted,
            FixedPointMathLib.fullMulDivUp(
                FixedPointMathLib.fullMulDivUp(amount, 1 << 96, sqrtPriceX96), 1 << 96, sqrtPriceX96
            )
        );
    }

    function testFuzz_Success_convert_PriceAboveUint128_OneForZeroFloorsOneBelow(uint256 multiple) public view {
        // Given: A sqrt price one above 2^128, and an amount worth a whole multiple.
        multiple = bound(multiple, 1, (1 << 63) - 1);
        uint256 sqrtPriceX96 = (1 << 128) + 1;
        uint256 amount = (multiple << 64) + 1;

        // When: Converting token1 into token0.
        uint256 converted = clMath.convert(sqrtPriceX96, false, amount, false);

        // Then: The two floors land one below the exact floor, which is the multiple.
        uint256 exact = FixedPointMathLib.fullMulDiv(amount, 1 << 192, sqrtPriceX96) / sqrtPriceX96;
        assertEq(exact, multiple);
        assertEq(converted, multiple - 1);
    }
}
