/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

interface IALMSyncExtension {
    function convertToAssets(uint256 shares) external view returns (uint256 assets);
    function convertToShares(uint256 assets) external view returns (uint256 shares);
    function maxDeposit(address receiver) external view returns (uint256 assets);
    function maxMint(address receiver) external view returns (uint256 shares);
    function maxRedeem(address owner) external view returns (uint256 shares);
    function maxWithdraw(address owner) external view returns (uint256 assets);
    function previewDeposit(uint256 assets) external view returns (uint256 shares);
    function previewMint(uint256 shares) external view returns (uint256 assets);
    function previewRedeem(uint256 shares) external view returns (uint256 assets);
    function totalAssets() external view returns (uint256 assets);
}
