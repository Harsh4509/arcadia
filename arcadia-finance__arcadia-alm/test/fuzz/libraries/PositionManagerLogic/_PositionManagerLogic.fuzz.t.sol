/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "../../ALMCore/_ALMCore.fuzz.t.sol";
import { PositionManagerLogicExtension } from "../../../utils/extensions/PositionManagerLogicExtension.sol";

/**
 * @notice Common logic needed by all "PositionManagerLogic" fuzz tests.
 */
abstract contract PositionManagerLogic_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    PositionManagerLogicExtension internal positionManagerLogic;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function deployPositionManagerLogic() internal {
        positionManagerLogic = new PositionManagerLogicExtension(
            address(POSITION_MANAGER), address(token0), address(token1), pool.tickSpacing()
        );
    }
}
