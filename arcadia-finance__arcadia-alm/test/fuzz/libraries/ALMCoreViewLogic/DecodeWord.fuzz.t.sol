/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "decodeWord" of library "ALMCoreViewLogic".
 */
contract DecodeWord_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_decodeWord_ReadsBothHalves(uint128 low, uint128 high) public view {
        // Given: A word holding two uint128 values, the first in its lowest bytes.
        bytes32 word = bytes32(abi.encodePacked(high, low));

        // When: Decoding it.
        (uint128 decodedLow, uint128 decodedHigh) = coreViewLogic.decodeWord(word);

        // Then: Both halves read back.
        assertEq(decodedLow, low);
        assertEq(decodedHigh, high);
    }
}
