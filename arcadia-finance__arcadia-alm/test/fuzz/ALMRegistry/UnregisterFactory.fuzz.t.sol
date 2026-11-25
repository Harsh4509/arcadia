/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMRegistry } from "../../../src/registry/ALMRegistry.sol";
import { ALMRegistry_Fuzz_Test } from "./_ALMRegistry.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { EnumerableSetLib } from "@solady/utils/EnumerableSetLib.sol";
import { Ownable } from "@solady/auth/Ownable.sol";

/**
 * @notice Fuzz tests for the function "unregisterFactory" of contract "ALMRegistry".
 */
contract UnregisterFactory_ALMRegistry_Fuzz_Test is ALMRegistry_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMRegistry_Fuzz_Test) {
        ALMRegistry_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_unregisterFactory_Unauthorized(
        RegistryState[] memory registryState,
        address caller,
        address factory
    ) public {
        // Given: A registry with factories registered.
        registryState = givenValidRegistryState(registryState, 0, type(uint256).max);
        setRegistryState(registryState);

        // And: The caller is not the owner.
        vm.assume(caller != users.owner);

        // When: Calling unregisterFactory().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.unregisterFactory(factory);
    }

    function testFuzz_Revert_unregisterFactory_ValueIsZeroSentinel(RegistryState[] memory registryState) public {
        // Given: A registry with factories registered.
        registryState = givenValidRegistryState(registryState, 0, type(uint256).max);
        setRegistryState(registryState);

        // When: The owner unregisters the zero sentinel of the factory set.
        // Then: It reverts.
        vm.prank(users.owner);
        vm.expectRevert(EnumerableSetLib.ValueIsZeroSentinel.selector);
        registry.unregisterFactory(Constants.SET_ZERO_SENTINEL);
    }

    function testFuzz_Revert_unregisterFactory_NotRegistered(RegistryState[] memory registryState, address factory)
        public
    {
        // Given: A registry with factories registered.
        registryState = givenValidRegistryState(registryState, 0, type(uint256).max);
        setRegistryState(registryState);

        // And: A factory that is not registered.
        vm.assume(factory != Constants.SET_ZERO_SENTINEL);
        for (uint256 i; i < registryState.length; ++i) {
            vm.assume(factory != registryState[i].factory);
        }

        // When: The owner unregisters the factory.
        // Then: It reverts.
        vm.prank(users.owner);
        vm.expectRevert(ALMRegistry.NotRegistered.selector);
        registry.unregisterFactory(factory);
    }

    function testFuzz_Revert_unregisterFactory_NotRegistered_AlreadyUnregistered(
        RegistryState[] memory registryState,
        uint256 index
    ) public {
        // Given: A registry with at least one factory registered.
        registryState = givenValidRegistryState(registryState, 1, type(uint256).max);
        setRegistryState(registryState);

        // And: One of those factories was unregistered.
        index = bound(index, 0, registryState.length - 1);
        vm.prank(users.owner);
        registry.unregisterFactory(registryState[index].factory);

        // When: The owner unregisters it again.
        // Then: It reverts.
        vm.prank(users.owner);
        vm.expectRevert(ALMRegistry.NotRegistered.selector);
        registry.unregisterFactory(registryState[index].factory);
    }

    function testFuzz_Success_unregisterFactory_SmallSet_KeepsOrder(RegistryState[] memory registryState, uint256 index)
        public
    {
        // Given: At most as many factories registered as the set keeps inline.
        registryState = givenValidRegistryState(registryState, 1, Constants.MAX_INLINE_SET_LENGTH);
        setRegistryState(registryState);

        // And: One of those factories.
        index = bound(index, 0, registryState.length - 1);

        // When: The owner unregisters that factory.
        vm.expectEmit(address(registry));
        emit ALMRegistry.FactoryUnregistered(registryState[index].factory);
        vm.prank(users.owner);
        registry.unregisterFactory(registryState[index].factory);

        // Then: The factory is no longer registered and its lens is cleared.
        assertFalse(registry.isFactoryRegistered(registryState[index].factory));
        assertEq(registry.factoryToLens(registryState[index].factory), address(0));

        // And: The others remain registered with their lenses, in registration order.
        assertEq(registry.factoriesLength(), registryState.length - 1);
        for (uint256 i; i < registryState.length - 1; ++i) {
            RegistryState memory expected = registryState[i < index ? i : i + 1];
            assertEq(registry.factoriesAt(i), expected.factory);
            assertTrue(registry.isFactoryRegistered(expected.factory));
            assertEq(registry.factoryToLens(expected.factory), expected.lens);
        }
    }

    function testFuzz_Success_unregisterFactory_LargeSet_MovesLastIntoGap(
        RegistryState[] memory registryState,
        uint256 index
    ) public {
        // Given: A registry with more factories registered than the set keeps inline.
        registryState = givenValidRegistryState(registryState, Constants.MAX_INLINE_SET_LENGTH + 1, type(uint256).max);
        setRegistryState(registryState);

        // And: One of those factories.
        index = bound(index, 0, registryState.length - 1);

        // When: The owner unregisters that factory.
        vm.expectEmit(address(registry));
        emit ALMRegistry.FactoryUnregistered(registryState[index].factory);
        vm.prank(users.owner);
        registry.unregisterFactory(registryState[index].factory);

        // Then: The factory is no longer registered and its lens is cleared.
        assertFalse(registry.isFactoryRegistered(registryState[index].factory));
        assertEq(registry.factoryToLens(registryState[index].factory), address(0));

        // And: The last factory moved into the gap, the others kept position and lens.
        uint256 last = registryState.length - 1;
        assertEq(registry.factoriesLength(), last);
        for (uint256 i; i < last; ++i) {
            RegistryState memory expected = registryState[i == index ? last : i];
            assertEq(registry.factoriesAt(i), expected.factory);
            assertTrue(registry.isFactoryRegistered(expected.factory));
            assertEq(registry.factoryToLens(expected.factory), expected.lens);
        }
    }
}
