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
 * @notice Fuzz tests for the function "setAdmin" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract SetAdmin_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_setAdmin_Unauthorized(PoolState memory poolState, address caller, address newAdmin)
        public
    {
        // Given: A factory with every role set.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: The caller is not the owner.
        vm.assume(caller != users.owner);

        // When: Calling setAdmin().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.setAdmin(newAdmin);
    }

    function testFuzz_Success_setAdmin(PoolState memory poolState, address newAdmin) public {
        // Given: A factory with every role set.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // When: The owner sets the admin.
        vm.prank(users.owner);
        vm.expectEmit(address(almFactory));
        emit ALMFactory.AdminSet(newAdmin);
        almFactory.setAdmin(newAdmin);

        // Then: The admin is updated.
        assertEq(almFactory.admin(), newAdmin);
    }

    function testFuzz_Success_setAdmin_RotatesOnAnExistingCore(PoolState memory poolState, address newAdmin, uint8 cap)
        public
    {
        // Given: A factory with a core over the pool.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: A new admin other than the current one, and a cap within the bound.
        vm.assume(newAdmin != users.admin && newAdmin != address(0));
        cap = uint8(bound(cap, 0, ConfigLib.MAX_RANGE_CAP));

        // When: The owner rotates the admin.
        vm.prank(users.owner);
        almFactory.setAdmin(newAdmin);

        // Then: The new admin reaches the existing core without the core being touched.
        vm.prank(newAdmin);
        vm.expectEmit(address(core));
        emit IALMCoreEvents.RangeCapSet(cap);
        almFactory.setRangeCap(address(core), cap);
    }

    function testFuzz_Success_setAdmin_FormerAdminLosesTheCore(PoolState memory poolState, address newAdmin, uint8 cap)
        public
    {
        // Given: A factory with a core over the pool.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The owner rotated the admin, and a cap within the bound.
        vm.assume(newAdmin != users.admin && newAdmin != address(0));
        cap = uint8(bound(cap, 0, ConfigLib.MAX_RANGE_CAP));
        vm.prank(users.owner);
        almFactory.setAdmin(newAdmin);

        // When: The former admin calls setRangeCap() on the existing core.
        // Then: It reverts.
        vm.prank(users.admin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.setRangeCap(address(core), cap);
    }
}
