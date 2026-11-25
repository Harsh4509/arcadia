/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Fuzz_Test } from "../../Fuzz.t.sol";
import { PoolTokensLibExtension } from "../../../utils/extensions/PoolTokensLibExtension.sol";

/**
 * @notice Common logic needed by all "PoolTokensLib" fuzz tests.
 */
abstract contract PoolTokensLib_Fuzz_Test is Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    PoolTokensLibExtension internal poolTokensLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();
        poolTokensLib = new PoolTokensLibExtension();
    }
}
