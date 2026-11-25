/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CLMath_Fuzz_Test } from "./_CLMath.fuzz.t.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getAmountsForLiquidity" of library "CLMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetAmountsForLiquidity_CLMath_Fuzz_Test is CLMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getAmountsForLiquidity_BelowRange(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public view {
        // Given: An ascending range.
        sqrtPriceAX96 = uint160(bound(sqrtPriceAX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 2));
        sqrtPriceBX96 = uint160(bound(sqrtPriceBX96, sqrtPriceAX96 + 1, TickMath.MAX_SQRT_PRICE - 1));

        // And: A price at or below the lower bound.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, sqrtPriceAX96));

        // When: Computing the amounts.
        (uint256 amount0, uint256 amount1) =
            clMath.getAmountsForLiquidity(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidity);

        // Then: The range holds token0 over its full width.
        assertEq(amount0, SqrtPriceMath.getAmount0Delta(sqrtPriceAX96, sqrtPriceBX96, liquidity, false));

        // And: It holds no token1.
        assertEq(amount1, 0);
    }

    function testFuzz_Success_getAmountsForLiquidity_InRange(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public view {
        // Given: An ascending range wide enough to hold a price strictly inside it.
        sqrtPriceAX96 = uint160(bound(sqrtPriceAX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 3));
        sqrtPriceBX96 = uint160(bound(sqrtPriceBX96, sqrtPriceAX96 + 2, TickMath.MAX_SQRT_PRICE - 1));

        // And: A price strictly inside the range.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, sqrtPriceAX96 + 1, sqrtPriceBX96 - 1));

        // When: Computing the amounts.
        (uint256 amount0, uint256 amount1) =
            clMath.getAmountsForLiquidity(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidity);

        // Then: token0 covers the upper half of the range.
        assertEq(amount0, SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtPriceBX96, liquidity, false));

        // And: token1 covers the lower half.
        assertEq(amount1, SqrtPriceMath.getAmount1Delta(sqrtPriceAX96, sqrtPriceX96, liquidity, false));
    }

    function testFuzz_Success_getAmountsForLiquidity_AboveRange(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public view {
        // Given: An ascending range.
        sqrtPriceAX96 = uint160(bound(sqrtPriceAX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 2));
        sqrtPriceBX96 = uint160(bound(sqrtPriceBX96, sqrtPriceAX96 + 1, TickMath.MAX_SQRT_PRICE - 1));

        // And: A price at or above the upper bound.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, sqrtPriceBX96, TickMath.MAX_SQRT_PRICE - 1));

        // When: Computing the amounts.
        (uint256 amount0, uint256 amount1) =
            clMath.getAmountsForLiquidity(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidity);

        // Then: The range holds no token0.
        assertEq(amount0, 0);

        // And: It holds token1 over its full width.
        assertEq(amount1, SqrtPriceMath.getAmount1Delta(sqrtPriceAX96, sqrtPriceBX96, liquidity, false));
    }

    function testFuzz_Success_getAmountsForLiquidity_ZeroWidth(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceABX96,
        uint128 liquidity
    ) public view {
        // Given: A price and a range whose two bounds coincide.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        sqrtPriceABX96 = uint160(bound(sqrtPriceABX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // When: Computing the amounts, rounding down.
        (uint256 amount0, uint256 amount1) =
            clMath.getAmountsForLiquidity(sqrtPriceX96, sqrtPriceABX96, sqrtPriceABX96, liquidity);

        // Then: The range holds no token0.
        assertEq(amount0, 0);

        // And: It holds no token1.
        assertEq(amount1, 0);
    }
}
