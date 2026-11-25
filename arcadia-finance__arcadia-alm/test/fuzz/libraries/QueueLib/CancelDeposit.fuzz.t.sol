/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { Epoch, PoolTokens, Record, ShareAccount } from "../../../../src/core/types/State.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";
import { stdError } from "@forge-std/StdError.sol";

/**
 * @notice Fuzz tests for the function "cancelDeposit" of library "QueueLib".
 */
contract CancelDeposit_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_cancelDeposit_EscrowBelowTheAssets(
        address vault,
        address controller,
        uint32 pendingEpoch,
        Record memory record,
        ShareAccount memory shareAccount,
        uint128 escrowed,
        bool isToken0
    ) public {
        // Given: A pending deposit record within a TokenDelta component.
        record.epoch = pendingEpoch;
        record.amountIn = uint128(bound(record.amountIn, 1, Constants.MAX_FUZZED_AMOUNT));
        shareAccount.pendingShares = uint128(bound(shareAccount.pendingShares, record.pendingShares, type(uint128).max));
        queueLib.setPendingEpochs(vault, pendingEpoch, 0);
        queueLib.setDepositRecord(vault, controller, record);
        queueLib.setDepositEpoch(vault, pendingEpoch, Epoch({ amountIn: record.amountIn, amountOut: 0 }));
        queueLib.setShareAccount(controller, shareAccount);

        // And: An escrow below the record's assets.
        escrowed = uint128(bound(escrowed, 0, record.amountIn - 1));
        queueLib.setEscrowed(isToken0 ? escrowed : 0, isToken0 ? 0 : escrowed);

        // When: Cancelling the deposit.
        // Then: It reverts on the underflow.
        vm.expectRevert(stdError.arithmeticError);
        queueLib.cancelDeposit(vault, controller, isToken0);
    }

    function testFuzz_Success_cancelDeposit_TakesTheRequestBack(
        address vault,
        address controller,
        uint32 pendingEpoch,
        Record memory record,
        ShareAccount memory shareAccount,
        uint128 escrowed,
        bool isToken0
    ) public {
        // Given: A pending deposit record within a TokenDelta component.
        record.epoch = pendingEpoch;
        record.amountIn = uint128(bound(record.amountIn, 1, Constants.MAX_FUZZED_AMOUNT));
        shareAccount.pendingShares = uint128(bound(shareAccount.pendingShares, record.pendingShares, type(uint128).max));
        queueLib.setPendingEpochs(vault, pendingEpoch, 0);
        queueLib.setDepositRecord(vault, controller, record);
        queueLib.setDepositEpoch(vault, pendingEpoch, Epoch({ amountIn: record.amountIn, amountOut: 0 }));
        queueLib.setShareAccount(controller, shareAccount);

        // And: An escrow over the record's assets.
        escrowed = uint128(bound(escrowed, record.amountIn, type(uint128).max));
        queueLib.setEscrowed(isToken0 ? escrowed : 0, isToken0 ? 0 : escrowed);

        // When: Cancelling the deposit.
        queueLib.cancelDeposit(vault, controller, isToken0);

        // Then: The record is empty, and the pending epoch falls by its assets.
        Record memory recordAfter = queueLib.getDepositRecord(vault, controller);
        assertEq(recordAfter.amountIn, 0);
        assertEq(recordAfter.pendingShares, 0);
        assertEq(queueLib.getDepositEpoch(vault, pendingEpoch).amountIn, 0);

        // And: The record's pending aLP leaves the controller's pending shares.
        assertEq(queueLib.getShareAccount(controller).pendingShares, shareAccount.pendingShares - record.pendingShares);

        // And: The escrow of the vault's token falls by the assets.
        PoolTokens memory poolTokens = queueLib.getPoolTokens();
        assertEq(isToken0 ? poolTokens.escrowed.amount0 : poolTokens.escrowed.amount1, escrowed - record.amountIn);
        assertEq(isToken0 ? poolTokens.escrowed.amount1 : poolTokens.escrowed.amount0, 0);
    }
}
