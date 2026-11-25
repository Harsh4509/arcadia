/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CLMathExtension } from "../../../utils/extensions/CLMathExtension.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { Range_Fuzz_Test } from "../_Range.fuzz.t.sol";

/**
 * @notice Common logic needed by all "CLMath" fuzz tests.
 */
abstract contract CLMath_Fuzz_Test is Range_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    CLMathExtension internal clMath;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        Fuzz_Test.setUp();
        clMath = new CLMathExtension();
    }
}
