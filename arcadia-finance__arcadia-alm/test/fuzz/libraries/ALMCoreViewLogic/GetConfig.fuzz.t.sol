/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { Config } from "../../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getConfig" of library "ALMCoreViewLogic".
 */
contract GetConfig_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
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

    function testFuzz_Success_getConfig_ReadsEveryFieldFreeOfItsNeighbours(Config memory config) public {
        // Given: Every field of the configuration, written through the accessor.
        almCore.setConfig(config);

        // When: Reading the configuration.
        Config memory read = coreViewLogic.getConfig(address(almCore));

        // Then: Every field reads back.
        assertEq(read.totalCap, config.totalCap);
        assertEq(read.perUserCap, config.perUserCap);
        assertEq(read.paused, config.paused);
        assertEq(read.protocolEmissionFeeBps, config.protocolEmissionFeeBps);
        assertEq(read.protocolSwapFeeBps, config.protocolSwapFeeBps);
        assertEq(read.feeRecipient, config.feeRecipient);
        assertEq(read.twapWindow, config.twapWindow);
        assertEq(read.maxSpotFromTwap, config.maxSpotFromTwap);
        assertEq(read.maxSpotFromTrusted, config.maxSpotFromTrusted);
        assertEq(read.maxTwapFromTrusted, config.maxTwapFromTrusted);
        assertEq(read.maxShortfallBps, config.maxShortfallBps);
        assertEq(read.maxSwapCostBps, config.maxSwapCostBps);
        assertEq(read.minPlanInterval, config.minPlanInterval);
        assertEq(read.rangeCap, config.rangeCap);
        assertEq(read.lastPlanAt, config.lastPlanAt);
        assertEq(read.windowEnd, config.windowEnd);
        assertEq(read.rewardPoolToken, config.rewardPoolToken);
        assertEq(read.arbBlockNumber, config.arbBlockNumber);
    }
}
