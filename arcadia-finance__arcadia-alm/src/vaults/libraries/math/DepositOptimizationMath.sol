/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { CLMath } from "../../../shared/libraries/math/CLMath.sol";
import { EquivalentPosition } from "../../types/EquivalentPosition.sol";
import { EquivalentPositionMath } from "./EquivalentPositionMath.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { PoolLogic } from "../../../shared/libraries/logic/PoolLogic.sol";
import { QuadraticMath } from "./QuadraticMath.sol";
import { Snapshot, SnapshotLib } from "../../types/Snapshot.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { StepComputations, SwapState, SwapStateLib } from "../../types/SwapState.sol";

/**
 * @title Deposit Optimization Math.
 * @author Pragma Labs
 * @notice Quotes a deposit: the swap after which its balances match the core's composition, with the most tokenIn it takes.
 */
// forge-lint: disable-next-item(require-revert-in-loop, uninitialized-local, unsafe-typecast)
library DepositOptimizationMath {
    using EquivalentPositionMath for EquivalentPosition;
    using FixedPointMathLib for uint256;
    using SnapshotLib for Snapshot;
    using SwapStateLib for StepComputations;
    using SwapStateLib for SwapState;

    /* //////////////////////////////////////////////////////////////
                                 CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The maximal balance relative to the liquidity of the pool, with 192 binary precision.
    uint256 internal constant MAX_NORMALIZED = 1 << 252;

    /* //////////////////////////////////////////////////////////////
                                   ERRORS
    ////////////////////////////////////////////////////////////// */

    error AmountInTooLarge();

    /* //////////////////////////////////////////////////////////////
                                    SWAP
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the swap of tokenIn after which the balances match the composition of the ranges and the idle tokens.
     * @param snapshot The core's snapshot, whose fees rise by those the swap earns the core.
     * @param pool The Metadex CL pool.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param balanceIn The balance of tokenIn before the swap.
     * @return sqrtPriceNew The square root of the pool price after the swap, with 96 binary precision.
     * @return amountIn The tokenIn the swap costs, its fee included.
     * @return amountOut The amount of tokenOut, zero when the pool has no liquidity or the balances need none of it.
     * @dev Walks the pool's swap steps and solves in the step where the optimal swap lies.
     */
    function computeSwap(Snapshot memory snapshot, address pool, bool zeroForOne, uint256 balanceIn)
        internal
        view
        returns (uint160 sqrtPriceNew, uint256 amountIn, uint256 amountOut)
    {
        // Start at the pool's price, tick, liquidity and fees, and the core's equivalent position at spot.
        SwapState memory state = SwapStateLib.getSwapState(snapshot, pool, zeroForOne);
        state.feeShare = snapshot.getFeeShare(pool);

        // The mint's rounding margin on the position's tokenIn.
        uint256 roundingMargin;
        // Unchecked: the core holds at most MAX_RANGE_CAP ranges.
        unchecked {
            roundingMargin = 2 * snapshot.ranges.length + 4;
        }

        // Walk the pool's swap steps until the step that holds the optimal swap, and solve for it there.
        uint160 sqrtPriceLimitX96 = PoolLogic.sqrtPriceLimit(zeroForOne);
        StepComputations memory step;
        while (state.liquidity > 0) {
            // Compute the step, and take the balance's rounding margin off.
            step.setNextTick(state, pool, zeroForOne, sqrtPriceLimitX96);
            state.computeSwapStep(step, zeroForOne, true);
            uint256 balanceNet;
            // Unchecked: the rounding is below 2^69.
            unchecked {
                balanceNet = balanceIn.zeroFloorSub(snapshot.getRounding(step.sqrtPriceTargetX96, zeroForOne) + 3);
            }

            // Calculate the core's share of the step's fee.
            uint256 feesIn = state.getStepFees(step, true);

            // The optimal swap lies in this step if the balance runs out within it,
            bool last;
            last = state.amountIn + step.amountIn + step.feeAmount > balanceNet;
            if (!last) {
                // or if swapping through the whole step would buy more tokenOut than the position needs.
                (uint256 positionAmountIn, uint256 positionAmountOut) =
                    state.position.amountsAt(step.sqrtPriceTargetX96, zeroForOne);
                positionAmountIn += feesIn + roundingMargin;
                last = balanceNet
                    <= getBalanceIn(
                        state.amountIn + step.amountIn + step.feeAmount,
                        state.amountOut + step.amountOut,
                        positionAmountIn,
                        positionAmountOut
                    );
            }
            if (last) {
                // Solve for the optimal swap within this step.
                (sqrtPriceNew,) = getAmountOut(
                    zeroForOne, state, balanceNet.zeroFloorSub(state.amountIn), state.amountOut, roundingMargin
                );

                // End the step at the optimal price if it lies within it, else walk on.
                if (zeroForOne ? sqrtPriceNew > step.sqrtPriceTargetX96 : sqrtPriceNew < step.sqrtPriceTargetX96) {
                    step.sqrtPriceTargetX96 = sqrtPriceNew;
                    state.computeSwapStep(step, zeroForOne, true);
                    feesIn = state.getStepFees(step, true);
                }
            }

            // The core accrues its fees.
            state.accrueFees(snapshot, zeroForOne, feesIn);
            if (!state.crossTick(step, snapshot, pool, zeroForOne, sqrtPriceLimitX96)) break;
        }
        (sqrtPriceNew, amountIn, amountOut) = (state.sqrtPriceX96, state.amountIn, state.amountOut);
    }

    /* //////////////////////////////////////////////////////////////
                                  PREVIEW
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the shares a deposit mints.
     * @param snapshot The core's snapshot, whose fees rise by those the swap earns the core.
     * @param pool The Metadex CL pool.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param balanceIn The balance of tokenIn deposited.
     * @return shares The aLP shares the balances after the swap mint.
     */
    function previewDeposit(Snapshot memory snapshot, address pool, bool zeroForOne, uint256 balanceIn)
        internal
        view
        returns (uint256 shares)
    {
        // Calculate the swap, and the shares the balances left and bought mint at its end price.
        (uint160 sqrtPriceNew, uint256 amountSwapIn, uint256 amountSwapOut) =
            computeSwap(snapshot, pool, zeroForOne, balanceIn);
        shares = snapshot.getMintShares(sqrtPriceNew, balanceIn - amountSwapIn, amountSwapOut, zeroForOne);
    }

    /* //////////////////////////////////////////////////////////////
                                    MAX
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the most tokenIn a deposit takes with its swap ending at or before a price and its mint at most
     * a number of shares, for any fill of the swap.
     * @param snapshot The core's snapshot.
     * @param pool The Metadex CL pool.
     * @param sqrtPriceLimitX96 The square root of the price the deposit's swap may not pass, with 96 binary precision.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param shares The most aLP shares the core mints.
     * @return assets The amount of tokenIn.
     * @dev A deposit of assets mints at most assets * supply / V, with V the core's holdings valued in tokenIn at spot:
     *     its swap buys at no better than spot and the core's ranges sell along it at no worse.
     * @dev Its swap passes the limit only when its balances there hold more tokenIn than the core's position.
     */
    function maxDeposit(
        Snapshot memory snapshot,
        address pool,
        uint256 sqrtPriceLimitX96,
        bool zeroForOne,
        uint256 shares
    ) internal view returns (uint256 assets) {
        // Keep the swap within the core's max swap cost.
        sqrtPriceLimitX96 = zeroForOne
            ? FixedPointMathLib.max(sqrtPriceLimitX96, snapshot.getSwapCostLimit(true))
            : FixedPointMathLib.min(sqrtPriceLimitX96, snapshot.getSwapCostLimit(false));

        // Start at the pool's price, tick, liquidity and fees, and the core's equivalent position at spot.
        SwapState memory state = SwapStateLib.getSwapState(snapshot, pool, zeroForOne);
        state.feeShare = snapshot.getFeeShare(pool);
        {
            // Get the core's tokenIn and tokenOut at spot.
            (uint256 amountIn, uint256 amountOut) = state.position.amountsAt(snapshot.sqrtPriceX96, zeroForOne);

            // Cap the assets at the shares' value of the core in tokenIn, each token less n for amountsAt's floors.
            assets = shares.saturatingMul(
                amountIn.zeroFloorSub(snapshot.ranges.length)
                    + CLMath.convert(
                        snapshot.sqrtPriceX96, !zeroForOne, amountOut.zeroFloorSub(snapshot.ranges.length), false
                    )
            ) / snapshot.supply;

            // Without a swap the tokenIn alone mints, which it does only when the core takes no tokenOut.
            if (state.liquidity == 0 || amountOut == 0) {
                (, uint256 amountMintOut,) = snapshot.getMintAmounts(snapshot.sqrtPriceX96, snapshot.supply, zeroForOne);
                return amountMintOut == 0 ? assets : 0;
            }

            // No deposit mints when the most shares' part of the core's tokenOut mints none.
            amountOut = amountOut.fullMulDiv(shares, snapshot.supply);
            if (snapshot.getMintShares(snapshot.sqrtPriceX96, assets, amountOut, zeroForOne) == 0) return 0;
        }
        // Keep the price limit within the pool's range, and one short of it for the solve's floors.
        sqrtPriceLimitX96 = zeroForOne
            ? FixedPointMathLib.max(sqrtPriceLimitX96, PoolLogic.sqrtPriceLimit(true))
            : FixedPointMathLib.min(sqrtPriceLimitX96, PoolLogic.sqrtPriceLimit(false));
        sqrtPriceLimitX96 = zeroForOne
            ? FixedPointMathLib.min(sqrtPriceLimitX96 + 1, state.sqrtPriceX96)
            : FixedPointMathLib.max(sqrtPriceLimitX96 - 1, state.sqrtPriceX96);

        // Walk the pool's swap steps to the price limit, the core accruing its fees.
        StepComputations memory step;
        while (state.liquidity > 0) {
            // Compute the step and accrue the core's fees, rounding the step to the limit down as the solve does.
            step.setNextTick(state, pool, zeroForOne, uint160(sqrtPriceLimitX96));
            {
                bool roundUp = step.sqrtPriceTargetX96 != sqrtPriceLimitX96;
                state.computeSwapStep(step, zeroForOne, roundUp);
                state.accrueFees(snapshot, zeroForOne, state.getStepFees(step, roundUp));
            }
            if (!state.crossTick(step, snapshot, pool, zeroForOne, uint160(sqrtPriceLimitX96))) break;
        }

        // A swap that runs out of pool liquidity ends before the limit.
        if (state.sqrtPriceX96 != sqrtPriceLimitX96) return assets;

        // Cap the assets at the deposit whose optimal swap ends exactly at the limit.
        (uint256 positionAmountIn, uint256 positionAmountOut) = EquivalentPositionMath.amountsAt(
            snapshot.getPosition(uint160(sqrtPriceLimitX96), zeroForOne), uint160(sqrtPriceLimitX96), zeroForOne
        );
        // Take 1 off the position's tokenIn and add 1 to its tokenOut.
        assets = FixedPointMathLib.min(
            assets,
            getBalanceIn(state.amountIn, state.amountOut, positionAmountIn.zeroFloorSub(1), positionAmountOut + 1)
        );
    }

    /* //////////////////////////////////////////////////////////////
                                  HELPERS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the largest deposit whose optimal swap ends at or before a price.
     * @param amountIn The tokenIn a swap to the price costs, its fee included.
     * @param amountOut The tokenOut a swap to the price buys.
     * @param positionAmountIn The tokenIn the core's position holds at the price.
     * @param positionAmountOut The tokenOut the core's position holds at the price.
     * @return balanceIn The deposit in tokenIn, type(uint256).max when the position holds no tokenOut or it does not fit.
     * @dev Swapped to the price, this deposit leaves tokenIn and tokenOut in the position's ratio.
     */
    function getBalanceIn(uint256 amountIn, uint256 amountOut, uint256 positionAmountIn, uint256 positionAmountOut)
        internal
        pure
        returns (uint256 balanceIn)
    {
        if (positionAmountOut == 0) return type(uint256).max;
        balanceIn = amountIn.saturatingAdd(amountOut.fullMulDiv(positionAmountIn, positionAmountOut));
    }

    /**
     * @notice Calculates the amountOut of a swap of tokenIn, after which the balances match the equivalent position.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param state The swap's state at the step: its price, liquidity, fee, the share of fees kept and the core's position.
     * @param balanceIn The balance of tokenIn before the swap.
     * @param balanceOut The balance of tokenOut before the swap.
     * @param roundingMargin The rounding margin on the position's tokenIn.
     * @return sqrtPriceNew The square root of the pool price after the swap of amountOut, at most the position's bound.
     * @return amountOut The amount of tokenOut.
     * @dev Requires a nonzero liquidity.
     */
    function getAmountOut(
        bool zeroForOne,
        SwapState memory state,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 roundingMargin
    ) internal pure returns (uint160 sqrtPriceNew, uint256 amountOut) {
        // Calculate the new sqrtPrice at which the balances match the position.
        sqrtPriceNew = getSqrtPrice(zeroForOne, state, balanceIn, balanceOut, roundingMargin);

        // The largest amountOut reaching that price, at most where the whole balance of tokenIn, net of fee, moves it.
        uint256 balanceInLessFee;
        // Unchecked: the pool's fee is at most 100_000.
        unchecked {
            balanceInLessFee = balanceIn.fullMulDiv(1e6 - state.fee, 1e6);
        }
        if (zeroForOne) {
            // Stop at the price balanceInLessFee reaches.
            sqrtPriceNew = uint160(
                FixedPointMathLib.max(
                    sqrtPriceNew,
                    SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
                        state.sqrtPriceX96, state.liquidity, balanceInLessFee, true
                    )
                )
            );
            amountOut = SqrtPriceMath.getAmount1Delta(sqrtPriceNew, state.sqrtPriceX96, state.liquidity, false);
        } else {
            // Unchecked: getSqrtPrice bounds the balance's move at 2^60 times the price.
            unchecked {
                sqrtPriceNew = uint160(
                    FixedPointMathLib.min(
                        sqrtPriceNew, state.sqrtPriceX96 + balanceInLessFee.fullMulDiv(1 << 96, state.liquidity)
                    )
                );
            }
            amountOut = SqrtPriceMath.getAmount0Delta(state.sqrtPriceX96, sqrtPriceNew, state.liquidity, false);
        }

        // Short of the bound, the step ends at the price its amountOut moves the pool to.
        if (sqrtPriceNew != state.position.sqrtPriceBound) {
            sqrtPriceNew =
                SqrtPriceMath.getNextSqrtPriceFromOutput(state.sqrtPriceX96, state.liquidity, amountOut, zeroForOne);
        }
    }

    /**
     * @notice Calculates the new sqrtPrice after the swap, at which the balances match the equivalent position.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param state The swap's state at the step: its price, liquidity, fee, the share of fees kept and the core's position.
     * @param balanceIn The balance of tokenIn before the swap.
     * @param balanceOut The balance of tokenOut before the swap.
     * @param roundingMargin The rounding margin on the position's tokenIn.
     * @return sqrtPriceNew The sqrtPrice at which the balances match the equivalent position, with 96 binary precision.
     * @dev The position's amounts at s, d0 = W / s − c0 and d1 = W * s − c1, take the place of a range's bounds.
     *     The quadratic is written in the move of the square root price of tokenIn, s = s0 * (1 − δ) for zeroForOne and
     *     s = s0 / (1 − δ) for oneForZero, where its coefficients are nonnegative for either sign of c0 and c1.
     */
    function getSqrtPrice(
        bool zeroForOne,
        SwapState memory state,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 roundingMargin
    ) internal pure returns (uint160 sqrtPriceNew) {
        // Solve the quadratic for the relative move of the square root price of tokenIn.
        (int256 quadraticCoefficient, int256 linearCoefficient, int256 constantCoefficient) =
            getQuadraticCoefficients(zeroForOne, state, balanceIn, balanceOut, roundingMargin);
        uint256 sqrtPriceDelta = QuadraticMath.getRoot(quadraticCoefficient, linearCoefficient, constantCoefficient);

        // Move the square root price of tokenIn by the root, at most to the position's bound.
        sqrtPriceNew =
            CLMath.getNextSqrtPrice(zeroForOne, state.sqrtPriceX96, state.position.sqrtPriceBound, sqrtPriceDelta);
    }

    /**
     * @notice Calculates the quadratic in the relative move of the square root price of tokenIn, cleared of its denominators.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param state The swap's state at the step: its price, liquidity, fee, the share of fees kept and the core's position.
     * @param balanceIn The balance of tokenIn before the swap.
     * @param balanceOut The balance of tokenOut before the swap.
     * @param roundingMargin The rounding margin on the position's tokenIn.
     * @return quadraticCoefficient The quadratic coefficient, with 192 binary precision.
     * @return linearCoefficient The linear coefficient, with 192 binary precision.
     * @return constantCoefficient The constant coefficient, with 192 binary precision.
     * @dev (α * m − κ * δ) * (εOut − ω * δ) = (β + δ) * (εIn + (ω + ρ − εIn) * δ) with m = 1 − δ expands to
     *     A * δ² − B * δ + C = 0, A = (α + κ − 1) * ω + εIn − ρ and B = C + (α + β) * ω + κ * εOut + εIn + β * ρ.
     * @dev ρ = (κ − 1) * φ * ωU is the fee the position's unstaked liquidity ωU earns on the step.
     * @dev C = α * εOut − β * εIn.
     */
    function getQuadraticCoefficients(
        bool zeroForOne,
        SwapState memory state,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 roundingMargin
    ) internal pure returns (int256 quadraticCoefficient, int256 linearCoefficient, int256 constantCoefficient) {
        // Calculate the balances relative to the pool liquidity, and the position relative to its largest part.
        (
            uint256 balanceInNormalized,
            uint256 balanceOutNormalized,
            uint256 positionLiquidityNormalized,
            uint256 positionAmountInNormalized,
            uint256 positionAmountOutNormalized,
            uint256 feeTerm
        ) = getNormalizedParameters(zeroForOne, state, balanceIn, balanceOut, roundingMargin);

        // Calculate the coefficients from the normalized balances, the fee and the normalized position.
        // Unchecked: the balances are at most MAX_NORMALIZED and the position's terms at most 2^192.
        unchecked {
            // C = α * εOut − β * εIn
            constantCoefficient = int256(balanceInNormalized.fullMulDivN(positionAmountOutNormalized, 192))
                - int256(balanceOutNormalized.fullMulDivN(positionAmountInNormalized, 192)); // 192 binary precision.

            // The ratio of the gross to the net amountIn: κ = 1 / (1 − fee)
            uint256 feeFactor = (1e6 << 192) / (1e6 - state.fee); // 192 binary precision.

            // A = (α + κ − 1) * ω + εIn
            quadraticCoefficient = int256(
                (balanceInNormalized + feeFactor - (1 << 192)).fullMulDivN(positionLiquidityNormalized, 192)
                + positionAmountInNormalized
            );

            // B = C + (α + β) * ω + κ * εOut + εIn
            linearCoefficient = constantCoefficient
                + int256(
                    (balanceInNormalized + balanceOutNormalized).fullMulDivN(positionLiquidityNormalized, 192)
                        + feeFactor.fullMulDivN(positionAmountOutNormalized, 192) + positionAmountInNormalized
                );

            // ρ, less in A and, times β, more in B.
            quadraticCoefficient -= int256(feeTerm);
            linearCoefficient += int256(balanceOutNormalized.fullMulDivN(feeTerm, 192));
        }
    }

    /**
     * @notice Expresses the swap and position parameters as the dimensionless quantities the quadratic is written in.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param state The swap's state at the step: its price, liquidity, fee, the share of fees kept and the core's position.
     * @param balanceIn The balance of tokenIn before the swap.
     * @param balanceOut The balance of tokenOut before the swap.
     * @param roundingMargin The rounding margin on the position's tokenIn.
     * @return balanceInNormalized The balance of tokenIn relative to the liquidity of the pool, with 192 binary precision.
     * @return balanceOutNormalized The balance of tokenOut relative to the liquidity of the pool, with 192 binary precision.
     * @return positionLiquidityNormalized The liquidity of the position relative to its largest part, with 192 binary precision.
     * @return positionAmountInNormalized The tokenIn the position holds relative to its largest part, with 192 binary precision.
     * @return positionAmountOutNormalized The tokenOut the position holds relative to its largest part, with 192 binary precision.
     * @return feeTerm The fee the position's unstaked liquidity earns per move, ρ, with 192 binary precision.
     * @dev The quadratic is homogeneous in the position, so the position is normalized by its own largest part.
     */
    function getNormalizedParameters(
        bool zeroForOne,
        SwapState memory state,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 roundingMargin
    )
        internal
        pure
        returns (
            uint256 balanceInNormalized,
            uint256 balanceOutNormalized,
            uint256 positionLiquidityNormalized,
            uint256 positionAmountInNormalized,
            uint256 positionAmountOutNormalized,
            uint256 feeTerm
        )
    {
        // The position in units of liquidity: W, d0 * s0 and d1 / s0, each with 64 binary precision.
        {
            (uint256 positionAmountIn, uint256 positionAmountOut) =
                state.position.amountsAt(state.sqrtPriceX96, zeroForOne);
            positionAmountIn += roundingMargin;
            positionLiquidityNormalized = state.position.liquidity << 64;
            positionAmountInNormalized = zeroForOne
                ? positionAmountIn.fullMulDivN(state.sqrtPriceX96, 32)
                : positionAmountIn.fullMulDiv(1 << 160, state.sqrtPriceX96);
            positionAmountOutNormalized = zeroForOne
                ? positionAmountOut.fullMulDiv(1 << 160, state.sqrtPriceX96)
                : positionAmountOut.fullMulDivN(state.sqrtPriceX96, 32);
        }

        // The position relative to its largest part.
        {
            uint256 largest = FixedPointMathLib.max(
                FixedPointMathLib.max(positionLiquidityNormalized, positionAmountInNormalized),
                FixedPointMathLib.max(positionAmountOutNormalized, 1)
            );
            positionLiquidityNormalized = positionLiquidityNormalized.fullMulDiv(1 << 192, largest); // 192 binary precision.
            positionAmountInNormalized = positionAmountInNormalized.fullMulDiv(1 << 192, largest); // 192 binary precision.
            positionAmountOutNormalized = positionAmountOutNormalized.fullMulDiv(1 << 192, largest); // 192 binary precision.
        }

        // The fee the position's unstaked liquidity earns: ρ = (κ − 1) * φ * ωU, with κ − 1 = fee / (1 − fee) and φ its share kept.
        if (state.position.unstakedLiquidity > 0) {
            // Unchecked: the liquidities are below 2^132, the fee share is at most 1e10 and the fee at most 100_000.
            unchecked {
                feeTerm = positionLiquidityNormalized.fullMulDiv(
                    state.position.unstakedLiquidity * state.feeShare, state.position.liquidity * 1e10
                );
                feeTerm = ((uint256(state.fee) << 192) / (1e6 - state.fee)).fullMulDivN(feeTerm, 192); // 192 binary precision.
            }
        }

        // The balances in units of the pool liquidity, dividing by L before s0: a0 * s0 / L and a1 / (L * s0)
        balanceInNormalized = zeroForOne
            ? balanceIn.fullMulDiv(uint256(state.sqrtPriceX96) << 96, state.liquidity)
            : balanceIn.fullMulDiv(1 << 128, state.liquidity).fullMulDiv(1 << 160, state.sqrtPriceX96); // 192 binary precision.
        balanceOutNormalized = zeroForOne
            ? balanceOut.fullMulDiv(1 << 128, state.liquidity).fullMulDiv(1 << 160, state.sqrtPriceX96)
            : balanceOut.fullMulDiv(uint256(state.sqrtPriceX96) << 96, state.liquidity); // 192 binary precision.

        // Checks.
        if (balanceInNormalized > MAX_NORMALIZED || balanceOutNormalized > MAX_NORMALIZED) revert AmountInTooLarge();
    }
}
