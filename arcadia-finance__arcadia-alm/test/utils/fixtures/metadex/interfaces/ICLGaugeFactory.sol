/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

interface ICLGaugeFactory {
    struct PenaltyConfig {
        uint256 minStakeBlocks;
        uint256 penaltyRate;
    }

    function createGauge(address target, bytes calldata factoryData) external returns (address gauge, address emissions);
    function effectivePenaltyConfig(address gauge) external view returns (PenaltyConfig memory);
    function emissionCap(address gauge) external view returns (uint128);
    function leafVoter() external view returns (address);
    function MAX_PIPS() external view returns (uint256);
    function maxMinStakeBlocks() external view returns (uint256);
    function maxShareCap() external view returns (uint256);
    function minStakeBlocks(address gauge) external view returns (uint256);
    function nft() external view returns (address);
    function referralConfig(address gauge) external view returns (address referral, uint256 share);
    function setEmergencyWithdrawEnabled(bool enabled) external;
    function setEmissionCap(address gauge, uint128 cap) external;
    function setMaxShareCap(uint256 cap) external;
    function setMinStakeBlocks(address gauge, uint256 minStakeBlocks) external;
    function setPenaltyConfig(uint256 minStakeBlocks, uint256 penaltyRate) external;
    function setReferralConfig(address gauge, address referral, uint256 share) external;
}
