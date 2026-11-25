/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "getPendingRedeemEpoch" of library "ALMCoreViewLogic".
 */
contract GetPendingRedeemEpoch_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
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

    function testFuzz_Success_getPendingRedeemEpoch_ReadsItsOwnQueue(
        address vault,
        uint32 pendingEpoch,
        uint32 otherEpoch
    ) public {
        // Given: A pending redeem epoch, and another pending deposit epoch.
        almCore.setPendingEpochs(vault, otherEpoch, pendingEpoch);

        // When: Reading the pending redeem epoch.
        uint32 read = coreViewLogic.getPendingRedeemEpoch(address(almCore), vault);

        // Then: The redeem queue's epoch reads back.
        assertEq(read, pendingEpoch);
    }
}
