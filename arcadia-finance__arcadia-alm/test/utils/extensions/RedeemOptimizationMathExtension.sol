/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { RedeemOptimizationMath } from "../../../src/vaults/libraries/math/RedeemOptimizationMath.sol";
import { Snapshot } from "../../../src/vaults/types/Snapshot.sol";

contract RedeemOptimizationMathExtension {
    function previewRedeem(
        Snapshot memory snapshot,
        address pool,
        bool zeroForOne,
        uint256 shares,
        uint256 roundingMarginIn
    ) external view returns (uint256 amountOut) {
        amountOut = RedeemOptimizationMath.previewRedeem(snapshot, pool, zeroForOne, shares, roundingMarginIn);
    }

    function maxRedeem(Snapshot memory snapshot, address pool, bool zeroForOne, uint256 shares)
        external
        view
        returns (uint256 redeemable)
    {
        redeemable = RedeemOptimizationMath.maxRedeem(snapshot, pool, zeroForOne, shares);
    }
}
