/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CalldataLogic } from "../../../../src/core/libraries/logic/CalldataLogic.sol";
import { CalldataLogic_Fuzz_Test } from "./_CalldataLogic.fuzz.t.sol";
import { CalldataLogicExtension } from "../../../utils/extensions/CalldataLogicExtension.sol";

/**
 * @notice Fuzz tests for the function "decodeRange" of library "CalldataLogic".
 */
// forge-lint: disable-next-item(unused-return)
contract DecodeRange_CalldataLogic_Fuzz_Test is CalldataLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_decodeRange_InvalidPayload(bytes calldata data, uint256 length) public {
        // Given: A payload that is not the length the command fixes.
        bytes memory payload = givenInvalidLength(data, CalldataLogic.CLOSE_RANGE_LENGTH, length);

        // When: Decoding it.
        // Then: It reverts.
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        calldataLogic.decodeRange(payload);
    }

    function testFuzz_Success_decodeRange_RoundTripsEveryField(uint8 index, uint96 tokenId) public view {
        // Given: A payload packed the way the keeper packs it.
        bytes memory payload = abi.encodePacked(index, tokenId);

        // When: Decoding it.
        (uint256 decodedIndex, uint256 decodedTokenId) = calldataLogic.decodeRange(payload);

        // Then: Every field comes back as it went in.
        assertEq(decodedIndex, index);
        assertEq(decodedTokenId, tokenId);
    }

    function testFuzz_Success_decodeRange_IgnoresTheBytesAfterThePayload(uint8 index, uint96 tokenId) public view {
        // Given: A payload packed as the keeper packs it, followed by all-ones bytes.
        bytes memory payload = abi.encodePacked(index, tokenId);

        // When: Decoding it.
        (bool success, bytes memory result) =
            decodeDirty(abi.encodeCall(CalldataLogicExtension.decodeRange, (payload)), payload.length);

        // Then: Every field comes back as it went in.
        assertTrue(success);
        (uint256 decodedIndex, uint256 decodedTokenId) = abi.decode(result, (uint256, uint256));
        assertEq(decodedIndex, index);
        assertEq(decodedTokenId, tokenId);
    }
}
