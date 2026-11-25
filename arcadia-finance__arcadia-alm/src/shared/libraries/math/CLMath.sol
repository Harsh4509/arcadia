/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @title CL Math.
 * @author Pragma Labs
 * @notice Concentrated liquidity math: conversions, steps and bands of a price, and what a Metadex CL position holds at a price.
 */
// forge-lint: disable-next-item(require-revert-in-loop, unsafe-typecast)
library CLMath {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  ERRORS
    ////////////////////////////////////////////////////////////// */

    error NoLiquidityForToken0();

    /* //////////////////////////////////////////////////////////////
                                 PRICES
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Converts an amount between the two tokens at any sqrtPrice, without slippage or fees.
     * @param sqrtPriceX96 The square root of the price (token1/token0), with 96 binary precision.
     * @param zeroForOne True to convert token0 into token1, false for token1 into token0.
     * @param amount The amount converted.
     * @param roundUp True to round the converted amount up, false to round it down.
     * @return converted The converted amount.
     */
    function convert(uint256 sqrtPriceX96, bool zeroForOne, uint256 amount, bool roundUp)
        internal
        pure
        returns (uint256 converted)
    {
        if (sqrtPriceX96 > type(uint128).max) {
            if (roundUp) {
                converted = zeroForOne
                    ? amount.fullMulDivUp(sqrtPriceX96.fullMulDivUp(sqrtPriceX96, 1 << 64), 1 << 128)
                    : amount.fullMulDivUp(1 << 96, sqrtPriceX96).fullMulDivUp(1 << 96, sqrtPriceX96);
            } else {
                converted = zeroForOne
                    ? amount.fullMulDiv(sqrtPriceX96.fullMulDiv(sqrtPriceX96, 1 << 64), 1 << 128)
                    : amount.fullMulDiv(1 << 96, sqrtPriceX96).fullMulDiv(1 << 96, sqrtPriceX96);
            }
        } else {
            // Unchecked: sqrtPriceX96 fits uint128.
            unchecked {
                uint256 priceX192 = sqrtPriceX96 * sqrtPriceX96;
                if (roundUp) {
                    converted = zeroForOne
                        ? amount.fullMulDivUp(priceX192, 1 << 192)
                        : amount.fullMulDivUp(1 << 192, priceX192);
                } else {
                    converted =
                        zeroForOne ? amount.fullMulDiv(priceX192, 1 << 192) : amount.fullMulDiv(1 << 192, priceX192);
                }
            }
        }
    }

    /**
     * @notice Moves the square root price of tokenIn by a relative amount, at most to a bound.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param sqrtPriceOld The square root of the price (token1/token0) before the move, with 96 binary precision.
     * @param sqrtPriceBound The square root of the price the move stops at the latest, with 96 binary precision.
     * @param sqrtPriceDelta The relative move of the square root price of tokenIn, with 192 binary precision.
     * @return sqrtPriceNew The square root of the price after the move, with 96 binary precision.
     */
    function getNextSqrtPrice(bool zeroForOne, uint256 sqrtPriceOld, uint256 sqrtPriceBound, uint256 sqrtPriceDelta)
        internal
        pure
        returns (uint160 sqrtPriceNew)
    {
        // Unchecked: sqrtPriceBound is on the move's side of sqrtPriceOld, except for a pool at MIN_SQRT_PRICE.
        unchecked {
            if (zeroForOne) {
                // The move stops at sqrtPriceBound: δ ≥ (s0 − sqrtPriceBound) / s0
                if (sqrtPriceDelta >= (sqrtPriceOld - sqrtPriceBound).fullMulDivUnchecked(1 << 192, sqrtPriceOld)) {
                    return uint160(sqrtPriceBound);
                }
                sqrtPriceNew = uint160(sqrtPriceOld - sqrtPriceOld.fullMulDivN(sqrtPriceDelta, 192));
            } else {
                // The move stops at sqrtPriceBound: δ ≥ (sqrtPriceBound − s0) / sqrtPriceBound
                if (sqrtPriceDelta >= (sqrtPriceBound - sqrtPriceOld).fullMulDivUnchecked(1 << 192, sqrtPriceBound)) {
                    return uint160(sqrtPriceBound);
                }
                sqrtPriceNew = uint160(sqrtPriceOld.fullMulDivUnchecked(1 << 192, (1 << 192) - sqrtPriceDelta));
            }
        }
    }

    /**
     * @notice The sqrt prices within a ratio band around a sqrt price.
     * @param sqrtPriceX96 The reference sqrt price.
     * @param deviation The 1e18-scaled ratio band around the sqrt price.
     * @return sqrtPriceLowerX96 The lowest sqrt price inside the band.
     * @return sqrtPriceUpperX96 The highest sqrt price inside the band.
     */
    function getBand(uint256 sqrtPriceX96, uint256 deviation)
        internal
        pure
        returns (uint256 sqrtPriceLowerX96, uint256 sqrtPriceUpperX96)
    {
        uint256 scale;
        // Unchecked: the deviation is a uint64 at every caller.
        unchecked {
            scale = 1e18 + deviation;
        }
        // Both round inward, so the bounds lie inside the band.
        sqrtPriceLowerX96 = sqrtPriceX96.fullMulDivUp(1e18, scale);
        sqrtPriceUpperX96 = sqrtPriceX96.fullMulDiv(scale, 1e18);
    }

    /* //////////////////////////////////////////////////////////////
                                POSITIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The least amounts the position manager derives a liquidity of at least `liquidity` from.
     * @param sqrtPriceX96 The current sqrt price.
     * @param sqrtPriceAX96 One bound of the range.
     * @param sqrtPriceBX96 The other bound of the range.
     * @param liquidity The liquidity the amounts have to reach.
     * @return amount0 The token0 amount.
     * @return amount1 The token1 amount.
     */
    function getAmountsForLiquidityRoundingUp(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        // Calculate the token amounts with the price below, inside or above the range, rounded up.
        if (sqrtPriceX96 <= sqrtPriceAX96) {
            amount0 = getAmount0ForLiquidityRoundingUp(sqrtPriceAX96, sqrtPriceBX96, liquidity);
        } else if (sqrtPriceX96 < sqrtPriceBX96) {
            amount0 = getAmount0ForLiquidityRoundingUp(sqrtPriceX96, sqrtPriceBX96, liquidity);
            amount1 = getAmount1ForLiquidityRoundingUp(sqrtPriceAX96, sqrtPriceX96, liquidity);
        } else {
            amount1 = getAmount1ForLiquidityRoundingUp(sqrtPriceAX96, sqrtPriceBX96, liquidity);
        }
    }

    /**
     * @notice The least token0 the position manager derives a liquidity of at least `liquidity` from.
     * @param sqrtPriceAX96 The lower bound.
     * @param sqrtPriceBX96 The upper bound.
     * @param liquidity The liquidity the amounts have to reach.
     * @return amount0 The token0 amount.
     */
    function getAmount0ForLiquidityRoundingUp(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0)
    {
        // Calculate the product of the bounds, J = floor(a * b / 2^96), the position manager's own divisor.
        uint256 intermediate = uint256(sqrtPriceAX96).fullMulDivN(sqrtPriceBX96, 96);

        // Checks.
        if (intermediate == 0) revert NoLiquidityForToken0();

        // Calculate the token0 for the liquidity between the bounds, rounded up.
        // Unchecked: the bounds are ordered at every caller.
        unchecked {
            amount0 = uint256(liquidity).fullMulDivUp(sqrtPriceBX96 - sqrtPriceAX96, intermediate);
        }
    }

    /**
     * @notice The least token1 the position manager derives a liquidity of at least `liquidity` from.
     * @param sqrtPriceAX96 The lower bound.
     * @param sqrtPriceBX96 The upper bound.
     * @param liquidity The liquidity the amounts have to reach.
     * @return amount1 The token1 amount.
     */
    function getAmount1ForLiquidityRoundingUp(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity)
        internal
        pure
        returns (uint256 amount1)
    {
        // Calculate the token1 for the liquidity between the bounds, rounded up.
        // Unchecked: the bounds are ordered at every caller.
        unchecked {
            amount1 = uint256(liquidity).fullMulDivUp(sqrtPriceBX96 - sqrtPriceAX96, 1 << 96);
        }
    }

    /**
     * @notice Computes the token amounts a liquidity range holds at the current price, rounded down.
     * @param sqrtPriceX96 The current sqrt price.
     * @param sqrtPriceAX96 One bound of the range.
     * @param sqrtPriceBX96 The other bound of the range.
     * @param liquidity The liquidity.
     * @return amount0 The token0 amount.
     * @return amount1 The token1 amount.
     */
    function getAmountsForLiquidity(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        // Calculate the token amounts with the price below, inside or above the range, rounded down.
        if (sqrtPriceX96 <= sqrtPriceAX96) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceAX96, sqrtPriceBX96, liquidity, false);
        } else if (sqrtPriceX96 < sqrtPriceBX96) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtPriceBX96, liquidity, false);
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtPriceAX96, sqrtPriceX96, liquidity, false);
        } else {
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtPriceAX96, sqrtPriceBX96, liquidity, false);
        }
    }

    /**
     * @notice Computes the token amounts a liquidity position holds at the current price, rounded down.
     * @param sqrtPriceX96 The current sqrt price.
     * @param tickLower The lower tick of the liquidity position.
     * @param tickUpper The upper tick of the liquidity position.
     * @param liquidity The liquidity.
     * @return amount0 The token0 amount.
     * @return amount1 The token1 amount.
     */
    function getPrincipalAmounts(uint160 sqrtPriceX96, int24 tickLower, int24 tickUpper, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = getAmountsForLiquidity(
            sqrtPriceX96, TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), liquidity
        );
    }

    /* //////////////////////////////////////////////////////////////
                              MINT LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The token amounts one range owes for a mint of shares, rounded up.
     * @param sqrtPriceX96 The price to value the range at.
     * @param sqrtPriceLowerX96 The sqrt price at the range's lower tick.
     * @param sqrtPriceUpperX96 The sqrt price at the range's upper tick.
     * @param rangeLiquidity The range's liquidity.
     * @param shares The aLP shares minted.
     * @param supply The aLP supply before this mint.
     * @return amount0 The token0 the position manager takes for the range's liquidity claimed by shares.
     * @return amount1 The token1 the position manager takes for the range's liquidity claimed by shares.
     */
    function getMintAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceLowerX96,
        uint160 sqrtPriceUpperX96,
        uint256 rangeLiquidity,
        uint256 shares,
        uint256 supply
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        // Calculate the range's liquidity claimed by the shares, rounded up.
        uint128 liquidity = SafeCastLib.toUint128(rangeLiquidity.fullMulDivUp(shares, supply));

        // Calculate the token amounts for that liquidity at the price, rounded up.
        (amount0, amount1) =
            getAmountsForLiquidityRoundingUp(sqrtPriceX96, sqrtPriceLowerX96, sqrtPriceUpperX96, liquidity);
    }
}
