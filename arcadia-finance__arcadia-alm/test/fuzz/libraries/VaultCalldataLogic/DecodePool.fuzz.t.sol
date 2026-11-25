/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { VaultCalldataLogic_Fuzz_Test } from "./_VaultCalldataLogic.fuzz.t.sol";
import { VaultCalldataLogicExtension } from "../../../utils/extensions/VaultCalldataLogicExtension.sol";

/**
 * @notice Fuzz tests for the function "decodePool" of library "CalldataLogic" of the vaults.
 */
contract DecodePool_VaultCalldataLogic_Fuzz_Test is VaultCalldataLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_decodePool_ReadsTheAppendedParameter(
        bytes calldata arguments,
        bool assetIsToken0,
        address core,
        address pool
    ) public view {
        // Given: Any arguments, with the vault's parameters appended.
        // When: Decoding the pool.
        (bool success, bytes memory result) =
            callWithParameters(VaultCalldataLogicExtension.decodePool.selector, arguments, assetIsToken0, core, pool);

        // Then: It is the appended pool.
        assertTrue(success);
        assertEq(abi.decode(result, (address)), pool);
    }
}
