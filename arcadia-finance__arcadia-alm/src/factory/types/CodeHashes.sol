/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

/**
 * @notice The creation code hash of each pool contract.
 */
struct CodeHashes {
    bytes32 core;
    bytes32 keeperExtension;
    bytes32 adminExtension;
    bytes32 syncVault;
    bytes32 asyncVault;
    bytes32 syncExtension;
}
