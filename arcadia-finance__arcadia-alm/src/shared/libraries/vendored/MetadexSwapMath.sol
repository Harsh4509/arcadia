/**
 * https://github.com/dromos-labs/metadex-slipstream-public/blob/main/contracts/core/libraries/SwapMath.sol
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
pragma solidity ^0.8.34;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";

/**
 * @title Metadex Swap Math.
 * @notice The Metadex CL pool's swap step, ported to 0.8.
 */
// forge-lint: disable-next-item(unsafe-typecast)
library MetadexSwapMath {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The result of one swap step within a tick, as the Metadex CL pool computes it.
     * @param sqrtPriceCurrentX96 The square root of the pool price, with 96 binary precision.
     * @param sqrtPriceTargetX96 The square root of the price the step may not pass, with 96 binary precision.
     * @param liquidity The usable liquidity.
     * @param amountRemaining The input left to swap when positive, the output left to buy when negative.
     * @param feePips The fee taken from the input, with 6 decimals precision.
     * @return sqrtPriceNextX96 The square root of the price after the step, with 96 binary precision.
     * @return amountIn The input the step takes, without the fee.
     * @return amountOut The output the step pays.
     * @return feeAmount The fee the step takes from the input.
     * @dev Vendored from SwapMath.computeSwapStep, ported to 0.8 with the same checked and unchecked arithmetic.
     */
    function computeSwapStep(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        int256 amountRemaining,
        uint24 feePips
    ) internal pure returns (uint160 sqrtPriceNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) {
        // Unchecked: vendored, unchecked under solc 0.7.6.
        unchecked {
            bool zeroForOne = sqrtPriceCurrentX96 >= sqrtPriceTargetX96;
            bool exactIn = amountRemaining >= 0;

            // Calculate the price the step ends at, the target when the remainder reaches it.
            if (exactIn) {
                uint256 amountRemainingLessFee = uint256(amountRemaining).fullMulDiv(1e6 - feePips, 1e6);
                amountIn = zeroForOne
                    ? SqrtPriceMath.getAmount0Delta(sqrtPriceTargetX96, sqrtPriceCurrentX96, liquidity, true)
                    : SqrtPriceMath.getAmount1Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, true);
                sqrtPriceNextX96 = amountRemainingLessFee >= amountIn
                    ? sqrtPriceTargetX96
                    : SqrtPriceMath.getNextSqrtPriceFromInput(
                        sqrtPriceCurrentX96, liquidity, amountRemainingLessFee, zeroForOne
                    );
            } else {
                amountOut = zeroForOne
                    ? SqrtPriceMath.getAmount1Delta(sqrtPriceTargetX96, sqrtPriceCurrentX96, liquidity, false)
                    : SqrtPriceMath.getAmount0Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, false);
                sqrtPriceNextX96 = uint256(-amountRemaining) >= amountOut
                    ? sqrtPriceTargetX96
                    : SqrtPriceMath.getNextSqrtPriceFromOutput(
                        sqrtPriceCurrentX96, liquidity, uint256(-amountRemaining), zeroForOne
                    );
            }

            // Calculate the input and output between the two prices, keeping the amount computed at a reached target.
            bool max = sqrtPriceTargetX96 == sqrtPriceNextX96;
            if (zeroForOne) {
                if (!max || !exactIn) {
                    amountIn = SqrtPriceMath.getAmount0Delta(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity, true);
                }
                if (!max || exactIn) {
                    amountOut = SqrtPriceMath.getAmount1Delta(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity, false);
                }
            } else {
                if (!max || !exactIn) {
                    amountIn = SqrtPriceMath.getAmount1Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, true);
                }
                if (!max || exactIn) {
                    amountOut = SqrtPriceMath.getAmount0Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, false);
                }
            }

            // Cap the output at the output left to buy.
            if (!exactIn && amountOut > uint256(-amountRemaining)) amountOut = uint256(-amountRemaining);

            // Take the rest of the input as the fee when the step stops short of the target, else the fee on the input.
            feeAmount = exactIn && sqrtPriceNextX96 != sqrtPriceTargetX96
                ? uint256(amountRemaining) - amountIn
                : amountIn.fullMulDivUp(feePips, 1e6 - feePips);
        }
    }
}
