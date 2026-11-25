/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "../../ALMCore/_ALMCore.fuzz.t.sol";
import { PoolLogicExtension } from "../../../utils/extensions/PoolLogicExtension.sol";

/**
 * @notice Common logic needed by all "PoolLogic" fuzz tests.
 */
abstract contract PoolLogic_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    PoolLogicExtension internal poolLogic;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        poolLogic = new PoolLogicExtension();
    }
}
