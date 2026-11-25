/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CommandLogic } from "../../../src/core/libraries/logic/CommandLogic.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";

/**
 * @notice Symbolic tests for the function "pausable" of library "CommandLogic".
 */
contract Pausable_CommandLogic_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function prove_pausable_RefusesExactlyTheBuildupAndSwapSteps(uint8 command) public pure {
        // Given: Any byte.
        bool buildupOrSwap = (command >= CommandLogic.SWAP_VIA_POOL && command <= CommandLogic.SWAP_VIA_ROUTER)
            || (command >= CommandLogic.OPEN_RANGE && command <= CommandLogic.INCREASE_STAKED_LIQUIDITY);

        // When: Asking whether a paused core refuses it.
        // Then: It does exactly for the buildup and swap opcodes.
        assertEq(CommandLogic.pausable(command), buildupOrSwap);
    }
}
