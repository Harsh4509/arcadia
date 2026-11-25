/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory } from "../../../src/factory/ALMFactory.sol";
import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { Ownable } from "@solady/auth/Ownable.sol";

/**
 * @notice Fuzz tests for the function "setSteward" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract SetSteward_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_setSteward_Unauthorized(PoolState memory poolState, address caller, address newSteward)
        public
    {
        // Given: A factory with every role set.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: The caller is not the owner.
        vm.assume(caller != users.owner);

        // When: Calling setSteward().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.setSteward(newSteward);
    }

    function testFuzz_Success_setSteward(PoolState memory poolState, address newSteward) public {
        // Given: A factory with every role set.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // When: The owner sets the steward.
        vm.prank(users.owner);
        vm.expectEmit(address(almFactory));
        emit ALMFactory.StewardSet(newSteward);
        almFactory.setSteward(newSteward);

        // Then: The steward is updated.
        assertEq(almFactory.steward(), newSteward);
    }

    function testFuzz_Success_setSteward_RotatesTheRole(PoolState memory poolState, address newSteward) public {
        // Given: A factory with every role set.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A new steward other than the current one.
        vm.assume(newSteward != users.steward);

        // When: The owner rotates the steward.
        vm.prank(users.owner);
        almFactory.setSteward(newSteward);

        // Then: The former steward no longer revokes the guardian.
        vm.prank(users.steward);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.revokeGuardian();

        // And: The new steward does.
        vm.prank(newSteward);
        almFactory.revokeGuardian();
        assertEq(almFactory.guardian(), address(0));
    }
}
