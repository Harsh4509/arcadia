/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Epoch, Record, ShareAccount } from "../../../../src/core/types/State.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "clearRedeem" of library "QueueLib".
 */
contract ClearRedeem_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_clearRedeem_MovesTheRequestIntoTheClearedEpoch(
        address vault,
        address controller,
        uint32 pendingEpoch,
        uint32 lastClearedEpoch,
        Record memory record,
        ShareAccount memory shareAccount,
        uint128 otherIn,
        uint128 clearedIn
    ) public {
        // Given: A pending redeem record, its shares pending.
        lastClearedEpoch = uint32(bound(lastClearedEpoch, 0, type(uint32).max - 1));
        if (lastClearedEpoch >= pendingEpoch) ++lastClearedEpoch;
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint128).max));
        record.epoch = pendingEpoch;
        record.pendingShares = 0;
        queueLib.setPendingEpochs(vault, 0, pendingEpoch);
        queueLib.setRedeemRecord(vault, controller, record);
        queueLib.setShareAccount(controller, shareAccount);

        // And: Other requests in the pending epoch, earlier clears in the cleared one.
        otherIn = uint128(bound(otherIn, 0, type(uint128).max - record.amountIn));
        clearedIn = uint128(bound(clearedIn, 0, type(uint128).max - record.amountIn - otherIn));
        queueLib.setLastClearedEpochs(vault, 0, lastClearedEpoch);
        queueLib.setRedeemEpoch(vault, pendingEpoch, Epoch({ amountIn: record.amountIn + otherIn, amountOut: 0 }));
        queueLib.setRedeemEpoch(vault, lastClearedEpoch, Epoch({ amountIn: clearedIn, amountOut: 0 }));

        // When: Clearing the redeem.
        queueLib.clearRedeem(vault, controller);

        // Then: The record sits in the cleared epoch, with its shares.
        Record memory recordAfter = queueLib.getRedeemRecord(vault, controller);
        assertEq(recordAfter.epoch, lastClearedEpoch);
        assertEq(recordAfter.amountIn, record.amountIn);

        // And: Its shares move from the pending epoch's input to the cleared epoch's.
        assertEq(queueLib.getRedeemEpoch(vault, pendingEpoch).amountIn, otherIn);
        assertEq(queueLib.getRedeemEpoch(vault, lastClearedEpoch).amountIn, uint256(clearedIn) + record.amountIn);

        // And: The controller's pending aLP is untouched.
        assertEq(queueLib.getShareAccount(controller).pendingShares, shareAccount.pendingShares);
    }
}
