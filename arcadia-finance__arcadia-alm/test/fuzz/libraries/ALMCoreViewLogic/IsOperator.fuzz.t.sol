/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "isOperator" of library "ALMCoreViewLogic".
 */
contract IsOperator_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_isOperator_ReadsUnderBothKeys(address controller_, address operator, bool approved)
        public
    {
        // Given: An approval a vault wrote for a controller and an operator.
        vm.assume(controller_ != operator);
        vm.prank(asyncVault0);
        almCore.setOperator(controller_, operator, approved);

        // When: Reading the pair both ways round.
        // Then: The approval reads back, and the reversed pair stays unset.
        assertEq(coreViewLogic.isOperator(address(almCore), controller_, operator), approved);
        assertFalse(coreViewLogic.isOperator(address(almCore), operator, controller_));
    }
}
