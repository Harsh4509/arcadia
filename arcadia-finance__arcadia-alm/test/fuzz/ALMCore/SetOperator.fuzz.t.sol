/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setOperator" of contract "ALMCore".
 */
contract SetOperator_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_setOperator_OnlyVault(address caller, address controller_, address operator, bool approved)
        public
    {
        // Given: A caller that is none of the core's four vaults.
        vm.assume(caller != almCore.vault(address(token0)) && caller != almCore.vault(address(token1)));
        vm.assume(caller != asyncVault0 && caller != asyncVault1);

        // When: The caller writes an operator approval.
        // Then: It reverts, so only a controller's own call through a vault can approve.
        vm.prank(caller);
        vm.expectRevert(ALMCore.OnlyVault.selector);
        almCore.setOperator(controller_, operator, approved);
    }

    function testFuzz_Success_setOperator(address controller_, address operator, bool approved, uint256 index) public {
        // Given: One of the core's four vaults.
        index = bound(index, 0, 3);
        address[4] memory vaults =
            [almCore.vault(address(token0)), almCore.vault(address(token1)), asyncVault0, asyncVault1];

        // When: The vault writes an operator approval.
        vm.prank(vaults[index]);
        bool success = almCore.setOperator(controller_, operator, approved);

        // Then: The core keeps it.
        assertTrue(success);
        assertEq(coreViewLogic.isOperator(address(almCore), controller_, operator), approved);
    }
}
