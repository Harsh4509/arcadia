/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { DepositOptimizationMath_Fuzz_Test } from "./_DepositOptimizationMath.fuzz.t.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";

/**
 * @notice Fuzz tests for the function "getBalanceIn" of library "DepositOptimizationMath".
 */
contract GetBalanceIn_DepositOptimizationMath_Fuzz_Test is DepositOptimizationMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getBalanceIn_UnboundedWithoutPositionTokenOut(
        uint256 amountIn,
        uint256 amountOut,
        uint256 positionAmountIn
    ) public view {
        // Given: A position holding no tokenOut.
        // When: Calculating the largest deposit.
        uint256 balanceIn = optimizationMath.getBalanceIn(amountIn, amountOut, positionAmountIn, 0);

        // Then: No deposit is too large.
        assertEq(balanceIn, type(uint256).max);
    }

    function testFuzz_Success_getBalanceIn_TheSwapsInputAndTheTokenInInThePositionsRatio(
        uint256 amountIn,
        uint256 amountOut,
        uint256 positionAmountIn,
        uint256 positionAmountOut
    ) public view {
        // Given: A position holding tokenOut, and the tokenIn in its ratio to the output.
        positionAmountOut = bound(positionAmountOut, 1, type(uint256).max);
        amountOut = bound(amountOut, 0, positionAmountOut);
        uint256 ratioIn = FullMath.mulDiv(amountOut, positionAmountIn, positionAmountOut);

        // And: A swap's input whose sum with it fits.
        amountIn = bound(amountIn, 0, type(uint256).max - ratioIn);

        // When: Calculating the largest deposit.
        uint256 balanceIn = optimizationMath.getBalanceIn(amountIn, amountOut, positionAmountIn, positionAmountOut);

        // Then: The swap's input and the tokenIn in the position's ratio, rounded down.
        assertEq(balanceIn, amountIn + ratioIn);
    }

    function testFuzz_Success_getBalanceIn_SaturatesPastAWord(
        uint256 amountIn,
        uint256 amountOut,
        uint256 positionAmountIn,
        uint256 positionAmountOut
    ) public view {
        // Given: A position holding tokenOut, and the tokenIn in its ratio to the output.
        positionAmountOut = bound(positionAmountOut, 1, type(uint256).max);
        amountOut = bound(amountOut, 1, positionAmountOut);
        positionAmountIn = bound(positionAmountIn, positionAmountOut, type(uint256).max);
        uint256 ratioIn = FullMath.mulDiv(amountOut, positionAmountIn, positionAmountOut);

        // And: A swap's input whose sum with it overflows.
        amountIn = bound(amountIn, type(uint256).max - ratioIn + 1, type(uint256).max);

        // When: Calculating the largest deposit.
        uint256 balanceIn = optimizationMath.getBalanceIn(amountIn, amountOut, positionAmountIn, positionAmountOut);

        // Then: It saturates.
        assertEq(balanceIn, type(uint256).max);
    }

    function testFuzz_Revert_getBalanceIn_TheRatioOverflows(
        uint256 amountIn,
        uint256 amountOut,
        uint256 positionAmountIn,
        uint256 positionAmountOut
    ) public {
        // Given: A swap's output at least twice the position's tokenOut.
        amountOut = bound(amountOut, 2, type(uint256).max);
        positionAmountOut = bound(positionAmountOut, 1, amountOut / 2);

        // And: A position tokenIn whose ratio times the output exceeds a word.
        positionAmountIn = bound(
            positionAmountIn, FullMath.mulDiv(type(uint256).max, positionAmountOut, amountOut) + 2, type(uint256).max
        );

        // When: Calculating the largest deposit.
        // Then: It reverts.
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        optimizationMath.getBalanceIn(amountIn, amountOut, positionAmountIn, positionAmountOut);
    }
}
