/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";
import { stdError } from "@forge-std/StdError.sol";

/**
 * @notice Fuzz tests for the function "startClearedEpoch" of library "QueueLib".
 */
contract StartClearedEpoch_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_startClearedEpoch_IdsExhausted(
        address vault,
        bool deposits,
        bool pendingAtMax,
        uint32 epoch
    ) public {
        // Given: A queue whose pending or last cleared epoch holds the highest id.
        uint32 pendingEpoch = pendingAtMax ? type(uint32).max : epoch;
        uint32 lastClearedEpoch = pendingAtMax ? epoch : type(uint32).max;
        queueLib.setPendingEpochs(vault, pendingEpoch, pendingEpoch);
        queueLib.setLastClearedEpochs(vault, lastClearedEpoch, lastClearedEpoch);

        // When: Starting its cleared epoch.
        // Then: It reverts on the overflow.
        vm.expectRevert(stdError.arithmeticError);
        queueLib.startClearedEpoch(vault, deposits);
    }

    function testFuzz_Success_startClearedEpoch_DrawsAFreshIdAndLeavesThePendingEpoch(
        address vault,
        bool deposits,
        uint32 pendingEpoch,
        uint32 lastClearedEpoch
    ) public {
        // Given: A pending and a last cleared epoch below the highest id.
        pendingEpoch = uint32(bound(pendingEpoch, 0, type(uint32).max - 1));
        lastClearedEpoch = uint32(bound(lastClearedEpoch, 0, type(uint32).max - 1));
        queueLib.setPendingEpochs(vault, pendingEpoch, pendingEpoch);
        queueLib.setLastClearedEpochs(vault, lastClearedEpoch, lastClearedEpoch);

        // When: Starting the queue's cleared epoch.
        queueLib.startClearedEpoch(vault, deposits);

        // Then: The cleared epoch is a fresh id, one above the highest issued.
        assertEq(
            deposits ? queueLib.getLastClearedDepositEpoch(vault) : queueLib.getLastClearedRedeemEpoch(vault),
            FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1
        );

        // And: The pending epoch stays the same.
        assertEq(
            deposits ? queueLib.getPendingDepositEpoch(vault) : queueLib.getPendingRedeemEpoch(vault), pendingEpoch
        );

        // And: The other queue's ids are untouched.
        assertEq(
            deposits ? queueLib.getLastClearedRedeemEpoch(vault) : queueLib.getLastClearedDepositEpoch(vault),
            lastClearedEpoch
        );
        assertEq(
            deposits ? queueLib.getPendingRedeemEpoch(vault) : queueLib.getPendingDepositEpoch(vault), pendingEpoch
        );
    }
}
