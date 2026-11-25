/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "../../ALMCore/_ALMCore.fuzz.t.sol";
import { IMetadexCLPool } from "../../../../src/interfaces/IMetadexCLPool.sol";
import { MetadexOracleExtension } from "../../../utils/extensions/MetadexOracleExtension.sol";

/**
 * @notice Common logic needed by all "MetadexOracle" fuzz tests.
 */
abstract contract MetadexOracle_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    MetadexOracleExtension internal oracleLibrary;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        oracleLibrary = new MetadexOracleExtension();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function mockObserve(int56 start, int56 end) internal {
        int56[] memory tickCumulatives = new int56[](2);
        (tickCumulatives[0], tickCumulatives[1]) = (start, end);
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(IMetadexCLPool.observe.selector),
            abi.encode(tickCumulatives, new uint160[](2))
        );
    }
}
