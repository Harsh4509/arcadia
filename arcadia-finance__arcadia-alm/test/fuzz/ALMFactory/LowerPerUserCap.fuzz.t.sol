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
 * @notice Fuzz tests for the function "lowerPerUserCap" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract LowerPerUserCap_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_lowerPerUserCap_Unauthorized(
        PoolState memory poolState,
        address caller,
        uint256 newPerUserCap
    ) public {
        // Given: A configured core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        setVaultConfigured();

        // And: The caller is neither the guardian nor the steward.
        vm.assume(caller != users.guardian && caller != users.steward);

        // When: Calling lowerPerUserCap().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.lowerPerUserCap(address(core), newPerUserCap);
    }

    function testFuzz_Revert_lowerPerUserCap_Unauthorized_Role(
        PoolState memory poolState,
        uint256 pick,
        uint256 newPerUserCap
    ) public {
        // Given: A configured core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        setVaultConfigured();

        // And: The caller holds another role than the guardian or the steward.
        address caller = roleAt(pick);
        vm.assume(caller != users.guardian && caller != users.steward);

        // When: Calling lowerPerUserCap().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.lowerPerUserCap(address(core), newPerUserCap);
    }

    function testFuzz_Revert_lowerPerUserCap_CoreNotValid(
        PoolState memory poolState,
        address candidate,
        uint256 newPerUserCap
    ) public {
        // Given: A configured core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        setVaultConfigured();

        // And: A candidate the factory did not create.
        vm.assume(candidate != address(core));

        // When: The steward calls lowerPerUserCap() on the candidate.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.lowerPerUserCap(candidate, newPerUserCap);
    }

    function testFuzz_Revert_lowerPerUserCap_CoreNotValid_HalfCreated(
        PoolState memory poolState,
        bool withSyncVaults,
        uint256 newPerUserCap
    ) public {
        // Given: A pool whose creation stopped after one or two of its transactions.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        address halfCreated = setHalfCreated(withSyncVaults);

        // When: The steward calls lowerPerUserCap() on the address its core will take.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.lowerPerUserCap(halfCreated, newPerUserCap);
    }

    function testFuzz_Revert_lowerPerUserCap_RoleCallsCoreDirectly(
        PoolState memory poolState,
        uint256 pick,
        uint256 newPerUserCap
    ) public {
        // Given: A configured core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        setVaultConfigured();

        // When: A role holder calls lowerPerUserCap() on the core itself.
        // Then: It reverts, the role being the factory's and not the caller's.
        vm.prank(roleAt(pick));
        vm.expectRevert(Ownable.Unauthorized.selector);
        core.lowerPerUserCap(newPerUserCap);
    }

    function testFuzz_Success_lowerPerUserCap(PoolState memory poolState, bool byGuardian, uint256 newPerUserCap)
        public
    {
        // Given: A configured core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        setVaultConfigured();

        // And: A cap below the configured one.
        newPerUserCap = bound(newPerUserCap, 0, type(uint128).max - 1);

        // And: The guardian or the steward calls.
        address caller = byGuardian ? users.guardian : users.steward;

        // When: Calling lowerPerUserCap().
        vm.prank(caller);
        vm.expectEmit(address(core));
        // Then: The core emits the per user cap lowered, reached through the factory.
        emit IALMCoreEvents.PerUserCapSet(newPerUserCap);
        almFactory.lowerPerUserCap(address(core), newPerUserCap);
    }
}
