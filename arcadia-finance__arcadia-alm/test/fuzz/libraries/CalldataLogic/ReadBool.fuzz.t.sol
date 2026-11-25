/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CalldataLogic_Fuzz_Test } from "./_CalldataLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "readBool" of library "CalldataLogic".
 */
contract ReadBool_CalldataLogic_Fuzz_Test is CalldataLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_readBool_TrueForAnyNonZeroByte(bytes memory head, uint8 flag, bytes memory tail)
        public
        view
    {
        // Given: A payload with a flag byte after a fuzzed head.
        bytes memory payload = abi.encodePacked(head, flag, tail);

        // When: Reading the flag.
        bool read = calldataLogic.readBool(payload, head.length);

        // Then: It is true exactly when the byte is non-zero.
        assertEq(read, flag != 0);
    }
}
