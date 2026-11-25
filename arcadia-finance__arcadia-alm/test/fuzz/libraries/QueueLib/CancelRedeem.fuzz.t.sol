/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Epoch, Record, ShareAccount } from "../../../../src/core/types/State.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "cancelRedeem" of library "QueueLib".
 */
contract CancelRedeem_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_cancelRedeem_TakesTheRequestBack(
        address vault,
        address controller,
        uint32 pendingEpoch,
        Record memory record,
        ShareAccount memory shareAccount
    ) public {
        // Given: A pending redeem record of the whole pending epoch.
        record.epoch = pendingEpoch;
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint128).max));
        record.pendingShares = 0;
        queueLib.setPendingEpochs(vault, 0, pendingEpoch);
        queueLib.setRedeemRecord(vault, controller, record);
        queueLib.setRedeemEpoch(vault, pendingEpoch, Epoch({ amountIn: record.amountIn, amountOut: 0 }));

        // And: The record's shares pending on the controller.
        shareAccount.pendingShares = uint128(bound(shareAccount.pendingShares, record.amountIn, type(uint128).max));
        queueLib.setShareAccount(controller, shareAccount);

        // When: Cancelling the redeem.
        queueLib.cancelRedeem(vault, controller);

        // Then: The record is empty, and the pending epoch falls by its shares.
        assertEq(queueLib.getRedeemRecord(vault, controller).amountIn, 0);
        assertEq(queueLib.getRedeemEpoch(vault, pendingEpoch).amountIn, 0);

        // And: The shares leave the controller's pending shares.
        assertEq(queueLib.getShareAccount(controller).pendingShares, shareAccount.pendingShares - record.amountIn);
    }
}
