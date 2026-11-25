/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { BaseVault_Fuzz_Test } from "./_BaseVault.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "share" of contract "BaseVault", over both vault kinds.
 */
contract Share_BaseVault_Fuzz_Test is BaseVault_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(BaseVault_Fuzz_Test) {
        BaseVault_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_share_IsTheCore(PoolState memory poolState, uint256 index) public {
        // Given: The four vaults over a pool at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        index = bound(index, 0, vaults.length - 1);

        // When: Reading the share of one of them.
        // Then: It is the core every vault of the pool is registered on.
        assertEq(vaults[index].share(), address(almCore));
    }
}
