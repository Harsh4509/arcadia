/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

/**
 * @notice The four vaults over one core.
 */
struct Vaults {
    address syncVault0;
    address syncVault1;
    address asyncVault0;
    address asyncVault1;
}
