/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { ConfigLib_Fuzz_Test } from "./_ConfigLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the fee cap of library "ConfigLib".
 */
contract MaxFeeBps_ConfigLib_Fuzz_Test is ConfigLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_maxFeeBps_MatchesTheSpec(uint16 feeBps) public pure {
        // Given: Any protocol fee in basis points.

        // When: Checking it against the cap.
        bool allowed = feeBps <= ConfigLib.MAX_FEE_BPS;

        // Then: The cap admits exactly the fees up to 5_000 of 10_000.
        assertEq(allowed, feeBps <= 5000);
        assertEq(ConfigLib.BPS_DENOMINATOR, 10_000);
    }
}
