/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { EquivalentPosition } from "./EquivalentPosition.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IMetadexCLPool } from "../../interfaces/IMetadexCLPool.sol";
import { MetadexTickBitmap } from "../../shared/libraries/vendored/MetadexTickBitmap.sol";
import { PoolLogic } from "../../shared/libraries/logic/PoolLogic.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { Snapshot, SnapshotLib } from "./Snapshot.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { SwapMath } from "@uniswap/v4-core/src/libraries/SwapMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice The state of a swap as it walks the pool's swap steps.
 */
struct SwapState {
    // The pool's sqrt price.
    uint160 sqrtPriceX96;
    // The pool's tick.
    int24 tick;
    // The pool's liquidity at the price.
    uint128 liquidity;
    // The pool's tick spacing.
    int24 tickSpacing;
    // The pool's fee, with 6 decimals precision.
    uint24 fee;
    // The share of its fees the unstaked liquidity keeps, net of levy and protocol share, with 10 decimals precision.
    uint256 feeShare;
    // The tokenIn the swap has taken so far, its fees included.
    uint256 amountIn;
    // The tokenOut the swap has paid so far.
    uint256 amountOut;
    // The core's equivalent position at the price.
    EquivalentPosition position;
}

/**
 * @notice A swap step, as the pool's swap computes it.
 */
struct StepComputations {
    // The next initialized tick or bitmap word end in the swap's direction.
    int24 tickNext;
    // True when tickNext is initialized.
    bool initialized;
    // The sqrt price at tickNext.
    uint160 sqrtPriceNextX96;
    // The sqrt price the step swaps to: sqrtPriceNextX96, not past the price limit.
    uint160 sqrtPriceTargetX96;
    // The tokenIn the step takes, without its fee.
    uint256 amountIn;
    // The tokenOut the step pays.
    uint256 amountOut;
    // The fee the step takes.
    uint256 feeAmount;
}

/**
 * @title Swap State Library.
 * @author Pragma Labs
 * @notice Walks a swap's state through the pool's swap steps, with the core's equivalent position along it.
 */
