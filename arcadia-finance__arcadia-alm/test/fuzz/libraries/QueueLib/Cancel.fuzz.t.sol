/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Epoch, Record } from "../../../../src/core/types/State.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "cancel" of library "QueueLib".
 */
contract Cancel_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_cancel_EmptiesTheRecordAndLowersTheEpoch(Record memory record, Epoch memory epoch)
        public
    {
        // Given: A pending record with its pending aLP, inside the epoch input.
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint128).max));
        epoch.amountIn = uint128(bound(epoch.amountIn, record.amountIn, type(uint128).max));
        queueLib.setRecord(0, record);
        queueLib.setEpoch(epoch);

        // When: Cancelling it.
        uint256 released = queueLib.cancel(0);

        // Then: All its pending aLP is released.
        assertEq(released, record.pendingShares);

        // And: The record is empty.
        Record memory recordAfter = queueLib.getRecord(0);
        assertEq(recordAfter.epoch, 0);
        assertEq(recordAfter.amountIn, 0);
        assertEq(recordAfter.pendingShares, 0);

        // And: The epoch input falls by the record's amount, its output unchanged.
        assertEq(queueLib.getEpoch().amountIn, epoch.amountIn - record.amountIn);
        assertEq(queueLib.getEpoch().amountOut, epoch.amountOut);
    }
}
