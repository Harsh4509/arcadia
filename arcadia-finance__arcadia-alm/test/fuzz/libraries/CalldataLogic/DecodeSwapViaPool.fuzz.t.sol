/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CalldataLogic } from "../../../../src/core/libraries/logic/CalldataLogic.sol";
import { CalldataLogic_Fuzz_Test } from "./_CalldataLogic.fuzz.t.sol";
import { CalldataLogicExtension } from "../../../utils/extensions/CalldataLogicExtension.sol";

/**
 * @notice Fuzz tests for the function "decodeSwapViaPool" of library "CalldataLogic".
 */
// forge-lint: disable-next-item(unused-return)
contract DecodeSwapViaPool_CalldataLogic_Fuzz_Test is CalldataLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_decodeSwapViaPool_InvalidPayload(bytes calldata data, uint256 length) public {
        // Given: A payload that is not the length the command fixes.
        bytes memory payload = givenInvalidLength(data, CalldataLogic.SWAP_VIA_POOL_LENGTH, length);

        // When: Decoding it.
        // Then: It reverts.
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        calldataLogic.decodeSwapViaPool(payload);
    }

    function testFuzz_Success_decodeSwapViaPool_RoundTripsEveryField(
        bool zeroForOne,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96,
        uint256 minAmountOut
    ) public view {
        // Given: A payload packed the way the keeper packs it.
        bytes memory payload = abi.encodePacked(zeroForOne, amountIn, sqrtPriceLimitX96, minAmountOut);

        // When: Decoding it.
        (
            bool decodedZeroForOne,
            uint256 decodedAmountIn,
            uint160 decodedSqrtPriceLimitX96,
            uint256 decodedAmountOutMin
        ) = calldataLogic.decodeSwapViaPool(payload);

        // Then: Every field comes back as it went in.
        assertEq(decodedZeroForOne, zeroForOne);
        assertEq(decodedAmountIn, amountIn);
        assertEq(decodedSqrtPriceLimitX96, sqrtPriceLimitX96);
        assertEq(decodedAmountOutMin, minAmountOut);
    }

    function testFuzz_Success_decodeSwapViaPool_IgnoresTheBytesAfterThePayload(
        bool zeroForOne,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96,
        uint256 minAmountOut
    ) public view {
        // Given: A payload packed as the keeper packs it, followed by all-ones bytes.
        bytes memory payload = abi.encodePacked(zeroForOne, amountIn, sqrtPriceLimitX96, minAmountOut);

        // When: Decoding it.
        (bool success, bytes memory result) =
            decodeDirty(abi.encodeCall(CalldataLogicExtension.decodeSwapViaPool, (payload)), payload.length);

        // Then: Every field comes back as it went in.
        assertTrue(success);
        assertEq(keccak256(result), keccak256(abi.encode(zeroForOne, amountIn, sqrtPriceLimitX96, minAmountOut)));
    }
}
