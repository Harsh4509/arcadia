/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "getLastClearedRedeemEpoch" of library "ALMCoreViewLogic".
 */
contract GetLastClearedRedeemEpoch_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
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

    function testFuzz_Success_getLastClearedRedeemEpoch_ReadsItsOwnField(
        address vault,
        uint32 lastClearedEpoch,
        uint32 otherEpoch
    ) public {
        // Given: A last cleared redeem epoch, another id in every other field.
        almCore.setPendingEpochs(vault, otherEpoch, otherEpoch);
        almCore.setLastClearedEpochs(vault, otherEpoch, lastClearedEpoch);

        // When: Reading the last cleared redeem epoch.
        uint32 read = coreViewLogic.getLastClearedRedeemEpoch(address(almCore), vault);

        // Then: The redeem queue's last cleared epoch reads back.
        assertEq(read, lastClearedEpoch);
    }
}
