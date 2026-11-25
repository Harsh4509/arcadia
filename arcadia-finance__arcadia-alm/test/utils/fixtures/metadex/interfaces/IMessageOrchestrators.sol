/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

interface ILeafMessageOrchestrator {
    function adapter() external view returns (address);
    function setAdapter(address adapter) external;
}

interface IRootMessageOrchestrator {
    function setAdapter(uint256 chainId, address adapter) external;
}
