/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

interface IArbSys {
    function arbBlockNumber() external view returns (uint256);
}
