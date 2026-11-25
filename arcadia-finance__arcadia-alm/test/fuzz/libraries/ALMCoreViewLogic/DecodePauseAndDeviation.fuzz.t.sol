/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { Config } from "../../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "decodePauseAndDeviation" of library "ALMCoreViewLogic".
 */
contract DecodePauseAndDeviation_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_decodePauseAndDeviation_ReadsItsFieldsFreeOfTheirNeighbours(Config memory config)
        public
        view
    {
        // Given: The pause and fees word, packed in storage order from its lowest byte.
        uint256 word = uint256(
            bytes32(
                abi.encodePacked(
                    config.rewardPoolToken,
                    config.windowEnd,
                    config.maxSpotFromTrusted,
                    config.maxSpotFromTwap,
                    config.twapWindow,
                    config.protocolSwapFeeBps,
                    config.protocolEmissionFeeBps,
                    config.paused
                )
            )
        );

        // When: Decoding the pause flag and the spot band around the TWAP.
        (bool paused, uint64 maxSpotFromTwap) = coreViewLogic.decodePauseAndDeviation(word);

        // Then: Both read back.
        assertEq(paused, config.paused);
        assertEq(maxSpotFromTwap, config.maxSpotFromTwap);
    }
}
