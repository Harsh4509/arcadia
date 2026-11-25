/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { Vaults } from "../core/types/Vaults.sol";

interface IALMFactory {
    function allCores(uint256 index) external view returns (address core);
    function allCoresLength() external view returns (uint256 length);
    function getCore(address pool) external view returns (address core);
    function getVaults(address core) external view returns (Vaults memory vaults);
    function isCore(address core) external view returns (bool valid);
    function isKeeper(address core, address keeper) external view returns (bool approved);
    function poolOf(address core) external view returns (address pool);
}
