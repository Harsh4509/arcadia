/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { PoolTokens } from "../../../../src/core/types/State.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";
import { stdError } from "@forge-std/StdError.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "clearAllDeposits" of library "QueueLib".
 */
contract ClearAllDeposits_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_clearAllDeposits_EscrowBelowTheAssets(
        address vault,
        bool isToken0,
        uint128 escrowed,
        uint256 assets
    ) public {
        // Given: An escrow of the vault's token below the epoch's assets.
        escrowed = uint128(bound(escrowed, 0, Constants.MAX_FUZZED_AMOUNT - 1));
        queueLib.setEscrowed(isToken0 ? escrowed : 0, isToken0 ? 0 : escrowed);
        assets = bound(assets, uint256(escrowed) + 1, Constants.MAX_FUZZED_AMOUNT);

        // When: Clearing all deposits.
        // Then: It reverts on the underflow.
        vm.expectRevert(stdError.arithmeticError);
        queueLib.clearAllDeposits(vault, isToken0, assets);
    }

    function testFuzz_Revert_clearAllDeposits_IdsExhausted(
        address vault,
        bool isToken0,
        bool pendingAtMax,
        uint32 epoch
    ) public {
        // Given: A deposit queue whose pending or last cleared epoch has the top id.
        queueLib.setPendingEpochs(vault, pendingAtMax ? type(uint32).max : epoch, 0);
        queueLib.setLastClearedEpochs(vault, pendingAtMax ? epoch : type(uint32).max, 0);

        // When: Clearing all deposits.
        // Then: It reverts on the overflow.
        vm.expectRevert(stdError.arithmeticError);
        queueLib.clearAllDeposits(vault, isToken0, 0);
    }

    function testFuzz_Success_clearAllDeposits_MovesTheEscrowIntoTheBuffer(
        address vault,
        bool isToken0,
        uint128 escrowed,
        uint128 buffer,
        uint256 assets
    ) public {
        // Given: An escrow covering the epoch's assets and room in the buffer.
        assets = bound(assets, 0, Constants.MAX_FUZZED_AMOUNT);
        escrowed = uint128(bound(escrowed, assets, type(uint128).max));
        buffer = uint128(bound(buffer, 0, type(uint128).max - assets));
        queueLib.setEscrowed(isToken0 ? escrowed : 0, isToken0 ? 0 : escrowed);
        queueLib.setBuffers(isToken0 ? buffer : 0, isToken0 ? 0 : buffer);

        // When: Clearing all deposits.
        TokenDelta delta = queueLib.clearAllDeposits(vault, isToken0, assets);

        // Then: The assets move from the escrow to the buffer.
        PoolTokens memory poolTokens = queueLib.getPoolTokens();
        assertEq(isToken0 ? poolTokens.escrowed.amount0 : poolTokens.escrowed.amount1, escrowed - assets);
        assertEq(isToken0 ? poolTokens.buffer.amount0 : poolTokens.buffer.amount1, buffer + assets);

        // And: The returned delta is that move into the buffer.
        assertEq(int256(isToken0 ? delta.amount0() : delta.amount1()), int256(assets));
        assertEq(int256(isToken0 ? delta.amount1() : delta.amount0()), 0);
    }

    function testFuzz_Success_clearAllDeposits_ClearsThePendingEpochAndOpensAFreshOne(
        address vault,
        bool isToken0,
        uint32 pendingEpoch,
        uint32 lastClearedEpoch
    ) public {
        // Given: A pending and a last cleared deposit epoch below the highest id.
        pendingEpoch = uint32(bound(pendingEpoch, 0, type(uint32).max - 1));
        lastClearedEpoch = uint32(bound(lastClearedEpoch, 0, type(uint32).max - 1));
        queueLib.setPendingEpochs(vault, pendingEpoch, 0);
        queueLib.setLastClearedEpochs(vault, lastClearedEpoch, 0);

        // When: Clearing all deposits.
        queueLib.clearAllDeposits(vault, isToken0, 0);

        // Then: The pending epoch is the cleared one.
        assertEq(queueLib.getLastClearedDepositEpoch(vault), pendingEpoch);

        // And: A fresh id becomes the pending epoch, one above the highest issued.
        assertEq(queueLib.getPendingDepositEpoch(vault), FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);

        // And: The cleared epoch holds no output yet.
        assertEq(queueLib.getDepositEpoch(vault, pendingEpoch).amountOut, 0);
    }
}
