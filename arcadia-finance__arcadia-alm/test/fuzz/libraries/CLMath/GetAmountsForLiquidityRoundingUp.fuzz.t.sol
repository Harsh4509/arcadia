/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FixedPoint96 } from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { LiquidityAmounts } from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import { CLMath } from "../../../../src/shared/libraries/math/CLMath.sol";
import { CLMath_Fuzz_Test } from "./_CLMath.fuzz.t.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getAmountsForLiquidityRoundingUp" of library "CLMath".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract GetAmountsForLiquidityRoundingUp_CLMath_Fuzz_Test is CLMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getAmountsForLiquidityRoundingUp_NoLiquidityForToken0(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public {
        // Given: An ascending range whose bounds multiply to under the manager's unit.
        sqrtPriceAX96 = uint160(bound(sqrtPriceAX96, TickMath.MIN_SQRT_PRICE, Constants.SQRT_Q96 - 1));
        sqrtPriceBX96 = uint160(bound(sqrtPriceBX96, sqrtPriceAX96 + 1, (FixedPoint96.Q96 - 1) / sqrtPriceAX96));

        // And: A price at or below the lower bound.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, sqrtPriceAX96));

        // When: Computing the amounts.
        // Then: It reverts.
        vm.expectRevert(CLMath.NoLiquidityForToken0.selector);
        clMath.getAmountsForLiquidityRoundingUp(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidity);
    }

    function testFuzz_Success_getAmountsForLiquidityRoundingUp_BelowRange(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public view {
        // Given: An ascending range token0 buys liquidity in.
        sqrtPriceAX96 = uint160(bound(sqrtPriceAX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 3));
        uint256 earning = FullMath.mulDivRoundingUp(FixedPoint96.Q96, 1, sqrtPriceAX96);
        sqrtPriceBX96 = uint160(
            bound(sqrtPriceBX96, earning > sqrtPriceAX96 + 2 ? earning : sqrtPriceAX96 + 2, TickMath.MAX_SQRT_PRICE - 1)
        );
        uint256 intermediate = FullMath.mulDiv(sqrtPriceAX96, sqrtPriceBX96, FixedPoint96.Q96);
        uint256 span = sqrtPriceBX96 - sqrtPriceAX96;
        liquidity = uint128(
            bound(
                liquidity,
                0,
                intermediate >= span ? type(uint128).max : FullMath.mulDiv(type(uint128).max, intermediate, span)
            )
        );

        // And: A price at or below the lower bound.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, sqrtPriceAX96));

        // When: Computing the amounts.
        (uint256 amount0, uint256 amount1) =
            clMath.getAmountsForLiquidityRoundingUp(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidity);

        // Then: The token0 amount is the least buying the liquidity back, and no token1.
        assertLeastAmounts(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidity, amount0, amount1);
    }

    function testFuzz_Success_getAmountsForLiquidityRoundingUp_InRange(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public view {
        // Given: An ascending range token0 buys liquidity in, with a price inside.
        sqrtPriceAX96 = uint160(bound(sqrtPriceAX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 3));
        uint256 earning = FullMath.mulDivRoundingUp(FixedPoint96.Q96, 1, sqrtPriceAX96);
        sqrtPriceBX96 = uint160(
            bound(sqrtPriceBX96, earning > sqrtPriceAX96 + 2 ? earning : sqrtPriceAX96 + 2, TickMath.MAX_SQRT_PRICE - 1)
        );
        uint256 intermediate = FullMath.mulDiv(sqrtPriceAX96, sqrtPriceBX96, FixedPoint96.Q96);
        uint256 span = sqrtPriceBX96 - sqrtPriceAX96;
        liquidity = uint128(
            bound(
                liquidity,
                0,
                intermediate >= span ? type(uint128).max : FullMath.mulDiv(type(uint128).max, intermediate, span)
            )
        );

        // And: A price strictly inside the range.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, sqrtPriceAX96 + 1, sqrtPriceBX96 - 1));

        // When: Computing the amounts.
        (uint256 amount0, uint256 amount1) =
            clMath.getAmountsForLiquidityRoundingUp(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidity);

        // Then: Each amount is the least buying the liquidity back on its side.
        assertLeastAmounts(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidity, amount0, amount1);
    }

    function testFuzz_Success_getAmountsForLiquidityRoundingUp_AboveRange(
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
            clMath.getAmountsForLiquidityRoundingUp(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidity);

        // Then: No token0, and the token1 amount is the least buying the liquidity back.
        assertLeastAmounts(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidity, amount0, amount1);
    }

    function testFuzz_Success_getAmountsForLiquidityRoundingUp_NeverBelowTheExactAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public view {
        // Given: An ascending range token0 buys liquidity in, and a price anywhere.
        sqrtPriceAX96 = uint160(bound(sqrtPriceAX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 3));
        uint256 earning = FullMath.mulDivRoundingUp(FixedPoint96.Q96, 1, sqrtPriceAX96);
        sqrtPriceBX96 = uint160(
            bound(sqrtPriceBX96, earning > sqrtPriceAX96 + 2 ? earning : sqrtPriceAX96 + 2, TickMath.MAX_SQRT_PRICE - 1)
        );
        uint256 intermediate = FullMath.mulDiv(sqrtPriceAX96, sqrtPriceBX96, FixedPoint96.Q96);
        uint256 span = sqrtPriceBX96 - sqrtPriceAX96;
        liquidity = uint128(
            bound(
                liquidity,
                0,
                intermediate >= span ? type(uint128).max : FullMath.mulDiv(type(uint128).max, intermediate, span)
            )
        );
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // When: Computing the amounts rounded up and the amounts the range holds.
        (uint256 amount0, uint256 amount1) =
            clMath.getAmountsForLiquidityRoundingUp(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidity);
        (uint256 exact0, uint256 exact1) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidity);

        // Then: The amounts cover the token0 the range holds.
        assertGe(amount0, exact0);

        // And: It covers the token1 the range holds.
        assertGe(amount1, exact1);
    }

    function testFuzz_Success_getAmountsForLiquidityRoundingUp_AtTheUpperBoundOfALowRange(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public view {
        // Given: An ascending range whose upper bound squared is under the unit.
        sqrtPriceAX96 = uint160(bound(sqrtPriceAX96, TickMath.MIN_SQRT_PRICE, Constants.SQRT_Q96 - 2));
        sqrtPriceBX96 = uint160(bound(sqrtPriceBX96, sqrtPriceAX96 + 1, Constants.SQRT_Q96 - 1));

        // When: Computing the amounts at a price on the upper bound.
        (uint256 amount0, uint256 amount1) =
            clMath.getAmountsForLiquidityRoundingUp(sqrtPriceBX96, sqrtPriceAX96, sqrtPriceBX96, liquidity);

        // Then: The range holds token1 alone, and no token0 math runs.
        assertEq(amount0, 0);
        assertEq(amount1, SqrtPriceMath.getAmount1Delta(sqrtPriceAX96, sqrtPriceBX96, liquidity, true));
    }
}
