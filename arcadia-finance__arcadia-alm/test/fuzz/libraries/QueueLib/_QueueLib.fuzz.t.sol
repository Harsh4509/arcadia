/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Fuzz_Test } from "../../Fuzz.t.sol";
import { QueueLibExtension } from "../../../utils/extensions/QueueLibExtension.sol";

/**
 * @notice Common logic needed by all "QueueLib" fuzz tests.
 */
abstract contract QueueLib_Fuzz_Test is Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    QueueLibExtension internal queueLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();
        queueLib = new QueueLibExtension();
    }
}
