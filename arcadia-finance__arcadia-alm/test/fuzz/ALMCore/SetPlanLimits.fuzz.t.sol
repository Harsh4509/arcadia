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
 * @notice Fuzz tests for the function "setPlanLimits" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events, unsafe-typecast)
contract SetPlanLimits_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_setPlanLimits_Unauthorized(address caller, uint16 loss, uint16 swapCost, uint32 interval)
        public
    {
        // Given: The caller is not the factory.
        vm.assume(caller != factory);

        // When: Calling setPlanLimits().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseCore.Unauthorized.selector);
        almCore.setPlanLimits(loss, swapCost, interval);
    }

    function testFuzz_Revert_setPlanLimits_InvalidMaxShortfall(uint16 loss, uint16 swapCost, uint32 interval) public {
        // Given: A loss bound above the whole.
        loss = uint16(bound(loss, almCore.BPS_DENOMINATOR_() + 1, type(uint16).max));

        // When: Calling setPlanLimits().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.InvalidMaxShortfall.selector);
        almCore.setPlanLimits(loss, swapCost, interval);
    }

    function testFuzz_Revert_setPlanLimits_InvalidMaxSwapCost(uint16 loss, uint16 swapCost, uint32 interval) public {
        // Given: A loss bound inside its range, and a swap cost bound above the whole.
        loss = uint16(bound(loss, 0, almCore.BPS_DENOMINATOR_()));
        swapCost = uint16(bound(swapCost, almCore.BPS_DENOMINATOR_() + 1, type(uint16).max));

        // When: Calling setPlanLimits().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.InvalidMaxSwapCost.selector);
        almCore.setPlanLimits(loss, swapCost, interval);
    }

    function testFuzz_Success_setPlanLimits(uint16 loss, uint16 swapCost, uint32 interval) public {
        // Given: Both bounds inside their range.
        loss = uint16(bound(loss, 0, almCore.BPS_DENOMINATOR_()));
        swapCost = uint16(bound(swapCost, 0, almCore.BPS_DENOMINATOR_()));

        // When: The factory sets them.
        vm.prank(factory);
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.PlanLimitsSet(loss, swapCost, interval);
        almCore.setPlanLimits(loss, swapCost, interval);

        // Then: They are stored.
        assertEq(almCore.maxShortfallBps_(), loss);
        assertEq(almCore.maxSwapCostBps_(), swapCost);
        assertEq(almCore.minPlanInterval_(), interval);
    }
}
