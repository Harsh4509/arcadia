/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CalldataLogic } from "../../../../src/core/libraries/logic/CalldataLogic.sol";
import { CalldataLogic_Fuzz_Test } from "./_CalldataLogic.fuzz.t.sol";
import { CalldataLogicExtension } from "../../../utils/extensions/CalldataLogicExtension.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

/**
 * @notice Fuzz tests for the function "decodeControllers" of library "CalldataLogic".
 */
// forge-lint: disable-next-item(unused-return)
contract DecodeControllers_CalldataLogic_Fuzz_Test is CalldataLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_decodeControllers_InvalidPayload_ShorterThanTheQueue(
        bytes calldata payload,
        uint256 length
    ) public {
        // Given: A payload shorter than a queue.
        payload = payload[:bound(length, 0, FixedPointMathLib.min(payload.length, CalldataLogic.QUEUE_LENGTH - 1))];

        // When: Decoding it.
        // Then: It reverts.
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        calldataLogic.decodeControllers(payload);
    }

    function testFuzz_Revert_decodeControllers_InvalidPayload_PartialController(
        bool isToken0,
        bool isDeposit,
        bytes calldata controllers,
        uint256 partialLength
    ) public {
        // Given: A queue followed by whole controllers and then part of one more.
        uint256 whole = controllers.length - controllers.length % CalldataLogic.CONTROLLER_LENGTH;
        partialLength = bound(partialLength, 1, CalldataLogic.CONTROLLER_LENGTH - 1);
        bytes memory payload = abi.encodePacked(isToken0, isDeposit, controllers[:whole], new bytes(partialLength));

        // When: Decoding it.
        // Then: It reverts.
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        calldataLogic.decodeControllers(payload);
    }

    function testFuzz_Success_decodeControllers_ReadsTheQueueAndCountsTheControllers(
        bool isToken0,
        bool isDeposit,
        bytes calldata controllers
    ) public view {
        // Given: A queue followed by whole controllers.
        uint256 count = controllers.length / CalldataLogic.CONTROLLER_LENGTH;
        bytes memory payload =
            abi.encodePacked(isToken0, isDeposit, controllers[:count * CalldataLogic.CONTROLLER_LENGTH]);

        // When: Decoding it.
        (bool decodedIsToken0, bool decodedIsDeposit, uint256 decodedCount) = calldataLogic.decodeControllers(payload);

        // Then: The queue comes back as it went in, with the controller count.
        assertEq(decodedIsToken0, isToken0);
        assertEq(decodedIsDeposit, isDeposit);
        assertEq(decodedCount, count);
    }

    function testFuzz_Success_decodeControllers_IgnoresTheBytesAfterThePayload(bool isToken0, bool isDeposit)
        public
        view
    {
        // Given: A queue with no controllers, followed by bytes that are all ones.
        bytes memory payload = abi.encodePacked(isToken0, isDeposit);

        // When: Decoding it.
        (bool success, bytes memory result) =
            decodeDirty(abi.encodeCall(CalldataLogicExtension.decodeControllers, (payload)), payload.length);

        // Then: The queue comes back as it went in, with no controllers.
        assertTrue(success);
        assertEq(keccak256(result), keccak256(abi.encode(isToken0, isDeposit, uint256(0))));
    }
}
