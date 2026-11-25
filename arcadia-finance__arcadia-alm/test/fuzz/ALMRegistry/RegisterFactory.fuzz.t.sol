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
 * @notice Fuzz tests for the function "registerFactory" of contract "ALMRegistry".
 */
contract RegisterFactory_ALMRegistry_Fuzz_Test is ALMRegistry_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMRegistry_Fuzz_Test) {
        ALMRegistry_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_registerFactory_Unauthorized(
        RegistryState[] memory registryState,
        address caller,
        address factory,
        address lens
    ) public {
        // Given: A registry with factories registered.
        registryState = givenValidRegistryState(registryState, 0, type(uint256).max);
        setRegistryState(registryState);

        // And: The caller is not the owner.
        vm.assume(caller != users.owner);

        // When: Calling registerFactory().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.registerFactory(factory, lens);
    }

    function testFuzz_Revert_registerFactory_ZeroAddress_Factory(RegistryState[] memory registryState, address lens)
        public
    {
        // Given: A registry with factories registered.
        registryState = givenValidRegistryState(registryState, 0, type(uint256).max);
        setRegistryState(registryState);

        // When: The owner registers the zero factory.
        // Then: It reverts.
        vm.prank(users.owner);
        vm.expectRevert(ALMRegistry.ZeroAddress.selector);
        registry.registerFactory(address(0), lens);
    }

    function testFuzz_Revert_registerFactory_ZeroAddress_Lens(RegistryState[] memory registryState, address factory)
        public
    {
        // Given: A registry with factories registered.
        registryState = givenValidRegistryState(registryState, 0, type(uint256).max);
        setRegistryState(registryState);

        // When: The owner registers a factory without a lens.
        // Then: It reverts.
        vm.prank(users.owner);
        vm.expectRevert(ALMRegistry.ZeroAddress.selector);
        registry.registerFactory(factory, address(0));
    }

    function testFuzz_Revert_registerFactory_ValueIsZeroSentinel(RegistryState[] memory registryState, address lens)
        public
    {
        // Given: A registry with factories registered.
        registryState = givenValidRegistryState(registryState, 0, type(uint256).max);
        setRegistryState(registryState);

        // And: A non-zero lens.
        vm.assume(lens != address(0));

        // When: The owner registers the zero sentinel of the factory set.
        // Then: It reverts.
        vm.prank(users.owner);
        vm.expectRevert(EnumerableSetLib.ValueIsZeroSentinel.selector);
        registry.registerFactory(Constants.SET_ZERO_SENTINEL, lens);
    }

    function testFuzz_Revert_registerFactory_AlreadyRegistered(
        RegistryState[] memory registryState,
        uint256 index,
        address lens
    ) public {
        // Given: A registry with at least one factory registered.
        registryState = givenValidRegistryState(registryState, 1, type(uint256).max);
        setRegistryState(registryState);

        // And: One of those factories, and a non-zero lens.
        index = bound(index, 0, registryState.length - 1);
        vm.assume(lens != address(0));

        // When: The owner registers that factory again.
        // Then: It reverts.
        vm.prank(users.owner);
        vm.expectRevert(ALMRegistry.AlreadyRegistered.selector);
        registry.registerFactory(registryState[index].factory, lens);
    }

    function testFuzz_Success_registerFactory(RegistryState[] memory registryState, address factory, address lens)
        public
    {
        // Given: A registry with factories registered.
        registryState = givenValidRegistryState(registryState, 0, type(uint256).max);
        setRegistryState(registryState);

        // And: A non-zero factory that is not registered, and a non-zero lens.
        vm.assume(factory != address(0) && lens != address(0));
        vm.assume(factory != Constants.SET_ZERO_SENTINEL);
        for (uint256 i; i < registryState.length; ++i) {
            vm.assume(factory != registryState[i].factory);
        }

        // When: The owner registers the factory.
        vm.expectEmit(address(registry));
        emit ALMRegistry.FactoryRegistered(factory, lens);
        vm.prank(users.owner);
        registry.registerFactory(factory, lens);

        // Then: The factory is registered.
        assertTrue(registry.isFactoryRegistered(factory));

        // And: It is appended after the earlier factories, which are unchanged.
        assertEq(registry.factoriesLength(), registryState.length + 1);
        for (uint256 i; i < registryState.length; ++i) {
            assertEq(registry.factoriesAt(i), registryState[i].factory);
            assertEq(registry.factoryToLens(registryState[i].factory), registryState[i].lens);
        }
        assertEq(registry.factoriesAt(registryState.length), factory);

        // And: It is mapped to its lens.
        assertEq(registry.factoryToLens(factory), lens);
    }
}
