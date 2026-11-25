/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Fuzz_Test } from "../../Fuzz.t.sol";
import { TokenDeltaLibExtension } from "../../../utils/extensions/TokenDeltaLibExtension.sol";

/**
 * @notice Common logic needed by all "TokenDeltaLib" fuzz tests.
 */
abstract contract TokenDeltaLib_Fuzz_Test is Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    TokenDeltaLibExtension internal tokenDeltaLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        Fuzz_Test.setUp();
        tokenDeltaLib = new TokenDeltaLibExtension();
    }
}
