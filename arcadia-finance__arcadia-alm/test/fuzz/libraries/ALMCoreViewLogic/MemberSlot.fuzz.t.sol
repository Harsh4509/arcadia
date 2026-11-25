/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { STATE_SLOT } from "../../../../src/core/abstracts/storage/Storage.sol";

/**
 * @notice Fuzz tests for the function "memberSlot" of library "ALMCoreViewLogic".
 */
contract MemberSlot_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_memberSlot_IsTheStateSlotPlusTheOffset(uint256 offset) public view {
        // Given: Any member offset the state slot does not overflow at.
        offset = bound(offset, 0, type(uint256).max - uint256(STATE_SLOT));

        // When: Deriving the member's slot.
        bytes32 slot = coreViewLogic.memberSlot(offset);

        // Then: It is the offset past the state's ERC-7201 slot.
        assertEq(slot, bytes32(uint256(STATE_SLOT) + offset));
    }
}
