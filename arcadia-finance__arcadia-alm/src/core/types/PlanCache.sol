/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { CLMath } from "../../shared/libraries/math/CLMath.sol";
import { Config, State } from "./State.sol";
import { ConfigLib } from "../libraries/state/ConfigLib.sol";
import { CoreImmutables } from "./CoreImmutables.sol";
import { EmissionsLogic } from "../libraries/logic/EmissionsLogic.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { TokenDelta, TokenDeltaLib } from "./TokenDelta.sol";

/**
 * @notice The values a keeper plan is checked against and its queue settlements are priced at.
 */
struct PlanCache {
    uint256 openedRanges;
    uint256 supplyBefore;
    uint256 valueBefore;
    uint256 depositAssets0;
    uint256 depositAssets1;
    uint256 redeemShares0;
    uint256 redeemShares1;
    uint256 blockNumber;
    uint160 trustedSqrtPriceX96;
    uint160 spotSqrtPriceX96;
    int256 amount0;
    int256 amount1;
    TokenDelta swapDelta;
    CoreImmutables immutables;
}

using PlanCacheLib for PlanCache global;

/**
 * @title Plan Cache Library.
 * @author Pragma Labs
 * @notice One keeper execution's trusted price, starting supply and value, held tokens and opened ranges.
 */
