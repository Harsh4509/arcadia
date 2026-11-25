/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Fuzz_Test } from "../../Fuzz.t.sol";
import { MetadexSwapMathExtension } from "../../../utils/extensions/MetadexSwapMathExtension.sol";

/**
 * @notice Common logic needed by all "MetadexSwapMath" fuzz tests.
 */
abstract contract MetadexSwapMath_Fuzz_Test is Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    MetadexSwapMathExtension internal metadexSwapMath;
    // Slipstream's own 0.7.6 SwapMath behind the same function.
    MetadexSwapMathExtension internal slipstreamSwapMath;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();
        metadexSwapMath = new MetadexSwapMathExtension();
        slipstreamSwapMath =
            MetadexSwapMathExtension(deployCode("out/SlipstreamSwapMathMock.sol/SlipstreamSwapMathMock.json"));
    }
}
