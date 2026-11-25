/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "allCoresLength" of contract "ALMFactory".
 */
contract AllCoresLength_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_allCoresLength_ZeroWithoutCores(PoolState memory poolState) public {
        // Given: A factory without cores.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // When: Asking for the number of cores.
        // Then: It is zero.
        assertEq(almFactory.allCoresLength(), 0);
    }

    function testFuzz_Success_allCoresLength_ListsACreatedCoreWithItsPool(PoolState memory poolState) public {
        // Given: A factory with a core over the pool.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // When: Listing the cores.
        // Then: The core is the only one, and maps back to its pool.
        assertEq(almFactory.allCoresLength(), 1);
        assertEq(almFactory.allCores(0), address(core));
        assertEq(almFactory.poolOf(address(core)), address(pool));
    }
}
