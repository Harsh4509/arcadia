/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMRegistry_Fuzz_Test } from "./_ALMRegistry.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "factoriesAt" of contract "ALMRegistry".
 */
contract FactoriesAt_ALMRegistry_Fuzz_Test is ALMRegistry_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMRegistry_Fuzz_Test) {
        ALMRegistry_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_factoriesAt_ZeroPastTheEnd(RegistryState[] memory registryState, uint256 index) public {
        // Given: A registry with factories registered.
        registryState = givenValidRegistryState(registryState, 0, type(uint256).max);
        setRegistryState(registryState);

        // And: An index past the last factory.
        index = bound(index, registryState.length, type(uint256).max);

        // When: Reading the factory at that index.
        // Then: It is the zero address.
        assertEq(registry.factoriesAt(index), address(0));
    }

    function testFuzz_Success_factoriesAt(RegistryState[] memory registryState, uint256 index) public {
        // Given: A registry with at least one factory registered.
        registryState = givenValidRegistryState(registryState, 1, type(uint256).max);
        setRegistryState(registryState);

        // And: An index of one of those factories.
        index = bound(index, 0, registryState.length - 1);

        // When: Reading the factory at that index.
        address factory = registry.factoriesAt(index);

        // Then: It is the factory registered at that position, mapped to its lens.
        assertEq(factory, registryState[index].factory);
        assertEq(registry.factoryToLens(factory), registryState[index].lens);
    }
}
