/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { EquivalentPosition } from "../../types/EquivalentPosition.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { PoolLogic } from "../../../shared/libraries/logic/PoolLogic.sol";
import { PricedRange } from "../../types/PricedRange.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";

/**
 * @title Equivalent Position Math.
 * @author Pragma Labs
 * @notice The one position whose token amounts equal those of every range and the buffer together.
 */
// forge-lint: disable-next-item(unsafe-typecast)
library EquivalentPositionMath {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The position of every range and the idle tokens together, over the pool's next swap step.
     * @param ranges The priced ranges.
     * @param sqrtPriceX96 The pool's price.
     * @param zeroForOne True when the step moves the price down.
     * @param idle0 The token0 in the buffer and uncollected fees.
     * @param idle1 The token1 in the buffer and uncollected fees.
     * @return position The equivalent position.
     * @dev A range outside the price holds a fixed amount of one token, as the idle tokens do, so both fold into the constants.
     */
    function getPosition(
        PricedRange[] memory ranges,
        uint160 sqrtPriceX96,
        bool zeroForOne,
        uint256 idle0,
        uint256 idle1
    ) internal pure returns (EquivalentPosition memory position) {
        // Fold the idle tokens into the constants.
        // Unchecked: the idle tokens are non-negative int256 values.
        unchecked {
            position.constant0 = -SafeCastLib.toInt256(idle0);
            position.constant1 = -SafeCastLib.toInt256(idle1);
        }

        // Start the price bound at the most extreme pool price in the step's direction.
        position.sqrtPriceBound = PoolLogic.sqrtPriceLimit(zeroForOne);

        for (uint256 i; i < ranges.length; ++i) {
            PricedRange memory range = ranges[i];
            uint256 liquidity = range.liquidity;
            if (liquidity == 0) continue;

            uint160 lower = range.sqrtPriceLowerX96;
            uint160 upper = range.sqrtPriceUpperX96;

            // Tighten the price bound to the range's nearest edge in the step's direction.
            if (zeroForOne) {
                uint160 edge = upper < sqrtPriceX96 ? upper : lower;
                if (edge < sqrtPriceX96 && edge > position.sqrtPriceBound) position.sqrtPriceBound = edge;
            } else {
                uint160 edge = lower > sqrtPriceX96 ? lower : upper;
                if (edge > sqrtPriceX96 && edge < position.sqrtPriceBound) position.sqrtPriceBound = edge;
            }

            // Fold the range into the position's liquidity and constants.
            if (zeroForOne
                    ? lower < sqrtPriceX96 && sqrtPriceX96 <= upper
                    : lower <= sqrtPriceX96 && sqrtPriceX96 < upper) {
                // Unchecked: at most MAX_RANGE_CAP ranges of uint128 liquidity, with amounts below 2^192 each.
                unchecked {
                    position.liquidity += liquidity;
                    position.unstakedLiquidity += range.unstakedLiquidity;
                    position.constant0 += int256(liquidity.fullMulDiv(1 << 96, upper));
                    position.constant1 += int256(liquidity.fullMulDivN(lower, 96));
                }
            } else if (sqrtPriceX96 <= lower) {
                // The price is below the range, which holds token0 alone.
                uint256 amount0;
                // Unchecked: the range's lower price is below its upper price.
                unchecked {
                    amount0 = liquidity.fullMulDiv(1 << 96, lower) - liquidity.fullMulDiv(1 << 96, upper);
                }
                position.constant0 -= int256(amount0);
            } else {
                // The price is above the range, which holds token1 alone.
                uint256 amount1;
                // Unchecked: the range's lower price is below its upper price.
                unchecked {
                    amount1 = liquidity.fullMulDivN(upper - lower, 96);
                }
                position.constant1 -= int256(amount1);
            }
        }
    }

    /**
     * @notice The token amounts of the position at a price.
     * @param position The equivalent position.
     * @param sqrtPriceX96 The price to value at.
     * @param zeroForOne True when token0 is swapped for token1.
     * @return amountIn The amount of tokenIn.
     * @return amountOut The amount of tokenOut.
     */
    function amountsAt(EquivalentPosition memory position, uint160 sqrtPriceX96, bool zeroForOne)
        internal
        pure
        returns (uint256 amountIn, uint256 amountOut)
    {
        // Calculate the token amounts of the position's liquidity at the price, less the constants.
        int256 own0 = int256(position.liquidity.fullMulDiv(1 << 96, sqrtPriceX96)) - position.constant0;
        int256 own1 = int256(position.liquidity.fullMulDivN(sqrtPriceX96, 96)) - position.constant1;

        // If an amount is negative, floor it at zero.
        (uint256 amount0, uint256 amount1) =
            (uint256(FixedPointMathLib.max(own0, 0)), uint256(FixedPointMathLib.max(own1, 0)));

        // Order the amounts by the swap's direction.
        (amountIn, amountOut) = zeroForOne ? (amount0, amount1) : (amount1, amount0);
    }
}
