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
 * @notice Fuzz tests for the function "setProtocolFees" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(reentrancy-events, unsafe-typecast)
contract SetProtocolFees_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_setProtocolFees_Unauthorized(
        PoolState memory poolState,
        address caller,
        uint16 newProtocolEmissionFeeBps,
        uint16 newProtocolSwapFeeBps,
        address newFeeRecipient
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The caller is not the admin.
        vm.assume(caller != users.admin);

        // When: Calling setProtocolFees().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.setProtocolFees(address(core), newProtocolEmissionFeeBps, newProtocolSwapFeeBps, newFeeRecipient);
    }

    function testFuzz_Revert_setProtocolFees_Unauthorized_Role(
        PoolState memory poolState,
        uint256 pick,
        uint16 newProtocolEmissionFeeBps,
        uint16 newProtocolSwapFeeBps,
        address newFeeRecipient
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The caller holds another role than the admin.
        address caller = roleAt(pick);
        vm.assume(caller != users.admin);

        // When: Calling setProtocolFees().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.setProtocolFees(address(core), newProtocolEmissionFeeBps, newProtocolSwapFeeBps, newFeeRecipient);
    }

    function testFuzz_Revert_setProtocolFees_CoreNotValid(
        PoolState memory poolState,
        address candidate,
        uint16 newProtocolEmissionFeeBps,
        uint16 newProtocolSwapFeeBps,
        address newFeeRecipient
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: A candidate the factory did not create.
        vm.assume(candidate != address(core));

        // When: The admin calls setProtocolFees() on the candidate.
        // Then: It reverts.
        vm.prank(users.admin);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.setProtocolFees(candidate, newProtocolEmissionFeeBps, newProtocolSwapFeeBps, newFeeRecipient);
    }

    function testFuzz_Revert_setProtocolFees_CoreNotValid_HalfCreated(
        PoolState memory poolState,
        bool withSyncVaults,
        uint16 newProtocolEmissionFeeBps,
        uint16 newProtocolSwapFeeBps,
        address newFeeRecipient
    ) public {
        // Given: A pool whose creation stopped after one or two of its transactions.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        address halfCreated = setHalfCreated(withSyncVaults);

        // When: The admin calls setProtocolFees() on the address its core will take.
        // Then: It reverts.
        vm.prank(users.admin);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.setProtocolFees(halfCreated, newProtocolEmissionFeeBps, newProtocolSwapFeeBps, newFeeRecipient);
    }

    function testFuzz_Revert_setProtocolFees_RoleCallsCoreDirectly(
        PoolState memory poolState,
        uint256 pick,
        uint16 newProtocolEmissionFeeBps,
        uint16 newProtocolSwapFeeBps,
        address newFeeRecipient
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // When: A role holder calls setProtocolFees() on the core itself.
        // Then: It reverts, the role being the factory's and not the caller's.
        vm.prank(roleAt(pick));
        vm.expectRevert(Ownable.Unauthorized.selector);
        core.setProtocolFees(newProtocolEmissionFeeBps, newProtocolSwapFeeBps, newFeeRecipient);
    }

    function testFuzz_Success_setProtocolFees(
        PoolState memory poolState,
        uint16 newProtocolEmissionFeeBps,
        uint16 newProtocolSwapFeeBps,
        address newFeeRecipient
    ) public {
        // Given: A core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: Both fees within the protocol maximum and a recipient to pay them to.
        newProtocolEmissionFeeBps = uint16(bound(newProtocolEmissionFeeBps, 0, ConfigLib.MAX_FEE_BPS));
        newProtocolSwapFeeBps = uint16(bound(newProtocolSwapFeeBps, 0, ConfigLib.MAX_FEE_BPS));
        vm.assume(newFeeRecipient != address(0));

        // When: The admin calls setProtocolFees().
        vm.prank(users.admin);
        vm.expectEmit(address(core));
        // Then: The core emits the fees and their recipient, reached through the factory.
        emit IALMCoreEvents.ProtocolFeesSet(newProtocolEmissionFeeBps, newProtocolSwapFeeBps, newFeeRecipient);
        almFactory.setProtocolFees(address(core), newProtocolEmissionFeeBps, newProtocolSwapFeeBps, newFeeRecipient);
    }
}
