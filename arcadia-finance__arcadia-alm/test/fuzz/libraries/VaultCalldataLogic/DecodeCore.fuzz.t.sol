/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { VaultCalldataLogic_Fuzz_Test } from "./_VaultCalldataLogic.fuzz.t.sol";
import { VaultCalldataLogicExtension } from "../../../utils/extensions/VaultCalldataLogicExtension.sol";

/**
 * @notice Fuzz tests for the function "decodeCore" of library "CalldataLogic" of the vaults.
 */
contract DecodeCore_VaultCalldataLogic_Fuzz_Test is VaultCalldataLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_decodeCore_ReadsTheAppendedParameter(
        bytes calldata arguments,
        bool assetIsToken0,
        address core,
        address pool
    ) public view {
        // Given: Any arguments, with the vault's parameters appended.
        // When: Decoding the core.
        (bool success, bytes memory result) =
            callWithParameters(VaultCalldataLogicExtension.decodeCore.selector, arguments, assetIsToken0, core, pool);

        // Then: It is the appended core.
        assertTrue(success);
        assertEq(abi.decode(result, (address)), core);
    }
}
