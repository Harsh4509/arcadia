/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Claimable, Epoch, Record, ShareAccount } from "../../../../src/core/types/State.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "creditRedeem" of library "QueueLib".
 */
contract CreditRedeem_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_creditRedeem_SkipsAPendingRecord(address vault, address controller, Record memory record)
        public
    {
        // Given: A redeem record in the pending epoch.
        queueLib.setPendingEpochs(vault, 0, record.epoch);
        queueLib.setRedeemRecord(vault, controller, record);

        // When: Crediting the record.
        queueLib.creditRedeem(vault, controller);

        // Then: The record stays and nothing reaches the pile.
        Record memory recordAfter = queueLib.getRedeemRecord(vault, controller);
        assertEq(recordAfter.amountIn, record.amountIn);
        assertEq(recordAfter.epoch, record.epoch);
        assertEq(queueLib.getClaimableRedeem(vault, controller).amountIn, 0);
    }

    function testFuzz_Success_creditRedeem_SkipsAnEmptyRecord(
        address vault,
        address controller,
        uint32 pendingEpoch,
        Record memory record
    ) public {
        // Given: An empty redeem record outside the pending epoch.
        pendingEpoch = uint32(bound(pendingEpoch, 0, type(uint32).max - 1));
        if (pendingEpoch >= record.epoch) ++pendingEpoch;
        record.amountIn = 0;
        queueLib.setPendingEpochs(vault, 0, pendingEpoch);
        queueLib.setRedeemRecord(vault, controller, record);

        // When: Crediting the record.
        queueLib.creditRedeem(vault, controller);

        // Then: The record stays and nothing reaches the pile.
        assertEq(queueLib.getRedeemRecord(vault, controller).epoch, record.epoch);
        assertEq(queueLib.getClaimableRedeem(vault, controller).amountIn, 0);
    }

    function testFuzz_Success_creditRedeem_CreditsASettledRecord(
        address vault,
        address controller,
        uint32 pendingEpoch,
        Record memory record,
        Epoch memory epoch,
        ShareAccount memory shareAccount
    ) public {
        // Given: A settled redeem record of the whole epoch.
        pendingEpoch = uint32(bound(pendingEpoch, 0, type(uint32).max - 1));
        if (pendingEpoch >= record.epoch) ++pendingEpoch;
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint128).max));
        epoch.amountIn = record.amountIn;
        queueLib.setPendingEpochs(vault, 0, pendingEpoch);
        queueLib.setRedeemRecord(vault, controller, record);
        queueLib.setRedeemEpoch(vault, record.epoch, epoch);

        // And: The record's shares pending on the controller.
        shareAccount.pendingShares = uint128(bound(shareAccount.pendingShares, record.amountIn, type(uint128).max));
        queueLib.setShareAccount(controller, shareAccount);

        // When: Crediting the record.
        queueLib.creditRedeem(vault, controller);

        // Then: The pile takes the record's shares and whole output, the record clears.
        Claimable memory claimable = queueLib.getClaimableRedeem(vault, controller);
        assertEq(claimable.amountIn, record.amountIn);
        assertEq(claimable.amountOut, epoch.amountOut);
        assertEq(queueLib.getRedeemRecord(vault, controller).amountIn, 0);

        // And: The shares leave the controller's pending shares.
        assertEq(queueLib.getShareAccount(controller).pendingShares, shareAccount.pendingShares - record.amountIn);
    }
}
