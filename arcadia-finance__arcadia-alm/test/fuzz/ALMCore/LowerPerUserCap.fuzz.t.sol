/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMAdminExtension } from "../../../src/core/ALMAdminExtension.sol";
import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { BaseCore } from "../../../src/core/abstracts/base/BaseCore.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";

/**
 * @notice Fuzz tests for the function "lowerPerUserCap" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract LowerPerUserCap_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_lowerPerUserCap_Unauthorized(address caller, uint256 currentCap, uint256 newCap) public {
        // Given: The caller is not the factory.
        vm.assume(caller != factory);

        // And: A per user cap is in place.
        currentCap = bound(currentCap, 1, type(uint128).max);
        vm.prank(factory);
        almCore.setPerUserCap(currentCap);

        // When: Calling lowerPerUserCap().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseCore.Unauthorized.selector);
        almCore.lowerPerUserCap(newCap);
    }

    function testFuzz_Revert_lowerPerUserCap_PerUserCapNotLowered(uint256 currentCap, uint256 newCap) public {
        // Given: The new cap is not strictly below the current one.
        currentCap = bound(currentCap, 0, type(uint128).max - 1);
        newCap = bound(newCap, currentCap, type(uint256).max);
        vm.prank(factory);
        almCore.setPerUserCap(currentCap);

        // When: The factory calls lowerPerUserCap().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.PerUserCapNotLowered.selector);
        almCore.lowerPerUserCap(newCap);
    }

    function testFuzz_Revert_lowerPerUserCap_PerUserCapNotLowered_EqualToTheCurrent(uint256 currentCap) public {
        // Given: A current cap.
        currentCap = bound(currentCap, 0, type(uint128).max - 1);
        vm.prank(factory);
        almCore.setPerUserCap(currentCap);

        // When: The factory lowers it to the same cap.
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.PerUserCapNotLowered.selector);
        almCore.lowerPerUserCap(currentCap);
    }

    function testFuzz_Success_lowerPerUserCap(uint256 currentCap, uint256 newCap) public {
        // Given: The new cap is strictly below the current one.
        currentCap = bound(currentCap, 1, type(uint128).max);
        newCap = bound(newCap, 0, currentCap - 1);
        vm.prank(factory);
        almCore.setPerUserCap(currentCap);

        // And: The factory calls.
        vm.prank(factory);

        // When: Calling lowerPerUserCap().
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.PerUserCapSet(newCap);
        almCore.lowerPerUserCap(newCap);

        // Then: The per user cap is updated.
        assertEq(almCore.perUserCap_(), newCap);
    }
}
