/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { DepositOptimizationMath } from "../../../src/vaults/libraries/math/DepositOptimizationMath.sol";
import { EquivalentPosition } from "../../../src/vaults/types/EquivalentPosition.sol";
import { Snapshot } from "../../../src/vaults/types/Snapshot.sol";
import { SwapState } from "../../../src/vaults/types/SwapState.sol";

contract DepositOptimizationMathExtension {
    function computeSwap(Snapshot memory snapshot, address pool, bool zeroForOne, uint256 balanceIn)
        external
        view
        returns (uint160 sqrtPriceNew, uint256 amountIn, uint256 amountOut, uint256 fees0, uint256 fees1)
    {
        (sqrtPriceNew, amountIn, amountOut) = DepositOptimizationMath.computeSwap(snapshot, pool, zeroForOne, balanceIn);
        (fees0, fees1) = (snapshot.fees0, snapshot.fees1);
    }

    function previewDeposit_(Snapshot memory snapshot, address pool, bool zeroForOne, uint256 balanceIn)
        external
        view
        returns (uint256 shares)
    {
        shares = DepositOptimizationMath.previewDeposit(snapshot, pool, zeroForOne, balanceIn);
    }

    function maxDeposit(
        Snapshot memory snapshot,
        address pool,
        uint256 sqrtPriceLimitX96,
        bool zeroForOne,
        uint256 shares
    ) external view returns (uint256 assets) {
        assets = DepositOptimizationMath.maxDeposit(snapshot, pool, sqrtPriceLimitX96, zeroForOne, shares);
    }

    function getBalanceIn(uint256 amountIn, uint256 amountOut, uint256 positionAmountIn, uint256 positionAmountOut)
        external
        pure
        returns (uint256 balanceIn)
    {
        balanceIn = DepositOptimizationMath.getBalanceIn(amountIn, amountOut, positionAmountIn, positionAmountOut);
    }

    function getAmountOut(
        bool zeroForOne,
        SwapState memory state,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 roundingMargin
    ) external pure returns (uint160 sqrtPriceNew, uint256 amountOut) {
        (sqrtPriceNew, amountOut) = DepositOptimizationMath.getAmountOut(
            zeroForOne, state, balanceIn, balanceOut, roundingMargin
        );
    }

    function getSqrtPrice(
        bool zeroForOne,
        SwapState memory state,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 roundingMargin
    ) external pure returns (uint160 sqrtPriceNew) {
        sqrtPriceNew = DepositOptimizationMath.getSqrtPrice(zeroForOne, state, balanceIn, balanceOut, roundingMargin);
    }

    function getQuadraticCoefficients(
        bool zeroForOne,
        SwapState memory state,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 roundingMargin
    ) external pure returns (int256 quadraticCoefficient, int256 linearCoefficient, int256 constantCoefficient) {
        (quadraticCoefficient, linearCoefficient, constantCoefficient) =
            DepositOptimizationMath.getQuadraticCoefficients(zeroForOne, state, balanceIn, balanceOut, roundingMargin);
    }

    function getNormalizedParameters(
        bool zeroForOne,
        SwapState memory state,
        uint256 balanceIn,
        uint256 balanceOut,
        EquivalentPosition memory position,
        uint256 roundingMargin
    ) external pure returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        state.position = position;
        return DepositOptimizationMath.getNormalizedParameters(zeroForOne, state, balanceIn, balanceOut, roundingMargin);
    }
}
