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
 * @notice Fuzz tests for the function "decodeOpen" of library "CalldataLogic".
 */
// forge-lint: disable-next-item(unused-return)
contract DecodeOpen_CalldataLogic_Fuzz_Test is CalldataLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_decodeOpen_InvalidPayload(bytes calldata data, uint256 length) public {
        // Given: A payload that is not the length the command fixes.
        bytes memory payload = givenInvalidLength(data, CalldataLogic.OPEN_RANGE_LENGTH, length);

        // When: Decoding it.
        // Then: It reverts.
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        calldataLogic.decodeOpen(payload);
    }

    function testFuzz_Success_decodeOpen_RoundTripsEveryField(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) public view {
        // Given: A payload packed the way the keeper packs it.
        bytes memory payload =
            abi.encodePacked(tickLower, tickUpper, amount0Desired, amount1Desired, amount0Min, amount1Min);

        // When: Decoding it.
        IMetadexCLPositionManager.MintParams memory params = calldataLogic.decodeOpen(payload);

        // Then: Every field comes back as it went in.
        assertEq(params.tickLower, tickLower);
        assertEq(params.tickUpper, tickUpper);
        assertEq(params.amount0Desired, amount0Desired);
        assertEq(params.amount1Desired, amount1Desired);
        assertEq(params.amount0Min, amount0Min);
        assertEq(params.amount1Min, amount1Min);
    }

    function testFuzz_Success_decodeOpen_IgnoresTheBytesAfterThePayload(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) public view {
        // Given: A payload packed as the keeper packs it, followed by all-ones bytes.
        bytes memory payload =
            abi.encodePacked(tickLower, tickUpper, amount0Desired, amount1Desired, amount0Min, amount1Min);

        // When: Decoding it.
        (bool success, bytes memory result) =
            decodeDirty(abi.encodeCall(CalldataLogicExtension.decodeOpen, (payload)), payload.length);

        // Then: Every field comes back as it went in.
        assertTrue(success);
        IMetadexCLPositionManager.MintParams memory params = IMetadexCLPositionManager.MintParams({
            token0: address(0),
            token1: address(0),
            tickSpacing: 0,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: address(0),
            deadline: 0,
            sqrtPriceX96: 0
        });
        assertEq(keccak256(result), keccak256(abi.encode(params)));
    }
}
