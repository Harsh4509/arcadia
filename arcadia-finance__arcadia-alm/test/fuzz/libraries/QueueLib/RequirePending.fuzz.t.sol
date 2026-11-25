/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { QueueLib } from "../../../../src/core/libraries/state/QueueLib.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "requirePending" of library "QueueLib".
 */
contract RequirePending_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_requirePending_ZeroAmount(uint256 recordEpoch, uint256 pendingEpoch) public {
        // Given: An empty record in any epoch.

        // When: Requiring it to be pending.
        // Then: It reverts.
        vm.expectRevert(QueueLib.RequestNotPending.selector);
        queueLib.requirePending(recordEpoch, pendingEpoch, 0);
    }

    function testFuzz_Revert_requirePending_EarlierEpoch(uint256 recordEpoch, uint256 pendingEpoch, uint256 amount)
        public
    {
        // Given: A record with an amount in an epoch that is no longer the pending one.
        pendingEpoch = bound(pendingEpoch, 0, type(uint256).max - 1);
        if (pendingEpoch >= recordEpoch) ++pendingEpoch;
        amount = bound(amount, 1, type(uint256).max);

        // When: Requiring it to be pending.
        // Then: It reverts.
        vm.expectRevert(QueueLib.RequestNotPending.selector);
        queueLib.requirePending(recordEpoch, pendingEpoch, amount);
    }

    function testFuzz_Success_requirePending_PendingEpoch(uint256 pendingEpoch, uint256 amount) public view {
        // Given: A record with an amount in the pending epoch.
        amount = bound(amount, 1, type(uint256).max);

        // When: Requiring it to be pending.
        (bool success,) =
            address(queueLib).staticcall(abi.encodeCall(queueLib.requirePending, (pendingEpoch, pendingEpoch, amount)));

        // Then: It does not revert.
        assertTrue(success);
    }
}
