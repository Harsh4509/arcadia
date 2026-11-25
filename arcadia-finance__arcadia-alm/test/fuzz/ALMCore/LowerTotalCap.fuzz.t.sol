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
 * @notice Fuzz tests for the function "lowerTotalCap" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract LowerTotalCap_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_lowerTotalCap_Unauthorized(address caller, uint256 currentCap, uint256 newCap) public {
        // Given: The caller is not the factory.
        vm.assume(caller != factory);

        // And: A total cap is in place.
        currentCap = bound(currentCap, 1, type(uint128).max);
        vm.prank(factory);
        almCore.setTotalCap(currentCap);

        // When: Calling lowerTotalCap().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseCore.Unauthorized.selector);
        almCore.lowerTotalCap(newCap);
    }

    function testFuzz_Revert_lowerTotalCap_TotalCapNotLowered(uint256 currentCap, uint256 newCap) public {
        // Given: The new cap is not strictly below the current one.
        currentCap = bound(currentCap, 0, type(uint128).max - 1);
        newCap = bound(newCap, currentCap, type(uint256).max);
        vm.prank(factory);
        almCore.setTotalCap(currentCap);

        // When: The factory calls lowerTotalCap().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.TotalCapNotLowered.selector);
        almCore.lowerTotalCap(newCap);
    }

    function testFuzz_Revert_lowerTotalCap_TotalCapNotLowered_EqualToTheCurrent(uint256 currentCap) public {
        // Given: A current cap.
        currentCap = bound(currentCap, 0, type(uint128).max - 1);
        vm.prank(factory);
        almCore.setTotalCap(currentCap);

        // When: The factory lowers it to the same cap.
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.TotalCapNotLowered.selector);
        almCore.lowerTotalCap(currentCap);
    }

    function testFuzz_Success_lowerTotalCap(uint256 currentCap, uint256 newCap) public {
        // Given: The new cap is strictly below the current one.
        currentCap = bound(currentCap, 1, type(uint128).max);
        newCap = bound(newCap, 0, currentCap - 1);
        vm.prank(factory);
        almCore.setTotalCap(currentCap);

        // And: The factory calls.
        vm.prank(factory);

        // When: Calling lowerTotalCap().
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.TotalCapSet(newCap);
        almCore.lowerTotalCap(newCap);

        // Then: The total cap is updated.
        assertEq(almCore.totalCap_(), newCap);
    }
}
