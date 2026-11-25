/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultAsync_Fuzz_Test } from "./_ALMVaultAsync.fuzz.t.sol";

/**
 * @notice Fuzz tests for the deployment of contract "ALMVaultAsync".
 */
contract Deploy_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultAsync_Fuzz_Test) {
        ALMVaultAsync_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_deploy_ReadsItsOwnConfiguration(bool isToken0) public {
        // Given: The vaults over a pool.

        // When: Reading the asynchronous vault over one of the two pool tokens.
        ALMVaultAsync vault = asyncVaultFor(isToken0);

        // Then: Its share is its core, its asset that pool token, and it is not paused.
        assertEq(vault.share(), address(almCore));
        assertEq(vault.asset(), (isToken0 ? address(token0) : address(token1)));
        assertFalse(vault.paused());
    }
}
