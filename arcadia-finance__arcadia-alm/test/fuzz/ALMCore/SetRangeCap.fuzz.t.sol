/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMAdminExtension } from "../../../src/core/ALMAdminExtension.sol";
import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { BaseCore } from "../../../src/core/abstracts/base/BaseCore.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";

/**
 * @notice Fuzz tests for the function "setRangeCap" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract SetRangeCap_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_setRangeCap_Unauthorized(address caller, uint8 newCap) public {
        // Given: The caller is not the factory.
        vm.assume(caller != factory);

        // When: Calling setRangeCap().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseCore.Unauthorized.selector);
        almCore.setRangeCap(newCap);
    }

    function testFuzz_Revert_setRangeCap_InvalidRangeCap(uint8 newCap) public {
        // Given: A cap above the bound.
        newCap = uint8(bound(newCap, uint256(ConfigLib.MAX_RANGE_CAP) + 1, type(uint8).max));

        // When: The factory calls setRangeCap().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.InvalidRangeCap.selector);
        almCore.setRangeCap(newCap);
    }

    function testFuzz_Success_setRangeCap(uint8 newCap) public {
        // Given: A cap within the bound.
        newCap = uint8(bound(newCap, 0, ConfigLib.MAX_RANGE_CAP));

        // And: The factory calls.
        vm.prank(factory);

        // When: Calling setRangeCap().
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.RangeCapSet(newCap);
        almCore.setRangeCap(newCap);

        // Then: The range cap is updated.
        assertEq(almCore.rangeCap_(), newCap);
    }
}
