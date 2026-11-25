/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "isPending" of library "QueueLib".
 */
contract IsPending_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_isPending_ZeroAmount(uint256 recordEpoch, uint256 pendingEpoch) public view {
        // Given: An empty record in any epoch.

        // When: Checking whether it is pending.
        bool result = queueLib.isPending(recordEpoch, pendingEpoch, 0);

        // Then: It is not.
        assertFalse(result);
    }

    function testFuzz_Success_isPending_PendingEpoch(uint256 pendingEpoch, uint256 amount) public view {
        // Given: A record with an amount in the pending epoch.
        amount = bound(amount, 1, type(uint256).max);

        // When: Checking whether it is pending.
        bool result = queueLib.isPending(pendingEpoch, pendingEpoch, amount);

        // Then: It is pending.
        assertTrue(result);
    }

    function testFuzz_Success_isPending_EarlierEpoch(uint256 recordEpoch, uint256 pendingEpoch, uint256 amount)
        public
        view
    {
        // Given: A record with an amount in an epoch that is no longer the pending one.
        pendingEpoch = bound(pendingEpoch, 0, type(uint256).max - 1);
        if (pendingEpoch >= recordEpoch) ++pendingEpoch;
        amount = bound(amount, 1, type(uint256).max);

        // When: Checking whether it is pending.
        bool result = queueLib.isPending(recordEpoch, pendingEpoch, amount);

        // Then: It is not pending.
        assertFalse(result);
    }

    function testFuzz_Success_isPending_ZeroAmountInThePendingEpoch(uint256 pendingEpoch) public view {
        // Given: An empty record in the pending epoch.

        // When: Checking whether it is pending.
        bool result = queueLib.isPending(pendingEpoch, pendingEpoch, 0);

        // Then: It is not.
        assertFalse(result);
    }
}
