/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { BaseCore } from "../../../src/core/abstracts/base/BaseCore.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";

/**
 * @notice Fuzz tests for the function "setPerUserCap" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract SetPerUserCap_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_setPerUserCap_Unauthorized(address caller, uint256 newCap) public {
        // Given: The caller is not the factory.
        vm.assume(caller != factory);

        // When: Calling setPerUserCap().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseCore.Unauthorized.selector);
        almCore.setPerUserCap(newCap);
    }

    function testFuzz_Revert_setPerUserCap_Overflow(uint256 newCap) public {
        // Given: A cap above what a uint128 holds.
        newCap = bound(newCap, uint256(type(uint128).max) + 1, type(uint256).max);

        // When: The factory calls setPerUserCap().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(SafeCastLib.Overflow.selector);
        almCore.setPerUserCap(newCap);
    }

    function testFuzz_Success_setPerUserCap(uint256 newCap) public {
        // Given: A cap inside the range the limits hold.
        newCap = bound(newCap, 0, type(uint128).max);

        // And: The factory calls.
        vm.prank(factory);

        // When: Calling setPerUserCap().
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.PerUserCapSet(newCap);
        almCore.setPerUserCap(newCap);

        // Then: The per user cap is updated.
        assertEq(almCore.perUserCap_(), newCap);
    }
}
