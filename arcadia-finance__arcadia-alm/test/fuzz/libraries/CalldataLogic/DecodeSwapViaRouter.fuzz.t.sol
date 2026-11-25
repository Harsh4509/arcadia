/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CalldataLogic } from "../../../../src/core/libraries/logic/CalldataLogic.sol";
import { CalldataLogic_Fuzz_Test } from "./_CalldataLogic.fuzz.t.sol";
import { CalldataLogicExtension } from "../../../utils/extensions/CalldataLogicExtension.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

/**
 * @notice Fuzz tests for the function "decodeSwapViaRouter" of library "CalldataLogic".
 */
// forge-lint: disable-next-item(unused-return)
contract DecodeSwapViaRouter_CalldataLogic_Fuzz_Test is CalldataLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_decodeSwapViaRouter_InvalidPayload(bytes calldata payload, uint256 length) public {
        // Given: A payload with no room for the router calldata after the fixed fields.
        payload =
            payload[:bound(length, 0, FixedPointMathLib.min(payload.length, CalldataLogic.SWAP_VIA_ROUTER_LENGTH))];

        // When: Decoding it.
        // Then: It reverts.
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        calldataLogic.decodeSwapViaRouter(payload);
    }

    function testFuzz_Revert_decodeSwapViaRouter_InvalidPayload_FixedFieldsOnly(
        address router,
        uint256 amountIn,
        bool zeroForOne,
        uint256 minAmountOut
    ) public {
        // Given: A payload holding the fixed fields and no router calldata.
        bytes memory payload = abi.encodePacked(router, amountIn, zeroForOne, minAmountOut);

        // When: Decoding it.
        // Then: It reverts.
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        calldataLogic.decodeSwapViaRouter(payload);
    }

    function testFuzz_Success_decodeSwapViaRouter_RoundTripsEveryField(
        address router,
        uint256 amountIn,
        bool zeroForOne,
        uint256 minAmountOut,
        bytes1 head,
        bytes calldata tail
    ) public view {
        // Given: A payload carrying at least one byte of router calldata.
        bytes memory data = bytes.concat(head, tail);
        bytes memory payload = abi.encodePacked(router, amountIn, zeroForOne, minAmountOut, data);

        // When: Decoding it.
        (
            address decodedRouter,
            uint256 decodedAmountIn,
            bool decodedZeroForOne,
            uint256 decodedAmountOutMin,
            bytes memory decodedData
        ) = calldataLogic.decodeSwapViaRouter(payload);

        // Then: Every field comes back as it went in, the calldata being the whole tail.
        assertEq(decodedRouter, router);
        assertEq(decodedAmountIn, amountIn);
        assertEq(decodedZeroForOne, zeroForOne);
        assertEq(decodedAmountOutMin, minAmountOut);
        assertEq(keccak256(decodedData), keccak256(data));
    }

    function testFuzz_Success_decodeSwapViaRouter_IgnoresTheBytesAfterThePayload(
        address router,
        uint256 amountIn,
        bool zeroForOne,
        uint256 minAmountOut,
        bytes1 head,
        bytes calldata tail
    ) public view {
        // Given: A payload packed as the keeper packs it, followed by all-ones bytes.
        bytes memory data = bytes.concat(head, tail);
        bytes memory payload = abi.encodePacked(router, amountIn, zeroForOne, minAmountOut, data);

        // When: Decoding it.
        (bool success, bytes memory result) =
            decodeDirty(abi.encodeCall(CalldataLogicExtension.decodeSwapViaRouter, (payload)), payload.length);

        // Then: Every field comes back as it went in.
        assertTrue(success);
        assertEq(keccak256(result), keccak256(abi.encode(router, amountIn, zeroForOne, minAmountOut, data)));
    }
}
