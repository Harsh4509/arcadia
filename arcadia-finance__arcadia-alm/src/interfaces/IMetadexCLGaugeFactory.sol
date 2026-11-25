/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

interface IMetadexCLGaugeFactory {
    struct PenaltyConfig {
        uint256 minStakeBlocks;
        uint256 penaltyRate;
    }

    function effectivePenaltyConfig(address gauge) external view returns (PenaltyConfig memory);
    function referralConfig(address gauge) external view returns (address referral, uint256 share);
}
