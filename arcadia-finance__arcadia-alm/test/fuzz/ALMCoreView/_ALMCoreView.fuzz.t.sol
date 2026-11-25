/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { BaseVault_Fuzz_Test } from "../BaseVault/_BaseVault.fuzz.t.sol";

/**
 * @notice Common logic needed by all "ALMCoreView" fuzz tests.
 */
abstract contract ALMCoreView_Fuzz_Test is BaseVault_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    // The lens over the cores of the test's factory.
    ALMCoreView internal coreView;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(BaseVault_Fuzz_Test) {
        BaseVault_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function deployCoreView() internal {
        coreView = new ALMCoreView(factory);
    }
}
