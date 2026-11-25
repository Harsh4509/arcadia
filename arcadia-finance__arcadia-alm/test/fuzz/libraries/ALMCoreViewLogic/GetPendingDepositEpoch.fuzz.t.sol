/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "getPendingDepositEpoch" of library "ALMCoreViewLogic".
 */
contract GetPendingDepositEpoch_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
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

    function testFuzz_Success_getPendingDepositEpoch_ReadsItsOwnQueue(
        address vault,
        uint32 pendingEpoch,
        uint32 otherEpoch
    ) public {
        // Given: A pending deposit epoch, and another pending redeem epoch.
        almCore.setPendingEpochs(vault, pendingEpoch, otherEpoch);

        // When: Reading the pending deposit epoch.
        uint32 read = coreViewLogic.getPendingDepositEpoch(address(almCore), vault);

        // Then: The deposit queue's epoch reads back.
        assertEq(read, pendingEpoch);
    }
}
