/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { BaseCore } from "../../../src/core/abstracts/base/BaseCore.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";

/**
 * @notice Fuzz tests for the function "pause" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract Pause_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_pause_Unauthorized(address caller) public {
        // Given: The caller is not the factory.
        vm.assume(caller != factory);

        // When: Calling pause().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseCore.Unauthorized.selector);
        almCore.pause();
    }

    function testFuzz_Success_pause(bool paused) public {
        // Given: A core paused or not.
        if (paused) {
            vm.prank(factory);
            almCore.pause();
        }

        // And: The factory calls.
        vm.prank(factory);

        // When: Calling pause().
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.PausedSet(true);
        almCore.pause();

        // Then: The vault is paused.
        assertTrue(almCore.paused_());
    }
}
