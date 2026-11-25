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
 * @notice Fuzz tests for the function "setCapExempt" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract SetCapExempt_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_setCapExempt_Unauthorized(
        PoolState memory poolState,
        address caller,
        address account,
        bool exempt
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The caller is not the admin.
        vm.assume(caller != users.admin);

        // When: Calling setCapExempt().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.setCapExempt(address(core), account, exempt);
    }

    function testFuzz_Revert_setCapExempt_CoreNotValid(
        PoolState memory poolState,
        address candidate,
        address account,
        bool exempt
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: A candidate the factory did not create.
        vm.assume(candidate != address(core));

        // When: The admin calls setCapExempt() on the candidate.
        // Then: It reverts.
        vm.prank(users.admin);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.setCapExempt(candidate, account, exempt);
    }

    function testFuzz_Revert_setCapExempt_RoleCallsCoreDirectly(
        PoolState memory poolState,
        uint256 pick,
        address account,
        bool exempt
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // When: A role holder calls setCapExempt() on the core itself.
        // Then: It reverts, the role being the factory's and not the caller's.
        vm.prank(roleAt(pick));
        vm.expectRevert(Ownable.Unauthorized.selector);
        core.setCapExempt(account, exempt);
    }

    function testFuzz_Success_setCapExempt(PoolState memory poolState, address account, bool exempt) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // When: The admin calls setCapExempt().
        vm.prank(users.admin);
        vm.expectEmit(address(core));
        // Then: The core emits the exemption, reached through the factory.
        emit IALMCoreEvents.CapExemptSet(account, exempt);
        almFactory.setCapExempt(address(core), account, exempt);
    }
}
