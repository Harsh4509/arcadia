/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { BaseCore } from "../../../src/core/abstracts/base/BaseCore.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";

/**
 * @notice Fuzz tests for the function "unpause" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract Unpause_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_unpause_Unauthorized(address caller) public {
        // Given: The vault is paused and the caller is not the factory.
        vm.prank(factory);
        almCore.pause();
        vm.assume(caller != factory);

        // When: Calling unpause().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseCore.Unauthorized.selector);
        almCore.unpause();
    }

    function testFuzz_Success_unpause(bool paused) public {
        // Given: A core paused or not.
        if (paused) {
            vm.prank(factory);
            almCore.pause();
        }

        // And: The factory calls.
        vm.prank(factory);

        // When: Calling unpause().
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.PausedSet(false);
        almCore.unpause();

        // Then: The vault is unpaused.
        assertFalse(almCore.paused_());
    }
}
