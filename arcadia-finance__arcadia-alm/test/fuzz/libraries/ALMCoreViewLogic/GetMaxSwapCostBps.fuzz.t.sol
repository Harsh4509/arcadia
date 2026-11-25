/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { Config } from "../../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getMaxSwapCostBps" of library "ALMCoreViewLogic".
 */
contract GetMaxSwapCostBps_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
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

    function testFuzz_Success_getMaxSwapCostBps_ReadsTheMaxSwapCostFreeOfItsNeighbours(Config memory config) public {
        // Given: Every field of the configuration, written through it.
        almCore.setConfig(config);

        // When: Reading the max swap cost.
        uint16 maxSwapCostBps = coreViewLogic.getMaxSwapCostBps(address(almCore));

        // Then: It reads back, as the core's own accessor reads it.
        assertEq(maxSwapCostBps, config.maxSwapCostBps);
        assertEq(maxSwapCostBps, almCore.maxSwapCostBps_());
    }
}
