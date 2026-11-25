/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CalldataLogic } from "../../../../src/core/libraries/logic/CalldataLogic.sol";
import { CalldataLogic_Fuzz_Test } from "./_CalldataLogic.fuzz.t.sol";
import { CalldataLogicExtension } from "../../../utils/extensions/CalldataLogicExtension.sol";
import { IMetadexCLPositionManager } from "../../../../src/interfaces/IMetadexCLPositionManager.sol";

/**
 * @notice Fuzz tests for the function "decodeIncrease" of library "CalldataLogic".
 */
// forge-lint: disable-next-item(unused-return)
contract DecodeIncrease_CalldataLogic_Fuzz_Test is CalldataLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_decodeIncrease_InvalidPayload(bytes calldata data, uint256 length, bool staked) public {
        // Given: A payload that is not the length the side fixes.
        bytes memory payload = givenInvalidLength(
            data,
            staked ? CalldataLogic.INCREASE_STAKED_LIQUIDITY_LENGTH : CalldataLogic.INCREASE_LIQUIDITY_LENGTH,
            length
        );

        // When: Decoding it.
        // Then: It reverts.
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        calldataLogic.decodeIncrease(payload, staked);
    }

    function testFuzz_Success_decodeIncrease_RoundTripsEveryField(
        uint8 index,
        IMetadexCLPositionManager.IncreaseLiquidityParams memory packed,
        bool acceptPenalty,
        bool staked
    ) public view {
        // Given: A payload packed as the keeper packs it, acceptPenalty only when staked.
        packed.tokenId = bound(packed.tokenId, 0, type(uint96).max);
        acceptPenalty = staked && acceptPenalty;
        bytes memory payload = abi.encodePacked(
            index,
            uint96(packed.tokenId),
            packed.amount0Desired,
            packed.amount1Desired,
            packed.amount0Min,
            packed.amount1Min
        );
        if (staked) payload = bytes.concat(payload, abi.encodePacked(acceptPenalty));

        // When: Decoding it.
        (uint256 index_, IMetadexCLPositionManager.IncreaseLiquidityParams memory params, bool acceptPenalty_) =
            calldataLogic.decodeIncrease(payload, staked);

        // Then: Every field comes back as it went in.
        assertEq(index_, index);
        assertEq(params.tokenId, packed.tokenId);
        assertEq(params.amount0Desired, packed.amount0Desired);
        assertEq(params.amount1Desired, packed.amount1Desired);
        assertEq(params.amount0Min, packed.amount0Min);
        assertEq(params.amount1Min, packed.amount1Min);
        assertEq(acceptPenalty_, acceptPenalty);
    }

    function testFuzz_Success_decodeIncrease_IgnoresTheBytesAfterThePayload(
        uint8 index,
        IMetadexCLPositionManager.IncreaseLiquidityParams memory packed,
        bool acceptPenalty,
        bool staked
    ) public view {
        // Given: A payload packed as the keeper packs it, followed by all-ones bytes.
        packed.tokenId = bound(packed.tokenId, 0, type(uint96).max);
        acceptPenalty = staked && acceptPenalty;
        bytes memory payload = abi.encodePacked(
            index,
            uint96(packed.tokenId),
            packed.amount0Desired,
            packed.amount1Desired,
            packed.amount0Min,
            packed.amount1Min
        );
        if (staked) payload = bytes.concat(payload, abi.encodePacked(acceptPenalty));

        // When: Decoding it.
        (bool success, bytes memory result) =
            decodeDirty(abi.encodeCall(CalldataLogicExtension.decodeIncrease, (payload, staked)), payload.length);

        // Then: Every field comes back as it went in.
        assertTrue(success);
        IMetadexCLPositionManager.IncreaseLiquidityParams memory params =
            IMetadexCLPositionManager.IncreaseLiquidityParams({
                tokenId: packed.tokenId,
                amount0Desired: packed.amount0Desired,
                amount1Desired: packed.amount1Desired,
                amount0Min: packed.amount0Min,
                amount1Min: packed.amount1Min,
                deadline: 0
            });
        assertEq(keccak256(result), keccak256(abi.encode(index, params, acceptPenalty)));
    }
}
