/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { DepositOptimizationMathExtension } from "../../../utils/extensions/DepositOptimizationMathExtension.sol";
import { DepositOptimizationMath_Fuzz_Test } from "./_DepositOptimizationMath.fuzz.t.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { SwapState } from "../../../../src/vaults/types/SwapState.sol";

/**
 * @notice Fuzz tests for the function "getQuadraticCoefficients" of library "DepositOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetQuadraticCoefficients_DepositOptimizationMath_Fuzz_Test is DepositOptimizationMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getQuadraticCoefficients_TheCoefficientsOfTheNormalizedParameters(
        DepositParams memory params,
        bool zeroForOne,
        uint256 unstakedLiquidity,
        uint256 feeShare
    ) public view {
        // Given: A deposit, a position on its segment, its unstaked part and fee share.
        givenValidDepositParams(params, zeroForOne);
        params.positionUnstakedLiquidity = bound(unstakedLiquidity, 0, params.positionLiquidity);
        SwapState memory state = swapStateOf(params);
        state.feeShare = bound(feeShare, 0, Constants.FEE_SHARE_UNIT);

        // When: Calculating the quadratic's coefficients.
        (bool success, bytes memory coefficients) = address(optimizationMath)
            .staticcall(
                abi.encodeCall(
                    DepositOptimizationMathExtension.getQuadraticCoefficients,
                    (zeroForOne, state, params.balanceIn, params.balanceOut, params.roundingMargin)
                )
            );
        assertTrue(success);

        // Then: A, B and C are those of the definition in the normalized parameters.
        bytes memory normalized;
        (success, normalized) = address(optimizationMath)
            .staticcall(
                abi.encodeCall(
                    DepositOptimizationMathExtension.getNormalizedParameters,
                    (zeroForOne, state, params.balanceIn, params.balanceOut, state.position, params.roundingMargin)
                )
            );
        assertTrue(success);
        uint256 kappa = (1e6 << 192) / (1e6 - params.fee);
        {
            (,, int256 constantCoefficient) = abi.decode(coefficients, (int256, int256, int256));
            (uint256 alpha, uint256 beta,, uint256 epsilonIn, uint256 epsilonOut,) =
                abi.decode(normalized, (uint256, uint256, uint256, uint256, uint256, uint256));
            assertEq(
                constantCoefficient,
                int256(FullMath.mulDiv(alpha, epsilonOut, 1 << 192))
                    - int256(FullMath.mulDiv(beta, epsilonIn, 1 << 192))
            );
        }
        {
            (int256 quadraticCoefficient,,) = abi.decode(coefficients, (int256, int256, int256));
            (uint256 alpha,, uint256 omega, uint256 epsilonIn,, uint256 rho) =
                abi.decode(normalized, (uint256, uint256, uint256, uint256, uint256, uint256));
            assertEq(
                quadraticCoefficient,
                int256(FullMath.mulDiv(alpha + kappa - (1 << 192), omega, 1 << 192) + epsilonIn) - int256(rho)
            );
        }
        {
            (, int256 linearCoefficient, int256 constantCoefficient) =
                abi.decode(coefficients, (int256, int256, int256));
            (uint256 alpha, uint256 beta, uint256 omega, uint256 epsilonIn, uint256 epsilonOut, uint256 rho) =
                abi.decode(normalized, (uint256, uint256, uint256, uint256, uint256, uint256));
            assertEq(
                linearCoefficient - constantCoefficient,
                int256(
                    FullMath.mulDiv(alpha + beta, omega, 1 << 192) + FullMath.mulDiv(kappa, epsilonOut, 1 << 192)
                        + epsilonIn + FullMath.mulDiv(beta, rho, 1 << 192)
                )
            );
        }
    }

    function testFuzz_Success_getQuadraticCoefficients_TheQuadraticCoefficientIsAtLeastThePositionsTokenIn(
        DepositParams memory params,
        bool zeroForOne,
        uint256 unstakedLiquidity,
        uint256 feeShare
    ) public view {
        // Given: A deposit, a position on its segment, its unstaked part and fee share.
        givenValidDepositParams(params, zeroForOne);
        params.positionUnstakedLiquidity = bound(unstakedLiquidity, 0, params.positionLiquidity);
        SwapState memory state = swapStateOf(params);
        state.feeShare = bound(feeShare, 0, Constants.FEE_SHARE_UNIT);

        // When: Calculating the quadratic's coefficients.
        (int256 quadraticCoefficient,,) = optimizationMath.getQuadraticCoefficients(
            zeroForOne, state, params.balanceIn, params.balanceOut, params.roundingMargin
        );

        // Then: A is at least the position's normalized tokenIn, so at least zero.
        (,,, uint256 epsilonIn,,) = optimizationMath.getNormalizedParameters(
            zeroForOne, state, params.balanceIn, params.balanceOut, state.position, params.roundingMargin
        );
        assertGe(quadraticCoefficient, int256(epsilonIn));
    }

    function testFuzz_Success_getQuadraticCoefficients_TheLinearCoefficientIsAtLeastTheConstant(
        DepositParams memory params,
        bool zeroForOne,
        uint256 unstakedLiquidity,
        uint256 feeShare
    ) public view {
        // Given: A deposit, a position on its segment, its unstaked part and fee share.
        givenValidDepositParams(params, zeroForOne);
        params.positionUnstakedLiquidity = bound(unstakedLiquidity, 0, params.positionLiquidity);
        SwapState memory state = swapStateOf(params);
        state.feeShare = bound(feeShare, 0, Constants.FEE_SHARE_UNIT);

        // When: Calculating the quadratic's coefficients.
        (, int256 linearCoefficient, int256 constantCoefficient) = optimizationMath.getQuadraticCoefficients(
            zeroForOne, state, params.balanceIn, params.balanceOut, params.roundingMargin
        );

        // Then: B is at least C.
        assertGe(linearCoefficient, constantCoefficient);
    }
}
