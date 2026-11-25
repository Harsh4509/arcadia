/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { STATE_SLOT } from "../../../../src/core/abstracts/storage/Storage.sol";

/**
 * @notice Fuzz tests for the function "queueSlot" of library "ALMCoreViewLogic".
 */
contract QueueSlot_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_queueSlot_IsTheOffsetPastTheVaultsQueue(address vault, uint256 offset) public view {
        // Given: Any vault, and any offset into its queue.

        // When: Deriving the queue member's slot.
        bytes32 slot = coreViewLogic.queueSlot(vault, offset);

        // Then: It is the offset past the vault's entry of the queues mapping at B + 20.
        uint256 expected;
        unchecked {
            expected = uint256(keccak256(abi.encode(vault, uint256(STATE_SLOT) + 20))) + offset;
        }
        assertEq(slot, bytes32(expected));
    }
}
