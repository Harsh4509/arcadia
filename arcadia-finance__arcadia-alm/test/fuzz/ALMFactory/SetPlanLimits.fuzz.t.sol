/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory } from "../../../src/factory/ALMFactory.sol";
import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { Ownable } from "@solady/auth/Ownable.sol";

/**
 * @notice Fuzz tests for the function "setPlanLimits" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(reentrancy-events, unsafe-typecast)
contract SetPlanLimits_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_setPlanLimits_Unauthorized(
        PoolState memory poolState,
        address caller,
        uint16 newMaxShortfallBps,
        uint16 newMaxSwapCostBps,
        uint32 newMinPlanInterval
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The caller is not the admin.
        vm.assume(caller != users.admin);

        // When: Calling setPlanLimits().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.setPlanLimits(address(core), newMaxShortfallBps, newMaxSwapCostBps, newMinPlanInterval);
    }

    function testFuzz_Revert_setPlanLimits_Unauthorized_Role(
        PoolState memory poolState,
        uint256 pick,
        uint16 newMaxShortfallBps,
        uint16 newMaxSwapCostBps,
        uint32 newMinPlanInterval
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The caller holds another role than the admin.
        address caller = roleAt(pick);
        vm.assume(caller != users.admin);

        // When: Calling setPlanLimits().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.setPlanLimits(address(core), newMaxShortfallBps, newMaxSwapCostBps, newMinPlanInterval);
    }

    function testFuzz_Revert_setPlanLimits_CoreNotValid(
        PoolState memory poolState,
        address candidate,
        uint16 newMaxShortfallBps,
        uint16 newMaxSwapCostBps,
        uint32 newMinPlanInterval
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: A candidate the factory did not create.
        vm.assume(candidate != address(core));

        // When: The admin calls setPlanLimits() on the candidate.
        // Then: It reverts.
        vm.prank(users.admin);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.setPlanLimits(candidate, newMaxShortfallBps, newMaxSwapCostBps, newMinPlanInterval);
    }

    function testFuzz_Revert_setPlanLimits_CoreNotValid_HalfCreated(
        PoolState memory poolState,
        bool withSyncVaults,
        uint16 newMaxShortfallBps,
        uint16 newMaxSwapCostBps,
        uint32 newMinPlanInterval
    ) public {
        // Given: A pool whose creation stopped after one or two of its transactions.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        address halfCreated = setHalfCreated(withSyncVaults);

        // When: The admin calls setPlanLimits() on the address its core will take.
        // Then: It reverts.
        vm.prank(users.admin);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.setPlanLimits(halfCreated, newMaxShortfallBps, newMaxSwapCostBps, newMinPlanInterval);
    }

    function testFuzz_Revert_setPlanLimits_RoleCallsCoreDirectly(
        PoolState memory poolState,
        uint256 pick,
        uint16 newMaxShortfallBps,
        uint16 newMaxSwapCostBps,
        uint32 newMinPlanInterval
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // When: A role holder calls setPlanLimits() on the core itself.
        // Then: It reverts, the role being the factory's and not the caller's.
        vm.prank(roleAt(pick));
        vm.expectRevert(Ownable.Unauthorized.selector);
        core.setPlanLimits(newMaxShortfallBps, newMaxSwapCostBps, newMinPlanInterval);
    }

    function testFuzz_Success_setPlanLimits(
        PoolState memory poolState,
        uint16 newMaxShortfallBps,
        uint16 newMaxSwapCostBps,
        uint32 newMinPlanInterval
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: Bounds no wider than the whole value.
        newMaxShortfallBps = uint16(bound(newMaxShortfallBps, 0, ConfigLib.BPS_DENOMINATOR));
        newMaxSwapCostBps = uint16(bound(newMaxSwapCostBps, 0, ConfigLib.BPS_DENOMINATOR - 1));

        // When: The admin calls setPlanLimits().
        vm.prank(users.admin);
        vm.expectEmit(address(core));
        // Then: The core emits the three bounds, reached through the factory.
        emit IALMCoreEvents.PlanLimitsSet(newMaxShortfallBps, newMaxSwapCostBps, newMinPlanInterval);
        almFactory.setPlanLimits(address(core), newMaxShortfallBps, newMaxSwapCostBps, newMinPlanInterval);
    }
}
