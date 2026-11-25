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
 * @notice Fuzz tests for the function "setGuardian" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract SetGuardian_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_setGuardian_Unauthorized(PoolState memory poolState, address caller, address newGuardian)
        public
    {
        // Given: A factory with every role set.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: The caller is not the owner.
        vm.assume(caller != users.owner);

        // When: Calling setGuardian().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.setGuardian(newGuardian);
    }

    function testFuzz_Success_setGuardian(PoolState memory poolState, address newGuardian) public {
        // Given: A factory with every role set.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // When: The owner sets the guardian.
        vm.prank(users.owner);
        vm.expectEmit(address(almFactory));
        emit ALMFactory.GuardianSet(newGuardian);
        almFactory.setGuardian(newGuardian);

        // Then: The guardian is updated.
        assertEq(almFactory.guardian(), newGuardian);
    }

    function testFuzz_Success_setGuardian_RotatesOnAnExistingCore(PoolState memory poolState, address newGuardian)
        public
    {
        // Given: A factory with a core over the pool.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: A new guardian other than the current one and the steward.
        vm.assume(newGuardian != users.guardian && newGuardian != users.steward);

        // When: The owner rotates the guardian.
        vm.prank(users.owner);
        almFactory.setGuardian(newGuardian);

        // Then: The former guardian no longer reaches the existing core.
        vm.prank(users.guardian);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.pause(address(core));

        // And: The new guardian pauses it.
        vm.prank(newGuardian);
        vm.expectEmit(address(core));
        emit IALMCoreEvents.PausedSet(true);
        almFactory.pause(address(core));
    }
}
