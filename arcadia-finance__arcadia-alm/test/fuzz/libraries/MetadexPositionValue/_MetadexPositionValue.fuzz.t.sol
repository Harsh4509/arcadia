/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { MetadexPositionValueExtension } from "../../../utils/extensions/MetadexPositionValueExtension.sol";
import { PositionManagerLogic_Fuzz_Test } from "../PositionManagerLogic/_PositionManagerLogic.fuzz.t.sol";

/**
 * @notice Common logic needed by all "MetadexPositionValue" fuzz tests.
 */
abstract contract MetadexPositionValue_Fuzz_Test is PositionManagerLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    MetadexPositionValueExtension internal positionValue;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(PositionManagerLogic_Fuzz_Test) {
        PositionManagerLogic_Fuzz_Test.setUp();
        positionValue = new MetadexPositionValueExtension();
    }
}
