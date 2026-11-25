/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultAsync_Fuzz_Test } from "./_ALMVaultAsync.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "isOperator" of contract "ALMVaultAsync".
 */
contract IsOperator_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
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

    function testFuzz_Success_isOperator(address controller_, address operator, bool approved, bool isToken0) public {
        // Given: An approval the core keeps.
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        vm.prank(address(vault));
        almCore.setOperator(controller_, operator, approved);

        // When: Reading the operator status through the vault.
        bool status = vault.isOperator(controller_, operator);

        // Then: It is the core's approval.
        assertEq(status, approved);
    }
}
