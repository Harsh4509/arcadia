/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CalldataLogicExtension } from "../../../utils/extensions/CalldataLogicExtension.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";

/**
 * @notice Common logic needed by all "CalldataLogic" fuzz tests.
 */
abstract contract CalldataLogic_Fuzz_Test is Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    CalldataLogicExtension internal calldataLogic;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();
        calldataLogic = new CalldataLogicExtension();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function decodeDirty(bytes memory callData, uint256 payloadLength)
        internal
        view
        returns (bool success, bytes memory result)
    {
        bytes memory dirty = bytes.concat(callData, bytes32(type(uint256).max));
        for (uint256 i = callData.length - (32 - payloadLength % 32) % 32; i < callData.length; ++i) {
            dirty[i] = 0xff;
        }

        (success, result) = address(calldataLogic).staticcall(dirty);
    }

    function givenInvalidLength(bytes calldata data, uint256 validLength, uint256 length)
        internal
        pure
        returns (bytes memory payload)
    {
        // And: The data cut or zero padded to any length but the valid one.
        uint256 maxLength = FixedPointMathLib.max(data.length, validLength + 1);
        length = (validLength + bound(length, 1, maxLength)) % (maxLength + 1);
        uint256 kept = FixedPointMathLib.min(length, data.length);
        payload = bytes.concat(data[:kept], new bytes(length - kept));
    }
}
