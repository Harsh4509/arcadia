/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "getLastClearedDepositEpoch" of library "ALMCoreViewLogic".
 */
contract GetLastClearedDepositEpoch_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
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

    function testFuzz_Success_getLastClearedDepositEpoch_ReadsItsOwnField(
        address vault,
        uint32 lastClearedEpoch,
        uint32 otherEpoch
    ) public {
        // Given: A last cleared deposit epoch, another id in every other field.
        almCore.setPendingEpochs(vault, otherEpoch, otherEpoch);
        almCore.setLastClearedEpochs(vault, lastClearedEpoch, otherEpoch);

        // When: Reading the last cleared deposit epoch.
        uint32 read = coreViewLogic.getLastClearedDepositEpoch(address(almCore), vault);

        // Then: The deposit queue's last cleared epoch reads back.
        assertEq(read, lastClearedEpoch);
    }
}
