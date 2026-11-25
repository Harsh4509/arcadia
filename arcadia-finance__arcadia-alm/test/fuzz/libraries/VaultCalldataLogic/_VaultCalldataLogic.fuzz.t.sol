/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Fuzz_Test } from "../../Fuzz.t.sol";
import { VaultCalldataLogicExtension } from "../../../utils/extensions/VaultCalldataLogicExtension.sol";

/**
 * @notice Common logic needed by all "CalldataLogic" fuzz tests of the vaults.
 */
abstract contract VaultCalldataLogic_Fuzz_Test is Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    VaultCalldataLogicExtension internal calldataLogic;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();
        calldataLogic = new VaultCalldataLogicExtension();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function callWithParameters(
        bytes4 selector,
        bytes calldata arguments,
        bool assetIsToken0,
        address core,
        address pool
    ) internal view returns (bool success, bytes memory result) {
        // And: The arguments, then the vault's parameters and their length.
        bytes memory parameters = abi.encode(assetIsToken0, core, pool);
        (success, result) =
            address(calldataLogic).staticcall(abi.encodePacked(selector, arguments, parameters, parameters.length));
    }
}
