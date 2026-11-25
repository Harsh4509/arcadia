/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { CoreParameters } from "../core/types/CoreParameters.sol";
import { VaultParameters } from "../vaults/types/VaultParameters.sol";

interface IBaseFactory {
    function parameters() external view returns (CoreParameters memory params);
    function vaultParameters() external view returns (VaultParameters memory params);
}
