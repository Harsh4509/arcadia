/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { Record } from "../../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getRedeemRecord" of library "ALMCoreViewLogic".
 */
contract GetRedeemRecord_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
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

    function testFuzz_Success_getRedeemRecord_ReadsTheWord(address vault, address controller_, Record memory record)
        public
    {
        // Given: A redeem record.
        almCore.setRedeemRecord(vault, controller_, record);

        // When: Reading it.
        Record memory read = coreViewLogic.getRedeemRecord(address(almCore), vault, controller_);

        // Then: Every field reads back.
        assertEq(read.epoch, record.epoch);
        assertEq(read.amountIn, record.amountIn);
        assertEq(read.pendingShares, record.pendingShares);
    }
}
