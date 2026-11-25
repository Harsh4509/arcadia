/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { RedeemOptimizationMath_Fuzz_Test } from "../RedeemOptimizationMath/_RedeemOptimizationMath.fuzz.t.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SwapState } from "../../../../src/vaults/types/SwapState.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getQuadraticCoefficients" of library "WithdrawOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetQuadraticCoefficients_WithdrawOptimizationMath_Fuzz_Test is RedeemOptimizationMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getQuadraticCoefficients_FromTheNormalizedTerms(
        SwapState memory state,
        uint256 rangeCount,
        bool zeroForOne,
        uint256 amountOutLeft,
        uint256 holdingsIn,
        uint256 holdingsOut,
        uint256 amountIn
    ) public view {
        // Given: n ranges, the pool's liquidity, fee and price, the core's part W.
        Snapshot memory snapshot;
        snapshot.ranges = new PricedRange[](bound(rangeCount, 1, ConfigLib.MAX_RANGE_CAP));
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 1),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 1)
            )
        );
        state.liquidity = uint128(bound(state.liquidity, 1, Constants.MAX_SOLVER_LIQUIDITY));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));
        state.position.liquidity = bound(state.position.liquidity, 0, state.liquidity);

        // And: Holdings B and A of 1 to 2^64 at 2^96, C up to B, a up to A.
        holdingsIn = bound(holdingsIn, 1 << 96, Constants.MAX_SOLVER_HOLDINGS);
        holdingsOut = bound(holdingsOut, 1 << 96, Constants.MAX_SOLVER_HOLDINGS);
        amountIn = bound(amountIn, 0, holdingsIn);
        amountOutLeft = bound(amountOutLeft, 0, holdingsOut);

        // When: Calculating the coefficients.
        bytes memory coefficients = abi.encodeCall(
            withdrawMath.getQuadraticCoefficients,
            (snapshot, zeroForOne, amountOutLeft, holdingsIn, holdingsOut, state, amountIn)
        );
        (, coefficients) = address(withdrawMath).staticcall(coefficients);

        // Then: They are r + l floored at zero, r + a + h and a, of the normalized terms.
        int256[3] memory terms;
        uint256 liquidityTerm;
        {
            uint256 holdings = FixedPointMathLib.max(holdingsIn, holdingsOut);
            liquidityTerm = FullMath.mulDiv(
                FullMath.mulDiv(snapshot.ranges.length * state.position.liquidity, 1 << 192, holdings),
                1e6,
                1e6 - uint256(state.fee)
            );
            uint256[4] memory amounts;
            if (zeroForOne) {
                amounts[0] = uint256(state.liquidity) * state.sqrtPriceX96;
                amounts[1] = state.position.liquidity * state.sqrtPriceX96;
                amounts[2] = FullMath.mulDiv(state.liquidity + snapshot.ranges.length, 1 << 192, state.sqrtPriceX96);
                amounts[3] = FullMath.mulDiv(state.position.liquidity, 1 << 192, state.sqrtPriceX96);
            } else {
                amounts[0] = FullMath.mulDiv(state.liquidity, 1 << 192, state.sqrtPriceX96);
                amounts[1] = FullMath.mulDiv(state.position.liquidity, 1 << 192, state.sqrtPriceX96);
                amounts[2] = (state.liquidity + snapshot.ranges.length) * state.sqrtPriceX96;
                amounts[3] = state.position.liquidity * state.sqrtPriceX96;
            }
            terms[0] = int256(FullMath.mulDiv(amounts[0], holdingsIn, holdings))
                - int256(FullMath.mulDiv(amountIn, amounts[1], holdings));
            terms[1] = int256(FullMath.mulDiv(amountOutLeft, holdingsIn, holdings))
                - int256(FullMath.mulDiv(amountIn, holdingsOut, holdings));
            terms[2] =
                (int256(FullMath.mulDiv(amounts[2], holdingsOut, holdings))
                        - int256(FullMath.mulDiv(amountOutLeft, amounts[3], holdings))) * 1e6
                    / int256(1e6 - uint256(state.fee));
        }
        uint256 largest = FixedPointMathLib.max(
            FixedPointMathLib.max(FixedPointMathLib.abs(terms[0]), FixedPointMathLib.abs(terms[1])),
            FixedPointMathLib.max(FixedPointMathLib.max(FixedPointMathLib.abs(terms[2]), liquidityTerm), 1)
        );
        for (uint256 i; i < 3; ++i) {
            int256 normalized = int256(FullMath.mulDiv(FixedPointMathLib.abs(terms[i]), 1 << 192, largest));
            terms[i] = terms[i] < 0 ? -normalized : normalized;
        }
        int256 quadratic = terms[0] + int256(FullMath.mulDiv(liquidityTerm, 1 << 192, largest));
        assertEq(coefficients, abi.encode(quadratic, terms[0] + terms[1] + terms[2], terms[1]));
    }
}
