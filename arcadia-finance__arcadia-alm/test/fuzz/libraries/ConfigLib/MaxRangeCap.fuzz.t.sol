/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { ConfigLib_Fuzz_Test } from "./_ConfigLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the range cap bound of library "ConfigLib".
 */
contract MaxRangeCap_ConfigLib_Fuzz_Test is ConfigLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_maxRangeCap_MatchesTheSpec(uint8 rangeCap) public pure {
        // Given: Any range cap.

        // When: Checking it against the bound.
        bool allowed = rangeCap <= ConfigLib.MAX_RANGE_CAP;

        // Then: The bound admits exactly the caps up to 14 ranges.
        assertEq(allowed, rangeCap <= 14);
        assertEq(ConfigLib.MAX_RANGE_CAP, 14);
    }
}
