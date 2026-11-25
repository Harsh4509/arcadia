/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { Record } from "../../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getDepositRecord" of library "ALMCoreViewLogic".
 */
contract GetDepositRecord_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getDepositRecord_ReadsTheWord(address vault, address controller_, Record memory record)
        public
    {
        // Given: A deposit record.
        almCore.setDepositRecord(vault, controller_, record);

        // When: Reading it.
        Record memory read = coreViewLogic.getDepositRecord(address(almCore), vault, controller_);

        // Then: Every field reads back.
        assertEq(read.epoch, record.epoch);
        assertEq(read.amountIn, record.amountIn);
        assertEq(read.pendingShares, record.pendingShares);
    }
}
