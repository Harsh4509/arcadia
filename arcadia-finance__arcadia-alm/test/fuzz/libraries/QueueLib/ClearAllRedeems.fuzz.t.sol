/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";
import { stdError } from "@forge-std/StdError.sol";

/**
 * @notice Fuzz tests for the function "clearAllRedeems" of library "QueueLib".
 */
contract ClearAllRedeems_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_clearAllRedeems_IdsExhausted(address vault, bool pendingAtMax, uint32 epoch) public {
        // Given: A redeem queue whose pending or last cleared epoch holds the highest id.
        queueLib.setPendingEpochs(vault, 0, pendingAtMax ? type(uint32).max : epoch);
        queueLib.setLastClearedEpochs(vault, 0, pendingAtMax ? epoch : type(uint32).max);

        // When: Clearing all redeems.
        // Then: It reverts on the overflow.
        vm.expectRevert(stdError.arithmeticError);
        queueLib.clearAllRedeems(vault);
    }

    function testFuzz_Success_clearAllRedeems_ClearsThePendingEpochAndOpensAFreshOne(
        address vault,
        uint32 pendingEpoch,
        uint32 lastClearedEpoch
    ) public {
        // Given: A pending and a last cleared redeem epoch below the highest id.
        pendingEpoch = uint32(bound(pendingEpoch, 0, type(uint32).max - 1));
        lastClearedEpoch = uint32(bound(lastClearedEpoch, 0, type(uint32).max - 1));
        queueLib.setPendingEpochs(vault, 0, pendingEpoch);
        queueLib.setLastClearedEpochs(vault, 0, lastClearedEpoch);

        // When: Clearing all redeems.
        queueLib.clearAllRedeems(vault);

        // Then: The pending epoch is the cleared one.
        assertEq(queueLib.getLastClearedRedeemEpoch(vault), pendingEpoch);

        // And: A fresh id becomes the pending epoch, one above the highest issued.
        assertEq(queueLib.getPendingRedeemEpoch(vault), FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);

        // And: The cleared epoch holds no output yet.
        assertEq(queueLib.getRedeemEpoch(vault, pendingEpoch).amountOut, 0);
    }
}
