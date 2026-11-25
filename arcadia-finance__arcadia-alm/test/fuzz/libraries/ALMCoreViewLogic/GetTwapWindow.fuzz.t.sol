/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { Config } from "../../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getTwapWindow" of library "ALMCoreViewLogic".
 */
contract GetTwapWindow_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getTwapWindow_ReadsTheWindowFreeOfItsNeighbours(Config memory config) public {
        // Given: Every field of the configuration, written through it.
        almCore.setConfig(config);

        // When: Reading the TWAP window.
        uint32 twapWindow = coreViewLogic.getTwapWindow(address(almCore));

        // Then: It reads back.
        assertEq(twapWindow, config.twapWindow);
    }
}
