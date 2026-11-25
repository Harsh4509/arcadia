/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CalldataLogic_Fuzz_Test } from "./_CalldataLogic.fuzz.t.sol";
import { CalldataLogicExtension } from "../../../utils/extensions/CalldataLogicExtension.sol";
import { CoreImmutables } from "../../../../src/core/types/CoreImmutables.sol";

/**
 * @notice Fuzz tests for the function "decodeCoreImmutables" of library "CalldataLogic".
 */
contract DecodeCoreImmutables_CalldataLogic_Fuzz_Test is CalldataLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_decodeCoreImmutables_ReadsTheAppendedMetadata(
        bytes calldata arguments,
        CoreImmutables memory immutables
    ) public view {
        // Given: Arguments, then the immutables and their length as ERC-3448 metadata.
        bytes memory metadata = abi.encode(immutables);
        bytes memory callData = abi.encodePacked(
            CalldataLogicExtension.decodeCoreImmutables.selector, arguments, metadata, metadata.length
        );

        // When: Decoding the immutables.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: Every field comes back as it went in.
        assertTrue(success);
        assertEq(keccak256(result), keccak256(metadata));
    }
}
