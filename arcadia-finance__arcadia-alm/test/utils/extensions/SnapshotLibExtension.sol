/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { EquivalentPosition } from "../../../src/vaults/types/EquivalentPosition.sol";
import { IALMCore } from "../../../src/interfaces/IALMCore.sol";
import { PricedRange } from "../../../src/vaults/types/PricedRange.sol";
import { Snapshot, SnapshotLib } from "../../../src/vaults/types/Snapshot.sol";

contract SnapshotLibExtension {
    using SnapshotLib for IALMCore;

    function getSnapshot(address core, address pool, address vault) external view returns (Snapshot memory snapshot) {
        snapshot = IALMCore(core).getSnapshot(pool, vault);
    }

    function getFeeShare(Snapshot memory snapshot, address pool) external view returns (uint256 feeShare) {
        feeShare = SnapshotLib.getFeeShare(snapshot, pool);
    }

    function getSwapCostLimit(Snapshot memory snapshot, bool zeroForOne)
        external
        view
        returns (uint160 sqrtPriceLimitX96)
    {
        sqrtPriceLimitX96 = SnapshotLib.getSwapCostLimit(snapshot, zeroForOne);
    }

    function getSwapCostLimit(uint256 sqrtPriceX96, uint256 fee, uint256 maxSwapCostBps, bool zeroForOne)
        external
        pure
        returns (uint160 sqrtPriceLimitX96)
    {
        sqrtPriceLimitX96 = SnapshotLib.getSwapCostLimit(sqrtPriceX96, fee, maxSwapCostBps, zeroForOne);
    }

    function decodePricedRanges(bytes32[] memory words, uint128[] memory positionLiquidity)
        external
        pure
        returns (PricedRange[] memory ranges)
    {
        ranges = SnapshotLib.decodePricedRanges(words, positionLiquidity);
    }

    function idle(Snapshot memory snapshot) external pure returns (uint256 idle0, uint256 idle1) {
        (idle0, idle1) = SnapshotLib.idle(snapshot);
    }

    function getPosition(Snapshot memory snapshot, uint160 sqrtPriceX96, bool zeroForOne)
        external
        pure
        returns (EquivalentPosition memory position)
    {
        position = SnapshotLib.getPosition(snapshot, sqrtPriceX96, zeroForOne);
    }

    function getAmountsAt(Snapshot memory snapshot, uint160 sqrtPriceX96)
        external
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = SnapshotLib.getAmountsAt(snapshot, sqrtPriceX96);
    }

    function getMintAmounts(
        PricedRange[] memory ranges,
        uint160 sqrtPriceX96,
        uint256 idle0,
        uint256 idle1,
        uint256 shares,
        uint256 supply,
        bool zeroForOne
    ) external pure returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1,) = SnapshotLib.getMintAmounts(
            snapshotOf(ranges, idle0, idle1, supply), sqrtPriceX96, shares, zeroForOne
        );
        if (!zeroForOne) (amount0, amount1) = (amount1, amount0);
    }

    function getMintLiquidityDelta(
        PricedRange[] memory ranges,
        uint160 sqrtPriceX96,
        uint256 shares,
        uint256 supply,
        bool zeroForOne
    ) external pure returns (uint256 activeLiquidityDelta) {
        (,, activeLiquidityDelta) = SnapshotLib.getMintAmounts(
            snapshotOf(ranges, 0, 0, supply), sqrtPriceX96, shares, zeroForOne
        );
    }

    function getMintShares(
        PricedRange[] memory ranges,
        uint256 idle0,
        uint256 idle1,
        uint256 supply,
        uint160 sqrtPriceX96,
        uint256 amount0,
        uint256 amount1,
        bool zeroForOne
    ) external pure returns (uint256 shares) {
        (uint256 amountIn, uint256 amountOut) = zeroForOne ? (amount0, amount1) : (amount1, amount0);
        shares = SnapshotLib.getMintShares(
            snapshotOf(ranges, idle0, idle1, supply), sqrtPriceX96, amountIn, amountOut, zeroForOne
        );
    }

    function getBurnAmounts(Snapshot memory snapshot, uint160 sqrtPriceX96, uint256 shares, bool zeroForOne)
        external
        pure
        returns (uint256 amount0, uint256 amount1, uint256 activeLiquidityDelta)
    {
        (amount0, amount1, activeLiquidityDelta) =
            SnapshotLib.getBurnAmounts(snapshot, sqrtPriceX96, shares, zeroForOne);
        if (!zeroForOne) (amount0, amount1) = (amount1, amount0);
    }

    function getRounding(Snapshot memory snapshot, uint256 sqrtPriceX96, bool isToken0)
        external
        pure
        returns (uint256 maxRounding)
    {
        maxRounding = SnapshotLib.getRounding(snapshot, sqrtPriceX96, isToken0);
    }

    function snapshotOf(PricedRange[] memory ranges, uint256 idle0, uint256 idle1, uint256 supply)
        internal
        pure
        returns (Snapshot memory snapshot)
    {
        snapshot = Snapshot({
            buffer0: idle0,
            buffer1: idle1,
            fees0: 0,
            fees1: 0,
            supply: supply,
            sqrtPriceX96: 0,
            tick: 0,
            fee: 0,
            core: IALMCore(address(0)),
            ranges: ranges
        });
    }
}
