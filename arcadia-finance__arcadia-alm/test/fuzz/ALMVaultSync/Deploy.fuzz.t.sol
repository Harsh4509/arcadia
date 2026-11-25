/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";

/**
 * @notice Fuzz tests for the deployment of contract "ALMVaultSync".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract Deploy_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultSync_Fuzz_Test) {
        ALMVaultSync_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_deploy_ReadsItsOwnConfiguration(bool isToken0) public {
        // Given: The synchronous vaults of a core.

        // When: Reading the vault over one of the two pool tokens.
        ALMVaultSync vault = vaultFor(isToken0);

        // Then: Its share is its core, its asset that pool token, and it is not paused.
        assertEq(vault.share(), address(almCore));
        assertEq(vault.asset(), (isToken0 ? address(token0) : address(token1)));
        assertFalse(vault.paused());
    }

    function testFuzz_Success_deploy_RegistersBothKindsOnTheCore(bool isToken0) public {
        // Given: The synchronous vaults of a core, and one of its two tokens.
        address token = address(isToken0 ? token0 : token1);

        // When: Reading the token's vaults off the core.
        // Then: The core resolves the token's synchronous vault by the ERC-7575 lookup.
        assertEq(almCore.vault(token), address(vaultFor(isToken0)));

        // And: The asynchronous vault of the token through its own.
        assertEq(almCore.asyncVault_(token), isToken0 ? asyncVault0 : asyncVault1);

        // And: The four are distinct.
        assertTrue(address(syncVault0) != address(syncVault1));
        assertTrue(asyncVault0 != asyncVault1);
        assertTrue(address(syncVault0) != asyncVault0);
    }

    function testFuzz_Success_deploy_ApprovesTheCoreForBothTokens(bool isToken0) public {
        // Given: The synchronous vaults of a core.

        // When: Reading the allowances the vault gave the core.
        ALMVaultSync vault = vaultFor(isToken0);

        // Then: The core may pull either token, so a mint never needs a fresh approval.
        assertEq(token0.allowance(address(vault), address(almCore)), type(uint256).max);
        assertEq(token1.allowance(address(vault), address(almCore)), type(uint256).max);
    }
}
