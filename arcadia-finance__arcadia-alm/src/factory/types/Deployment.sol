/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

/**
 * @notice One creation code and the contracts it deploys, one bit per contract.
 */
struct Deployment {
    uint8 contracts;
    bytes creationCode;
}
