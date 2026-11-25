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
 * @notice Fuzz tests for the function "setTotalCap" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract SetTotalCap_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_setTotalCap_Unauthorized(address caller, uint256 newTotalCap) public {
        // Given: The caller is not the factory.
        vm.assume(caller != factory);

        // When: Calling setTotalCap().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseCore.Unauthorized.selector);
        almCore.setTotalCap(newTotalCap);
    }

    function testFuzz_Revert_setTotalCap_Overflow(uint256 newTotalCap) public {
        // Given: A cap above what a uint128 holds.
        newTotalCap = bound(newTotalCap, uint256(type(uint128).max) + 1, type(uint256).max);

        // When: The factory calls setTotalCap().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(SafeCastLib.Overflow.selector);
        almCore.setTotalCap(newTotalCap);
    }

    function testFuzz_Success_setTotalCap(uint256 newTotalCap) public {
        // Given: A cap inside the range the limits hold.
        newTotalCap = bound(newTotalCap, 0, type(uint128).max);

        // And: The factory calls.
        vm.prank(factory);

        // When: Calling setTotalCap().
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.TotalCapSet(newTotalCap);
        almCore.setTotalCap(newTotalCap);

        // Then: The total cap is updated.
        assertEq(almCore.totalCap_(), newTotalCap);
    }
}
