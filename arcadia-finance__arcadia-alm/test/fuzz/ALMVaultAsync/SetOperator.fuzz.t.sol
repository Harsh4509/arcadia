/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultAsync_Fuzz_Test } from "./_ALMVaultAsync.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setOperator" of contract "ALMVaultAsync".
 */
contract SetOperator_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
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

    function testFuzz_Success_setOperator(address caller, address operator, bool approved, bool isToken0) public {
        // Given: An async vault.
        ALMVaultAsync vault = asyncVaultFor(isToken0);

        // When: The caller sets an operator.
        vm.prank(caller);
        bool success = vault.setOperator(operator, approved);

        // Then: It returns true, and the vault reads the approval back.
        assertTrue(success);
        assertEq(vault.isOperator(caller, operator), approved);
    }
}
