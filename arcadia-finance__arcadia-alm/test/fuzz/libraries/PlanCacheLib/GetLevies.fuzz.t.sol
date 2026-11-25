/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { PlanCacheLib_Fuzz_Test } from "./_PlanCacheLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "getLevies" of library "PlanCacheLib".
 */
contract GetLevies_PlanCacheLib_Fuzz_Test is PlanCacheLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getLevies_ZeroCost(
        uint256 depositIn,
        uint256 depositOut,
        uint256 redeemOut,
        uint256 redeemIn,
        uint256 swapped,
        uint256 heldIn,
        uint256 heldOut
    ) public view {
        // Given: Any flows, swap and holdings.
        depositIn = bound(depositIn, 0, Constants.MAX_FUZZED_AMOUNT);
        depositOut = bound(depositOut, 0, Constants.MAX_FUZZED_AMOUNT);
        redeemOut = bound(redeemOut, 0, Constants.MAX_FUZZED_AMOUNT);
        redeemIn = bound(redeemIn, 0, Constants.MAX_FUZZED_AMOUNT);
        swapped = bound(swapped, 0, Constants.MAX_FUZZED_AMOUNT);
        heldIn = bound(heldIn, 0, Constants.MAX_FUZZED_AMOUNT);
        heldOut = bound(heldOut, 0, Constants.MAX_FUZZED_AMOUNT);

        // When: Reading the levies of a swap that cost nothing.
        (uint256 depositLevy, uint256 redeemLevy) =
            planCacheLib.getLevies(depositIn, depositOut, redeemOut, redeemIn, 0, swapped, heldIn, heldOut);

        // Then: The flows are levied nothing.
        assertEq(depositLevy, 0);
        assertEq(redeemLevy, 0);
    }

    function testFuzz_Success_getLevies_ZeroSwapped(
        uint256 depositIn,
        uint256 depositOut,
        uint256 redeemOut,
        uint256 redeemIn,
        uint256 swapCost,
        uint256 heldIn,
        uint256 heldOut
    ) public view {
        // Given: Any flows and holdings, and a swap cost.
        depositIn = bound(depositIn, 0, Constants.MAX_FUZZED_AMOUNT);
        depositOut = bound(depositOut, 0, Constants.MAX_FUZZED_AMOUNT);
        redeemOut = bound(redeemOut, 0, Constants.MAX_FUZZED_AMOUNT);
        redeemIn = bound(redeemIn, 0, Constants.MAX_FUZZED_AMOUNT);
        swapCost = bound(swapCost, 1, Constants.MAX_FUZZED_AMOUNT);
        heldIn = bound(heldIn, 0, Constants.MAX_FUZZED_AMOUNT);
        heldOut = bound(heldOut, 0, Constants.MAX_FUZZED_AMOUNT);

        // When: Reading the levies of a swap that moved no token0 value.
        (uint256 depositLevy, uint256 redeemLevy) =
            planCacheLib.getLevies(depositIn, depositOut, redeemOut, redeemIn, swapCost, 0, heldIn, heldOut);

        // Then: The flows are levied nothing.
        assertEq(depositLevy, 0);
        assertEq(redeemLevy, 0);
    }

    function testFuzz_Success_getLevies_NothingHeld(
        uint256 depositIn,
        uint256 depositOut,
        uint256 redeemOut,
        uint256 redeemIn,
        uint256 swapCost,
        uint256 swapped
    ) public view {
        // Given: Any flows, and a swap that cost value.
        depositIn = bound(depositIn, 0, Constants.MAX_FUZZED_AMOUNT);
        depositOut = bound(depositOut, 0, Constants.MAX_FUZZED_AMOUNT);
        redeemOut = bound(redeemOut, 0, Constants.MAX_FUZZED_AMOUNT);
        redeemIn = bound(redeemIn, 0, Constants.MAX_FUZZED_AMOUNT);
        swapCost = bound(swapCost, 1, Constants.MAX_FUZZED_AMOUNT);
        swapped = bound(swapped, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: Reading the levies with nothing held after the payouts.
        (uint256 depositLevy, uint256 redeemLevy) =
            planCacheLib.getLevies(depositIn, depositOut, redeemOut, redeemIn, swapCost, swapped, 0, 0);

        // Then: The flows are levied nothing.
        assertEq(depositLevy, 0);
        assertEq(redeemLevy, 0);
    }

    function testFuzz_Success_getLevies_FlowsDidNotNeedTheSwap(
        uint256 deposit,
        uint256 redeem,
        uint256 offset0,
        uint256 offset1,
        uint256 swapCost,
        uint256 swapped,
        uint256 held
    ) public view {
        // Given: Equal holdings, and flows in the swap's direction twice their part.
        held = bound(held, 1, Constants.MAX_FUZZED_AMOUNT);
        deposit = bound(deposit, 0, Constants.MAX_FUZZED_AMOUNT / 4);
        redeem = bound(redeem, 0, Constants.MAX_FUZZED_AMOUNT / 4);

        // And: Offsetting flows whose part is at least the flows' part.
        offset0 = bound(offset0, 0, Constants.MAX_FUZZED_AMOUNT / 4);
        offset1 =
            bound(offset1, FixedPointMathLib.zeroFloorSub(deposit + redeem, offset0), Constants.MAX_FUZZED_AMOUNT / 2);

        // And: A swap that cost value.
        swapCost = bound(swapCost, 1, Constants.MAX_FUZZED_AMOUNT);
        swapped = bound(swapped, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: Reading the levies.
        (uint256 depositLevy, uint256 redeemLevy) =
            planCacheLib.getLevies(2 * deposit, 2 * offset0, 2 * redeem, 2 * offset1, swapCost, swapped, held, held);

        // Then: The flows are levied nothing.
        assertEq(depositLevy, 0);
        assertEq(redeemLevy, 0);
    }

    function testFuzz_Success_getLevies_ProRataRoundedUp(
        uint256 deposit,
        uint256 redeem,
        uint256 heldIn,
        uint256 heldOut,
        uint256 swapCost,
        uint256 swapped
    ) public view {
        // Given: Holdings and whole flows at their split, parts summing in an int128.
        uint256 most = FixedPointMathLib.sqrt(Constants.MAX_FUZZED_AMOUNT / 2);
        heldIn = bound(heldIn, 0, most);
        heldOut = bound(heldOut, 1, most);
        deposit = bound(deposit, 1, most);
        redeem = bound(redeem, 0, most);

        // And: A swap of at least their part, that cost at most what it moved.
        swapped = bound(swapped, deposit * heldOut + redeem * heldIn, Constants.MAX_FUZZED_AMOUNT);
        swapCost = bound(swapCost, 1, swapped);

        // When: Reading the levies.
        (uint256 depositLevy, uint256 redeemLevy) = planCacheLib.getLevies(
            deposit * (heldIn + heldOut), 0, redeem * (heldIn + heldOut), 0, swapCost, swapped, heldIn, heldOut
        );

        // Then: The cost at the swap's rate on their part is split pro rata, rounded up.
        (deposit, redeem) = (deposit * heldOut, redeem * heldIn);
        swapCost = FullMath.mulDivRoundingUp(swapCost, deposit + redeem, swapped);
        assertEq(depositLevy, FullMath.mulDivRoundingUp(swapCost, deposit, deposit + redeem));
        assertEq(redeemLevy, FullMath.mulDivRoundingUp(swapCost, redeem, deposit + redeem));
    }

    function testFuzz_Success_getLevies_EachLevyCappedAtItsFlow(
        uint256 deposit,
        uint256 redeem,
        uint256 held,
        uint256 swapCost,
        uint256 swapped
    ) public view {
        // Given: Equal holdings, and flows in the swap's direction twice their part.
        held = bound(held, 1, Constants.MAX_FUZZED_AMOUNT);
        deposit = bound(deposit, 1, Constants.MAX_FUZZED_AMOUNT / 8);
        redeem = bound(redeem, 1, Constants.MAX_FUZZED_AMOUNT / 8);

        // And: A swap no larger than their part, that cost at least twice their part.
        swapped = bound(swapped, 1, deposit + redeem);
        swapCost = bound(swapCost, 2 * (deposit + redeem), Constants.MAX_FUZZED_AMOUNT);

        // When: Reading the levies.
        (uint256 depositLevy, uint256 redeemLevy) =
            planCacheLib.getLevies(2 * deposit, 0, 2 * redeem, 0, swapCost, swapped, held, held);

        // Then: Each flow is levied its whole value and no more.
        assertEq(depositLevy, 2 * deposit);
        assertEq(redeemLevy, 2 * redeem);
    }

    function testFuzz_Success_getLevies_OnlyThePartAboveTheOffsettingFlows(
        uint256 deposit,
        uint256 redeem,
        uint256 offset0,
        uint256 offset1,
        uint256 swapCost,
        uint256 swapped,
        uint256 held
    ) public view {
        // Given: Equal holdings, and flows in the swap's direction twice their part.
        held = bound(held, 1, Constants.MAX_FUZZED_AMOUNT);
        deposit = bound(deposit, 1, Constants.MAX_FUZZED_AMOUNT / 4);
        redeem = bound(redeem, 1, Constants.MAX_FUZZED_AMOUNT / 4);

        // And: Offsetting flows whose part is below the flows' part.
        offset0 = bound(offset0, 0, deposit + redeem - 1);
        offset1 = bound(offset1, 0, deposit + redeem - 1 - offset0);

        // And: A swap of at least the net part, that cost at most what it moved.
        swapped = bound(swapped, deposit + redeem - offset0 - offset1, Constants.MAX_FUZZED_AMOUNT);
        swapCost = bound(swapCost, 1, swapped);

        // When: Reading the levies.
        (uint256 depositLevy, uint256 redeemLevy) =
            planCacheLib.getLevies(2 * deposit, 2 * offset0, 2 * redeem, 2 * offset1, swapCost, swapped, held, held);

        // Then: The cost on the net part is split pro rata over the flows, rounded up.
        swapCost = FullMath.mulDivRoundingUp(swapCost, deposit + redeem - offset0 - offset1, swapped);
        assertEq(depositLevy, FullMath.mulDivRoundingUp(swapCost, deposit, deposit + redeem));
        assertEq(redeemLevy, FullMath.mulDivRoundingUp(swapCost, redeem, deposit + redeem));
    }

    function testFuzz_Success_getLevies_PartCappedAtTheSwap(
        uint256 deposit,
        uint256 redeem,
        uint256 held,
        uint256 swapCost,
        uint256 swapped
    ) public view {
        // Given: Equal holdings, and flows in the swap's direction twice their part.
        held = bound(held, 1, Constants.MAX_FUZZED_AMOUNT);
        deposit = bound(deposit, 1, Constants.MAX_FUZZED_AMOUNT / 4);
        redeem = bound(redeem, 1, Constants.MAX_FUZZED_AMOUNT / 4);

        // And: A swap smaller than their part, that cost at most what it moved.
        swapped = bound(swapped, 1, deposit + redeem - 1);
        swapCost = bound(swapCost, 1, swapped);

        // When: Reading the levies.
        (uint256 depositLevy, uint256 redeemLevy) =
            planCacheLib.getLevies(2 * deposit, 0, 2 * redeem, 0, swapCost, swapped, held, held);

        // Then: The flows split the swap's whole cost pro rata, rounded up.
        assertEq(depositLevy, FullMath.mulDivRoundingUp(swapCost, deposit, deposit + redeem));
        assertEq(redeemLevy, FullMath.mulDivRoundingUp(swapCost, redeem, deposit + redeem));
    }

    function testFuzz_Success_getLevies_LossAboveTheRedeemValue(
        uint256 deposit,
        uint256 redeem,
        uint256 held,
        uint256 redeemValue,
        uint256 loss,
        uint256 swapped
    ) public view {
        // Given: Equal holdings, and flows in the swap's direction twice their part.
        held = bound(held, 1, Constants.MAX_FUZZED_AMOUNT);
        deposit = bound(deposit, 1, Constants.MAX_FUZZED_AMOUNT / 4);
        redeem = bound(redeem, 1, Constants.MAX_FUZZED_AMOUNT / 4);

        // And: A swap of at least their part, that lost more than the value before it.
        swapped = bound(swapped, deposit + redeem, Constants.MAX_FUZZED_AMOUNT);
        redeemValue = bound(redeemValue, 1, swapped - 1);
        loss = bound(loss, redeemValue + 1, swapped);

        // When: Reading the levies at the cost passed, capped at the value before.
        (uint256 depositLevy, uint256 redeemLevy) = planCacheLib.getLevies(
            2 * deposit,
            0,
            2 * redeem,
            0,
            redeemValue - FixedPointMathLib.zeroFloorSub(redeemValue, loss),
            swapped,
            held,
            held
        );

        // Then: The levies follow the cost passed, not the loss.
        redeemValue = FullMath.mulDivRoundingUp(redeemValue, deposit + redeem, swapped);
        assertEq(depositLevy, FullMath.mulDivRoundingUp(redeemValue, deposit, deposit + redeem));
        assertEq(redeemLevy, FullMath.mulDivRoundingUp(redeemValue, redeem, deposit + redeem));
    }
}
