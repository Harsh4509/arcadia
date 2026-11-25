/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync_Fuzz_Test } from "./_ALMVaultAsync.fuzz.t.sol";
import { ERC7540Operator } from "../../../src/vaults/abstracts/tokens/ERC7540Operator.sol";

/**
 * @notice Fuzz tests for the function "previewDeposit" of contract "ALMVaultAsync".
 */
contract PreviewDeposit_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
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

    function testFuzz_Revert_previewDeposit_PreviewNotSupported(uint256 assets, bool isToken0) public {
        // Given: An asynchronous vault.

        // When: Previewing a deposit.
        // Then: It reverts.
        vm.expectRevert(ERC7540Operator.PreviewNotSupported.selector);
        asyncVaultFor(isToken0).previewDeposit(assets);
    }
}
