/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMRegistry_Fuzz_Test } from "./_ALMRegistry.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { EnumerableSetLib } from "@solady/utils/EnumerableSetLib.sol";

/**
 * @notice Fuzz tests for the function "isFactoryRegistered" of contract "ALMRegistry".
 */
contract IsFactoryRegistered_ALMRegistry_Fuzz_Test is ALMRegistry_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMRegistry_Fuzz_Test) {
        ALMRegistry_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_isFactoryRegistered_ValueIsZeroSentinel(RegistryState[] memory registryState) public {
        // Given: A registry with factories registered.
        registryState = givenValidRegistryState(registryState, 0, type(uint256).max);
        setRegistryState(registryState);

        // When: Asking whether the zero sentinel of the factory set is registered.
        // Then: It reverts.
        vm.expectRevert(EnumerableSetLib.ValueIsZeroSentinel.selector);
        registry.isFactoryRegistered(Constants.SET_ZERO_SENTINEL);
    }

    function testFuzz_Success_isFactoryRegistered_FalseForAnUnregisteredFactory(
        RegistryState[] memory registryState,
        address factory
    ) public {
        // Given: A registry with factories registered.
        registryState = givenValidRegistryState(registryState, 0, type(uint256).max);
        setRegistryState(registryState);

        // And: A factory that is not registered.
        vm.assume(factory != Constants.SET_ZERO_SENTINEL);
        for (uint256 i; i < registryState.length; ++i) {
            vm.assume(factory != registryState[i].factory);
        }

        // When: Asking whether the factory is registered.
        // Then: It is not.
        assertFalse(registry.isFactoryRegistered(factory));
    }

    function testFuzz_Success_isFactoryRegistered_TrueForARegisteredFactory(
        RegistryState[] memory registryState,
        uint256 index
    ) public {
        // Given: A registry with at least one factory registered.
        registryState = givenValidRegistryState(registryState, 1, type(uint256).max);
        setRegistryState(registryState);

        // And: One of those factories.
        index = bound(index, 0, registryState.length - 1);

        // When: Asking whether the factory is registered.
        // Then: It is.
        assertTrue(registry.isFactoryRegistered(registryState[index].factory));
    }
}
