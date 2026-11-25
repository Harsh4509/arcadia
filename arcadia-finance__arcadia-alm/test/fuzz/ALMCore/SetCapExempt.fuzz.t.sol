/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { BaseCore } from "../../../src/core/abstracts/base/BaseCore.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";

/**
 * @notice Fuzz tests for the function "setCapExempt" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract SetCapExempt_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_setCapExempt_Unauthorized(address caller, address account, bool exempt) public {
        // Given: The caller is not the factory.
        vm.assume(caller != factory);

        // When: Calling setCapExempt().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseCore.Unauthorized.selector);
        almCore.setCapExempt(account, exempt);
    }

    function testFuzz_Success_setCapExempt(address account, bool exempt) public {
        // Given: A core as deployed.

        // When: The factory calls setCapExempt().
        vm.prank(factory);
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.CapExemptSet(account, exempt);
        almCore.setCapExempt(account, exempt);

        // Then: The exemption is stored.
        assertEq(almCore.isExempt_(account), exempt);
    }
}
