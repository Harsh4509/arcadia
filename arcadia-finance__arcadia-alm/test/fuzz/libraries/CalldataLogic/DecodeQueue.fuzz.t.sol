/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CalldataLogic } from "../../../../src/core/libraries/logic/CalldataLogic.sol";
import { CalldataLogic_Fuzz_Test } from "./_CalldataLogic.fuzz.t.sol";
import { CalldataLogicExtension } from "../../../utils/extensions/CalldataLogicExtension.sol";

/**
 * @notice Fuzz tests for the function "decodeQueue" of library "CalldataLogic".
 */
// forge-lint: disable-next-item(unused-return)
contract DecodeQueue_CalldataLogic_Fuzz_Test is CalldataLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_decodeQueue_InvalidPayload(bytes calldata data, uint256 length) public {
        // Given: A payload that is not the length of a queue.
        bytes memory payload = givenInvalidLength(data, CalldataLogic.QUEUE_LENGTH, length);

        // When: Decoding it.
        // Then: It reverts.
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        calldataLogic.decodeQueue(payload);
    }

    function testFuzz_Success_decodeQueue_ReadsTheVaultSideAndTheQueue(bool isToken0, bool isDeposit) public view {
        // Given: A payload packed the way the keeper packs it.
        bytes memory payload = abi.encodePacked(isToken0, isDeposit);

        // When: Decoding it.
        (bool decodedIsToken0, bool decodedIsDeposit) = calldataLogic.decodeQueue(payload);

        // Then: The vault side and the queue come back as they went in.
        assertEq(decodedIsToken0, isToken0);
        assertEq(decodedIsDeposit, isDeposit);
    }

    function testFuzz_Success_decodeQueue_IgnoresTheBytesAfterThePayload(bool isToken0, bool isDeposit) public view {
        // Given: A payload packed as the keeper packs it, then bytes of all ones.
        bytes memory payload = abi.encodePacked(isToken0, isDeposit);

        // When: Decoding it.
        (bool success, bytes memory result) =
            decodeDirty(abi.encodeCall(CalldataLogicExtension.decodeQueue, (payload)), payload.length);

        // Then: The vault side and the queue come back as they went in.
        assertTrue(success);
        assertEq(keccak256(result), keccak256(abi.encode(isToken0, isDeposit)));
    }
}
