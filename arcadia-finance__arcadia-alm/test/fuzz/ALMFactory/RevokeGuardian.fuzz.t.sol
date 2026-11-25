/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory } from "../../../src/factory/ALMFactory.sol";
import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { Ownable } from "@solady/auth/Ownable.sol";

/**
 * @notice Fuzz tests for the function "revokeGuardian" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract RevokeGuardian_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_revokeGuardian_Unauthorized(PoolState memory poolState, address caller) public {
        // Given: A factory with every role set.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: The caller is not the steward.
        vm.assume(caller != users.steward);

        // When: Calling revokeGuardian().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.revokeGuardian();
    }

    function testFuzz_Success_revokeGuardian(PoolState memory poolState) public {
        // Given: A factory with a core over the pool.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // When: The steward revokes the guardian.
        vm.prank(users.steward);
        vm.expectEmit(address(almFactory));
        emit ALMFactory.GuardianSet(address(0));
        almFactory.revokeGuardian();

        // Then: The role is empty.
        assertEq(almFactory.guardian(), address(0));
    }

    function testFuzz_Success_revokeGuardian_FormerGuardianLosesTheCore(PoolState memory poolState) public {
        // Given: A factory with a core over the pool.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The steward revoked the guardian.
        vm.prank(users.steward);
        almFactory.revokeGuardian();

        // When: The former guardian calls pause().
        // Then: It reverts.
        vm.prank(users.guardian);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.pause(address(core));
    }
}
