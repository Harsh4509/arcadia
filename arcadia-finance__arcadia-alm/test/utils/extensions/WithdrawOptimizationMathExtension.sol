/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Snapshot } from "../../../src/vaults/types/Snapshot.sol";
import { StepComputations, SwapState } from "../../../src/vaults/types/SwapState.sol";
import { WithdrawOptimizationMath } from "../../../src/vaults/libraries/math/WithdrawOptimizationMath.sol";

contract WithdrawOptimizationMathExtension {
    function previewWithdraw(Snapshot memory snapshot, address pool, bool zeroForOne, uint256 amountOut)
        external
        view
        returns (uint256 shares)
    {
        shares = WithdrawOptimizationMath.previewWithdraw(snapshot, pool, zeroForOne, amountOut);
    }

    function maxWithdraw(Snapshot memory snapshot, address pool, bool zeroForOne, uint256 shares)
        external
        view
        returns (uint256 amountOut)
    {
        amountOut = WithdrawOptimizationMath.maxWithdraw(snapshot, pool, zeroForOne, shares);
    }

    function getSharesForAmounts(
        Snapshot memory snapshot,
        bool zeroForOne,
        uint256 amountOut,
        uint256 holdingsIn,
        uint256 holdingsOut,
        SwapState memory state,
        StepComputations memory step,
        uint256 amountIn
    )
        external
        pure
        returns (
            uint256 shares,
            bool costBinds,
            uint256 holdingsInDelta,
            uint256 holdingsOutDelta,
            StepComputations memory
        )
    {
        (shares, costBinds, holdingsInDelta, holdingsOutDelta) =
            WithdrawOptimizationMath.getSharesForAmounts(
                snapshot, zeroForOne, amountOut, holdingsIn, holdingsOut, state, step, amountIn
            );
        return (shares, costBinds, holdingsInDelta, holdingsOutDelta, step);
    }

    function getSqrtPrice(
        Snapshot memory snapshot,
        bool zeroForOne,
        uint256 amountOutLeft,
        uint256 holdingsIn,
        uint256 holdingsOut,
        SwapState memory state,
        StepComputations memory step,
        uint256 amountIn
    ) external pure returns (uint160 sqrtPriceNew) {
        sqrtPriceNew = WithdrawOptimizationMath.getSqrtPrice(
            snapshot, zeroForOne, amountOutLeft, holdingsIn, holdingsOut, state, step, amountIn
        );
    }

    function getNextSqrtPrice(
        bool zeroForOne,
        SwapState memory state,
        StepComputations memory step,
        uint256 sqrtPriceDelta
    ) external pure returns (uint160 sqrtPriceNew) {
        sqrtPriceNew = WithdrawOptimizationMath.getNextSqrtPrice(zeroForOne, state, step, sqrtPriceDelta);
    }

    function getQuadraticCoefficients(
        Snapshot memory snapshot,
        bool zeroForOne,
        uint256 amountOutLeft,
        uint256 holdingsIn,
        uint256 holdingsOut,
        SwapState memory state,
        uint256 amountIn
    ) external pure returns (int256 quadraticCoefficient, int256 linearCoefficient, int256 constantCoefficient) {
        (quadraticCoefficient, linearCoefficient, constantCoefficient) =
            WithdrawOptimizationMath.getQuadraticCoefficients(
                snapshot, zeroForOne, amountOutLeft, holdingsIn, holdingsOut, state, amountIn
            );
    }

    function getNormalizedParameters(
        Snapshot memory snapshot,
        bool zeroForOne,
        uint256 amountOutLeft,
        uint256 holdingsIn,
        uint256 holdingsOut,
        SwapState memory state,
        uint256 amountIn
    )
        external
        pure
        returns (
            int256 reserveOutNormalized,
            int256 amountOutNormalized,
            int256 holdingsNormalized,
            uint256 liquidityNormalized
        )
    {
        (
            reserveOutNormalized, amountOutNormalized, holdingsNormalized, liquidityNormalized
        ) =
            WithdrawOptimizationMath.getNormalizedParameters(
                snapshot, zeroForOne, amountOutLeft, holdingsIn, holdingsOut, state, amountIn
            );
    }
}
