/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { Epoch, PoolTokens, Record, ShareAccount } from "../../../../src/core/types/State.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";
import { stdError } from "@forge-std/StdError.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "clearDeposit" of library "QueueLib".
 */
contract ClearDeposit_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_clearDeposit_EscrowBelowTheAssets(
        address vault,
        address controller,
        bool isToken0,
        uint32 pendingEpoch,
        uint32 lastClearedEpoch,
        Record memory record,
        uint128 escrowed
    ) public {
        // Given: A pending deposit within a TokenDelta component, a cleared epoch apart.
        lastClearedEpoch = uint32(bound(lastClearedEpoch, 0, type(uint32).max - 1));
        if (lastClearedEpoch >= pendingEpoch) ++lastClearedEpoch;
        record.epoch = pendingEpoch;
        record.amountIn = uint128(bound(record.amountIn, 1, Constants.MAX_FUZZED_AMOUNT));
        queueLib.setPendingEpochs(vault, pendingEpoch, 0);
        queueLib.setLastClearedEpochs(vault, lastClearedEpoch, 0);
        queueLib.setDepositRecord(vault, controller, record);
        queueLib.setDepositEpoch(vault, pendingEpoch, Epoch({ amountIn: record.amountIn, amountOut: 0 }));

        // And: An escrow of the vault's token below the record's assets.
        escrowed = uint128(bound(escrowed, 0, record.amountIn - 1));
        queueLib.setEscrowed(isToken0 ? escrowed : 0, isToken0 ? 0 : escrowed);

        // When: Clearing the deposit.
        // Then: It reverts on the underflow.
        vm.expectRevert(stdError.arithmeticError);
        queueLib.clearDeposit(vault, controller, isToken0);
    }

    function testFuzz_Success_clearDeposit_MovesTheRequestIntoTheClearedEpoch(
        address vault,
        address controller,
        bool isToken0,
        uint32 pendingEpoch,
        uint32 lastClearedEpoch,
        Record memory record,
        ShareAccount memory shareAccount,
        uint128 otherIn,
        uint128 clearedIn
    ) public {
        // Given: A pending deposit within a TokenDelta component, its aLP pending.
        lastClearedEpoch = uint32(bound(lastClearedEpoch, 0, type(uint32).max - 1));
        if (lastClearedEpoch >= pendingEpoch) ++lastClearedEpoch;
        record.epoch = pendingEpoch;
        record.amountIn = uint128(bound(record.amountIn, 1, Constants.MAX_FUZZED_AMOUNT));
        queueLib.setPendingEpochs(vault, pendingEpoch, 0);
        queueLib.setDepositRecord(vault, controller, record);
        queueLib.setShareAccount(controller, shareAccount);

        // And: Other requests in the pending epoch, earlier clears in the cleared one.
        otherIn = uint128(bound(otherIn, 0, type(uint128).max - record.amountIn));
        clearedIn = uint128(bound(clearedIn, 0, type(uint128).max - record.amountIn - otherIn));
        queueLib.setLastClearedEpochs(vault, lastClearedEpoch, 0);
        queueLib.setDepositEpoch(vault, pendingEpoch, Epoch({ amountIn: record.amountIn + otherIn, amountOut: 0 }));
        queueLib.setDepositEpoch(vault, lastClearedEpoch, Epoch({ amountIn: clearedIn, amountOut: 0 }));

        // And: An escrow over the record's assets.
        queueLib.setEscrowed(isToken0 ? record.amountIn : 0, isToken0 ? 0 : record.amountIn);

        // When: Clearing the deposit.
        queueLib.clearDeposit(vault, controller, isToken0);

        // Then: The record sits in the cleared epoch, with its assets and pending aLP.
        Record memory recordAfter = queueLib.getDepositRecord(vault, controller);
        assertEq(recordAfter.epoch, lastClearedEpoch);
        assertEq(recordAfter.amountIn, record.amountIn);
        assertEq(recordAfter.pendingShares, record.pendingShares);

        // And: Its assets move from the pending epoch's input to the cleared epoch's.
        assertEq(queueLib.getDepositEpoch(vault, pendingEpoch).amountIn, otherIn);
        assertEq(queueLib.getDepositEpoch(vault, lastClearedEpoch).amountIn, uint256(clearedIn) + record.amountIn);

        // And: The controller's pending and claimable aLP are untouched.
        ShareAccount memory shareAccountAfter = queueLib.getShareAccount(controller);
        assertEq(shareAccountAfter.pendingShares, shareAccount.pendingShares);
        assertEq(shareAccountAfter.claimableShares, shareAccount.claimableShares);
    }

    function testFuzz_Success_clearDeposit_MovesTheEscrowIntoTheBuffer(
        address vault,
        address controller,
        bool isToken0,
        uint32 pendingEpoch,
        uint32 lastClearedEpoch,
        Record memory record,
        uint128 escrowed,
        uint128 buffer
    ) public {
        // Given: A pending deposit within a TokenDelta component, a cleared epoch apart.
        lastClearedEpoch = uint32(bound(lastClearedEpoch, 0, type(uint32).max - 1));
        if (lastClearedEpoch >= pendingEpoch) ++lastClearedEpoch;
        record.epoch = pendingEpoch;
        record.amountIn = uint128(bound(record.amountIn, 1, Constants.MAX_FUZZED_AMOUNT));
        queueLib.setPendingEpochs(vault, pendingEpoch, 0);
        queueLib.setLastClearedEpochs(vault, lastClearedEpoch, 0);
        queueLib.setDepositRecord(vault, controller, record);
        queueLib.setDepositEpoch(vault, pendingEpoch, Epoch({ amountIn: record.amountIn, amountOut: 0 }));

        // And: An escrow covering the record's assets and room in the buffer.
        escrowed = uint128(bound(escrowed, record.amountIn, type(uint128).max));
        buffer = uint128(bound(buffer, 0, type(uint128).max - record.amountIn));
        queueLib.setEscrowed(isToken0 ? escrowed : 0, isToken0 ? 0 : escrowed);
        queueLib.setBuffers(isToken0 ? buffer : 0, isToken0 ? 0 : buffer);

        // When: Clearing the deposit.
        TokenDelta delta = queueLib.clearDeposit(vault, controller, isToken0);

        // Then: The assets move from the escrow to the buffer.
        PoolTokens memory poolTokens = queueLib.getPoolTokens();
        assertEq(isToken0 ? poolTokens.escrowed.amount0 : poolTokens.escrowed.amount1, escrowed - record.amountIn);
        assertEq(isToken0 ? poolTokens.buffer.amount0 : poolTokens.buffer.amount1, uint256(buffer) + record.amountIn);

        // And: The returned delta is that move into the buffer.
        assertEq(int256(isToken0 ? delta.amount0() : delta.amount1()), int256(uint256(record.amountIn)));
        assertEq(int256(isToken0 ? delta.amount1() : delta.amount0()), 0);
    }
}
