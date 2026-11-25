/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";
import { IERC165 } from "@forge-std/interfaces/IERC165.sol";
import { IERC7540Deposit, IERC7540Operator, IERC7540Redeem } from "@forge-std/interfaces/IERC7540.sol";
import { IERC7575 } from "@forge-std/interfaces/IERC7575.sol";

/**
 * @notice Fuzz tests for the function "supportsInterface" of contract "ALMVaultSync".
 */
contract SupportsInterface_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
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

    function testFuzz_Success_supportsInterface_Supported(bool isToken0) public {
        // Given: A synchronous vault.
        ALMVaultSync vault = vaultFor(isToken0);

        // When: Asking for ERC-165, the ERC-7575 vault and the ERC-7540 operator.
        // Then: It supports all three.
        assertTrue(vault.supportsInterface(type(IERC165).interfaceId));
        assertTrue(vault.supportsInterface(type(IERC7575).interfaceId));
        assertTrue(vault.supportsInterface(type(IERC7540Operator).interfaceId));
    }

    function testFuzz_Success_supportsInterface_NoRequestFlow(bool isToken0) public {
        // Given: A synchronous vault.
        ALMVaultSync vault = vaultFor(isToken0);

        // When: Asking for either asynchronous ERC-7540 side.
        // Then: It supports neither, settling every call at once.
        assertFalse(vault.supportsInterface(type(IERC7540Deposit).interfaceId));
        assertFalse(vault.supportsInterface(type(IERC7540Redeem).interfaceId));
    }

    function testFuzz_Success_supportsInterface_Unsupported(bytes4 interfaceId, bool isToken0) public {
        // Given: A synchronous vault, and an id it does not implement.
        ALMVaultSync vault = vaultFor(isToken0);
        vm.assume(
            interfaceId != type(IERC165).interfaceId && interfaceId != type(IERC7575).interfaceId
                && interfaceId != type(IERC7540Operator).interfaceId
        );

        // When: Asking for it.
        // Then: It is not supported.
        assertFalse(vault.supportsInterface(interfaceId));
    }
}
