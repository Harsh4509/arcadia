/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { STATE_SLOT } from "../../../../src/core/abstracts/storage/Storage.sol";

/**
 * @notice Fuzz tests for the function "mappingSlot" of library "ALMCoreViewLogic".
 */
contract MappingSlot_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_mappingSlot_IsTheKeysEntryOfTheMember(address key, uint256 offset) public view {
        // Given: Any key, and any member offset the state slot does not overflow at.
        offset = bound(offset, 0, type(uint256).max - uint256(STATE_SLOT));

        // When: Deriving the entry's slot.
        bytes32 slot = coreViewLogic.mappingSlot(key, offset);

        // Then: The hash of the key and the member's slot, Solidity's mapping layout.
        assertEq(slot, keccak256(abi.encode(key, uint256(STATE_SLOT) + offset)));
    }
}
