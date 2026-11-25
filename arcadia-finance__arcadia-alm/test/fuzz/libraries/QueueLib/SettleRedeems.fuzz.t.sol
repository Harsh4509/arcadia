/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { PoolTokensLib } from "../../../../src/core/libraries/state/PoolTokensLib.sol";
import { PoolTokens } from "../../../../src/core/types/State.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "settleRedeems" of library "QueueLib".
 */
contract SettleRedeems_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_settleRedeems_InsufficientBuffer(
        address vault,
        bool isToken0,
        uint32 lastClearedEpoch,
        uint128 buffer,
        uint256 assets
    ) public {
        // Given: A cleared redeem epoch and a buffer below its assets.
        queueLib.setLastClearedEpochs(vault, 0, lastClearedEpoch);
        buffer = uint128(bound(buffer, 0, type(uint128).max - 1));
        queueLib.setBuffers(isToken0 ? buffer : 0, isToken0 ? 0 : buffer);
        assets = bound(assets, uint256(buffer) + 1, type(uint256).max);

        // When: Settling the epoch.
        // Then: It reverts.
        vm.expectRevert(PoolTokensLib.InsufficientBuffer.selector);
        queueLib.settleRedeems(vault, isToken0, assets);
    }

    function testFuzz_Success_settleRedeems_SettlesTheClearedEpoch(
        address vault,
        bool isToken0,
        uint32 pendingEpoch,
        uint32 lastClearedEpoch,
        uint128 escrowed,
        uint128 buffer,
        uint256 assets
    ) public {
        // Given: A cleared redeem epoch apart from the pending one, a covering buffer.
        assets = bound(assets, 0, Constants.MAX_FUZZED_AMOUNT);
        buffer = uint128(bound(buffer, assets, type(uint128).max));
        escrowed = uint128(bound(escrowed, 0, type(uint128).max - assets));
        lastClearedEpoch = uint32(bound(lastClearedEpoch, 0, type(uint32).max - 1));
        if (lastClearedEpoch >= pendingEpoch) ++lastClearedEpoch;
        queueLib.setPendingEpochs(vault, 0, pendingEpoch);
        queueLib.setLastClearedEpochs(vault, 0, lastClearedEpoch);
        queueLib.setEscrowed(isToken0 ? escrowed : 0, isToken0 ? 0 : escrowed);
        queueLib.setBuffers(isToken0 ? buffer : 0, isToken0 ? 0 : buffer);

        // When: Settling the epoch.
        TokenDelta delta = queueLib.settleRedeems(vault, isToken0, assets);

        // Then: The assets move from the buffer to the escrow.
        PoolTokens memory poolTokens = queueLib.getPoolTokens();
        assertEq(isToken0 ? poolTokens.buffer.amount0 : poolTokens.buffer.amount1, buffer - assets);
        assertEq(isToken0 ? poolTokens.escrowed.amount0 : poolTokens.escrowed.amount1, escrowed + assets);

        // And: The returned delta is that move out of the buffer.
        assertEq(int256(isToken0 ? delta.amount0() : delta.amount1()), -int256(assets));
        assertEq(int256(isToken0 ? delta.amount1() : delta.amount0()), 0);

        // And: The cleared epoch stores the assets.
        assertEq(queueLib.getRedeemEpoch(vault, lastClearedEpoch).amountOut, assets);

        // And: The pending epoch stays the same and holds no output.
        assertEq(queueLib.getPendingRedeemEpoch(vault), pendingEpoch);
        assertEq(queueLib.getRedeemEpoch(vault, pendingEpoch).amountOut, 0);
    }
}
