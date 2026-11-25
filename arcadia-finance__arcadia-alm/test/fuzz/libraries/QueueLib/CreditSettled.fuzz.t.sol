/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Claimable, Epoch, Record } from "../../../../src/core/types/State.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";
import { stdError } from "@forge-std/StdError.sol";

/**
 * @notice Fuzz tests for the function "creditSettled" of library "QueueLib".
 */
contract CreditSettled_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_creditSettled_PileInPastUint128(
        uint128 amount,
        uint128 amountOut,
        Claimable memory claimable
    ) public {
        // Given: A record taking its whole epoch, and an input pile it pushes past cap.
        amount = uint128(bound(amount, 1, type(uint128).max));
        claimable.amountIn = uint128(bound(claimable.amountIn, type(uint128).max - amount + 1, type(uint128).max));
        claimable.amountOut = uint128(bound(claimable.amountOut, 0, type(uint128).max - amountOut));
        queueLib.setRecord(0, Record({ epoch: 0, amountIn: amount, pendingShares: 0 }));
        queueLib.setEpoch(Epoch({ amountIn: amount, amountOut: amountOut }));
        queueLib.setClaimable(claimable);

        // When: Crediting it.
        // Then: It reverts on the overflow.
        vm.expectRevert(stdError.arithmeticError);
        queueLib.creditSettled(0);
    }

    function testFuzz_Revert_creditSettled_PileOutPastUint128(
        uint128 amount,
        uint128 amountOut,
        Claimable memory claimable
    ) public {
        // Given: A record taking its whole epoch, and an output pile it pushes past cap.
        amount = uint128(bound(amount, 1, type(uint128).max));
        amountOut = uint128(bound(amountOut, 1, type(uint128).max));
        claimable.amountIn = uint128(bound(claimable.amountIn, 0, type(uint128).max - amount));
        claimable.amountOut = uint128(bound(claimable.amountOut, type(uint128).max - amountOut + 1, type(uint128).max));
        queueLib.setRecord(0, Record({ epoch: 0, amountIn: amount, pendingShares: 0 }));
        queueLib.setEpoch(Epoch({ amountIn: amount, amountOut: amountOut }));
        queueLib.setClaimable(claimable);

        // When: Crediting it.
        // Then: It reverts on the overflow.
        vm.expectRevert(stdError.arithmeticError);
        queueLib.creditSettled(0);
    }

    function testFuzz_Success_creditSettled_CreditsTheRecord(
        uint32 recordEpoch,
        uint128 amount,
        uint128 amountIn,
        uint128 amountOut,
        uint96 pendingShares
    ) public {
        // Given: A settled record against the remainders of its epoch.
        amount = uint128(bound(amount, 1, type(uint128).max));
        amountIn = uint128(bound(amountIn, amount, type(uint128).max));
        queueLib.setRecord(0, Record({ epoch: recordEpoch, amountIn: amount, pendingShares: pendingShares }));
        queueLib.setEpoch(Epoch({ amountIn: amountIn, amountOut: amountOut }));

        // When: Crediting it.
        (uint256 credited, uint256 cleared) = queueLib.creditSettled(0);

        // Then: It takes its amount at the remaining rate, rounded down.
        assertEq(credited, uint256(amount) * amountOut / amountIn);

        // And: Both remainders fall by its input and output.
        Epoch memory epoch = queueLib.getEpoch();
        assertEq(epoch.amountIn, amountIn - amount);
        assertEq(epoch.amountOut, amountOut - credited);

        // And: The pile takes both, and the record is cleared, its pending aLP returned.
        Claimable memory claimable = queueLib.getClaimable();
        assertEq(claimable.amountIn, amount);
        assertEq(claimable.amountOut, credited);
        Record memory record_ = queueLib.getRecord(0);
        assertEq(record_.epoch, 0);
        assertEq(record_.amountIn, 0);
        assertEq(record_.pendingShares, 0);
        assertEq(cleared, pendingShares);
    }

    function testFuzz_Success_creditSettled_AddsToThePile(uint128 amount, uint128 amountOut, Claimable memory claimable)
        public
    {
        // Given: A record taking its whole epoch, and a claimable pile with room for it.
        amount = uint128(bound(amount, 1, type(uint128).max));
        claimable.amountIn = uint128(bound(claimable.amountIn, 0, type(uint128).max - amount));
        claimable.amountOut = uint128(bound(claimable.amountOut, 0, type(uint128).max - amountOut));
        queueLib.setRecord(0, Record({ epoch: 0, amountIn: amount, pendingShares: 0 }));
        queueLib.setEpoch(Epoch({ amountIn: amount, amountOut: amountOut }));
        queueLib.setClaimable(claimable);

        // When: Crediting it.
        queueLib.creditSettled(0);

        // Then: Both sides of the pile grow by the record's input and the epoch's output.
        Claimable memory claimableAfter = queueLib.getClaimable();
        assertEq(claimableAfter.amountIn, uint256(claimable.amountIn) + amount);
        assertEq(claimableAfter.amountOut, uint256(claimable.amountOut) + amountOut);
    }

    function testFuzz_Success_creditSettled_SplitSumsToAmountOut(uint128[4] memory amounts, uint128 amountOut) public {
        // Given: An epoch split over four settled records.
        uint256 amountIn;
        for (uint256 i; i < 4; ++i) {
            amounts[i] = uint128(bound(amounts[i], 1, type(uint128).max / 4));
            amountIn += amounts[i];
            queueLib.setRecord(i, Record({ epoch: 0, amountIn: amounts[i], pendingShares: 0 }));
        }
        queueLib.setEpoch(Epoch({ amountIn: uint128(amountIn), amountOut: amountOut }));

        // When: Crediting every record in turn.
        uint256 credited;
        for (uint256 i; i < 3; ++i) {
            (uint256 amountOut_,) = queueLib.creditSettled(i);
            credited += amountOut_;
        }
        (uint256 last,) = queueLib.creditSettled(3);

        // Then: The last record takes the remainder, so the outputs sum to amountOut.
        assertEq(credited + last, amountOut);

        // And: Both remainders reach zero.
        Epoch memory epoch = queueLib.getEpoch();
        assertEq(epoch.amountIn, 0);
        assertEq(epoch.amountOut, 0);
    }

    function testFuzz_Success_creditSettled_RemainingRateNeverDrops(uint128[4] memory amounts, uint128 amountOut)
        public
    {
        // Given: An epoch split over four settled records.
        uint256 amountIn;
        for (uint256 i; i < 4; ++i) {
            amounts[i] = uint128(bound(amounts[i], 1, type(uint128).max / 4));
            amountIn += amounts[i];
            queueLib.setRecord(i, Record({ epoch: 0, amountIn: amounts[i], pendingShares: 0 }));
        }
        queueLib.setEpoch(Epoch({ amountIn: uint128(amountIn), amountOut: amountOut }));

        for (uint256 i; i < 4; ++i) {
            // When: Crediting the next record.
            (uint256 credited,) = queueLib.creditSettled(i);

            // Then: It gets at least its amount at the settled rate, rounded down.
            assertGt((credited + 1) * amountIn, uint256(amounts[i]) * amountOut);

            // And: The remaining rate is at least the settled rate.
            Epoch memory epoch = queueLib.getEpoch();
            assertGe(uint256(epoch.amountOut) * amountIn, uint256(amountOut) * epoch.amountIn);
        }
    }
}
