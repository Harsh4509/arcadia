/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync_Fuzz_Test } from "./_ALMVaultAsync.fuzz.t.sol";
import { IERC165 } from "@forge-std/interfaces/IERC165.sol";
import { IERC7540Deposit, IERC7540Operator, IERC7540Redeem } from "@forge-std/interfaces/IERC7540.sol";
import { IERC7575 } from "@forge-std/interfaces/IERC7575.sol";

/**
 * @notice Fuzz tests for the function "supportsInterface" of contract "ALMVaultAsync".
 */
contract SupportsInterface_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
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

    function testFuzz_Success_supportsInterface_Supported(bool isToken0) public {
        // Given: An asynchronous vault.

        // When: Asking for ERC-165, ERC-7575, the ERC-7540 operator and both async sides.
        // Then: It supports all five.
        assertTrue(asyncVaultFor(isToken0).supportsInterface(type(IERC165).interfaceId));
        assertTrue(asyncVaultFor(isToken0).supportsInterface(type(IERC7575).interfaceId));
        assertTrue(asyncVaultFor(isToken0).supportsInterface(type(IERC7540Operator).interfaceId));
        assertTrue(asyncVaultFor(isToken0).supportsInterface(type(IERC7540Deposit).interfaceId));
        assertTrue(asyncVaultFor(isToken0).supportsInterface(type(IERC7540Redeem).interfaceId));
    }

    function testFuzz_Success_supportsInterface_Unsupported(bytes4 interfaceId, bool isToken0) public {
        // Given: An asynchronous vault, and an id it does not implement.
        vm.assume(
            interfaceId != type(IERC165).interfaceId && interfaceId != type(IERC7575).interfaceId
                && interfaceId != type(IERC7540Operator).interfaceId
        );
        vm.assume(interfaceId != type(IERC7540Deposit).interfaceId && interfaceId != type(IERC7540Redeem).interfaceId);

        // When: Asking for it.
        // Then: It is not supported.
        assertFalse(asyncVaultFor(isToken0).supportsInterface(interfaceId));
    }
}
