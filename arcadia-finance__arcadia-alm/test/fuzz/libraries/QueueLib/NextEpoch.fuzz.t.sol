/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";
import { stdError } from "@forge-std/StdError.sol";

/**
 * @notice Fuzz tests for the function "nextEpoch" of library "QueueLib".
 */
contract NextEpoch_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_nextEpoch_PastUint32(
        address vault,
        bool deposits,
        bool pendingIsHighest,
        uint32 otherEpoch
    ) public {
        // Given: A queue whose highest epoch id is the last a uint32 holds.
        (uint32 pendingEpoch, uint32 lastClearedEpoch) =
            pendingIsHighest ? (type(uint32).max, otherEpoch) : (otherEpoch, type(uint32).max);
        queueLib.setPendingEpochs(vault, pendingEpoch, pendingEpoch);
        queueLib.setLastClearedEpochs(vault, lastClearedEpoch, lastClearedEpoch);

        // When: Reading the next epoch id.
        // Then: It reverts.
        vm.expectRevert(stdError.arithmeticError);
        queueLib.nextEpoch(vault, deposits);
    }

    function testFuzz_Success_nextEpoch_TheHighestIdPlusOne(
        address vault,
        bool deposits,
        uint32 pendingEpoch,
        uint32 lastClearedEpoch,
        uint32 otherEpoch
    ) public {
        // Given: A queue whose epoch ids are below the last a uint32 holds.
        pendingEpoch = uint32(bound(pendingEpoch, 0, type(uint32).max - 1));
        lastClearedEpoch = uint32(bound(lastClearedEpoch, 0, type(uint32).max - 1));

        // And: The other queue of the vault at any ids.
        if (deposits) {
            queueLib.setPendingEpochs(vault, pendingEpoch, otherEpoch);
            queueLib.setLastClearedEpochs(vault, lastClearedEpoch, otherEpoch);
        } else {
            queueLib.setPendingEpochs(vault, otherEpoch, pendingEpoch);
            queueLib.setLastClearedEpochs(vault, otherEpoch, lastClearedEpoch);
        }

        // When: Reading the next epoch id.
        uint32 epoch = queueLib.nextEpoch(vault, deposits);

        // Then: It is one past the higher of the pending and the last cleared id.
        assertEq(epoch, uint256(pendingEpoch > lastClearedEpoch ? pendingEpoch : lastClearedEpoch) + 1);
    }
}
