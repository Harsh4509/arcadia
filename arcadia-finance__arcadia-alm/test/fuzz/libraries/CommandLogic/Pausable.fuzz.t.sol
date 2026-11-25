/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CommandLogic } from "../../../../src/core/libraries/logic/CommandLogic.sol";
import { CommandLogic_Fuzz_Test } from "./_CommandLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "pausable" of library "CommandLogic".
 */
contract Pausable_CommandLogic_Fuzz_Test is CommandLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(CommandLogic_Fuzz_Test) {
        CommandLogic_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_pausable_RefusesEveryStepThatAddsValue(uint256 pick) public view {
        // Given: One of the six steps that move value into the vault's ranges or swap it.
        uint8[6] memory adding = [
            CommandLogic.OPEN_RANGE,
            CommandLogic.INCREASE_LIQUIDITY,
            CommandLogic.STAKE,
            CommandLogic.INCREASE_STAKED_LIQUIDITY,
            CommandLogic.SWAP_VIA_POOL,
            CommandLogic.SWAP_VIA_ROUTER
        ];
        pick = bound(pick, 0, adding.length - 1);

        // When: Asking whether a paused vault refuses it.
        // Then: It does.
        assertTrue(commandLogic.pausable(adding[pick]));
    }

    function testFuzz_Success_pausable_AllowsEveryTeardownStep(uint256 pick) public view {
        // Given: A step taking value out, a queue step its handler gates or settlement.
        uint8[9] memory teardown = [
            CommandLogic.CLOSE_RANGE,
            CommandLogic.DECREASE_LIQUIDITY,
            CommandLogic.COLLECT,
            CommandLogic.UNSTAKE,
            CommandLogic.EMERGENCY_UNSTAKE,
            CommandLogic.CLEAR_REQUESTS,
            CommandLogic.CLEAR_ALL_REQUESTS,
            CommandLogic.CANCEL_REQUESTS,
            CommandLogic.SETTLE_REQUESTS
        ];
        pick = bound(pick, 0, teardown.length - 1);

        // When: Asking whether a paused vault refuses it.
        // Then: It does not.
        assertFalse(commandLogic.pausable(teardown[pick]));
    }

    function testFuzz_Success_pausable_AllowsAByteOutsideTheTable(uint8 kind, uint8 place) public view {
        // Given: A byte the table does not name, its kind or place past the last.
        uint8[4] memory last = [
            CommandLogic.SETTLE_REQUESTS,
            CommandLogic.EMERGENCY_UNSTAKE,
            CommandLogic.SWAP_VIA_ROUTER,
            CommandLogic.INCREASE_STAKED_LIQUIDITY
        ];
        kind = uint8(bound(kind, 0, 15));
        place = uint8(bound(place, kind < last.length ? (last[kind] & 0x0f) + 1 : 0, 15));
        uint8 command = (kind << 4) | place;

        // When: Asking whether a paused vault refuses it.
        // Then: It does not, the unknown opcode being rejected by the dispatcher instead.
        assertFalse(commandLogic.pausable(command));
    }
}
