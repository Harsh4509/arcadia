/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Fuzz_Test } from "../../Fuzz.t.sol";
import { QuadraticMathExtension } from "../../../utils/extensions/QuadraticMathExtension.sol";

/**
 * @notice Common logic needed by all "QuadraticMath" fuzz tests.
 */
abstract contract QuadraticMath_Fuzz_Test is Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    QuadraticMathExtension internal quadraticMath;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();
        quadraticMath = new QuadraticMathExtension();
    }
}
