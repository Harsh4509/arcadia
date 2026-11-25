/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

interface ICLGauge {
    function claimEmissions(address account, address recipient) external;
    function claimEmissions(address account, address recipient, uint256[] calldata tokenIds) external;
    function deferredEmissions(address account) external view returns (uint256);
    function deposit(uint256 tokenId) external;
    function depositFor(uint256 tokenId, address owner) external;
    function depositBlock(uint256 tokenId) external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function earned(address account, uint256[] memory tokenIds) external view returns (uint256);
    function gaugeFactory() external view returns (address);
    function pool() external view returns (address);
    function stakedContains(address depositor, uint256 tokenId) external view returns (bool);
    function stakedValues(address depositor) external view returns (uint256[] memory);
    function voter() external view returns (address);
    function withdraw(uint256 tokenId) external;
}
