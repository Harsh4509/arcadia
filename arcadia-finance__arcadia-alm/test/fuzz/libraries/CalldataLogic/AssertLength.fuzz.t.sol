/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CalldataLogic } from "../../../../src/core/libraries/logic/CalldataLogic.sol";
import { CalldataLogic_Fuzz_Test } from "./_CalldataLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "assertLength" of library "CalldataLogic".
 */
contract AssertLength_CalldataLogic_Fuzz_Test is CalldataLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_assertLength_InvalidPayload(bytes calldata payload, uint256 length) public {
        // Given: A length the payload does not have.
        unchecked {
            length = payload.length + bound(length, 1, type(uint256).max);
        }

        // When: Asserting it.
        // Then: It reverts.
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        calldataLogic.assertLength(payload, length);
    }

    function testFuzz_Success_assertLength_MatchingLength(bytes calldata payload) public view {
        // Given: A payload.

        // When: Asserting its own length.
        (bool success,) =
            address(calldataLogic).staticcall(abi.encodeCall(calldataLogic.assertLength, (payload, payload.length)));

        // Then: It does not revert.
        assertTrue(success);
    }
}
