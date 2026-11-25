/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { DepositOptimizationMath } from "../../../../src/vaults/libraries/math/DepositOptimizationMath.sol";
import { DepositOptimizationMath_Fuzz_Test } from "./_DepositOptimizationMath.fuzz.t.sol";
import { FixedPoint96 } from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";

/**
 * @notice Fuzz tests for the function "getNormalizedParameters" of library "DepositOptimizationMath".
 */
contract GetNormalizedParameters_DepositOptimizationMath_Fuzz_Test is DepositOptimizationMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override {
        DepositOptimizationMath_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getNormalizedParameters_EmptyPosition(DepositParams memory params, bool zeroForOne)
        public
        view
    {
        // Given: A deposit and a position on its segment.
        givenValidDepositParams(params, zeroForOne);

        // And: The position is empty, without a rounding margin.
        params.positionLiquidity = 0;
        params.positionAmount0 = 0;
        params.positionAmount1 = 0;
        params.roundingMargin = 0;

        // When: Calling getNormalizedParameters().
        (
            ,,
            uint256 positionLiquidityNormalized,
            uint256 positionAmountInNormalized,
            uint256 positionAmountOutNormalized,
            uint256 feeTerm
        ) = getNormalizedParameters(params);

        // Then: The position's terms are zero.
        assertEq(positionLiquidityNormalized, 0);
        assertEq(positionAmountInNormalized, 0);
        assertEq(positionAmountOutNormalized, 0);
        assertEq(feeTerm, 0);
    }

    function testFuzz_Revert_getNormalizedParameters_ZeroLiquidity(DepositParams memory params, bool zeroForOne)
        public
    {
        // Given: A deposit and a position on its segment.
        givenValidDepositParams(params, zeroForOne);

        // And: liquidity is zero.
        params.liquidity = 0;

        // When: Calling getNormalizedParameters().
        // Then: It should revert.
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        getNormalizedParameters(params);
    }

    function testFuzz_Revert_getNormalizedParameters_ZeroForOne_AmountInTooLarge(DepositParams memory params) public {
        // Given: A deposit of token0 and a position on its segment.
        givenValidDepositParams(params, true);

        // And: Normalized amount0 exceeds MAX_NORMALIZED, its scaled form fits 256 bits.
        uint256 denominator = uint256(params.sqrtPriceOld) << 96;
        params.balanceIn = bound(
            params.balanceIn,
            FullMath.mulDivRoundingUp(DepositOptimizationMath.MAX_NORMALIZED + 1, params.liquidity, denominator),
            FullMath.mulDiv(type(uint256).max, params.liquidity, denominator)
        );

        // When: Calling getNormalizedParameters().
        // Then: It should revert.
        vm.expectRevert(DepositOptimizationMath.AmountInTooLarge.selector);
        getNormalizedParameters(params);
    }

    function testFuzz_Revert_getNormalizedParameters_ZeroForOne_BothBalancesTooLarge(DepositParams memory params)
        public
    {
        // Given: A deposit of token0 and a position on its segment.
        givenValidDepositParams(params, true);

        // And: Both normalized balances past MAX_NORMALIZED, scaled in 256 bits.
        uint256 denominator = uint256(params.sqrtPriceOld) << 96;
        params.balanceIn = bound(
            params.balanceIn,
            FullMath.mulDivRoundingUp(DepositOptimizationMath.MAX_NORMALIZED + 1, params.liquidity, denominator),
            FullMath.mulDiv(type(uint256).max, params.liquidity, denominator)
        );
        params.balanceOut = bound(
            params.balanceOut,
            FullMath.mulDivRoundingUp(
                FullMath.mulDivRoundingUp(DepositOptimizationMath.MAX_NORMALIZED + 1, params.sqrtPriceOld, 1 << 160),
                params.liquidity,
                1 << 128
            ),
            FullMath.mulDiv(
                FullMath.mulDiv(type(uint256).max, params.sqrtPriceOld, 1 << 160), params.liquidity, 1 << 128
            )
        );

        // When: Calling getNormalizedParameters().
        // Then: It should revert.
        vm.expectRevert(DepositOptimizationMath.AmountInTooLarge.selector);
        getNormalizedParameters(params);
    }

    function testFuzz_Revert_getNormalizedParameters_OneForZero_AmountInTooLarge(DepositParams memory params) public {
        // Given: A deposit of token1 and a position on its segment.
        givenValidDepositParams(params, false);

        // And: Normalized amount1 exceeds MAX_NORMALIZED, its scaled form fits 256 bits.
        params.balanceIn = bound(
            params.balanceIn,
            FullMath.mulDivRoundingUp(
                FullMath.mulDivRoundingUp(DepositOptimizationMath.MAX_NORMALIZED + 1, params.sqrtPriceOld, 1 << 160),
                params.liquidity,
                1 << 128
            ),
            FullMath.mulDiv(
                FullMath.mulDiv(type(uint256).max, params.sqrtPriceOld, 1 << 160), params.liquidity, 1 << 128
            )
        );

        // When: Calling getNormalizedParameters().
        // Then: It should revert.
        vm.expectRevert(DepositOptimizationMath.AmountInTooLarge.selector);
        getNormalizedParameters(params);
    }

    function testFuzz_Success_getNormalizedParameters_Position(DepositParams memory params, bool zeroForOne)
        public
        view
    {
        // Given: A deposit and a position on its segment.
        givenValidDepositParams(params, zeroForOne);

        // When: Calling getNormalizedParameters().
        (
            ,,
            uint256 positionLiquidityNormalized,
            uint256 positionAmountInNormalized,
            uint256 positionAmountOutNormalized,
        ) = getNormalizedParameters(params);

        // Then: The parts are W, d0 * s0 and d1 / s0 in 64 fraction bits, vs the largest.
        // And: The position's tokenIn holds the rounding margin.
        params = withTheMargin(params);
        uint256 liquidity = params.positionLiquidity << 64;
        uint256 amount0 = FullMath.mulDiv(params.positionAmount0, params.sqrtPriceOld, 1 << 32);
        uint256 amount1 = FullMath.mulDiv(params.positionAmount1, 1 << 160, params.sqrtPriceOld);
        uint256 largest = FixedPointMathLib.max(liquidity, FixedPointMathLib.max(amount0, amount1));
        assertEq(positionLiquidityNormalized, FullMath.mulDiv(liquidity, 1 << 192, largest));
        assertEq(positionAmountInNormalized, FullMath.mulDiv(zeroForOne ? amount0 : amount1, 1 << 192, largest));
        assertEq(positionAmountOutNormalized, FullMath.mulDiv(zeroForOne ? amount1 : amount0, 1 << 192, largest));

        // And: The largest part is exactly one.
        assertEq(
            FixedPointMathLib.max(
                positionLiquidityNormalized,
                FixedPointMathLib.max(positionAmountInNormalized, positionAmountOutNormalized)
            ),
            1 << 192
        );
    }

    function testFuzz_Success_getNormalizedParameters_TheMarginAddsToThePositionsTokenIn(
        DepositParams memory params,
        bool zeroForOne
    ) public view {
        // Given: A deposit and a position on its segment.
        givenValidDepositParams(params, zeroForOne);

        // And: A rounding margin on the position's tokenIn, their sum within a uint128.
        params.roundingMargin = bound(
            params.roundingMargin, 0, type(uint128).max - (zeroForOne ? params.positionAmount0 : params.positionAmount1)
        );

        // When: Calling getNormalizedParameters() with the margin.
        bytes memory normalized;
        {
            (
                uint256 balanceInNormalized,
                uint256 balanceOutNormalized,
                uint256 positionLiquidityNormalized,
                uint256 positionAmountInNormalized,
                uint256 positionAmountOutNormalized,
                uint256 feeTerm
            ) = getNormalizedParameters(params);
            normalized = abi.encode(
                balanceInNormalized,
                balanceOutNormalized,
                positionLiquidityNormalized,
                positionAmountInNormalized,
                positionAmountOutNormalized,
                feeTerm
            );
        }

        // Then: The parameters are those of a position holding the margin more tokenIn.
        params = withTheMargin(params);
        {
            (
                uint256 balanceInNormalized,
                uint256 balanceOutNormalized,
                uint256 positionLiquidityNormalized,
                uint256 positionAmountInNormalized,
                uint256 positionAmountOutNormalized,
                uint256 feeTerm
            ) = getNormalizedParameters(params);
            assertEq(
                normalized,
                abi.encode(
                    balanceInNormalized,
                    balanceOutNormalized,
                    positionLiquidityNormalized,
                    positionAmountInNormalized,
                    positionAmountOutNormalized,
                    feeTerm
                )
            );
        }
    }

    function testFuzz_Success_getNormalizedParameters_ZeroForOne_AmountIn(DepositParams memory params) public view {
        // Given: A deposit of token0 and a position on its segment.
        givenValidDepositParams(params, true);

        // When: Calling getNormalizedParameters().
        (uint256 balanceInNormalized,,,,,) = getNormalizedParameters(params);

        // Then: balanceInNormalized is a * sqrtPriceOld * 2^96 / L, rounded down.
        assertEq(
            balanceInNormalized, FullMath.mulDiv(params.balanceIn, uint256(params.sqrtPriceOld) << 96, params.liquidity)
        );
    }

    function testFuzz_Success_getNormalizedParameters_ZeroForOne_AtTheMaximum(DepositParams memory params) public view {
        // Given: A token0 deposit at price one into liquidity 2^96, and a position on it.
        givenValidDepositParams(params, true);
        params.sqrtPriceOld = uint160(FixedPoint96.Q96);
        params.liquidity = uint128(FixedPoint96.Q96);
        params.positionLiquidity = bound(params.positionLiquidity, 0, FixedPoint96.Q96);

        // And: The amount whose normalized form a * s0 * 2^96 / L is exactly 2^252.
        params.balanceIn = 1 << 156;

        // When: Calling getNormalizedParameters().
        (uint256 balanceInNormalized,,,,,) = getNormalizedParameters(params);

        // Then: The bound itself is accepted.
        assertEq(balanceInNormalized, DepositOptimizationMath.MAX_NORMALIZED);
    }

    function testFuzz_Success_getNormalizedParameters_OneForZero_AmountIn(DepositParams memory params) public view {
        // Given: A deposit of token1 and a position on its segment.
        givenValidDepositParams(params, false);

        // When: Calling getNormalizedParameters().
        (uint256 balanceInNormalized,,,,,) = getNormalizedParameters(params);

        // Then: balanceInNormalized is the floored bound, within ⌈2^160/sqrtPriceOld⌉.
        uint256 quotient = FullMath.mulDiv(params.balanceIn, 1 << 128, params.liquidity);
        uint256 remainder = FullMath.mulDiv(
            mulmod(params.balanceIn, 1 << 128, params.liquidity), 1 << 160, params.liquidity
        ) + mulmod(quotient, 1 << 160, params.sqrtPriceOld);
        uint256 exact = FullMath.mulDiv(quotient, 1 << 160, params.sqrtPriceOld) + remainder / params.sqrtPriceOld;
        assertLe(balanceInNormalized, exact);
        assertLe(exact, balanceInNormalized + FixedPointMathLib.divUp(1 << 160, params.sqrtPriceOld));
    }

    function testFuzz_Revert_getNormalizedParameters_ZeroForOne_BalanceOutTooLarge(DepositParams memory params) public {
        // Given: A deposit of token0 and a position on its segment.
        givenValidDepositParams(params, true);

        // And: Normalized token1 balance exceeds MAX_NORMALIZED and fits 256 bits scaled.
        params.balanceOut = bound(
            params.balanceOut,
            FullMath.mulDivRoundingUp(
                FullMath.mulDivRoundingUp(DepositOptimizationMath.MAX_NORMALIZED + 1, params.sqrtPriceOld, 1 << 160),
                params.liquidity,
                1 << 128
            ),
            FullMath.mulDiv(
                FullMath.mulDiv(type(uint256).max, params.sqrtPriceOld, 1 << 160), params.liquidity, 1 << 128
            )
        );

        // When: Calling getNormalizedParameters().
        // Then: It should revert.
        vm.expectRevert(DepositOptimizationMath.AmountInTooLarge.selector);
        getNormalizedParameters(params);
    }

    function testFuzz_Revert_getNormalizedParameters_OneForZero_BalanceOutTooLarge(DepositParams memory params) public {
        // Given: A deposit of token1 and a position on its segment.
        givenValidDepositParams(params, false);

        // And: Normalized token0 balance exceeds MAX_NORMALIZED and fits 256 bits scaled.
        uint256 denominator = uint256(params.sqrtPriceOld) << 96;
        params.balanceOut = bound(
            params.balanceOut,
            FullMath.mulDivRoundingUp(DepositOptimizationMath.MAX_NORMALIZED + 1, params.liquidity, denominator),
            FullMath.mulDiv(type(uint256).max, params.liquidity, denominator)
        );

        // When: Calling getNormalizedParameters().
        // Then: It should revert.
        vm.expectRevert(DepositOptimizationMath.AmountInTooLarge.selector);
        getNormalizedParameters(params);
    }

    function testFuzz_Success_getNormalizedParameters_ZeroForOne_BalanceOut(DepositParams memory params) public view {
        // Given: A deposit of token0 and a position on its segment.
        givenValidDepositParams(params, true);

        // When: Calling getNormalizedParameters().
        (, uint256 balanceOutNormalized,,,,) = getNormalizedParameters(params);

        // Then: It is the floored bound, within ⌈2^160 / sqrtPriceOld⌉ below it.
        uint256 quotient = FullMath.mulDiv(params.balanceOut, 1 << 128, params.liquidity);
        uint256 remainder = FullMath.mulDiv(
            mulmod(params.balanceOut, 1 << 128, params.liquidity), 1 << 160, params.liquidity
        ) + mulmod(quotient, 1 << 160, params.sqrtPriceOld);
        uint256 exact = FullMath.mulDiv(quotient, 1 << 160, params.sqrtPriceOld) + remainder / params.sqrtPriceOld;
        assertLe(balanceOutNormalized, exact);
        assertLe(exact, balanceOutNormalized + FixedPointMathLib.divUp(1 << 160, params.sqrtPriceOld));
    }

    function testFuzz_Success_getNormalizedParameters_OneForZero_BalanceOut(DepositParams memory params) public view {
        // Given: A deposit of token1 and a position on its segment.
        givenValidDepositParams(params, false);

        // When: Calling getNormalizedParameters().
        (, uint256 balanceOutNormalized,,,,) = getNormalizedParameters(params);

        // Then: balanceOutNormalized is h * sqrtPriceOld * 2^96 / L, rounded down.
        assertEq(
            balanceOutNormalized,
            FullMath.mulDiv(params.balanceOut, uint256(params.sqrtPriceOld) << 96, params.liquidity)
        );
    }

    function testFuzz_Success_getNormalizedParameters_OneForZero_BalanceOutAtTheMaximum(DepositParams memory params)
        public
        view
    {
        // Given: A token1 deposit at price one into liquidity 2^96, and a position on it.
        givenValidDepositParams(params, false);
        params.sqrtPriceOld = uint160(FixedPoint96.Q96);
        params.liquidity = uint128(FixedPoint96.Q96);
        params.positionLiquidity = bound(params.positionLiquidity, 0, FixedPoint96.Q96);

        // And: A token0 balance whose normalized form h * s0 * 2^96 / L is exactly 2^252.
        params.balanceOut = 1 << 156;

        // When: Calling getNormalizedParameters().
        (, uint256 balanceOutNormalized,,,,) = getNormalizedParameters(params);

        // Then: The bound itself is accepted.
        assertEq(balanceOutNormalized, DepositOptimizationMath.MAX_NORMALIZED);
    }
}
