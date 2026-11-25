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
 * @notice Fuzz tests for the function "unpause" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract Unpause_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_unpause_Unauthorized(PoolState memory poolState, address caller) public {
        // Given: A paused core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        vm.prank(users.guardian);
        almFactory.pause(address(core));

        // And: The caller is not the steward.
        vm.assume(caller != users.steward);

        // When: Calling unpause().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.unpause(address(core));
    }

    function testFuzz_Revert_unpause_Unauthorized_Role(PoolState memory poolState, uint256 pick) public {
        // Given: A paused core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        vm.prank(users.guardian);
        almFactory.pause(address(core));

        // And: The caller holds another role than the steward, the guardian among them.
        address caller = roleAt(pick);
        vm.assume(caller != users.steward);

        // When: Calling unpause().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.unpause(address(core));
    }

    function testFuzz_Revert_unpause_CoreNotValid(PoolState memory poolState, address candidate) public {
        // Given: A paused core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        vm.prank(users.guardian);
        almFactory.pause(address(core));

        // And: A candidate the factory did not create.
        vm.assume(candidate != address(core));

        // When: The steward unpauses the candidate.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.unpause(candidate);
    }

    function testFuzz_Revert_unpause_CoreNotValid_HalfCreated(PoolState memory poolState, bool withSyncVaults) public {
        // Given: A pool whose creation stopped after one or two of its transactions.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        address halfCreated = setHalfCreated(withSyncVaults);

        // When: The steward unpauses the address its core will take.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.unpause(halfCreated);
    }

    function testFuzz_Revert_unpause_RoleCallsCoreDirectly(PoolState memory poolState, uint256 pick) public {
        // Given: A paused core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        vm.prank(users.guardian);
        almFactory.pause(address(core));

        // When: A role holder calls unpause() on the core itself.
        // Then: It reverts, the role being the factory's and not the caller's.
        vm.prank(roleAt(pick));
        vm.expectRevert(Ownable.Unauthorized.selector);
        core.unpause();
    }

    function testFuzz_Revert_unpause_RoleCallsVaultDirectly(PoolState memory poolState, uint256 pick, uint256 index)
        public
    {
        // Given: A paused core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        vm.prank(users.guardian);
        almFactory.pause(address(core));

        // And: One of its four vaults.
        address[4] memory list = vaultsOf(vaults);
        BaseVault vault = BaseVault(list[bound(index, 0, list.length - 1)]);

        // When: A role holder calls unpause() on the vault itself.
        // Then: It reverts, the role being the factory's and not the caller's.
        vm.prank(roleAt(pick));
        vm.expectRevert(Ownable.Unauthorized.selector);
        vault.setPaused(false);
    }

    function testFuzz_Success_unpause(PoolState memory poolState) public {
        // Given: A paused core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        vm.prank(users.guardian);
        almFactory.pause(address(core));

        // When: The steward calls unpause().
        vm.prank(users.steward);
        // Then: The core and its four vaults are unpaused together.
        vm.expectEmit(address(core));
        emit IALMCoreEvents.PausedSet(false);
        vm.expectEmit(vaults.syncVault0);
        emit BaseVault.PausedSet(false);
        vm.expectEmit(vaults.syncVault1);
        emit BaseVault.PausedSet(false);
        vm.expectEmit(vaults.asyncVault0);
        emit BaseVault.PausedSet(false);
        vm.expectEmit(vaults.asyncVault1);
        emit BaseVault.PausedSet(false);
        almFactory.unpause(address(core));

        address[4] memory list = vaultsOf(vaults);
        for (uint256 i; i < 4; ++i) {
            assertFalse(BaseVault(list[i]).paused());
        }
    }
}
