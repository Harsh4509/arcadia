/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { PlanCache, PlanCacheLib } from "../../../src/core/types/PlanCache.sol";
import { PlanCacheLibExtension } from "../../utils/extensions/PlanCacheLibExtension.sol";
import { stdError } from "@forge-std/StdError.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { toTokenDelta } from "../../../src/core/types/TokenDelta.sol";

/**
 * @notice Symbolic tests for the library "PlanCacheLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract PlanCacheLib_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    PlanCacheLibExtension internal planCacheLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public {
        planCacheLib = new PlanCacheLibExtension();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function prove_closeRange_MovesTheLastFlagOntoTheClosedIndex(
        uint256 openedRanges,
        uint256 index,
        uint256 lastIndex,
        uint256 probe
    ) public pure {
        // Given: Any flags, a closed index up to the last index, and any probed index.
        vm.assume(index <= lastIndex && lastIndex < 256 && probe < 256);
        PlanCache memory cache;
        cache.openedRanges = openedRanges;
        bool lastOpened = (openedRanges >> lastIndex) & 1 == 1;
        bool probeOpened = (openedRanges >> probe) & 1 == 1;

        // When: Closing the range at the index.
        cache.closeRange(index, lastIndex);

        // Then: The last flag clears, the closed index takes it, every other flag stays.
        bool expected = probe == lastIndex ? false : probe == index ? lastOpened : probeOpened;
        assertEq(cache.isOpenedRange(probe), expected);
    }

    function prove_openRange_SetsOnlyThatFlag(uint256 openedRanges, uint256 index, uint256 probe) public pure {
        // Given: Any flags and any indices below 256.
        vm.assume(index < 256 && probe < 256);
        PlanCache memory cache;
        cache.openedRanges = openedRanges;
        bool probeOpened = (openedRanges >> probe) & 1 == 1;

        // When: Opening the range at the index.
        cache.openRange(index);

        // Then: That flag is set and every other flag stays.
        assertEq(cache.isOpenedRange(probe), probe == index || probeOpened);
    }

    function prove_getValueAfter_IsThePositiveToken1WithoutAPositiveToken0(
        int256 amount0,
        int256 amount1,
        uint160 trustedSqrtPriceX96
    ) public pure {
        // Given: A token0 amount that is not positive, any token1 amount and price.
        vm.assume(amount0 <= 0);
        PlanCache memory cache;
        (cache.amount0, cache.amount1, cache.trustedSqrtPriceX96) = (amount0, amount1, trustedSqrtPriceX96);

        // When: Valuing what the execution holds.
        // Then: It is the token1 amount, zero when negative.
        assertEq(cache.getValueAfter(), amount1 > 0 ? uint256(amount1) : 0);
    }

    /// forge-config: default.symbolic.solver_portfolio = ["cvc5-int", "bitwuzla"]
    function prove_checkShortfall_RevertsBelowTheFloor(
        uint256 valueBefore,
        uint256 supplyBefore,
        uint256 valueAfter,
        uint256 supplyAfter,
        uint256 maxShortfallBps
    ) public {
        // Given: uint128 values and supplies whose value per share is below the floor.
        vm.assume(valueBefore <= type(uint128).max && supplyBefore <= type(uint128).max);
        vm.assume(valueAfter <= type(uint128).max && supplyAfter <= type(uint128).max && supplyAfter != 0);
        vm.assume(maxShortfallBps <= ConfigLib.BPS_DENOMINATOR);
        vm.assume(
            valueAfter * supplyBefore / supplyAfter
                < valueBefore * (ConfigLib.BPS_DENOMINATOR - uint16(maxShortfallBps)) / ConfigLib.BPS_DENOMINATOR
        );
        planCacheLib.setMaxShortfallBps(uint16(maxShortfallBps));
        PlanCache memory cache;
        (cache.valueBefore, cache.supplyBefore) = (valueBefore, supplyBefore);

        // When: Checking the shortfall.
        // Then: It reverts.
        vm.expectRevert(PlanCacheLib.MaxShortfallExceeded.selector);
        planCacheLib.checkShortfall(cache, valueAfter, supplyAfter);
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_checkShortfall_SucceedsAtOrAboveTheFloor(
        uint256 valueBefore,
        uint256 supplyBefore,
        uint256 valueAfter,
        uint256 supplyAfter,
        uint256 maxShortfallBps
    ) public {
        // Given: uint128 values and supplies whose value per share keeps the floor.
        vm.assume(valueBefore <= type(uint128).max && supplyBefore <= type(uint128).max);
        vm.assume(valueAfter <= type(uint128).max && supplyAfter <= type(uint128).max && supplyAfter != 0);
        vm.assume(maxShortfallBps <= ConfigLib.BPS_DENOMINATOR);
        vm.assume(
            valueAfter * supplyBefore / supplyAfter
                >= valueBefore * (ConfigLib.BPS_DENOMINATOR - uint16(maxShortfallBps)) / ConfigLib.BPS_DENOMINATOR
        );
        planCacheLib.setMaxShortfallBps(uint16(maxShortfallBps));
        PlanCache memory cache;
        (cache.valueBefore, cache.supplyBefore) = (valueBefore, supplyBefore);

        // When: Checking the shortfall.
        (bool success,) = address(planCacheLib)
            .staticcall(abi.encodeCall(PlanCacheLibExtension.checkShortfall, (cache, valueAfter, supplyAfter)));

        // Then: It succeeds.
        assertTrue(success);
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_checkShortfall_NeverRevertsWithoutALoss(
        uint256 valueBefore,
        uint256 supplyBefore,
        uint256 valueAfter,
        uint256 supplyAfter,
        uint256 maxShortfallBps
    ) public {
        // Given: uint128 values and supplies whose value per share did not drop.
        vm.assume(valueBefore <= type(uint128).max && supplyBefore <= type(uint128).max);
        vm.assume(valueAfter <= type(uint128).max && supplyAfter <= type(uint128).max && supplyAfter != 0);
        vm.assume(valueAfter * supplyBefore >= valueBefore * supplyAfter);
        vm.assume(maxShortfallBps <= ConfigLib.BPS_DENOMINATOR);
        planCacheLib.setMaxShortfallBps(uint16(maxShortfallBps));
        PlanCache memory cache;
        (cache.valueBefore, cache.supplyBefore) = (valueBefore, supplyBefore);

        // When: Checking the shortfall.
        (bool success,) = address(planCacheLib)
            .staticcall(abi.encodeCall(PlanCacheLibExtension.checkShortfall, (cache, valueAfter, supplyAfter)));

        // Then: It succeeds.
        assertTrue(success);
    }

    function prove_applyBufferDelta_SucceedsIffBothSumsFitInt256(
        int256 amount0,
        int256 amount1,
        int128 delta0,
        int128 delta1
    ) public view {
        // Given: Any held amounts and any delta.
        PlanCache memory cache;
        (cache.amount0, cache.amount1) = (amount0, amount1);
        bool fits0 = delta0 >= 0 ? amount0 <= type(int256).max - delta0 : amount0 >= type(int256).min - delta0;
        bool fits1 = delta1 >= 0 ? amount1 <= type(int256).max - delta1 : amount1 >= type(int256).min - delta1;

        // When: Adding the delta to the held amounts.
        (bool success, bytes memory result) = address(planCacheLib)
            .staticcall(abi.encodeCall(PlanCacheLibExtension.applyBufferDelta, (cache, toTokenDelta(delta0, delta1))));

        // Then: It succeeds exactly when both sums fit, and holds them.
        assertEq(success, fits0 && fits1);
        if (success) {
            PlanCache memory applied = abi.decode(result, (PlanCache));
            assertEq(applied.amount0, amount0 + delta0);
            assertEq(applied.amount1, amount1 + delta1);
        } else {
            assertEq(result, stdError.arithmeticError);
        }
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_applyLiquidityDelta_RemovingTheAddedLiquidityRestoresTheAmounts(
        int128 amount0,
        int128 amount1,
        uint160 trustedSqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public pure {
        // Given: int128 amounts, a valid range, and any liquidity worth below 2^127.
        vm.assume(TickMath.MIN_TICK <= tickLower && tickLower < tickUpper && tickUpper <= TickMath.MAX_TICK);
        (uint256 principal0, uint256 principal1) =
            CLMath.getPrincipalAmounts(trustedSqrtPriceX96, tickLower, tickUpper, liquidity);
        vm.assume(principal0 < 1 << 127 && principal1 < 1 << 127);
        PlanCache memory cache;
        (cache.amount0, cache.amount1, cache.trustedSqrtPriceX96) = (amount0, amount1, trustedSqrtPriceX96);

        // When: Adding the liquidity, then removing it.
        cache.applyLiquidityDelta(tickLower, tickUpper, int256(uint256(liquidity)));
        int256 added0 = cache.amount0;
        int256 added1 = cache.amount1;
        cache.applyLiquidityDelta(tickLower, tickUpper, -int256(uint256(liquidity)));

        // Then: Adding never lowers either amount, and removing restores both.
        assertGe(added0, amount0);
        assertGe(added1, amount1);
        assertEq(cache.amount0, amount0);
        assertEq(cache.amount1, amount1);
    }

    function prove_isOpenedRange_IsTheFlagAtTheIndex(uint256 openedRanges, uint256 index) public pure {
        // Given: Any flags and any index.
        PlanCache memory cache;
        cache.openedRanges = openedRanges;

        // When: Reading whether the range at the index is opened.
        // Then: It is the bit at the index, false past 255.
        assertEq(cache.isOpenedRange(index), index < 256 && openedRanges & (1 << index) != 0);
    }

    function prove_hasUnsettledEpochs_IsWhetherAnyQueueWasCleared(
        uint256 depositAssets0,
        uint256 depositAssets1,
        uint256 redeemShares0,
        uint256 redeemShares1
    ) public pure {
        // Given: Any cleared amounts.
        PlanCache memory cache;
        (cache.depositAssets0, cache.depositAssets1) = (depositAssets0, depositAssets1);
        (cache.redeemShares0, cache.redeemShares1) = (redeemShares0, redeemShares1);

        // When: Checking for unsettled epochs.
        // Then: There are some exactly when any queue has a nonzero cleared amount.
        assertEq(
            cache.hasUnsettledEpochs(),
            depositAssets0 != 0 || depositAssets1 != 0 || redeemShares0 != 0 || redeemShares1 != 0
        );
    }

    function prove_getCleared_ReadsTheNamedQueue(
        uint256 depositAssets0,
        uint256 depositAssets1,
        uint256 redeemShares0,
        uint256 redeemShares1,
        bool isDeposit,
        bool isToken0
    ) public pure {
        // Given: Any cleared amounts.
        PlanCache memory cache;
        (cache.depositAssets0, cache.depositAssets1) = (depositAssets0, depositAssets1);
        (cache.redeemShares0, cache.redeemShares1) = (redeemShares0, redeemShares1);

        // When: Reading the amount cleared of one queue.
        uint256 cleared = cache.getCleared(isDeposit, isToken0);

        // Then: It is that queue's field.
        if (isDeposit) assertEq(cleared, isToken0 ? depositAssets0 : depositAssets1);
        else assertEq(cleared, isToken0 ? redeemShares0 : redeemShares1);
    }

    function prove_setCleared_WritesOnlyTheNamedQueue(
        uint256 depositAssets0,
        uint256 depositAssets1,
        uint256 redeemShares0,
        uint256 redeemShares1,
        bool isDeposit,
        bool isToken0,
        uint256 cleared
    ) public pure {
        // Given: Any cleared amounts.
        PlanCache memory cache;
        (cache.depositAssets0, cache.depositAssets1) = (depositAssets0, depositAssets1);
        (cache.redeemShares0, cache.redeemShares1) = (redeemShares0, redeemShares1);

        // When: Setting the amount cleared of one queue.
        cache.setCleared(isDeposit, isToken0, cleared);

        // Then: That queue's field holds it, and the other three stay.
        assertEq(cache.depositAssets0, isDeposit && isToken0 ? cleared : depositAssets0);
        assertEq(cache.depositAssets1, isDeposit && !isToken0 ? cleared : depositAssets1);
        assertEq(cache.redeemShares0, !isDeposit && isToken0 ? cleared : redeemShares0);
        assertEq(cache.redeemShares1, !isDeposit && !isToken0 ? cleared : redeemShares1);
    }

    function prove_getLevies_AreNothingWithoutACostOrHoldings(
        uint256 depositIn,
        uint256 depositOut,
        uint256 redeemOut,
        uint256 redeemIn,
        uint256 swapCost,
        uint256 swapped,
        uint256 heldIn,
        uint256 heldOut
    ) public pure {
        // Given: Holdings whose sum fits, and no cost, nothing swapped or nothing held.
        vm.assume(heldIn <= type(uint256).max - heldOut);
        vm.assume(swapCost == 0 || swapped == 0 || heldIn + heldOut == 0);

        // When: Taking the levies.
        (uint256 depositLevy, uint256 redeemLevy) =
            PlanCacheLib.getLevies(depositIn, depositOut, redeemOut, redeemIn, swapCost, swapped, heldIn, heldOut);

        // Then: Both are zero.
        assertEq(depositLevy, 0);
        assertEq(redeemLevy, 0);
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_getLevies_EachLevyIsAtMostItsFlowAndTheSwapsCost(
        uint256 depositIn,
        uint256 depositOut,
        uint256 redeemOut,
        uint256 redeemIn,
        uint256 swapCost,
        uint256 swapped,
        uint256 heldIn,
        uint256 heldOut
    ) public pure {
        // Given: Flows and holdings below 2^127, a cost and a swap below 2^128.
        vm.assume(depositIn < 1 << 127 && depositOut < 1 << 127 && redeemOut < 1 << 127 && redeemIn < 1 << 127);
        vm.assume(heldIn < 1 << 127 && heldOut < 1 << 127 && swapCost < 1 << 128 && swapped < 1 << 128);

        // When: Taking the levies.
        (uint256 depositLevy, uint256 redeemLevy) =
            PlanCacheLib.getLevies(depositIn, depositOut, redeemOut, redeemIn, swapCost, swapped, heldIn, heldOut);

        // Then: Each is at most its flow and the swap's cost.
        assertLe(depositLevy, depositIn);
        assertLe(redeemLevy, redeemOut);
        assertLe(depositLevy, swapCost);
        assertLe(redeemLevy, swapCost);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getLevies_TogetherAreAtMostTheSwapsCostPlusOne(
        uint256 depositIn,
        uint256 depositOut,
        uint256 redeemOut,
        uint256 redeemIn,
        uint256 swapCost,
        uint256 swapped,
        uint256 heldIn,
        uint256 heldOut
    ) public pure {
        // Given: Flows and holdings below 2^127, a cost and a swap below 2^128.
        vm.assume(depositIn < 1 << 127 && depositOut < 1 << 127 && redeemOut < 1 << 127 && redeemIn < 1 << 127);
        vm.assume(heldIn < 1 << 127 && heldOut < 1 << 127 && swapCost < 1 << 128 && swapped < 1 << 128);

        // When: Taking the levies.
        (uint256 depositLevy, uint256 redeemLevy) =
            PlanCacheLib.getLevies(depositIn, depositOut, redeemOut, redeemIn, swapCost, swapped, heldIn, heldOut);

        // Then: Together they are at most the swap's cost plus one wei.
        assertLe(depositLevy + redeemLevy, swapCost + 1);
    }
}