// forge-lint: disable-next-item(require-revert-in-loop, uninitialized-local, unsafe-typecast)
library PlanCacheLib {
    using FixedPointMathLib for uint256;
    using TokenDeltaLib for TokenDelta;

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error MaxShortfallExceeded();
    error ZeroSupply();
    error ZeroValue();

    /* //////////////////////////////////////////////////////////////
                                EXECUTION
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Starts an execution at the price its value is measured against.
     * @param state The core state.
     * @param immutables The immutables of the core.
     * @param trustedSqrtPriceX96 The price the execution is valued at.
     * @param spotSqrtPriceX96 The pool's spot price at the start of the execution.
     * @param supplyBefore The aLP supply the execution starts on.
     * @param amount0 The token0 principal of every range.
     * @param amount1 The token1 principal of every range.
     * @return cache The plan cache, valued in token1 at that price.
     */
    function start(
        State storage state,
        CoreImmutables memory immutables,
        uint160 trustedSqrtPriceX96,
        uint160 spotSqrtPriceX96,
        uint256 supplyBefore,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (PlanCache memory cache) {
        // Cache the starting supply.
        cache.supplyBefore = supplyBefore;

        // Calculate the value before the execution, in token1 at the trusted price.
        // Unchecked: the principal of every range plus a uint128 buffer fits 256 bits.
        unchecked {
            amount0 += state.poolTokens.buffer.amount0;
            amount1 += state.poolTokens.buffer.amount1;
        }
        cache.valueBefore = amount1 + CLMath.convert(trustedSqrtPriceX96, true, amount0, false);
        (cache.amount0, cache.amount1) = (SafeCastLib.toInt256(amount0), SafeCastLib.toInt256(amount1));

        // Cache the gauge's block number.
        cache.blockNumber = EmissionsLogic.getBlockNumber(state.config.arbBlockNumber);

        // Cache the trusted and spot prices and the core immutables.
        cache.trustedSqrtPriceX96 = trustedSqrtPriceX96;
        cache.spotSqrtPriceX96 = spotSqrtPriceX96;
        cache.immutables = immutables;
    }

    /**
     * @notice Reverts when an execution dropped the value per share at the trusted price by more than maxShortfallBps.
     * @param cache The plan cache.
     * @param config The governance parameters.
     * @param valueAfter The value after the execution.
     * @param supplyAfter The aLP supply after it.
     */
    function checkShortfall(PlanCache memory cache, Config storage config, uint256 valueAfter, uint256 supplyAfter)
        internal
        view
    {
        // Checks.
        // Unchecked: maxShortfallBps is at most BPS_DENOMINATOR.
        unchecked {
            if (
                valueAfter.fullMulDiv(cache.supplyBefore, supplyAfter)
                    < cache.valueBefore
                        .fullMulDiv(ConfigLib.BPS_DENOMINATOR - config.maxShortfallBps, ConfigLib.BPS_DENOMINATOR)
            ) revert MaxShortfallExceeded();
        }
    }

    /* //////////////////////////////////////////////////////////////
                                 DELTAS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Adds a buffer delta to the tokens the execution holds.
     * @param cache The plan cache.
     * @param delta The token amounts credited to the buffer, negative for the amounts taken out of it.
     */
    function applyBufferDelta(PlanCache memory cache, TokenDelta delta) internal pure {
        cache.amount0 += delta.amount0();
        cache.amount1 += delta.amount1();
    }

    /**
     * @notice Adds the principal of a liquidity change to the tokens the execution holds.
     * @param cache The plan cache.
     * @param tickLower The lower tick of the range.
     * @param tickUpper The upper tick of the range.
     * @param liquidityDelta The liquidity added, negative for the liquidity removed.
     */
    function applyLiquidityDelta(PlanCache memory cache, int24 tickLower, int24 tickUpper, int256 liquidityDelta)
        internal
        pure
    {
        (uint256 amount0, uint256 amount1) = CLMath.getPrincipalAmounts(
            cache.trustedSqrtPriceX96, tickLower, tickUpper, uint128(FixedPointMathLib.abs(liquidityDelta))
        );
        TokenDelta principal = TokenDeltaLib.fromAmounts(amount0, amount1);
        cache.applyBufferDelta(liquidityDelta < 0 ? principal.neg() : principal);
    }

    /* //////////////////////////////////////////////////////////////
                                 RANGES
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Marks a range as opened by the execution.
     * @param cache The plan cache.
     * @param index The index of the range.
     */
    function openRange(PlanCache memory cache, uint256 index) internal pure {
        // Set the opened flag of the range.
        cache.openedRanges |= 1 << index;
    }

    /**
     * @notice Moves the last range's opened flag onto a closed range's index.
     * @param cache The plan cache.
     * @param index The index of the closed range.
     * @param lastIndex The index of the last range.
     */
    function closeRange(PlanCache memory cache, uint256 index, uint256 lastIndex) internal pure {
        // Move the opened flag of the last range onto the closed range.
        uint256 opened = cache.openedRanges;
        opened = (opened & ~(1 << index)) | (((opened >> lastIndex) & 1) << index);

        // Clear the opened flag of the last range.
        cache.openedRanges = opened & ~(1 << lastIndex);
    }

    /**
     * @notice Whether the execution opened a range.
     * @param cache The plan cache.
     * @param index The index of the range.
     * @return opened True when the execution opened it.
     */
    function isOpenedRange(PlanCache memory cache, uint256 index) internal pure returns (bool opened) {
        opened = ((cache.openedRanges >> index) & 1) != 0;
    }

    /* //////////////////////////////////////////////////////////////
                               SETTLEMENT
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns whether the plan cleared epochs it has not settled yet.
     * @param cache The plan cache.
     * @return unsettled True when a cleared epoch is not settled.
     */
    function hasUnsettledEpochs(PlanCache memory cache) internal pure returns (bool unsettled) {
        unsettled = (cache.depositAssets0 | cache.depositAssets1 | cache.redeemShares0 | cache.redeemShares1) != 0;
    }

    /**
     * @notice Returns the amount the plan cleared of a vault's queue.
     * @param cache The plan cache.
     * @param isDeposit True for the deposit queue, false for the redeem queue.
     * @param isToken0 True for the token0 vault.
     * @return cleared The assets or shares cleared.
     */
    function getCleared(PlanCache memory cache, bool isDeposit, bool isToken0) internal pure returns (uint256 cleared) {
        if (isDeposit) cleared = isToken0 ? cache.depositAssets0 : cache.depositAssets1;
        else cleared = isToken0 ? cache.redeemShares0 : cache.redeemShares1;
    }

    /**
     * @notice Sets the amount the plan cleared of a vault's queue.
     * @param cache The plan cache.
     * @param isDeposit True for the deposit queue, false for the redeem queue.
     * @param isToken0 True for the token0 vault.
     * @param cleared The assets or shares cleared.
     */
    function setCleared(PlanCache memory cache, bool isDeposit, bool isToken0, uint256 cleared) internal pure {
        if (isDeposit) {
            if (isToken0) cache.depositAssets0 = cleared;
            else cache.depositAssets1 = cleared;
        } else if (isToken0) {
            cache.redeemShares0 = cleared;
        } else {
            cache.redeemShares1 = cleared;
        }
    }

    /**
     * @notice The value the execution holds, a negative token amount valued at zero.
     * @param cache The plan cache.
     * @return valueAfter The value held, in token1 at the trusted price.
     */
    function getValueAfter(PlanCache memory cache) internal pure returns (uint256 valueAfter) {
        valueAfter = getValue(cache.trustedSqrtPriceX96, cache.amount0, cache.amount1, false);
    }

    /**
     * @notice The value of token amounts, a negative amount valued at zero.
     * @param trustedSqrtPriceX96 The price the execution is valued at.
     * @param amount0 The token0 amount.
     * @param amount1 The token1 amount.
     * @param roundUp True to round the value up, false to round it down.
     * @return value The value, in token1 at the trusted price.
     */
    function getValue(uint160 trustedSqrtPriceX96, int256 amount0, int256 amount1, bool roundUp)
        internal
        pure
        returns (uint256 value)
    {
        value = uint256(FixedPointMathLib.max(amount1, 0));
        if (amount0 > 0) value += CLMath.convert(trustedSqrtPriceX96, true, uint256(amount0), roundUp);
    }

    /**
     * @notice The payouts the cleared redeems are owed if the plan settled at its current state.
     * @param cache The plan cache.
     * @return owed0 The token0 owed to the token0 vault's redeems.
     * @return owed1 The token1 owed to the token1 vault's redeems.
     */
    function getOwed(PlanCache memory cache) internal pure returns (uint256 owed0, uint256 owed1) {
        if ((cache.redeemShares0 | cache.redeemShares1) == 0) return (0, 0);
        (,, owed0, owed1) = getSettlementAmountsOut(cache);
    }

    /**
     * @notice Calculates the aLP minted and the assets paid for the epochs the plan cleared, net of their levies.
     * @param cache The plan cache.
     * @return shares0 The aLP of the token0 vault's deposit epoch, rounded down.
     * @return shares1 The aLP of the token1 vault's deposit epoch, rounded down.
     * @return assets0 The token0 of the token0 vault's redeem epoch, rounded down.
     * @return assets1 The token1 of the token1 vault's redeem epoch, rounded down.
     */
    function getSettlementAmountsOut(PlanCache memory cache)
        internal
        pure
        returns (uint256 shares0, uint256 shares1, uint256 assets0, uint256 assets1)
    {
        // Calculate the token0 deposit's value, rounded down (in token1 at the trusted price).
        uint256 depositValue0 = CLMath.convert(cache.trustedSqrtPriceX96, true, cache.depositAssets0, false);

        // Calculate the existing aLP's value before the swap, rounded down and up.
        uint256 redeemValue;
        uint256 swapped;
        uint256 value;
        uint256 valueUp;
        {
            int256 amount0 = cache.amount0 - cache.swapDelta.amount0() - SafeCastLib.toInt256(cache.depositAssets0);
            int256 amount1 = cache.amount1 - cache.swapDelta.amount1() - SafeCastLib.toInt256(cache.depositAssets1);
            redeemValue = getValue(cache.trustedSqrtPriceX96, amount0, amount1, false);
            valueUp = getValue(cache.trustedSqrtPriceX96, amount0, amount1, true);
        }

        // Calculate its value after the swap, rounded down and up.
        {
            // Calculate the token0 value the swap moved, rounded down and up.
            uint256 amount0 = FixedPointMathLib.abs(cache.swapDelta.amount0());
            swapped = CLMath.convert(cache.trustedSqrtPriceX96, true, amount0, false);
            uint256 swappedUp = CLMath.convert(cache.trustedSqrtPriceX96, true, amount0, true);

            // Calculate the value the swap gained, rounded down.
            int256 gain = cache.swapDelta.amount1();
            if (cache.swapDelta.amount0() < 0) gain -= SafeCastLib.toInt256(swappedUp);
            else gain += SafeCastLib.toInt256(swapped);

            // Add the gain to the value before the swap, and the two roundings to the value rounded up.
            value = uint256(FixedPointMathLib.max(SafeCastLib.toInt256(redeemValue) + gain, 0));
            valueUp = value + valueUp - redeemValue + swappedUp - swapped;
        }

        // Checks.
        if (depositValue0 + cache.depositAssets1 != 0 && value == 0) revert ZeroValue();
        if (cache.supplyBefore == 0) revert ZeroSupply();

        // Calculate the redeem values.
        assets0 = cache.redeemShares0.fullMulDiv(value, cache.supplyBefore);
        assets1 = cache.redeemShares1.fullMulDiv(value, cache.supplyBefore);

        // Calculate the levies of the flows that needed the swap, in the swap's direction.
        uint256 depositLevy;
        uint256 redeemLevy;
        {
            // Calculate the holdings after paying the redeems.
            uint256 held0 = getValue(cache.trustedSqrtPriceX96, cache.amount0, 0, false);
            held0 = held0.zeroFloorSub(assets0);
            uint256 held1 = cache.amount1 > 0 ? uint256(cache.amount1) : 0;
            held1 = held1.zeroFloorSub(assets1);

            // Levy the value the swap lost, rounded up.
            (depositLevy, redeemLevy) = cache.swapDelta.amount0() < 0
                ? getLevies(
                    depositValue0,
                    cache.depositAssets1,
                    assets1,
                    assets0,
                    redeemValue.zeroFloorSub(value),
                    swapped,
                    held0,
                    held1
                )
                : getLevies(
                    cache.depositAssets1,
                    depositValue0,
                    assets0,
                    assets1,
                    redeemValue.zeroFloorSub(value),
                    swapped,
                    held1,
                    held0
                );
        }

        // Add the levies to the existing aLP's value, the redeems priced at most at its value before the swap.
        redeemValue = FixedPointMathLib.min(redeemValue, value + depositLevy + redeemLevy);
        valueUp += depositLevy + redeemLevy;

        // Take the levies off the flows that paid them.
        assets0 = redeemValue.fullMulDiv(cache.redeemShares0, cache.supplyBefore);
        assets1 = redeemValue.fullMulDiv(cache.redeemShares1, cache.supplyBefore);
        uint256 depositValue1 = cache.depositAssets1;
        if (cache.swapDelta.amount0() < 0) {
            depositValue0 -= depositLevy;
            assets1 -= redeemLevy;
        } else {
            depositValue1 -= depositLevy;
            assets0 -= redeemLevy;
        }

        // Calculate the shares and assets.
        if (depositValue0 != 0) shares0 = depositValue0.fullMulDiv(cache.supplyBefore, valueUp);
        if (depositValue1 != 0) shares1 = depositValue1.fullMulDiv(cache.supplyBefore, valueUp);
        assets0 = CLMath.convert(cache.trustedSqrtPriceX96, false, assets0, false);
    }

    /**
     * @notice Calculates the levies on the flows that needed the swap, pro rata to their part of it.
     * @param depositIn The deposit value in the swap's input token.
     * @param depositOut The deposit value in the swap's output token.
     * @param redeemOut The redeem value in the swap's output token.
     * @param redeemIn The redeem value in the swap's input token.
     * @param swapCost The value the swap lost, in token1 at the trusted price, rounded up.
     * @param swapped The token0 value the swap moved, in token1 at the trusted price, rounded down.
     * @param heldIn The value of the swap's input token held after the payouts.
     * @param heldOut The value of the swap's output token held after the payouts.
     * @return depositLevy The levy on the deposit in the swap's input token, rounded up.
     * @return redeemLevy The levy on the redeem paid in the swap's output token, rounded up.
     */
    function getLevies(
        uint256 depositIn,
        uint256 depositOut,
        uint256 redeemOut,
        uint256 redeemIn,
        uint256 swapCost,
        uint256 swapped,
        uint256 heldIn,
        uint256 heldOut
    ) internal pure returns (uint256 depositLevy, uint256 redeemLevy) {
        // If the swap cost nothing or nothing is held after the payouts, return.
        if (swapCost == 0 || swapped == 0 || heldIn + heldOut == 0) return (0, 0);

        // Calculate the part of each flow swapped in the swap's direction, and the part of the offsetting flows.
        uint256 depositSwap = depositIn.fullMulDiv(heldOut, heldIn + heldOut);
        uint256 redeemSwap = redeemOut.fullMulDiv(heldIn, heldIn + heldOut);
        uint256 offset =
            depositOut.fullMulDiv(heldIn, heldIn + heldOut) + redeemIn.fullMulDiv(heldOut, heldIn + heldOut);

        // If the flows did not need the swap, return.
        if (depositSwap + redeemSwap <= offset) return (0, 0);

        // Levy the swap's realised rate on the flows' part, pro rata and capped at each flow.
        uint256 levy = swapCost.fullMulDivUp(FixedPointMathLib.min(depositSwap + redeemSwap - offset, swapped), swapped);
        depositLevy = FixedPointMathLib.min(levy.fullMulDivUp(depositSwap, depositSwap + redeemSwap), depositIn);
        redeemLevy = FixedPointMathLib.min(levy.fullMulDivUp(redeemSwap, depositSwap + redeemSwap), redeemOut);
    }
}
