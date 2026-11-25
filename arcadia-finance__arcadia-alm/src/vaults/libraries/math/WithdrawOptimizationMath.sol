/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { EquivalentPositionMath } from "./EquivalentPositionMath.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IMetadexCLPool } from "../../../interfaces/IMetadexCLPool.sol";
import { PoolLogic } from "../../../shared/libraries/logic/PoolLogic.sol";
import { QuadraticMath } from "./QuadraticMath.sol";
import { RedeemOptimizationMath } from "./RedeemOptimizationMath.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { Snapshot, SnapshotLib } from "../../types/Snapshot.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { StepComputations, SwapState, SwapStateLib } from "../../types/SwapState.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @title Withdraw Optimization Math.
 * @author Pragma Labs
 * @notice Prices a burn of shares and the sale of the tokenIn it releases, for a withdraw.
 * @dev The sale's amounts are in tokens with 96 binary precision, so the pool's and the core's rounding stay exact.
 */
// forge-lint: disable-next-item(unsafe-typecast)
library WithdrawOptimizationMath {
    using FixedPointMathLib for uint256;
    using SnapshotLib for Snapshot;
    using SwapStateLib for StepComputations;
    using SwapStateLib for SwapState;

    /* //////////////////////////////////////////////////////////////
                                  PREVIEW
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the shares a withdraw of tokenOut burns, the burn's tokenIn sold for the rest of it.
     * @param snapshot The core's snapshot.
     * @param pool The Metadex CL pool.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param amountOut The tokenOut the withdraw pays.
     * @return shares The aLP shares burned, type(uint256).max when neither the burn nor the sale pays the withdraw.
     */
    function previewWithdraw(Snapshot memory snapshot, address pool, bool zeroForOne, uint256 amountOut)
        internal
        view
        returns (uint256 shares)
    {
        // Nothing pays nothing.
        if (amountOut == 0) return 0;

        // Start the sale at the pool's price, tick and liquidity.
        SwapState memory state = SwapStateLib.getSwapState(snapshot, pool, zeroForOne);

        // Get the tokens the whole supply releases at spot, less n for the equivalent position's floors: B and A.
        (uint256 holdingsIn, uint256 holdingsOut) =
            EquivalentPositionMath.amountsAt(state.position, snapshot.sqrtPriceX96, zeroForOne);
        (holdingsIn, holdingsOut) =
        (holdingsIn.zeroFloorSub(snapshot.ranges.length), holdingsOut.zeroFloorSub(snapshot.ranges.length));

        // Add the burn's rounding of tokenOut to the amount.
        amountOut += snapshot.getRounding(snapshot.sqrtPriceX96, !zeroForOne);

        // The burn alone.
        shares = amountOut > holdingsOut ? type(uint256).max : amountOut.fullMulDivUp(snapshot.supply, holdingsOut);
        if (holdingsIn == 0) return shares;

        // The sale's cost starts at the burn's rounding of tokenIn, all amounts with 96 binary precision.
        uint256 amountIn;
        // Unchecked: the rounding is below 2^69.
        unchecked {
            amountIn = snapshot.getRounding(snapshot.sqrtPriceX96, zeroForOne) * (1 << 96);
        }
        (holdingsIn, holdingsOut, amountOut) = (holdingsIn * (1 << 96), holdingsOut * (1 << 96), amountOut * (1 << 96));

        // Walk the pool's swap steps, keeping the fewest shares at their ends, to the step where the cost binds.
        uint160 sqrtPriceLimitX96 = PoolLogic.sqrtPriceLimit(zeroForOne);
        StepComputations memory step;
        while (state.liquidity > 0) {
            step.setNextTick(state, pool, zeroForOne, sqrtPriceLimitX96);
            if (step.sqrtPriceTargetX96 == state.sqrtPriceX96) {
                // A step that does not move the price rounds nothing.
                (step.amountIn, step.amountOut) = (0, 0);
            } else {
                // 2 + φ per step: the pool rounds the input up, and its fee up on that input.
                amountIn += ((2e6 - uint256(state.fee)) << 96).divUp(1e6 - uint256(state.fee));
                // 1 per step: the pool rounds the step's output down.
                amountOut += 1 << 96;

                (uint256 sharesStep, bool costBinds, uint256 holdingsInDelta, uint256 holdingsOutDelta) = getSharesForAmounts(
                    snapshot, zeroForOne, amountOut, holdingsIn, holdingsOut, state, step, amountIn
                );
                shares = FixedPointMathLib.min(shares, sharesStep);
                if (costBinds) {
                    // Past the whole supply's tokenIn or tokenOut, no later price pays within the supply.
                    if (amountIn > holdingsIn || amountOut - state.amountOut > holdingsOut + step.amountOut) {
                        return shares;
                    }
                    // The fewest shares lie at the two prices around where the cost starts to bind: the root and its neighbour.
                    // Unchecked: the sale's output so far is below the amount, a multiple of 2^96.
                    unchecked {
                        step.sqrtPriceTargetX96 = getSqrtPrice(
                            snapshot,
                            zeroForOne,
                            amountOut - state.amountOut + 1,
                            holdingsIn,
                            holdingsOut,
                            state,
                            step,
                            amountIn
                        );
                    }
                    (sharesStep, costBinds,,) = getSharesForAmounts(
                        snapshot, zeroForOne, amountOut, holdingsIn, holdingsOut, state, step, amountIn
                    );
                    shares = FixedPointMathLib.min(shares, sharesStep);
                    // Unchecked: the root lies between MIN_SQRT_PRICE and MAX_SQRT_PRICE.
                    unchecked {
                        step.sqrtPriceTargetX96 =
                            costBinds == zeroForOne ? step.sqrtPriceTargetX96 + 1 : step.sqrtPriceTargetX96 - 1;
                    }
                    (sharesStep,,,) = getSharesForAmounts(
                        snapshot, zeroForOne, amountOut, holdingsIn, holdingsOut, state, step, amountIn
                    );
                    return FixedPointMathLib.min(shares, sharesStep);
                }
                (holdingsIn, holdingsOut) = (holdingsIn + holdingsInDelta, holdingsOut.zeroFloorSub(holdingsOutDelta));
                amountIn += step.amountIn;
            }
            if (!state.crossTick(step, snapshot, pool, zeroForOne, sqrtPriceLimitX96)) break;
        }
    }

    /* //////////////////////////////////////////////////////////////
                                    MAX
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the most tokenOut a withdraw burning at most shares pays, within the core's max swap cost.
     * @param snapshot The core's snapshot.
     * @param pool The Metadex CL pool.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param shares The most aLP shares the withdraw burns.
     * @return amountOut The tokenOut, zero when the core holds tokenIn the pool cannot buy.
     */
    function maxWithdraw(Snapshot memory snapshot, address pool, bool zeroForOne, uint256 shares)
        internal
        view
        returns (uint256 amountOut)
    {
        // The most shares whose sale fills within the core's max swap cost.
        shares = RedeemOptimizationMath.maxRedeem(snapshot, pool, zeroForOne, shares);

        // The margins previewWithdraw prices a withdraw short by, in tokenIn and in tokenOut.
        uint160 sqrtPriceLimitX96 = snapshot.getSwapCostLimit(zeroForOne);
        uint256 roundingMarginIn;
        uint256 roundingMarginOut;
        {
            // The most steps of a sale to the band.
            uint256 steps;
            {
                int24 tickLimit = TickMath.getTickAtSqrtPrice(sqrtPriceLimitX96);
                uint256 ticks = uint256(
                    FixedPointMathLib.max(zeroForOne ? snapshot.tick - tickLimit : tickLimit - snapshot.tick, 0)
                );
                steps = ticks.divUp(uint256(int256(IMetadexCLPool(pool).tickSpacing()))) + 1;
            }

            // The tokenIn the sale is funded short by.
            uint128 ranges = uint128(snapshot.ranges.length);
            roundingMarginIn = (zeroForOne
                    ? SqrtPriceMath.getAmount0Delta(sqrtPriceLimitX96, snapshot.sqrtPriceX96, ranges, true)
                    : SqrtPriceMath.getAmount1Delta(snapshot.sqrtPriceX96, sqrtPriceLimitX96, ranges, true))
            .fullMulDivUp(1e6, 1e6 - snapshot.fee);
            roundingMarginIn += snapshot.getRounding(snapshot.sqrtPriceX96, zeroForOne) + 2 * ranges
            + ((2e6 - uint256(snapshot.fee)) * steps).divUp(1e6 - snapshot.fee);

            // The tokenOut the payout is short by.
            roundingMarginOut = snapshot.getRounding(snapshot.sqrtPriceX96, !zeroForOne) + steps + 2 * ranges;
        }

        // The redeem of those shares with the tokenIn margin left unsold, less the tokenOut margin.
        amountOut = RedeemOptimizationMath.previewRedeem(snapshot, pool, zeroForOne, shares, roundingMarginIn)
            .zeroFloorSub(roundingMarginOut);
    }

    /* //////////////////////////////////////////////////////////////
                                  HELPERS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the shares whose burn funds a sale to the step's target and, with it, pays the amount.
     * @param snapshot The core's snapshot.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param amountOut The tokenOut the withdraw pays, with the rounding.
     * @param holdingsIn The tokenIn the whole supply releases, plus the core's cost so far: B.
     * @param holdingsOut The tokenOut the whole supply releases, less the core's output so far: A.
     * @param state The sale's state at the step's start.
     * @param step The step, whose amountIn and amountOut become the pool's cost and output to its target.
     * @param amountIn The tokenIn the sale costs so far, with the rounding: C.
     * @return shares The aLP shares that both fund the sale and pay the amount, rounded up, type(uint256).max when none do.
     * @return costBinds True when funding the sale takes at least the shares that pay the amount.
     * @return holdingsInDelta The cost over the core's liquidity, its fee included, rounded down.
     * @return holdingsOutDelta The output over the core's liquidity, rounded up.
     * @dev The cost is at the pool's liquidity plus n, as the burn floors the liquidity it takes from each range.
     */
    function getSharesForAmounts(
        Snapshot memory snapshot,
        bool zeroForOne,
        uint256 amountOut,
        uint256 holdingsIn,
        uint256 holdingsOut,
        SwapState memory state,
        StepComputations memory step,
        uint256 amountIn
    ) internal pure returns (uint256 shares, bool costBinds, uint256 holdingsInDelta, uint256 holdingsOutDelta) {
        {
            // The pool's cost at its liquidity plus n, its fee included, rounded up, and its output, rounded down.
            uint256 liquidity = state.liquidity;
            uint256 liquidityCost;
            // Unchecked: the liquidity is a uint128 and the core holds at most MAX_RANGE_CAP ranges.
            unchecked {
                liquidityCost = (liquidity + snapshot.ranges.length) * 1e6;
            }
            {
                (uint256 sqrtPrice, uint256 sqrtPriceTarget) = (state.sqrtPriceX96, step.sqrtPriceTargetX96);
                if (zeroForOne) {
                    step.amountIn = liquidityCost.fullMulDivUp(1 << 192, sqrtPriceTarget * (1e6 - uint256(state.fee)))
                        - liquidityCost.fullMulDiv(1 << 192, sqrtPrice * (1e6 - uint256(state.fee)));
                    step.amountOut = liquidity * (sqrtPrice - sqrtPriceTarget);
                } else {
                    // Unchecked: the target is at or above the price, and the pool's fee is at most 100_000.
                    unchecked {
                        step.amountIn =
                            liquidityCost.fullMulDivUp(sqrtPriceTarget - sqrtPrice, 1e6 - uint256(state.fee));
                    }
                    step.amountOut = liquidity.fullMulDiv(1 << 192, sqrtPrice)
                        .zeroFloorSub(liquidity.fullMulDivUp(1 << 192, sqrtPriceTarget));
                }
            }

            // The core's part, from the same rounded amounts less their rounding, so it never grows faster than them.
            // Unchecked: the position's liquidity is below 2^132.
            unchecked {
                holdingsInDelta =
                    step.amountIn.zeroFloorSub(2).fullMulDiv(state.position.liquidity * 1e6, liquidityCost);
            }
            holdingsOutDelta = (step.amountOut + 2).fullMulDivUp(state.position.liquidity, liquidity);
        }

        // The cost binds when the pool's output pays the rest of the amount, or the shares that fund the sale also pay it.
        uint256 cost = amountIn + step.amountIn;
        uint256 amountOutLeft = amountOut.zeroFloorSub(state.amountOut + step.amountOut);
        (holdingsIn, holdingsOut) = (holdingsIn + holdingsInDelta, holdingsOut.zeroFloorSub(holdingsOutDelta));
        costBinds = amountOutLeft == 0
            || (holdingsOut > 0 && (cost > holdingsIn || cost.fullMulDiv(holdingsOut, holdingsIn) >= amountOutLeft));

        // Past the whole supply, or without the core's tokenOut, no shares pay.
        if (costBinds) shares = cost > holdingsIn ? type(uint256).max : cost.fullMulDivUp(snapshot.supply, holdingsIn);
        else if (holdingsOut == 0 || amountOutLeft > holdingsOut) shares = type(uint256).max;
        else shares = amountOutLeft.fullMulDivUp(snapshot.supply, holdingsOut);
    }

    /**
     * @notice Calculates the price nearest to where the sale's cost starts to set the shares, within the step.
     * @param snapshot The core's snapshot.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param amountOutLeft The tokenOut left to pay: a.
     * @param holdingsIn The tokenIn the whole supply releases, plus the core's cost so far: B.
     * @param holdingsOut The tokenOut the whole supply releases, less the core's output so far: A.
     * @param state The sale's state at the step's start, with the core's position W.
     * @param step The step, its target the price's bound.
     * @param amountIn The tokenIn the sale costs so far, with the rounding: C.
     * @return sqrtPriceNew The square root of the price, past the step's start and at most its target, with 96 binary precision.
     */
    function getSqrtPrice(
        Snapshot memory snapshot,
        bool zeroForOne,
        uint256 amountOutLeft,
        uint256 holdingsIn,
        uint256 holdingsOut,
        SwapState memory state,
        StepComputations memory step,
        uint256 amountIn
    ) internal pure returns (uint160 sqrtPriceNew) {
        // Solve the quadratic for the relative move of the square root price of tokenIn.
        (int256 quadraticCoefficient, int256 linearCoefficient, int256 constantCoefficient) =
            getQuadraticCoefficients(snapshot, zeroForOne, amountOutLeft, holdingsIn, holdingsOut, state, amountIn);
        uint256 sqrtPriceDelta = QuadraticMath.getRoot(quadraticCoefficient, linearCoefficient, constantCoefficient);

        // Move the square root price of tokenIn by the root: a root of zero is the first price past the step's start.
        sqrtPriceNew = getNextSqrtPrice(zeroForOne, state, step, sqrtPriceDelta);
    }

    /**
     * @notice Moves the square root price of tokenIn by a relative amount, to the nearest price, within the step.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param state The sale's state at the step's start.
     * @param step The step, its target the price's bound.
     * @param sqrtPriceDelta The relative move of the square root price of tokenIn, with 192 binary precision.
     * @return sqrtPriceNew The square root of the price, past the step's start and at most its target, with 96 binary precision.
     */
    function getNextSqrtPrice(
        bool zeroForOne,
        SwapState memory state,
        StepComputations memory step,
        uint256 sqrtPriceDelta
    ) internal pure returns (uint160 sqrtPriceNew) {
        // The move stops at the step's target, as CLMath.getNextSqrtPrice does: δ ≥ |target − s0| / max(s0, target).
        (uint256 sqrtPrice, uint256 sqrtPriceTarget) = (state.sqrtPriceX96, step.sqrtPriceTargetX96);
        if (
            sqrtPriceDelta
                >= (zeroForOne
                        ? (sqrtPrice - sqrtPriceTarget).fullMulDiv(1 << 192, sqrtPrice)
                        : (sqrtPriceTarget - sqrtPrice).fullMulDiv(1 << 192, sqrtPriceTarget))
        ) return uint160(sqrtPriceTarget);
        // Unchecked: the move is short of the step's target, so the price moves by less than their distance.
        unchecked {
            sqrtPrice = zeroForOne
                ? sqrtPrice - ((sqrtPrice.fullMulDivN(sqrtPriceDelta, 191) + 1) >> 1)
                : (sqrtPrice.fullMulDiv(1 << 193, (1 << 192) - sqrtPriceDelta) + 1) >> 1;
            sqrtPriceNew = uint160(
                zeroForOne
                    ? FixedPointMathLib.min(
                        FixedPointMathLib.max(sqrtPrice, step.sqrtPriceTargetX96), state.sqrtPriceX96 - 1
                    )
                    : FixedPointMathLib.max(
                        FixedPointMathLib.min(sqrtPrice, step.sqrtPriceTargetX96), state.sqrtPriceX96 + 1
                    )
            );
        }
    }

    /**
     * @notice Calculates the quadratic in the relative move of the square root price of tokenIn.
     * @param snapshot The core's snapshot.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param amountOutLeft The tokenOut left to pay: a.
     * @param holdingsIn The tokenIn the whole supply releases, plus the core's cost so far: B.
     * @param holdingsOut The tokenOut the whole supply releases, less the core's output so far: A.
     * @param state The sale's state at the step's start, with the core's position W.
     * @param amountIn The tokenIn the sale costs so far, with the rounding: C.
     * @return quadraticCoefficient The quadratic coefficient, with 192 binary precision.
     * @return linearCoefficient The linear coefficient, with 192 binary precision.
     * @return constantCoefficient The constant coefficient, with 192 binary precision.
     * @dev (R' + κ * n * W / B) * δ² − (R' + a' + κ * A * R_in / B − κ * a * W_in / B) * δ + a' = 0, with R' = R − C * W_out / B
     *     and a' = a − C * A / B, R the pool's tokenOut reserve, R_in its tokenIn reserve at its liquidity plus n.
     */
    function getQuadraticCoefficients(
        Snapshot memory snapshot,
        bool zeroForOne,
        uint256 amountOutLeft,
        uint256 holdingsIn,
        uint256 holdingsOut,
        SwapState memory state,
        uint256 amountIn
    ) internal pure returns (int256 quadraticCoefficient, int256 linearCoefficient, int256 constantCoefficient) {
        // Calculate the tokenOut reserve, amount, holdings term and liquidity term relative to the largest.
        (
            int256 reserveOutNormalized,
            int256 amountOutNormalized,
            int256 holdingsNormalized,
            uint256 liquidityNormalized
        ) = getNormalizedParameters(snapshot, zeroForOne, amountOutLeft, holdingsIn, holdingsOut, state, amountIn);

        // Calculate the coefficients from the normalized terms.
        // Unchecked: each normalized term is at most 2^192.
        unchecked {
            quadraticCoefficient = reserveOutNormalized + int256(liquidityNormalized);
            constantCoefficient = amountOutNormalized;
            linearCoefficient = reserveOutNormalized + amountOutNormalized + holdingsNormalized;
        }
    }

    /**
     * @notice Expresses the terms of the quadratic relative to the largest of them.
     * @param snapshot The core's snapshot.
     * @param zeroForOne True when token0 is swapped for token1.
     * @param amountOutLeft The tokenOut left to pay: a.
     * @param holdingsIn The tokenIn the whole supply releases, plus the core's cost so far: B.
     * @param holdingsOut The tokenOut the whole supply releases, less the core's output so far: A.
     * @param state The sale's state at the step's start, with the core's position W.
     * @param amountIn The tokenIn the sale costs so far, with the rounding: C.
     * @return reserveOutNormalized (R * B − C * W_out) / D, with 192 binary precision.
     * @return amountOutNormalized (a * B − C * A) / D, with 192 binary precision.
     * @return holdingsNormalized κ * (R_in * A − a * W_in) / D, with 192 binary precision.
     * @return liquidityNormalized κ * n * W * 2^192 / D, with 192 binary precision.
     * @dev The quadratic is homogeneous, so its terms are taken times B over D = max(B, A) and normalized by the largest.
     */
    function getNormalizedParameters(
        Snapshot memory snapshot,
        bool zeroForOne,
        uint256 amountOutLeft,
        uint256 holdingsIn,
        uint256 holdingsOut,
        SwapState memory state,
        uint256 amountIn
    )
        internal
        pure
        returns (
            int256 reserveOutNormalized,
            int256 amountOutNormalized,
            int256 holdingsNormalized,
            uint256 liquidityNormalized
        )
    {
        // The terms times B over the larger holdings, so each stays below one reserve, with 96 binary digits below a wei.
        uint256 holdings = FixedPointMathLib.max(holdingsIn, holdingsOut);

        // The n liquidity the burn's floors leave in the pool: κ * n * W over D.
        // Unchecked: the position's liquidity is below 2^132 and the pool's fee is at most 100_000.
        unchecked {
            liquidityNormalized = snapshot.ranges.length * state.position.liquidity;
            liquidityNormalized = liquidityNormalized.fullMulDiv(1 << 192, holdings).fullMulDiv(1e6, 1e6 - state.fee);
        }

        // The pool's tokenOut reserve R and the position's W_out: (R * B − C * W_out) over D.
        {
            (uint256 reserveOut, uint256 positionOut) = zeroForOne
                ? (uint256(state.liquidity) * state.sqrtPriceX96, state.position.liquidity * state.sqrtPriceX96)
                : (
                    uint256(state.liquidity).fullMulDiv(1 << 192, state.sqrtPriceX96),
                    state.position.liquidity.fullMulDiv(1 << 192, state.sqrtPriceX96)
                );
            // Unchecked: both terms are non-negative int256 values.
            unchecked {
                reserveOutNormalized = SafeCastLib.toInt256(reserveOut.fullMulDiv(holdingsIn, holdings))
                    - SafeCastLib.toInt256(amountIn.fullMulDiv(positionOut, holdings));
            }
        }

        // (a * B − C * A) over D.
        // Unchecked: both terms are non-negative int256 values.
        unchecked {
            amountOutNormalized = SafeCastLib.toInt256(amountOutLeft.fullMulDiv(holdingsIn, holdings))
                - SafeCastLib.toInt256(amountIn.fullMulDiv(holdingsOut, holdings));
        }

        // The pool's tokenIn reserve R_in at its liquidity plus n and the position's W_in: κ * (R_in * A − a * W_in) over D.
        {
            uint256 reserveIn = zeroForOne
                ? (state.liquidity + snapshot.ranges.length).fullMulDiv(1 << 192, state.sqrtPriceX96)
                : (state.liquidity + snapshot.ranges.length) * state.sqrtPriceX96;
            uint256 positionIn = zeroForOne
                ? state.position.liquidity.fullMulDiv(1 << 192, state.sqrtPriceX96)
                : state.position.liquidity * state.sqrtPriceX96;
            // Unchecked: both terms are non-negative int256 values.
            unchecked {
                holdingsNormalized = SafeCastLib.toInt256(reserveIn.fullMulDiv(holdingsOut, holdings))
                    - SafeCastLib.toInt256(positionIn.fullMulDiv(amountOutLeft, holdings));
            }
            holdingsNormalized = holdingsNormalized * 1e6 / int256(1e6 - uint256(state.fee));
        }

        // Relative to the largest term, with 192 binary precision.
        uint256 largest = FixedPointMathLib.max(
            FixedPointMathLib.max(uint256(reserveOutNormalized), FixedPointMathLib.abs(amountOutNormalized)),
            FixedPointMathLib.max(
                FixedPointMathLib.max(FixedPointMathLib.abs(holdingsNormalized), liquidityNormalized), 1
            )
        );
        // Unchecked: each normalized term is at most 2^192.
        unchecked {
            reserveOutNormalized = int256(uint256(reserveOutNormalized).fullMulDiv(1 << 192, largest));
            amountOutNormalized = int256(FixedPointMathLib.abs(amountOutNormalized).fullMulDiv(1 << 192, largest))
                * (amountOutNormalized < 0 ? -1 : int256(1));
            holdingsNormalized = int256(FixedPointMathLib.abs(holdingsNormalized).fullMulDiv(1 << 192, largest))
                * (holdingsNormalized < 0 ? -1 : int256(1));
        }
        liquidityNormalized = liquidityNormalized.fullMulDiv(1 << 192, largest);
    }
}
