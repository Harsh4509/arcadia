/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CalldataLogic_Fuzz_Test } from "./_CalldataLogic.fuzz.t.sol";
import { CalldataLogicExtension } from "../../../utils/extensions/CalldataLogicExtension.sol";

/**
 * @notice Fuzz tests for the function "readController" of library "CalldataLogic".
 */
contract ReadController_CalldataLogic_Fuzz_Test is CalldataLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_readController_ReadsTheController(
        bool isToken0,
        bool isDeposit,
        address[4] memory controllers,
        uint256 count,
        uint256 index
    ) public view {
        // Given: A queue followed by a list of controllers.
        count = bound(count, 1, controllers.length);
        index = bound(index, 0, count - 1);
        bytes memory payload = abi.encodePacked(isToken0, isDeposit);
        for (uint256 i; i < count; ++i) {
            payload = abi.encodePacked(payload, controllers[i]);
        }

        // When: Reading one controller.
        address controller = calldataLogic.readController(payload, index);

        // Then: It comes back as it went in.
        assertEq(controller, controllers[index]);
    }

    function testFuzz_Success_readController_IgnoresTheBytesAfterThePayload(
        bool isToken0,
        bool isDeposit,
        address controller
    ) public view {
        // Given: A queue and one controller, followed by bytes that are all ones.
        bytes memory payload = abi.encodePacked(isToken0, isDeposit, controller);

        // When: Reading the controller.
        (bool success, bytes memory result) =
            decodeDirty(abi.encodeCall(CalldataLogicExtension.readController, (payload, uint256(0))), payload.length);

        // Then: It comes back as it went in.
        assertTrue(success);
        assertEq(keccak256(result), keccak256(abi.encode(controller)));
    }
}
