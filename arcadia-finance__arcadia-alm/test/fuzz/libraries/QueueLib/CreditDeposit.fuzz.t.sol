/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Claimable, Epoch, Record, ShareAccount } from "../../../../src/core/types/State.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "creditDeposit" of library "QueueLib".
 */
contract CreditDeposit_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_creditDeposit_SkipsAPendingRecord(address vault, address controller, Record memory record)
        public
    {
        // Given: A deposit record in the pending epoch.
        queueLib.setPendingEpochs(vault, record.epoch, 0);
        queueLib.setDepositRecord(vault, controller, record);

        // When: Crediting the record.
        queueLib.creditDeposit(vault, controller);

        // Then: The record stays and nothing reaches the pile.
        Record memory recordAfter = queueLib.getDepositRecord(vault, controller);
        assertEq(recordAfter.amountIn, record.amountIn);
        assertEq(recordAfter.pendingShares, record.pendingShares);
        assertEq(queueLib.getClaimableDeposit(vault, controller).amountIn, 0);
    }

    function testFuzz_Success_creditDeposit_SkipsAnEmptyRecord(
        address vault,
        address controller,
        uint32 pendingEpoch,
        Record memory record
    ) public {
        // Given: An empty deposit record outside the pending epoch.
        pendingEpoch = uint32(bound(pendingEpoch, 0, type(uint32).max - 1));
        if (pendingEpoch >= record.epoch) ++pendingEpoch;
        record.amountIn = 0;
        queueLib.setPendingEpochs(vault, pendingEpoch, 0);
        queueLib.setDepositRecord(vault, controller, record);

        // When: Crediting the record.
        queueLib.creditDeposit(vault, controller);

        // Then: The record stays and nothing reaches the pile.
        assertEq(queueLib.getDepositRecord(vault, controller).pendingShares, record.pendingShares);
        assertEq(queueLib.getClaimableDeposit(vault, controller).amountIn, 0);
    }

    function testFuzz_Success_creditDeposit_CreditsASettledRecord(
        address vault,
        address controller,
        uint32 pendingEpoch,
        Record memory record,
        Epoch memory epoch,
        ShareAccount memory shareAccount
    ) public {
        // Given: A settled deposit of the whole epoch.
        pendingEpoch = uint32(bound(pendingEpoch, 0, type(uint32).max - 1));
        if (pendingEpoch >= record.epoch) ++pendingEpoch;
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint128).max));
        epoch.amountIn = record.amountIn;
        queueLib.setPendingEpochs(vault, pendingEpoch, 0);
        queueLib.setDepositRecord(vault, controller, record);
        queueLib.setDepositEpoch(vault, record.epoch, epoch);

        // And: The pending aLP covered, and room in the escrow for the epoch's output.
        shareAccount.pendingShares = uint128(bound(shareAccount.pendingShares, record.pendingShares, type(uint128).max));
        shareAccount.claimableShares =
            uint128(bound(shareAccount.claimableShares, 0, type(uint128).max - epoch.amountOut));
        queueLib.setShareAccount(controller, shareAccount);

        // When: Crediting the record.
        queueLib.creditDeposit(vault, controller);

        // Then: The pile takes the record's input and whole output, the record clears.
        Claimable memory claimable = queueLib.getClaimableDeposit(vault, controller);
        assertEq(claimable.amountIn, record.amountIn);
        assertEq(claimable.amountOut, epoch.amountOut);
        assertEq(queueLib.getDepositRecord(vault, controller).amountIn, 0);

        // And: The pending aLP is released and the output is escrowed for the controller.
        ShareAccount memory shareAccountAfter = queueLib.getShareAccount(controller);
        assertEq(shareAccountAfter.pendingShares, shareAccount.pendingShares - record.pendingShares);
        assertEq(shareAccountAfter.claimableShares, uint256(shareAccount.claimableShares) + epoch.amountOut);
    }
}
