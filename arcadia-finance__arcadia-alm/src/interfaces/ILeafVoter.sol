/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

interface ILeafVoter {
    enum ChainStatus {
        None,
        Active,
        Paused,
        Suspended,
        Sunset
    }

    function FACTORY_REGISTRY() external view returns (address);
    function chainStatus() external view returns (ChainStatus);
    function projectedCumulativeRewardShare(address gauge) external view returns (uint256);
}
