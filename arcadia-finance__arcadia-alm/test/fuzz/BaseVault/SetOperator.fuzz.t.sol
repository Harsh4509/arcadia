/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { BaseVault_Fuzz_Test } from "./_BaseVault.fuzz.t.sol";
import { ERC7540Operator } from "../../../src/vaults/abstracts/tokens/ERC7540Operator.sol";

/**
 * @notice Fuzz tests for the function "setOperator" of contract "BaseVault", over both vault kinds.
 */
contract SetOperator_BaseVault_Fuzz_Test is BaseVault_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(BaseVault_Fuzz_Test) {
        BaseVault_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_setOperator_Approves(address controller_, address operator, uint256 index) public {
        // Given: The four vaults over a pool.
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];

        // When: A controller approves an operator through one of them.
        vm.prank(controller_);
        vm.expectEmit(address(vault));
        emit ERC7540Operator.OperatorSet(controller_, operator, true);
        bool success = vault.setOperator(operator, true);

        // Then: It succeeds, and the core keeps the approval.
        assertTrue(success);
        assertTrue(coreViewLogic.isOperator(address(almCore), controller_, operator));
    }

    function testFuzz_Success_setOperator_Revokes(
        address controller_,
        address operator,
        uint256 index,
        uint256 revokeIndex
    ) public {
        // Given: The four vaults over a pool, and an operator approved on one of them.
        vm.prank(controller_);
        vaults[bound(index, 0, vaults.length - 1)].setOperator(operator, true);

        // When: The controller revokes it through any of them.
        BaseVault vault = vaults[bound(revokeIndex, 0, vaults.length - 1)];
        vm.prank(controller_);
        vm.expectEmit(address(vault));
        emit ERC7540Operator.OperatorSet(controller_, operator, false);
        vault.setOperator(operator, false);

        // Then: The core no longer keeps the approval.
        assertFalse(coreViewLogic.isOperator(address(almCore), controller_, operator));
    }
}
