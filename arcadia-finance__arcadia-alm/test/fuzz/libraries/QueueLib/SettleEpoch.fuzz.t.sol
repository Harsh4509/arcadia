/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Epoch } from "../../../../src/core/types/State.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";

/**
 * @notice Fuzz tests for the function "settleEpoch" of library "QueueLib".
 */
contract SettleEpoch_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_settleEpoch_OutputPastUint128(Epoch memory epoch, uint256 amountOut) public {
        // Given: A pending epoch, and an output a uint128 does not hold.
        queueLib.setEpoch(epoch);
        amountOut = bound(amountOut, uint256(type(uint128).max) + 1, type(uint256).max);

        // When: Settling the epoch.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        queueLib.settleEpoch(amountOut);
    }

    function testFuzz_Success_settleEpoch_StoresOutput(Epoch memory epoch, uint128 amountOut) public {
        // Given: A pending epoch.
        queueLib.setEpoch(epoch);

        // When: Settling it.
        queueLib.settleEpoch(amountOut);

        // Then: It stores the output and keeps its input.
        Epoch memory epochAfter = queueLib.getEpoch();
        assertEq(epochAfter.amountIn, epoch.amountIn);
        assertEq(epochAfter.amountOut, amountOut);
    }
}
