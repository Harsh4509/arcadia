/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { MetadexSwapMath } from "../../../shared/libraries/vendored/MetadexSwapMath.sol";
import { PoolLogic } from "../../../shared/libraries/logic/PoolLogic.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { Snapshot, SnapshotLib } from "../../types/Snapshot.sol";
import { StepComputations, SwapState, SwapStateLib } from "../../types/SwapState.sol";

/**
 * @title Redeem Optimization Math.
 * @author Pragma Labs
 * @notice Prices a burn of shares and the sale of the tokenIn it releases, for a redeem.
 */
// forge-lint: disable-next-item(unsafe-typecast)
library RedeemOptimizationMath {
    using FixedPointMathLib for uint256;
    using SnapshotLib for Snapshot;
    using SwapStateLib for StepComputations;
    using SwapStateLib for SwapState;

    /* //////////////////////////////////////////////////////////////
                                  PREVIEW
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the tokenOut a redeem of shares pays.
     * @param snapshot The core's snapshot.
     * @param pool The Metadex CL pool.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param shares The aLP shares burned.
     * @param roundingMarginIn The tokenIn of the burn the sale leaves unsold.
     * @return amountOut The tokenOut the burn releases plus what the pool's sale of the burn's tokenIn buys.
     * @dev Walks the pool's steps as its exact input swap does, against the liquidity the burn leaves.
     */
    function previewRedeem(
        Snapshot memory snapshot,
        address pool,
        bool zeroForOne,
        uint256 shares,
        uint256 roundingMarginIn
    ) internal view returns (uint256 amountOut) {
        // Calculate the token amounts the burn releases at spot, and the liquidity it takes from the ranges in range.
        uint256 amountBurnIn;
        uint256 activeLiquidityDelta;
        (amountBurnIn, amountOut, activeLiquidityDelta) =
            snapshot.getBurnAmounts(snapshot.sqrtPriceX96, shares, zeroForOne);

        // Leave the rounding margin unsold.
        amountBurnIn = amountBurnIn.zeroFloorSub(roundingMarginIn);

        // Start at the pool's price, tick, liquidity and fees, and the core's equivalent position at spot.
        SwapState memory state = SwapStateLib.getSwapState(snapshot, pool, zeroForOne);

        // Walk the pool's swap steps until the tokenIn is sold.
        uint160 sqrtPriceLimitX96 = PoolLogic.sqrtPriceLimit(zeroForOne);
        StepComputations memory step;
        while (state.amountIn < amountBurnIn) {
            // Sell the tokenIn as the pool would, at the liquidity left after the burn.
            step.setNextTick(state, pool, zeroForOne, sqrtPriceLimitX96);
            (step.sqrtPriceTargetX96, step.amountIn, step.amountOut, step.feeAmount) = MetadexSwapMath.computeSwapStep(
                state.sqrtPriceX96,
                step.sqrtPriceTargetX96,
                uint128(uint256(state.liquidity).zeroFloorSub(activeLiquidityDelta)),
                SafeCastLib.toInt256(amountBurnIn - state.amountIn),
                state.fee
            );

            // At the core's edge, recompute the liquidity the burn removes.
            uint160 sqrtPriceBound = state.position.sqrtPriceBound;
            if (!state.crossTick(step, snapshot, pool, zeroForOne, sqrtPriceLimitX96)) break;
            if (state.sqrtPriceX96 == sqrtPriceBound) {
                (,, activeLiquidityDelta) = snapshot.getBurnAmounts(state.sqrtPriceX96, shares, zeroForOne);
            }
        }

        // Add what the sale of the burn's tokenIn buys to its tokenOut.
        amountOut += state.amountOut;
    }

    /* //////////////////////////////////////////////////////////////
                                    MAX
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the most of an amount of shares whose redeem sells its tokenIn within the core's max swap cost.
     * @param snapshot The core's snapshot.
     * @param pool The Metadex CL pool.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param shares The most aLP shares the redeem burns.
     * @return The aLP shares.
     * @dev The sale walks the pool's liquidity less the shares' part of the core's.
     */
    function maxRedeem(Snapshot memory snapshot, address pool, bool zeroForOne, uint256 shares)
        internal
        view
        returns (uint256)
    {
        // Get the tokenIn a burn of the whole supply releases at spot, without which no redeem sells.
        (uint256 amountBurnIn,,) = snapshot.getBurnAmounts(snapshot.sqrtPriceX96, snapshot.supply, zeroForOne);
        if (amountBurnIn == 0) return shares;

        // Walk the pool's swap steps to the price limit, summing the tokenIn they take.
        uint160 sqrtPriceLimitX96 = snapshot.getSwapCostLimit(zeroForOne);
        SwapState memory state = SwapStateLib.getSwapState(snapshot, pool, zeroForOne);
        StepComputations memory step;
        while (state.liquidity > 0) {
            step.setNextTick(state, pool, zeroForOne, sqrtPriceLimitX96);
            (step.sqrtPriceTargetX96, step.amountIn, step.amountOut, step.feeAmount) = MetadexSwapMath.computeSwapStep(
                state.sqrtPriceX96,
                step.sqrtPriceTargetX96,
                uint128(
                    uint256(state.liquidity)
                        .zeroFloorSub(state.position.liquidity.fullMulDivUp(shares, snapshot.supply))
                ),
                type(int256).max,
                state.fee
            );
            if (!state.crossTick(step, snapshot, pool, zeroForOne, sqrtPriceLimitX96)) break;
        }

        // Convert the tokenIn to shares, pro rata to the whole supply's tokenIn and its floors.
        return FixedPointMathLib.min(
            shares, state.amountIn.fullMulDiv(snapshot.supply, amountBurnIn + 2 * snapshot.ranges.length)
        );
    }
}
