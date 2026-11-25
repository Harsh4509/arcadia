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
 * @notice Fuzz tests for the function "setDeviation" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(reentrancy-events, unsafe-typecast)
contract SetDeviation_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_setDeviation_Unauthorized(
        PoolState memory poolState,
        address caller,
        uint32 newTwapWindow,
        uint256 newMaxSpotFromTwap,
        uint256 newMaxFromTrusted
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The caller is not the admin.
        vm.assume(caller != users.admin);

        // When: Calling setDeviation().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.setDeviation(address(core), newTwapWindow, newMaxSpotFromTwap, newMaxFromTrusted, newMaxFromTrusted);
    }

    function testFuzz_Revert_setDeviation_Unauthorized_Role(
        PoolState memory poolState,
        uint256 pick,
        uint32 newTwapWindow,
        uint256 newMaxSpotFromTwap,
        uint256 newMaxFromTrusted
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The caller holds another role than the admin.
        address caller = roleAt(pick);
        vm.assume(caller != users.admin);

        // When: Calling setDeviation().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.setDeviation(address(core), newTwapWindow, newMaxSpotFromTwap, newMaxFromTrusted, newMaxFromTrusted);
    }

    function testFuzz_Revert_setDeviation_CoreNotValid(
        PoolState memory poolState,
        address candidate,
        uint32 newTwapWindow,
        uint256 newMaxSpotFromTwap,
        uint256 newMaxFromTrusted
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: A candidate the factory did not create.
        vm.assume(candidate != address(core));

        // When: The admin calls setDeviation() on the candidate.
        // Then: It reverts.
        vm.prank(users.admin);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.setDeviation(candidate, newTwapWindow, newMaxSpotFromTwap, newMaxFromTrusted, newMaxFromTrusted);
    }

    function testFuzz_Revert_setDeviation_CoreNotValid_HalfCreated(
        PoolState memory poolState,
        bool withSyncVaults,
        uint32 newTwapWindow,
        uint256 newMaxSpotFromTwap,
        uint256 newMaxFromTrusted
    ) public {
        // Given: A pool whose creation stopped after one or two of its transactions.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        address halfCreated = setHalfCreated(withSyncVaults);

        // When: The admin calls setDeviation() on the address its core will take.
        // Then: It reverts.
        vm.prank(users.admin);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.setDeviation(halfCreated, newTwapWindow, newMaxSpotFromTwap, newMaxFromTrusted, newMaxFromTrusted);
    }

    function testFuzz_Revert_setDeviation_RoleCallsCoreDirectly(
        PoolState memory poolState,
        uint256 pick,
        uint32 newTwapWindow,
        uint256 newMaxSpotFromTwap,
        uint256 newMaxFromTrusted
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // When: A role holder calls setDeviation() on the core itself.
        // Then: It reverts, the role being the factory's and not the caller's.
        vm.prank(roleAt(pick));
        vm.expectRevert(Ownable.Unauthorized.selector);
        core.setDeviation(newTwapWindow, newMaxSpotFromTwap, newMaxFromTrusted, newMaxFromTrusted);
    }

    function testFuzz_Success_setDeviation(
        PoolState memory poolState,
        uint32 newTwapWindow,
        uint256 newMaxSpotFromTwap,
        uint256 newMaxSpotFromTrusted,
        uint256 newMaxTwapFromTrusted
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: A non-zero window, and three bands that fit their storage.
        newTwapWindow = uint32(bound(newTwapWindow, 1, type(uint32).max));
        newMaxSpotFromTwap = bound(newMaxSpotFromTwap, 0, type(uint64).max);
        newMaxSpotFromTrusted = bound(newMaxSpotFromTrusted, 0, type(uint64).max);
        newMaxTwapFromTrusted = bound(newMaxTwapFromTrusted, 0, type(uint64).max);

        // When: The admin calls setDeviation().
        vm.prank(users.admin);
        vm.expectEmit(address(core));
        // Then: The core emits the window and the bands, reached through the factory.
        emit IALMCoreEvents.DeviationSet(
            newTwapWindow, newMaxSpotFromTwap, newMaxSpotFromTrusted, newMaxTwapFromTrusted
        );
        almFactory.setDeviation(
            address(core), newTwapWindow, newMaxSpotFromTwap, newMaxSpotFromTrusted, newMaxTwapFromTrusted
        );
    }
}
