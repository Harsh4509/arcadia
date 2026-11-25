/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CalldataLogic_Fuzz_Test } from "./_CalldataLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "readKey" of library "CalldataLogic".
 */
contract ReadKey_CalldataLogic_Fuzz_Test is CalldataLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_readKey_ReadsTheIndexAndTheTokenId(uint8 index, uint96 tokenId, bytes memory tail)
        public
        view
    {
        // Given: A payload that starts with an index byte and a 12-byte token id.
        bytes memory payload = abi.encodePacked(index, tokenId, tail);

        // When: Reading its range key.
        (uint256 readIndex, uint256 readTokenId) = calldataLogic.readKey(payload);

        // Then: Both come back as they went in, whatever follows them.
        assertEq(readIndex, index);
        assertEq(readTokenId, tokenId);
    }
}
