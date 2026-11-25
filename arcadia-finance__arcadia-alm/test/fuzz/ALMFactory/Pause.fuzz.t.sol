/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory } from "../../../src/factory/ALMFactory.sol";
import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { Ownable } from "@solady/auth/Ownable.sol";

/**
 * @notice Fuzz tests for the function "pause" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract Pause_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_pause_Unauthorized(PoolState memory poolState, address caller) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The caller is neither the guardian nor the steward.
        vm.assume(caller != users.guardian && caller != users.steward);

        // When: Calling pause().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.pause(address(core));
    }

    function testFuzz_Revert_pause_Unauthorized_Role(PoolState memory poolState, uint256 pick) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The caller holds another role than the guardian or the steward.
        address caller = roleAt(pick);
        vm.assume(caller != users.guardian && caller != users.steward);

        // When: Calling pause().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.pause(address(core));
    }

    function testFuzz_Revert_pause_CoreNotValid(PoolState memory poolState, address candidate) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: A candidate the factory did not create.
        vm.assume(candidate != address(core));

        // When: The guardian pauses the candidate.
        // Then: It reverts.
        vm.prank(users.guardian);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.pause(candidate);
    }

    function testFuzz_Revert_pause_CoreNotValid_HalfCreated(PoolState memory poolState, bool withSyncVaults) public {
        // Given: A pool whose creation stopped after one or two of its transactions.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        address halfCreated = setHalfCreated(withSyncVaults);

        // When: The guardian pauses the address its core will take.
        // Then: It reverts.
        vm.prank(users.guardian);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.pause(halfCreated);
    }

    function testFuzz_Revert_pause_RoleCallsCoreDirectly(PoolState memory poolState, uint256 pick) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // When: A role holder calls pause() on the core itself.
        // Then: It reverts, the role being the factory's and not the caller's.
        vm.prank(roleAt(pick));
        vm.expectRevert(Ownable.Unauthorized.selector);
        core.pause();
    }

    function testFuzz_Revert_pause_RoleCallsVaultDirectly(PoolState memory poolState, uint256 pick, uint256 index)
        public
    {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: One of its four vaults.
        address[4] memory list = vaultsOf(vaults);
        BaseVault vault = BaseVault(list[bound(index, 0, list.length - 1)]);

        // When: A role holder calls pause() on the vault itself.
        // Then: It reverts, the role being the factory's and not the caller's.
        vm.prank(roleAt(pick));
        vm.expectRevert(Ownable.Unauthorized.selector);
        vault.setPaused(true);
    }

    function testFuzz_Success_pause(PoolState memory poolState, bool byGuardian) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The guardian or the steward calls.
        address caller = byGuardian ? users.guardian : users.steward;

        // When: Calling pause().
        vm.prank(caller);
        // Then: The core and its four vaults are paused together.
        vm.expectEmit(address(core));
        emit IALMCoreEvents.PausedSet(true);
        vm.expectEmit(vaults.syncVault0);
        emit BaseVault.PausedSet(true);
        vm.expectEmit(vaults.syncVault1);
        emit BaseVault.PausedSet(true);
        vm.expectEmit(vaults.asyncVault0);
        emit BaseVault.PausedSet(true);
        vm.expectEmit(vaults.asyncVault1);
        emit BaseVault.PausedSet(true);
        almFactory.pause(address(core));

        address[4] memory list = vaultsOf(vaults);
        for (uint256 i; i < 4; ++i) {
            assertTrue(BaseVault(list[i]).paused());
        }
    }
}
