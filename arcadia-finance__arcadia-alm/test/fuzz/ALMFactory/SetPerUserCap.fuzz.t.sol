/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory } from "../../../src/factory/ALMFactory.sol";
import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { Ownable } from "@solady/auth/Ownable.sol";

/**
 * @notice Fuzz tests for the function "setPerUserCap" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract SetPerUserCap_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_setPerUserCap_Unauthorized(
        PoolState memory poolState,
        address caller,
        uint256 newPerUserCap
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The caller is not the admin.
        vm.assume(caller != users.admin);

        // When: Calling setPerUserCap().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.setPerUserCap(address(core), newPerUserCap);
    }

    function testFuzz_Revert_setPerUserCap_Unauthorized_Role(
        PoolState memory poolState,
        uint256 pick,
        uint256 newPerUserCap
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The caller holds another role than the admin.
        address caller = roleAt(pick);
        vm.assume(caller != users.admin);

        // When: Calling setPerUserCap().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.setPerUserCap(address(core), newPerUserCap);
    }

    function testFuzz_Revert_setPerUserCap_CoreNotValid(
        PoolState memory poolState,
        address candidate,
        uint256 newPerUserCap
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: A candidate the factory did not create.
        vm.assume(candidate != address(core));

        // When: The admin calls setPerUserCap() on the candidate.
        // Then: It reverts.
        vm.prank(users.admin);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.setPerUserCap(candidate, newPerUserCap);
    }

    function testFuzz_Revert_setPerUserCap_CoreNotValid_HalfCreated(
        PoolState memory poolState,
        bool withSyncVaults,
        uint256 newPerUserCap
    ) public {
        // Given: A pool whose creation stopped after one or two of its transactions.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        address halfCreated = setHalfCreated(withSyncVaults);

        // When: The admin calls setPerUserCap() on the address its core will take.
        // Then: It reverts.
        vm.prank(users.admin);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.setPerUserCap(halfCreated, newPerUserCap);
    }

    function testFuzz_Revert_setPerUserCap_RoleCallsCoreDirectly(
        PoolState memory poolState,
        uint256 pick,
        uint256 newPerUserCap
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // When: A role holder calls setPerUserCap() on the core itself.
        // Then: It reverts, the role being the factory's and not the caller's.
        vm.prank(roleAt(pick));
        vm.expectRevert(Ownable.Unauthorized.selector);
        core.setPerUserCap(newPerUserCap);
    }

    function testFuzz_Success_setPerUserCap(PoolState memory poolState, uint256 newPerUserCap) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: A cap that fits its storage.
        newPerUserCap = bound(newPerUserCap, 0, type(uint128).max);

        // When: The admin calls setPerUserCap().
        vm.prank(users.admin);
        vm.expectEmit(address(core));
        // Then: The core emits the per user cap, reached through the factory.
        emit IALMCoreEvents.PerUserCapSet(newPerUserCap);
        almFactory.setPerUserCap(address(core), newPerUserCap);
    }
}
