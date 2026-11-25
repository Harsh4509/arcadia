/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreView_Fuzz_Test } from "./_ALMCoreView.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";

/**
 * @notice Fuzz tests for the function "isOperator" of contract "ALMCoreView".
 */
contract IsOperator_ALMCoreView_Fuzz_Test is ALMCoreView_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreView_Fuzz_Test) {
        ALMCoreView_Fuzz_Test.setUp();
        setSpotPoolState();
        deployCoreView();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_isOperator_CoreNotValid(address notCore, address controller_, address operator) public {
        // Given: An address the factory does not hold as a core.
        vm.assume(notCore != address(almCore));

        // When: Reading it through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.isOperator(notCore, controller_, operator);
    }

    function testFuzz_Revert_isOperator_CoreNotValid_HalfCreated(address controller_, address operator) public {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        address core = BaseVault(halfCreatedVaults()[0]).share();

        // When: Reading its core address through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.isOperator(core, controller_, operator);
    }

    function testFuzz_Success_isOperator_IsTheApproval(address controller_, address operator, bool approved) public {
        // Given: An approval a vault wrote for a controller and an operator.
        vm.prank(asyncVault0);
        almCore.setOperator(controller_, operator, approved);

        // When: Reading it through the lens.
        bool read = coreView.isOperator(address(almCore), controller_, operator);

        // Then: It reads back.
        assertEq(read, approved);
    }
}
