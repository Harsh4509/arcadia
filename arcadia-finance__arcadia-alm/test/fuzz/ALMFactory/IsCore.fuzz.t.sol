/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "isCore" of contract "ALMFactory".
 */
contract IsCore_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_isCore_FalseForAnythingNotCreated(PoolState memory poolState, address candidate) public {
        // Given: A factory with a core over the pool.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: A candidate that is not that core.
        vm.assume(candidate != address(core));

        // When: Asking whether the candidate is genuine.
        // Then: It is not.
        assertFalse(almFactory.isCore(candidate));
    }

    function testFuzz_Success_isCore_TrueForACreatedCore(PoolState memory poolState) public {
        // Given: A factory with a core over the pool.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // When: Asking whether that core is genuine.
        // Then: It is.
        assertTrue(almFactory.isCore(address(core)));
    }
}
