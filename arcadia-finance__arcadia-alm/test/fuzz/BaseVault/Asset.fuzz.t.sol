/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { BaseVault_Fuzz_Test } from "./_BaseVault.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "asset" of contract "BaseVault", over both vault kinds.
 */
contract Asset_BaseVault_Fuzz_Test is BaseVault_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(BaseVault_Fuzz_Test) {
        BaseVault_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_asset_IsItsPoolToken(PoolState memory poolState, uint256 index) public {
        // Given: The four vaults over a pool at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        index = bound(index, 0, vaults.length - 1);

        // When: Reading the asset of one of them.
        address asset = vaults[index].asset();

        // Then: It is token0 for the vaults over token0, token1 for the others.
        assertEq(asset, index % 2 == 0 ? pool.token0() : pool.token1());
    }

    function testFuzz_Success_asset_WithoutTheCore(PoolState memory poolState, uint256 index) public {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        address[4] memory list = halfCreatedVaults();
        index = bound(index, 0, list.length - 1);

        // When: Reading the asset of one of them.
        address asset = BaseVault(list[index]).asset();

        // Then: It is that vault's pool token, read without the core.
        assertEq(asset, index % 2 == 0 ? pool.token0() : pool.token1());
    }
}
