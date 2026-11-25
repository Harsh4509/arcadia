/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CommandLogic } from "../../../../src/core/libraries/logic/CommandLogic.sol";
import { CommandLogic_Fuzz_Test } from "./_CommandLogic.fuzz.t.sol";
import { Constants } from "../../../utils/Constants.sol";

/**
 * @notice Fuzz tests for the opcode table of library "CommandLogic".
 */
contract Opcodes_CommandLogic_Fuzz_Test is CommandLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(CommandLogic_Fuzz_Test) {
        CommandLogic_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_opcodes_MatchTheSpecTable(uint256 pick) public pure {
        // Given: Any opcode.
        uint8[15] memory opcodes = [
            CommandLogic.CLEAR_REQUESTS,
            CommandLogic.CLEAR_ALL_REQUESTS,
            CommandLogic.CANCEL_REQUESTS,
            CommandLogic.SETTLE_REQUESTS,
            CommandLogic.CLOSE_RANGE,
            CommandLogic.DECREASE_LIQUIDITY,
            CommandLogic.COLLECT,
            CommandLogic.UNSTAKE,
            CommandLogic.EMERGENCY_UNSTAKE,
            CommandLogic.SWAP_VIA_POOL,
            CommandLogic.SWAP_VIA_ROUTER,
            CommandLogic.OPEN_RANGE,
            CommandLogic.INCREASE_LIQUIDITY,
            CommandLogic.STAKE,
            CommandLogic.INCREASE_STAKED_LIQUIDITY
        ];
        pick = bound(pick, 0, opcodes.length - 1);

        // When: Reading its byte.
        uint8 opcode = opcodes[pick];

        // Then: It is the table's byte, the kind in the high nibble, place in the low.
        assertEq(opcode, uint8(Constants.OPCODES[pick]));
    }
}
