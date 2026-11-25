/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMRegistry_Fuzz_Test } from "./_ALMRegistry.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "factories" of contract "ALMRegistry".
 */
contract Factories_ALMRegistry_Fuzz_Test is ALMRegistry_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMRegistry_Fuzz_Test) {
        ALMRegistry_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_factories(RegistryState[] memory registryState) public {
        // Given: A registry with factories registered.
        registryState = givenValidRegistryState(registryState, 0, type(uint256).max);
        setRegistryState(registryState);

        // When: Listing the factories.
        address[] memory factories = registry.factories();

        // Then: Every factory is listed in registration order, mapped to its lens.
        assertEq(factories.length, registryState.length);
        for (uint256 i; i < registryState.length; ++i) {
            assertEq(factories[i], registryState[i].factory);
            assertEq(registry.factoryToLens(factories[i]), registryState[i].lens);
        }
    }
}
