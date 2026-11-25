/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { BaseVault_Fuzz_Test } from "./_BaseVault.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "isOperator" of contract "BaseVault", over both vault kinds.
 */
contract IsOperator_BaseVault_Fuzz_Test is BaseVault_Fuzz_Test {
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

    function testFuzz_Revert_isOperator_CoreNotDeployed(uint256 index, address controller_, address operator) public {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        address[4] memory list = halfCreatedVaults();
        address vault = list[bound(index, 0, list.length - 1)];

        // When: Reading isOperator() on one of its vaults.
        // Then: It reverts without data, the read of the core finding no code.
        vm.expectRevert(bytes(""));
        BaseVault(vault).isOperator(controller_, operator);
    }

    function testFuzz_Success_isOperator_FalseByDefault(address controller_, address operator, uint256 index) public {
        // Given: The four vaults over a pool, and no approval.
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];

        // When: Reading the operator status.
        // Then: Nobody operates for anybody.
        assertFalse(vault.isOperator(controller_, operator));
    }

    function testFuzz_Success_isOperator_SharedByEveryVault(address controller_, address operator, uint256 index)
        public
    {
        // Given: The four vaults over a pool, and an operator approved on one of them.
        vm.prank(controller_);
        vaults[bound(index, 0, vaults.length - 1)].setOperator(operator, true);

        // When: Reading the operator status on each vault.
        // Then: Every vault over the core reports it.
        for (uint256 i; i < vaults.length; ++i) {
            assertTrue(vaults[i].isOperator(controller_, operator));
        }
    }

    function testFuzz_Success_isOperator_OnlyForTheController(
        address controller_,
        address operator,
        address bystander,
        uint256 index
    ) public {
        // Given: The four vaults over a pool, a controller's operator, and a bystander.
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];
        vm.assume(bystander != controller_);
        vm.prank(controller_);
        vault.setOperator(operator, true);

        // When: Reading the operator status for the bystander.
        // Then: The operator acts for the controller only.
        assertFalse(vault.isOperator(bystander, operator));
    }
}
