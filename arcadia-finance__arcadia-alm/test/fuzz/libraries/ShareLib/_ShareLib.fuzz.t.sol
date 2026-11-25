/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Fuzz_Test } from "../../Fuzz.t.sol";
import { ShareLibExtension } from "../../../utils/extensions/ShareLibExtension.sol";

/**
 * @notice Common logic needed by all "ShareLib" fuzz tests.
 */
abstract contract ShareLib_Fuzz_Test is Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    ShareLibExtension internal shareLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();
        shareLib = new ShareLibExtension();
    }
}
