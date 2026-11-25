/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";

contract CLMathExtension {
    function convert(uint256 sqrtPriceX96, bool zeroForOne, uint256 amount, bool roundUp)
        external
        pure
        returns (uint256 converted)
    {
        converted = CLMath.convert(sqrtPriceX96, zeroForOne, amount, roundUp);
    }

    function getNextSqrtPrice(bool zeroForOne, uint256 sqrtPriceOld, uint256 sqrtPriceBound, uint256 sqrtPriceDelta)
        external
        pure
        returns (uint160 sqrtPriceNew)
    {
        sqrtPriceNew = CLMath.getNextSqrtPrice(zeroForOne, sqrtPriceOld, sqrtPriceBound, sqrtPriceDelta);
    }

    function getBand(uint256 sqrtPriceX96, uint256 deviation)
        external
        pure
        returns (uint256 sqrtPriceLowerX96, uint256 sqrtPriceUpperX96)
    {
        (sqrtPriceLowerX96, sqrtPriceUpperX96) = CLMath.getBand(sqrtPriceX96, deviation);
    }

    function getAmountsForLiquidityRoundingUp(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) external pure returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = CLMath.getAmountsForLiquidityRoundingUp(
            sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidity
        );
    }

    function getAmount0ForLiquidityRoundingUp(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity)
        external
        pure
        returns (uint256 amount0)
    {
        amount0 = CLMath.getAmount0ForLiquidityRoundingUp(sqrtPriceAX96, sqrtPriceBX96, liquidity);
    }

    function getAmount1ForLiquidityRoundingUp(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity)
        external
        pure
        returns (uint256 amount1)
    {
        amount1 = CLMath.getAmount1ForLiquidityRoundingUp(sqrtPriceAX96, sqrtPriceBX96, liquidity);
    }

    function getAmountsForLiquidity(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) external pure returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = CLMath.getAmountsForLiquidity(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidity);
    }

    function getPrincipalAmounts(uint160 sqrtPriceX96, int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = CLMath.getPrincipalAmounts(sqrtPriceX96, tickLower, tickUpper, liquidity);
    }

    function getMintAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceLowerX96,
        uint160 sqrtPriceUpperX96,
        uint256 rangeLiquidity,
        uint256 shares,
        uint256 supply
    ) external pure returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = CLMath.getMintAmounts(
            sqrtPriceX96, sqrtPriceLowerX96, sqrtPriceUpperX96, rangeLiquidity, shares, supply
        );
    }
}
