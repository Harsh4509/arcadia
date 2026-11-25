/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

/**
 * @notice A pool creation in progress: its deployed-contract bits and fee recipient.
 */
struct PendingCreation {
    uint8 contractsDeployed;
    address feeRecipient;
}
