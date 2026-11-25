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
 * @notice Fuzz tests for the function "decodePosition" of library "CalldataLogic".
 */
// forge-lint: disable-next-item(unused-return)
contract DecodePosition_CalldataLogic_Fuzz_Test is CalldataLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_decodePosition_InvalidPayload(bytes calldata data, uint256 length) public {
        // Given: A payload that is not the length the command fixes.
        bytes memory payload = givenInvalidLength(data, CalldataLogic.COLLECT_LENGTH, length);

        // When: Decoding it.
        // Then: It reverts.
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        calldataLogic.decodePosition(payload);
    }

    function testFuzz_Success_decodePosition_RoundTripsEveryField(uint96 tokenId) public view {
        // Given: A payload packed the way the keeper packs it.
        bytes memory payload = abi.encodePacked(tokenId);

        // When: Decoding it.
        IMetadexCLPositionManager.CollectParams memory params = calldataLogic.decodePosition(payload);

        // Then: Every field comes back as it went in.
        assertEq(params.tokenId, tokenId);
    }

    function testFuzz_Success_decodePosition_IgnoresTheBytesAfterThePayload(uint96 tokenId) public view {
        // Given: A payload packed as the keeper packs it, followed by all-ones bytes.
        bytes memory payload = abi.encodePacked(tokenId);

        // When: Decoding it.
        (bool success, bytes memory result) =
            decodeDirty(abi.encodeCall(CalldataLogicExtension.decodePosition, (payload)), payload.length);

        // Then: The token id comes back as it went in.
        assertTrue(success);
        IMetadexCLPositionManager.CollectParams memory params = IMetadexCLPositionManager.CollectParams({
            tokenId: tokenId, recipient: address(0), amount0Max: 0, amount1Max: 0
        });
        assertEq(keccak256(result), keccak256(abi.encode(params)));
    }
}
