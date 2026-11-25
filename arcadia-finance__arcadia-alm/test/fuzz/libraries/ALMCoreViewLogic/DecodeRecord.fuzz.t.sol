/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { Record } from "../../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "decodeRecord" of library "ALMCoreViewLogic".
 */
contract DecodeRecord_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_decodeRecord_ReadsEveryFieldFreeOfItsNeighbours(Record memory record) public view {
        // Given: A record's word, packed in storage order from its lowest byte.
        bytes32 word = bytes32(abi.encodePacked(record.pendingShares, record.amountIn, record.epoch));

        // When: Decoding it.
        (uint32 epoch, uint128 amountIn, uint96 pendingShares) = coreViewLogic.decodeRecord(word);

        // Then: Every field reads back.
        assertEq(epoch, record.epoch);
        assertEq(amountIn, record.amountIn);
        assertEq(pendingShares, record.pendingShares);
    }
}
