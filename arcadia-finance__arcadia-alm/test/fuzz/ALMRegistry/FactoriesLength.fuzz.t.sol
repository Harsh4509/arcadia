/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMRegistry_Fuzz_Test } from "./_ALMRegistry.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "factoriesLength" of contract "ALMRegistry".
 */
contract FactoriesLength_ALMRegistry_Fuzz_Test is ALMRegistry_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMRegistry_Fuzz_Test) {
        ALMRegistry_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_factoriesLength(RegistryState[] memory registryState) public {
        // Given: A registry with factories registered.
        registryState = givenValidRegistryState(registryState, 0, type(uint256).max);
        setRegistryState(registryState);

        // When: Asking for the number of factories.
        // Then: It is the number registered.
        assertEq(registry.factoriesLength(), registryState.length);
    }
}