library SwapStateLib {
    using FixedPointMathLib for uint256;
    using SnapshotLib for Snapshot;

    /* //////////////////////////////////////////////////////////////
                                    SWAP
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Starts a swap at the pool's price, tick, fee, liquidity and tick spacing, and the core's position there.
     * @param snapshot The core's snapshot.
     * @param pool The Metadex CL pool.
     * @param zeroForOne True when token0 is swapped for token1.
     * @return state The swap's state at its first step.
     */
    function getSwapState(Snapshot memory snapshot, address pool, bool zeroForOne)
        internal
        view
        returns (SwapState memory state)
    {
        (state.sqrtPriceX96, state.tick, state.fee) = (snapshot.sqrtPriceX96, snapshot.tick, snapshot.fee);
        (state.liquidity, state.tickSpacing) = (PoolLogic.liquidity(pool), IMetadexCLPool(pool).tickSpacing());
        state.position = snapshot.getPosition(snapshot.sqrtPriceX96, zeroForOne);
    }

    /**
     * @notice Sets the step's next tick: the next initialized tick or bitmap word end, and the price the step swaps to.
     * @param step The step.
     * @param state The swap's state.
     * @param pool The Metadex CL pool.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param sqrtPriceLimitX96 The square root of the price the swap may not pass, with 96 binary precision.
     */
    function setNextTick(
        StepComputations memory step,
        SwapState memory state,
        address pool,
        bool zeroForOne,
        uint160 sqrtPriceLimitX96
    ) internal view {
        (step.tickNext, step.initialized) = MetadexTickBitmap.nextInitializedTickWithinOneWord(
            pool, state.tick, state.tickSpacing, zeroForOne
        );

        // Keep the tick within MIN_TICK and MAX_TICK, as the pool's swap does.
        if (step.tickNext < TickMath.MIN_TICK) step.tickNext = TickMath.MIN_TICK;
        else if (step.tickNext > TickMath.MAX_TICK) step.tickNext = TickMath.MAX_TICK;

        step.sqrtPriceNextX96 = TickMath.getSqrtPriceAtTick(step.tickNext);
        step.sqrtPriceTargetX96 = SwapMath.getSqrtPriceTarget(zeroForOne, step.sqrtPriceNextX96, sqrtPriceLimitX96);
    }

    /**
     * @notice Computes the step's input, fee and output from the pool's price to the step's target.
     * @param state The swap's state.
     * @param step The step.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param roundUp True to round the input and the fee up, as the pool's swap does.
     */
    function computeSwapStep(SwapState memory state, StepComputations memory step, bool zeroForOne, bool roundUp)
        internal
        pure
    {
        (uint160 sqrtPrice, uint160 sqrtPriceTarget, uint128 liquidity) =
            (state.sqrtPriceX96, step.sqrtPriceTargetX96, state.liquidity);
        step.amountIn = zeroForOne
            ? SqrtPriceMath.getAmount0Delta(sqrtPriceTarget, sqrtPrice, liquidity, roundUp)
            : SqrtPriceMath.getAmount1Delta(sqrtPrice, sqrtPriceTarget, liquidity, roundUp);
        // Unchecked: the pool's fee is at most 100_000.
        unchecked {
            step.feeAmount = roundUp
                ? step.amountIn.fullMulDivUp(state.fee, 1e6 - state.fee)
                : step.amountIn.fullMulDiv(state.fee, 1e6 - state.fee);
        }
        step.amountOut = zeroForOne
            ? SqrtPriceMath.getAmount1Delta(sqrtPriceTarget, sqrtPrice, liquidity, false)
            : SqrtPriceMath.getAmount0Delta(sqrtPrice, sqrtPriceTarget, liquidity, false);
    }

    /**
     * @notice Calculates the share of the step's fee the core's unstaked liquidity in range keeps.
     * @param state The swap's state.
     * @param step The step.
     * @param roundUp True to round the fee share up.
     * @return feesIn The fee share, in tokenIn.
     */
    function getStepFees(SwapState memory state, StepComputations memory step, bool roundUp)
        internal
        pure
        returns (uint256 feesIn)
    {
        // Unchecked: a step's fee is below 2^189, the fee share at most 1e10 and the liquidity a uint128.
        unchecked {
            feesIn = roundUp
                ? (step.feeAmount * state.feeShare)
                .fullMulDivUp(state.position.unstakedLiquidity, 1e10 * uint256(state.liquidity))
                : (step.feeAmount * state.feeShare)
                .fullMulDiv(state.position.unstakedLiquidity, 1e10 * uint256(state.liquidity));
        }
    }

    /**
     * @notice Accrues a fee share to the core: its fees and the tokenIn its position holds rise by it.
     * @param state The swap's state.
     * @param snapshot The core's snapshot.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param feesIn The fee share, in tokenIn.
     */
    function accrueFees(SwapState memory state, Snapshot memory snapshot, bool zeroForOne, uint256 feesIn)
        internal
        pure
    {
        if (zeroForOne) {
            state.position.constant0 -= SafeCastLib.toInt256(feesIn);
            snapshot.fees0 += feesIn;
        } else {
            state.position.constant1 -= SafeCastLib.toInt256(feesIn);
            snapshot.fees1 += feesIn;
        }
    }

    /**
     * @notice Swaps to the step's target and crosses its tick short of the limit, renewing the core's position at its edge.
     * @param state The swap's state.
     * @param step The step.
     * @param snapshot The core's snapshot.
     * @param pool The Metadex CL pool.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param sqrtPriceLimitX96 The square root of the price the swap may not pass, with 96 binary precision.
     * @return True when the swap goes on past the step.
     */
    function crossTick(
        SwapState memory state,
        StepComputations memory step,
        Snapshot memory snapshot,
        address pool,
        bool zeroForOne,
        uint160 sqrtPriceLimitX96
    ) internal view returns (bool) {
        // Swap to the step's target.
        state.sqrtPriceX96 = step.sqrtPriceTargetX96;
        state.amountIn += step.amountIn + step.feeAmount;
        state.amountOut += step.amountOut;

        // Shift the tick if the step reached the next price short of the limit, else the swap ends.
        if (state.sqrtPriceX96 != step.sqrtPriceNextX96 || state.sqrtPriceX96 == sqrtPriceLimitX96) return false;
        if (step.initialized) {
            int256 liquidityNet = PoolLogic.liquidityNet(pool, step.tickNext);
            // Unchecked: the liquidity is a uint128 and the liquidity net an int128.
            unchecked {
                state.liquidity = SafeCastLib.toUint128(
                    SafeCastLib.toUint256(
                        int256(uint256(state.liquidity)) + (zeroForOne ? -liquidityNet : liquidityNet)
                    )
                );
            }
        }
        // Unchecked: setNextTick clamps tickNext to the pool's tick range.
        unchecked {
            state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
        }

        // Renew the core's position at its edge.
        if (state.sqrtPriceX96 == state.position.sqrtPriceBound) {
            state.position = snapshot.getPosition(state.sqrtPriceX96, zeroForOne);
        }
        return true;
    }
}
