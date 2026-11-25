/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { DepositOptimizationMath } from "../../../src/vaults/libraries/math/DepositOptimizationMath.sol";
import { DepositOptimizationMathExtension } from "../../utils/extensions/DepositOptimizationMathExtension.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { SwapState } from "../../../src/vaults/types/SwapState.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Symbolic tests for the library "DepositOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract DepositOptimizationMath_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    DepositOptimizationMathExtension internal depositOptimizationMath;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public {
        depositOptimizationMath = new DepositOptimizationMathExtension();
    }

    /* //////////////////////////////////////////////////////////////
                              HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function stateOf(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint24 fee,
        uint256 feeShare,
        uint128 positionLiquidity,
        uint128 unstakedLiquidity,
        int256 constant0,
        int256 constant1
    ) internal pure returns (SwapState memory state) {
        (state.sqrtPriceX96, state.liquidity, state.fee, state.feeShare) = (sqrtPriceX96, liquidity, fee, feeShare);
        (state.position.liquidity, state.position.unstakedLiquidity) = (positionLiquidity, unstakedLiquidity);
        (state.position.constant0, state.position.constant1) = (constant0, constant1);
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function prove_getBalanceIn_IsAtLeastTheSwapsInput(
        uint256 amountIn,
        uint256 amountOut,
        uint256 positionAmountIn,
        uint256 positionAmountOut
    ) public pure {
        // Given: Any swap and any position.
        // When: Taking the deposit whose swap ends at the price.
        // Then: It is at least the swap's input.
        assertGe(
            DepositOptimizationMath.getBalanceIn(amountIn, amountOut, positionAmountIn, positionAmountOut), amountIn
        );
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getBalanceIn_IsMonotoneInTheSwapsOutput(
        uint256 amountIn,
        uint256 amountOutLow,
        uint256 amountOutHigh,
        uint256 positionAmountIn,
        uint256 positionAmountOut
    ) public pure {
        // Given: Any swap input, two ordered swap outputs and any position.
        vm.assume(amountOutLow <= amountOutHigh);

        // When: Taking the deposit whose swap ends at the price, for both outputs.
        // Then: The larger output gives at least the smaller one's deposit.
        assertLe(
            DepositOptimizationMath.getBalanceIn(amountIn, amountOutLow, positionAmountIn, positionAmountOut),
            DepositOptimizationMath.getBalanceIn(amountIn, amountOutHigh, positionAmountIn, positionAmountOut)
        );
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getBalanceIn_ABalancePastItHoldsMoreTokenInThanThePositionsRatio(
        uint256 balanceIn,
        uint256 amountIn,
        uint256 amountOut,
        uint256 positionAmountIn,
        uint256 positionAmountOut
    ) public pure {
        // Given: Swap and tokenOut position < 2^120 each, balance past deposit to price.
        vm.assume(balanceIn < 1 << 120 && amountIn < 1 << 120 && amountOut < 1 << 120);
        vm.assume(positionAmountIn < 1 << 120 && positionAmountOut != 0 && positionAmountOut < 1 << 120);
        vm.assume(
            balanceIn > DepositOptimizationMath.getBalanceIn(amountIn, amountOut, positionAmountIn, positionAmountOut)
        );

        // When: Swapping to the price.
        // Then: The tokenIn left over the tokenOut bought exceeds the position's ratio.
        assertGt((balanceIn - amountIn) * positionAmountOut, amountOut * positionAmountIn);
    }

    function prove_getBalanceIn_IsUnboundedWithoutPositionTokenOut(
        uint256 amountIn,
        uint256 amountOut,
        uint256 positionAmountIn
    ) public pure {
        // Given: Any swap and a position without tokenOut.
        // When: Taking the deposit whose swap ends at the price.
        // Then: It is unbounded.
        assertEq(DepositOptimizationMath.getBalanceIn(amountIn, amountOut, positionAmountIn, 0), type(uint256).max);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getNormalizedParameters_NormalizeTheLargestPartOfThePositionToOne(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint128 positionLiquidity,
        int256 constant0,
        int256 constant1,
        bool zeroForOne
    ) public pure {
        // Given: Price < 2^128 with liquidity, a position with constants within 2^254.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= type(uint128).max && liquidity != 0);
        vm.assume(constant0 > -(1 << 254) && constant0 < 1 << 254 && constant1 > -(1 << 254) && constant1 < 1 << 254);
        SwapState memory state = stateOf(sqrtPriceX96, liquidity, 0, 0, positionLiquidity, 0, constant0, constant1);

        // When: Normalizing the parameters without balances.
        (
            ,,
            uint256 positionLiquidityNormalized,
            uint256 positionAmountInNormalized,
            uint256 positionAmountOutNormalized,
        ) = DepositOptimizationMath.getNormalizedParameters(zeroForOne, state, 0, 0, 0);

        // Then: The largest part is one, or every part is zero for an empty position.
        uint256 largest = positionLiquidityNormalized;
        if (positionAmountInNormalized > largest) largest = positionAmountInNormalized;
        if (positionAmountOutNormalized > largest) largest = positionAmountOutNormalized;
        assertTrue(largest == 1 << 192 || largest == 0);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getQuadraticCoefficients_TheQuadraticCoefficientIsNonNegative(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint24 fee,
        uint256 feeShare,
        uint128 positionLiquidity,
        uint128 unstakedLiquidity,
        int256 constant0,
        int256 constant1,
        uint256 balanceIn,
        uint256 balanceOut,
        bool zeroForOne
    ) public pure {
        // Given: Price < 2^128, liquidity, fee < one, unstaked part keeps <= its fee.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= type(uint128).max && liquidity != 0);
        vm.assume(fee < 1e6 && feeShare <= 1e10 && positionLiquidity != 0 && unstakedLiquidity <= positionLiquidity);
        vm.assume(constant0 > -(1 << 254) && constant0 < 1 << 254 && constant1 > -(1 << 254) && constant1 < 1 << 254);
        vm.assume(balanceIn < 1 << 128 && balanceOut < 1 << 128);
        SwapState memory state = stateOf(
            sqrtPriceX96, liquidity, fee, feeShare, positionLiquidity, unstakedLiquidity, constant0, constant1
        );

        // When: Taking the quadratic's coefficients.
        (int256 quadraticCoefficient,,) =
            DepositOptimizationMath.getQuadraticCoefficients(zeroForOne, state, balanceIn, balanceOut, 0);

        // Then: The quadratic coefficient is non-negative.
        assertGe(quadraticCoefficient, 0);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getQuadraticCoefficients_TheLinearCoefficientIsAtLeastTheConstantCoefficient(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint24 fee,
        uint256 feeShare,
        uint128 positionLiquidity,
        uint128 unstakedLiquidity,
        int256 constant0,
        int256 constant1,
        uint256 balanceIn,
        uint256 balanceOut,
        bool zeroForOne
    ) public pure {
        // Given: Price < 2^128, liquidity, fee < one, unstaked part keeps <= its fee.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= type(uint128).max && liquidity != 0);
        vm.assume(fee < 1e6 && feeShare <= 1e10 && positionLiquidity != 0 && unstakedLiquidity <= positionLiquidity);
        vm.assume(constant0 > -(1 << 254) && constant0 < 1 << 254 && constant1 > -(1 << 254) && constant1 < 1 << 254);
        vm.assume(balanceIn < 1 << 128 && balanceOut < 1 << 128);
        SwapState memory state = stateOf(
            sqrtPriceX96, liquidity, fee, feeShare, positionLiquidity, unstakedLiquidity, constant0, constant1
        );

        // When: Taking the quadratic's coefficients.
        (, int256 linearCoefficient, int256 constantCoefficient) =
            DepositOptimizationMath.getQuadraticCoefficients(zeroForOne, state, balanceIn, balanceOut, 0);

        // Then: The linear coefficient is at least the constant one.
        assertGe(linearCoefficient, constantCoefficient);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getNormalizedParameters_RevertsIffABalanceExceedsTheMaxNormalized(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint256 balanceIn,
        uint256 balanceOut
    ) public view {
        // Given: A price <= one with liquidity, no position, token0 balances below 2^64.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= 1 << 96 && liquidity != 0);
        vm.assume(balanceIn < 1 << 64 && balanceOut < 1 << 64);
        SwapState memory state = stateOf(sqrtPriceX96, liquidity, 0, 0, 0, 0, 0, 0);
        uint256 balanceInNormalized = balanceIn * (uint256(sqrtPriceX96) << 96) / liquidity;
        uint256 balanceOutOverLiquidity = (balanceOut << 128) / liquidity;

        // And: A balance of token1 whose normalization fits a word.
        vm.assume(balanceOutOverLiquidity < uint256(sqrtPriceX96) << 96);
        bool fits = balanceInNormalized <= DepositOptimizationMath.MAX_NORMALIZED
            && balanceOutOverLiquidity <= uint256(sqrtPriceX96) << 92;

        // When: Normalizing the parameters of a swap of token0.
        (bool success, bytes memory result) = address(depositOptimizationMath)
            .staticcall(
                abi.encodeCall(
                    DepositOptimizationMathExtension.getNormalizedParameters,
                    (true, state, balanceIn, balanceOut, state.position, 0)
                )
            );

        // Then: Reverts exactly when a balance over pool liquidity exceeds the max.
        assertEq(success, fits);
        if (!success) assertEq(result, abi.encodeWithSelector(DepositOptimizationMath.AmountInTooLarge.selector));
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getSqrtPrice_StaysBetweenThePriceAndTheBound(
        SwapState memory state,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 roundingMargin,
        bool zeroForOne
    ) public view {
        // Given: The coefficients' domain, a uint128 margin, a bound past the price.
        vm.assume(state.sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && state.sqrtPriceX96 <= type(uint128).max);
        vm.assume(state.liquidity != 0 && state.fee < 1e6 && state.feeShare <= 1e10);
        vm.assume(state.position.liquidity != 0 && state.position.unstakedLiquidity <= state.position.liquidity);
        vm.assume(state.position.constant0 > -(1 << 254) && state.position.constant0 < 1 << 254);
        vm.assume(state.position.constant1 > -(1 << 254) && state.position.constant1 < 1 << 254);
        vm.assume(balanceIn < 1 << 128 && balanceOut < 1 << 128 && roundingMargin < 1 << 128);
        uint160 bound = state.position.sqrtPriceBound;
        vm.assume(bound >= TickMath.MIN_SQRT_PRICE && bound <= type(uint128).max);
        vm.assume(zeroForOne ? bound <= state.sqrtPriceX96 : bound >= state.sqrtPriceX96);

        // When: Solving for the price at which the balances match the position.
        (bool success, bytes memory result) = address(depositOptimizationMath)
            .staticcall(
                abi.encodeCall(
                    DepositOptimizationMathExtension.getSqrtPrice,
                    (zeroForOne, state, balanceIn, balanceOut, roundingMargin)
                )
            );

        // Then: When it returns, the price lies between the pool's price and the bound.
        vm.assume(success);
        uint160 sqrtPriceNew = abi.decode(result, (uint160));
        if (zeroForOne) {
            assertGe(sqrtPriceNew, bound);
            assertLe(sqrtPriceNew, state.sqrtPriceX96);
        } else {
            assertGe(sqrtPriceNew, state.sqrtPriceX96);
            assertLe(sqrtPriceNew, bound);
        }
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getAmountOut_StaysWithinThePoolsMoveToTheBound(
        SwapState memory state,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 roundingMargin,
        bool zeroForOne
    ) public view {
        // Given: The coefficients' domain, a uint128 margin, a bound past the price.
        vm.assume(state.sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && state.sqrtPriceX96 <= type(uint128).max);
        vm.assume(state.liquidity != 0 && state.fee < 1e6 && state.feeShare <= 1e10);
        vm.assume(state.position.liquidity != 0 && state.position.unstakedLiquidity <= state.position.liquidity);
        vm.assume(state.position.constant0 > -(1 << 254) && state.position.constant0 < 1 << 254);
        vm.assume(state.position.constant1 > -(1 << 254) && state.position.constant1 < 1 << 254);
        vm.assume(balanceIn < 1 << 128 && balanceOut < 1 << 128 && roundingMargin < 1 << 128);
        uint160 bound = state.position.sqrtPriceBound;
        vm.assume(bound >= TickMath.MIN_SQRT_PRICE && bound <= type(uint128).max);
        vm.assume(zeroForOne ? bound <= state.sqrtPriceX96 : bound >= state.sqrtPriceX96);

        // When: Taking the swap's output.
        (bool success, bytes memory result) = address(depositOptimizationMath)
            .staticcall(
                abi.encodeCall(
                    DepositOptimizationMathExtension.getAmountOut,
                    (zeroForOne, state, balanceIn, balanceOut, roundingMargin)
                )
            );

        // Then: The price ends at most at the bound, and the output within the pool's.
        vm.assume(success);
        (uint160 sqrtPriceNew, uint256 amountOut) = abi.decode(result, (uint160, uint256));
        if (zeroForOne) {
            assertGe(sqrtPriceNew, bound);
            assertLe(sqrtPriceNew, state.sqrtPriceX96);
            assertLe(amountOut, SqrtPriceMath.getAmount1Delta(bound, state.sqrtPriceX96, state.liquidity, false));
        } else {
            assertGe(sqrtPriceNew, state.sqrtPriceX96);
            assertLe(sqrtPriceNew, bound);
            assertLe(amountOut, SqrtPriceMath.getAmount0Delta(state.sqrtPriceX96, bound, state.liquidity, false));
        }
    }
}
