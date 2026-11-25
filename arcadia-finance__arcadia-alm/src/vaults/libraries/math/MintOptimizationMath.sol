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
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { StepComputations, SwapState, SwapStateLib } from "../../types/SwapState.sol";

/**
 * @title Mint Optimization Math.
 * @author Pragma Labs
 * @notice Quotes a mint: the buy that covers its tokenOut, with the most shares it takes.
 */
// forge-lint: disable-next-item(uninitialized-local, unsafe-typecast)
library MintOptimizationMath {
    using FixedPointMathLib for uint256;
    using SnapshotLib for Snapshot;
    using SwapStateLib for StepComputations;
    using SwapStateLib for SwapState;

    /* //////////////////////////////////////////////////////////////
                                    SWAP
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the buy of tokenOut a mint of shares makes.
     * @param snapshot The core's snapshot, whose fees rise by those the swap earns the core.
     * @param pool The Metadex CL pool.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param shares The aLP shares minted.
     * @return sqrtPriceNew The square root of the pool price after the buy, with 96 binary precision.
     * @return amountIn The tokenIn the buy costs, its fee included.
     * @return amountOut The amount of tokenOut the mint buys, zero when the mint takes no tokenOut.
     * @dev Walks the pool's swap steps to the step where the buy covers the tokenOut the mint takes, and solves there.
     */
    function computeSwap(Snapshot memory snapshot, address pool, bool zeroForOne, uint256 shares)
        internal
        view
        returns (uint160 sqrtPriceNew, uint256 amountIn, uint256 amountOut)
    {
        // Start at the pool's price, tick, liquidity and fees, and the core's equivalent position at spot.
        SwapState memory state = SwapStateLib.getSwapState(snapshot, pool, zeroForOne);
        state.feeShare = snapshot.getFeeShare(pool);

        // Get the tokenOut the mint needs at spot, and its liquidity the buy trades against.
        (uint256 amountMintOut, uint256 activeLiquidityDelta) =
            getMintAmountOut(snapshot, snapshot.sqrtPriceX96, zeroForOne, shares);

        // Walk the pool's swap steps until the step where the buy covers the mint, and solve for the exact buy there.
        uint160 sqrtPriceLimitX96 = PoolLogic.sqrtPriceLimit(zeroForOne);
        StepComputations memory step;
        while (amountMintOut > state.amountOut && state.liquidity > 0) {
            step.setNextTick(state, pool, zeroForOne, sqrtPriceLimitX96);
            {
                // Compute the step, and how much the mint's tokenOut need drops over it.
                state.computeSwapStep(step, zeroForOne, true);
                uint256 amountMintOutDelta = zeroForOne
                    ? SqrtPriceMath.getAmount1Delta(
                        step.sqrtPriceTargetX96, state.sqrtPriceX96, SafeCastLib.toUint128(activeLiquidityDelta), false
                    )
                    : SqrtPriceMath.getAmount0Delta(
                        state.sqrtPriceX96, step.sqrtPriceTargetX96, SafeCastLib.toUint128(activeLiquidityDelta), false
                    );

                // The buy covers the mint in this step: end it at the exact buy, y = (need − bought) − K * y / L.
                if (state.amountOut + step.amountOut + amountMintOutDelta >= amountMintOut) {
                    (step.sqrtPriceTargetX96, step.amountIn, step.amountOut, step.feeAmount) =
                        MetadexSwapMath.computeSwapStep(
                            state.sqrtPriceX96,
                            step.sqrtPriceTargetX96,
                            state.liquidity,
                            -SafeCastLib.toInt256(
                                (amountMintOut - state.amountOut)
                                .fullMulDivUp(state.liquidity, uint256(state.liquidity) + activeLiquidityDelta)
                            ),
                            state.fee
                        );
                }
                amountMintOut = amountMintOut.zeroFloorSub(amountMintOutDelta);
            }

            // The core accrues its fees.
            state.accrueFees(snapshot, zeroForOne, state.getStepFees(step, true));

            // At the core's edge, recompute the mint's tokenOut need for the next position.
            uint160 sqrtPriceBound = state.position.sqrtPriceBound;
            if (!state.crossTick(step, snapshot, pool, zeroForOne, sqrtPriceLimitX96)) break;
            if (state.sqrtPriceX96 == sqrtPriceBound) {
                (amountMintOut, activeLiquidityDelta) =
                    getMintAmountOut(snapshot, state.sqrtPriceX96, zeroForOne, shares);
                // Spot moves to the edge only with a buy, of at least a wei.
                if (amountMintOut == 0) amountMintOut = 1;
            }
        }
        (sqrtPriceNew, amountIn, amountOut) = (state.sqrtPriceX96, state.amountIn, state.amountOut);
    }

    /* //////////////////////////////////////////////////////////////
                                  PREVIEW
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the tokenIn a mint of shares costs.
     * @param snapshot The core's snapshot, whose fees rise by those the swap earns the core.
     * @param pool The Metadex CL pool.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param shares The aLP shares minted.
     * @return assets The tokenIn the mint costs, its buy included.
     */
    function previewMint(Snapshot memory snapshot, address pool, bool zeroForOne, uint256 shares)
        internal
        view
        returns (uint256 assets)
    {
        // The tokenIn the buy of the mint's tokenOut costs, and the tokenIn the mint takes at the buy's end price.
        (uint160 sqrtPriceNew, uint256 amountSwapIn,) = computeSwap(snapshot, pool, zeroForOne, shares);
        (uint256 amountMintIn,,) = snapshot.getMintAmounts(sqrtPriceNew, shares, zeroForOne);
        assets = amountSwapIn + amountMintIn;
    }

    /* //////////////////////////////////////////////////////////////
                                    MAX
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the most shares whose buy of tokenOut ends at or before a price.
     * @param snapshot The core's snapshot.
     * @param pool The Metadex CL pool.
     * @param sqrtPriceLimitX96 The square root of the price the buy may not pass, with 96 binary precision.
     * @param zeroForOne True when token0 is swapped for token1.
     * @return shares The aLP shares, type(uint256).max when no mint takes tokenOut.
     * @dev The buy covers the mint where bought ≥ need, which holds at the walk's end for shares up to the tokenOut
     *     bought there over that of the whole supply.
     */
    function maxMint(Snapshot memory snapshot, address pool, uint256 sqrtPriceLimitX96, bool zeroForOne)
        internal
        view
        returns (uint256 shares)
    {
        // Calculate the tokenOut a mint of the whole supply takes at spot, without which no mint buys.
        (, uint256 amountMintOutSpot,) = snapshot.getMintAmounts(snapshot.sqrtPriceX96, snapshot.supply, zeroForOne);
        if (amountMintOutSpot == 0) return type(uint256).max;

        // Keep the swap within the core's max swap cost.
        sqrtPriceLimitX96 = zeroForOne
            ? FixedPointMathLib.max(sqrtPriceLimitX96, snapshot.getSwapCostLimit(true))
            : FixedPointMathLib.min(sqrtPriceLimitX96, snapshot.getSwapCostLimit(false));

        // Start at the pool's price, tick and liquidity.
        SwapState memory state = SwapStateLib.getSwapState(snapshot, pool, zeroForOne);

        // Walk the pool's swap steps to the price limit, or to where its liquidity runs out, summing the tokenOut.
        uint256 steps;
        {
            StepComputations memory step;
            while (state.liquidity > 0) {
                // Buy the step's tokenOut, rounded down as the pool pays it.
                step.setNextTick(state, pool, zeroForOne, uint160(sqrtPriceLimitX96));
                state.computeSwapStep(step, zeroForOne, false);
                ++steps;
                if (!state.crossTick(step, snapshot, pool, zeroForOne, uint160(sqrtPriceLimitX96))) break;
            }
        }

        // Without a buy, no mint is covered.
        if (state.amountOut == 0) return 0;

        // Calculate the tokenOut a mint of the whole supply takes at the walk's end.
        (, uint256 amountMintOutEnd,) = snapshot.getMintAmounts(state.sqrtPriceX96, snapshot.supply, zeroForOne);
        if (amountMintOutEnd == 0) return type(uint256).max;

        // previewMint's need over the mint's: per range a unit and 2 ceilings, the idle's ceiling, n, and 1 per step.
        uint256 rounding = snapshot.getRounding(snapshot.sqrtPriceX96, !zeroForOne) + steps;

        // Token0's amounts divide by J ≥ J0 = ⌊s0² / 2^96⌋, so each is at most 1 / J0 above its exact value.
        if (!zeroForOne) {
            uint256 priceX96 = uint256(snapshot.sqrtPriceX96).fullMulDivN(snapshot.sqrtPriceX96, 96);
            // J0 = 0 leaves the rounding of token0 unbounded.
            if (priceX96 == 0) return 0;
            // Ĉ = C + 2 * A + ⌈A / J0⌉, with A = ⌈C_spot / J0⌉.
            uint256 roundingSpot = amountMintOutSpot.divUp(priceX96);
            amountMintOutEnd += 2 * roundingSpot + roundingSpot.divUp(priceX96);
            // n * (2 * B + ⌈B / J0⌉ + 1) + 2, with B = ⌈u / J0⌉ for the liquidity units and the ceilings.
            uint256 roundingUnit = uint256(1 << 96).divUp(snapshot.sqrtPriceX96).divUp(priceX96);
            rounding += snapshot.ranges.length * (2 * roundingUnit + roundingUnit.divUp(priceX96) + 1) + 2;
        }

        // Leave room for the buy's last wei: it overshoots by up to 1 + K / L, with K / L ≤ shares / supply + 1.
        rounding += 2;

        // Subtract the rounding from the tokenOut the buy takes.
        if (state.amountOut <= rounding) return 0;

        // Convert the tokenOut to shares, pro rata to the tokenOut of the whole supply plus 1 for shares / supply.
        shares = (state.amountOut - rounding).fullMulDiv(snapshot.supply, amountMintOutEnd + 1);
    }

    /* //////////////////////////////////////////////////////////////
                                  HELPERS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the tokenOut a mint takes at a price, with the margins of its ceilings, and its liquidity in range.
     * @param snapshot The core's snapshot.
     * @param sqrtPriceX96 The square root of the pool price (token1/token0), with 96 binary precision.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param shares The aLP shares minted.
     * @return amountOut The tokenOut, zero when the mint takes none.
     * @return activeLiquidityDelta The mint's liquidity in the ranges the buy trades against.
     */
    function getMintAmountOut(Snapshot memory snapshot, uint160 sqrtPriceX96, bool zeroForOne, uint256 shares)
        internal
        pure
        returns (uint256 amountOut, uint256 activeLiquidityDelta)
    {
        (, amountOut, activeLiquidityDelta) = snapshot.getMintAmounts(sqrtPriceX96, shares, zeroForOne);

        // Add n for the price's ceilings and, for token0, the amount over J0 = floor(s0^2 / 2^96).
        if (amountOut > 0) {
            amountOut += snapshot.ranges.length
            + (zeroForOne ? 0 : amountOut.divUp(uint256(sqrtPriceX96).fullMulDivN(sqrtPriceX96, 96)));
        }
    }
}
