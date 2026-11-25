/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

interface IMetadexCLGauge {
    function claimEmissions(address account, address recipient, uint256[] calldata tokenIds) external;
    function deferredEmissions(address account) external view returns (uint256);
    function deposit(uint256 tokenId) external;
    function earned(address account, uint256[] calldata tokenIds) external view returns (uint256);
    function emergencyWithdraw(uint256 tokenId) external;
    function gaugeFactory() external view returns (address);
    function lastCumulativeRewardShare() external view returns (uint256);
    function pool() external view returns (address);
    function rewardGrowthInside(uint256 tokenId) external view returns (uint256);
    function voter() external view returns (address);
    function withdraw(uint256 tokenId) external;
}
