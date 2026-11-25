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
 * @notice Fuzz tests for the function "lowerTotalCap" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract LowerTotalCap_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_lowerTotalCap_Unauthorized(PoolState memory poolState, address caller, uint256 newTotalCap)
        public
    {
        // Given: A configured core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        setVaultConfigured();

        // And: The caller is neither the guardian nor the steward.
        vm.assume(caller != users.guardian && caller != users.steward);

        // When: Calling lowerTotalCap().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.lowerTotalCap(address(core), newTotalCap);
    }

    function testFuzz_Revert_lowerTotalCap_Unauthorized_Role(
        PoolState memory poolState,
        uint256 pick,
        uint256 newTotalCap
    ) public {
        // Given: A configured core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        setVaultConfigured();

        // And: The caller holds another role than the guardian or the steward.
        address caller = roleAt(pick);
        vm.assume(caller != users.guardian && caller != users.steward);

        // When: Calling lowerTotalCap().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.lowerTotalCap(address(core), newTotalCap);
    }

    function testFuzz_Revert_lowerTotalCap_CoreNotValid(
        PoolState memory poolState,
        address candidate,
        uint256 newTotalCap
    ) public {
        // Given: A configured core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        setVaultConfigured();

        // And: A candidate the factory did not create.
        vm.assume(candidate != address(core));

        // When: The steward calls lowerTotalCap() on the candidate.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.lowerTotalCap(candidate, newTotalCap);
    }

    function testFuzz_Revert_lowerTotalCap_CoreNotValid_HalfCreated(
        PoolState memory poolState,
        bool withSyncVaults,
        uint256 newTotalCap
    ) public {
        // Given: A pool whose creation stopped after one or two of its transactions.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        address halfCreated = setHalfCreated(withSyncVaults);

        // When: The steward calls lowerTotalCap() on the address its core will take.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.lowerTotalCap(halfCreated, newTotalCap);
    }

    function testFuzz_Revert_lowerTotalCap_RoleCallsCoreDirectly(
        PoolState memory poolState,
        uint256 pick,
        uint256 newTotalCap
    ) public {
        // Given: A configured core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        setVaultConfigured();

        // When: A role holder calls lowerTotalCap() on the core itself.
        // Then: It reverts, the role being the factory's and not the caller's.
        vm.prank(roleAt(pick));
        vm.expectRevert(Ownable.Unauthorized.selector);
        core.lowerTotalCap(newTotalCap);
    }

    function testFuzz_Success_lowerTotalCap(PoolState memory poolState, bool byGuardian, uint256 newTotalCap) public {
        // Given: A configured core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        setVaultConfigured();

        // And: A cap below the configured one.
        newTotalCap = bound(newTotalCap, 0, type(uint128).max - 1);

        // And: The guardian or the steward calls.
        address caller = byGuardian ? users.guardian : users.steward;

        // When: Calling lowerTotalCap().
        vm.prank(caller);
        vm.expectEmit(address(core));
        // Then: The core emits the total cap lowered, reached through the factory.
        emit IALMCoreEvents.TotalCapSet(newTotalCap);
        almFactory.lowerTotalCap(address(core), newTotalCap);
    }
}
