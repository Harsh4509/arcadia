/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

interface IEmissionsHandler {
    function RECEIPT_TOKEN() external view returns (address);
    function pendingRedeems(address recipient) external view returns (uint256);
}
