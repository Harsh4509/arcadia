/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

/**
 * @notice The immutables of a vault.
 */
struct VaultParameters {
    bool assetIsToken0;
    address core;
    address pool;
    address syncExtension;
}
