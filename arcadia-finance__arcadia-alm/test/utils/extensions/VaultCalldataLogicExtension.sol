/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CalldataLogic } from "../../../src/vaults/libraries/logic/CalldataLogic.sol";

contract VaultCalldataLogicExtension {
    function decodeAssetIsToken0() external pure returns (bool assetIsToken0) {
        assetIsToken0 = CalldataLogic.decodeAssetIsToken0();
    }

    function decodeCore() external pure returns (address core) {
        core = CalldataLogic.decodeCore();
    }

    function decodePool() external pure returns (address pool) {
        pool = CalldataLogic.decodePool();
    }
}
