/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { Epoch } from "../../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getDepositEpoch" of library "ALMCoreViewLogic".
 */
contract GetDepositEpoch_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getDepositEpoch_ReadsTheWord(address vault, uint32 id, Epoch memory epoch) public {
        // Given: A deposit epoch.
        almCore.setDepositEpoch(vault, id, epoch);

        // When: Reading it.
        Epoch memory read = coreViewLogic.getDepositEpoch(address(almCore), vault, id);

        // Then: Its input and output read back.
        assertEq(read.amountIn, epoch.amountIn);
        assertEq(read.amountOut, epoch.amountOut);
    }
}
