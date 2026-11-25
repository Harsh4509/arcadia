/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Symbolic_Test } from "../Symbolic.t.sol";
import { VaultCalldataLogicExtension } from "../../utils/extensions/VaultCalldataLogicExtension.sol";

/**
 * @notice Symbolic tests for the parameter decoders of library "CalldataLogic" of the vaults.
 */
contract Decoders_VaultCalldataLogic_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    VaultCalldataLogicExtension internal calldataLogic;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public {
        calldataLogic = new VaultCalldataLogicExtension();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function prove_decodeAssetIsToken0_ReadsTheAppendedParameter(
        bytes32 arguments,
        bool assetIsToken0,
        address core,
        address pool
    ) public view {
        // Given: Any arguments, with the parameters appended as the vault forwards.
        bytes memory callData = abi.encodePacked(
            VaultCalldataLogicExtension.decodeAssetIsToken0.selector,
            arguments,
            abi.encode(assetIsToken0, core, pool),
            uint256(0x60)
        );

        // When: Decoding whether the asset is token0.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: It is the appended flag.
        assertTrue(success);
        assertEq(abi.decode(result, (bool)), assetIsToken0);
    }

    function prove_decodeCore_ReadsTheAppendedParameter(
        bytes32 arguments,
        bool assetIsToken0,
        address core,
        address pool
    ) public view {
        // Given: Any arguments, with the parameters appended as the vault forwards.
        bytes memory callData = abi.encodePacked(
            VaultCalldataLogicExtension.decodeCore.selector,
            arguments,
            abi.encode(assetIsToken0, core, pool),
            uint256(0x60)
        );

        // When: Decoding the core.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: It is the appended core.
        assertTrue(success);
        assertEq(abi.decode(result, (address)), core);
    }

    function prove_decodePool_ReadsTheAppendedParameter(
        bytes32 arguments,
        bool assetIsToken0,
        address core,
        address pool
    ) public view {
        // Given: Any arguments, with the parameters appended as the vault forwards.
        bytes memory callData = abi.encodePacked(
            VaultCalldataLogicExtension.decodePool.selector,
            arguments,
            abi.encode(assetIsToken0, core, pool),
            uint256(0x60)
        );

        // When: Decoding the pool.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: It is the appended pool.
        assertTrue(success);
        assertEq(abi.decode(result, (address)), pool);
    }
}
