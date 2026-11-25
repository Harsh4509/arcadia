/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { MintOptimizationMath } from "../../../src/vaults/libraries/math/MintOptimizationMath.sol";
import { Snapshot } from "../../../src/vaults/types/Snapshot.sol";

contract MintOptimizationMathExtension {
    function computeSwap(Snapshot memory snapshot, address pool, bool zeroForOne, uint256 shares)
        external
        view
        returns (uint160 sqrtPriceNew, uint256 amountIn, uint256 amountOut, uint256 fees0, uint256 fees1)
    {
        (sqrtPriceNew, amountIn, amountOut) = MintOptimizationMath.computeSwap(snapshot, pool, zeroForOne, shares);
        (fees0, fees1) = (snapshot.fees0, snapshot.fees1);
    }

    function previewMint(Snapshot memory snapshot, address pool, bool zeroForOne, uint256 shares)
        external
        view
        returns (uint256 assets)
    {
        assets = MintOptimizationMath.previewMint(snapshot, pool, zeroForOne, shares);
    }

    function maxMint(Snapshot memory snapshot, address pool, uint256 sqrtPriceLimitX96, bool zeroForOne)
        external
        view
        returns (uint256 shares)
    {
        shares = MintOptimizationMath.maxMint(snapshot, pool, sqrtPriceLimitX96, zeroForOne);
    }

    function getMintAmountOut(Snapshot memory snapshot, uint160 sqrtPriceX96, bool zeroForOne, uint256 shares)
        external
        pure
        returns (uint256 amountOut, uint256 activeLiquidityDelta)
    {
        (amountOut, activeLiquidityDelta) =
            MintOptimizationMath.getMintAmountOut(snapshot, sqrtPriceX96, zeroForOne, shares);
    }
}
