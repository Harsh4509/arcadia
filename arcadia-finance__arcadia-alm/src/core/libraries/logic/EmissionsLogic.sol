/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IArbSys } from "../../../interfaces/IArbSys.sol";
import { ILeafVoter } from "../../../interfaces/ILeafVoter.sol";
import { IMetadexCLGauge } from "../../../interfaces/IMetadexCLGauge.sol";
import { IMetadexCLGaugeFactory } from "../../../interfaces/IMetadexCLGaugeFactory.sol";
import { IMetadexCLPool } from "../../../interfaces/IMetadexCLPool.sol";
import { Range } from "../../types/Range.sol";
import { RangesLib } from "../state/RangesLib.sol";
import { State } from "../../types/State.sol";

/**
 * @title Emissions Logic.
 * @author Pragma Labs
 * @notice Reads the Metadex emissions: whether the chain mints, and a range's penalty window.
 * @dev isPenaltyWindowOpen duplicates Gauge._applyPenalty's strict comparison, so it must be re-verified on every Metadex release.
 */
// forge-lint: disable-next-item(calls-loop, uninitialized-local, unsafe-typecast, unused-return)
library EmissionsLogic {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The denominator of the gauge's penalty rate and referral share.
    uint256 internal constant MAX_PIPS = 1e6;

    /* //////////////////////////////////////////////////////////////
                                  LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Whether the chain currently lets its gauges mint emissions.
     * @param leafVoter The LeafVoter of the chain.
     * @return mintable True when the chain status is Active or Sunset.
     */
    function isMintable(address leafVoter) internal view returns (bool mintable) {
        // Get the chain status (mintable when Active or Sunset).
        ILeafVoter.ChainStatus status = ILeafVoter(leafVoter).chainStatus();
        mintable = status == ILeafVoter.ChainStatus.Active || status == ILeafVoter.ChainStatus.Sunset;
    }

    /**
     * @notice The block number the chain's gauges count penalty windows in.
     * @param arbBlockNumber True when the gauges count blocks with ArbSys.arbBlockNumber.
     * @return blockNumber The block number.
     */
    function getBlockNumber(bool arbBlockNumber) internal view returns (uint256 blockNumber) {
        blockNumber = arbBlockNumber ? IArbSys(address(0x64)).arbBlockNumber() : block.number;
    }

    /**
     * @notice The penalty configuration in force for a gauge.
     * @param gaugeFactory The factory that created the gauge.
     * @param gauge The CL gauge.
     * @return config The penalty configuration.
     */
    function getPenaltyConfig(address gaugeFactory, address gauge)
        internal
        view
        returns (IMetadexCLGaugeFactory.PenaltyConfig memory config)
    {
        config = IMetadexCLGaugeFactory(gaugeFactory).effectivePenaltyConfig(gauge);
    }

    /**
     * @notice Whether a claim or unstake of the range would be haircut by the gauge at a block.
     * @param stakedBlock The block the range was staked in.
     * @param config The penalty configuration in force for the gauge the range is staked in.
     * @param blockNumber The gauge's current block number.
     * @return open True while the penalty window is open.
     */
    function isPenaltyWindowOpen(
        uint256 stakedBlock,
        IMetadexCLGaugeFactory.PenaltyConfig memory config,
        uint256 blockNumber
    ) internal pure returns (bool open) {
        // Calculate whether the range is inside the penalty window.
        open = config.penaltyRate > 0 && blockNumber < stakedBlock + config.minStakeBlocks;
    }

    /* //////////////////////////////////////////////////////////////
                            HIDDEN EMISSIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The emissions the gauge hides behind the penalty windows of the staked sides, before the protocol fee.
     * @param state The core state.
     * @param gauge The CL gauge the ranges are staked in.
     * @param gaugeFactory The factory that created the gauge.
     * @param leafVoter The LeafVoter of the chain.
     * @return hidden The hidden emissions.
     * @return windowEnd The first block at which no staked side is inside its penalty window, zero when none is.
     * @dev Rebuilds CLGauge.earned without _applyPenalty, re-verify on every Metadex release.
     */
    function getHiddenEmissions(State storage state, address gauge, address gaugeFactory, address leafVoter)
        internal
        view
        returns (uint256 hidden, uint48 windowEnd)
    {
        // Get the penalty configuration and the referral share of the gauge.
        IMetadexCLGaugeFactory.PenaltyConfig memory config;
        uint256 share;
        config = getPenaltyConfig(gaugeFactory, gauge);
        (, share) = IMetadexCLGaugeFactory(gaugeFactory).referralConfig(gauge);

        // Get the pool's reward growth, advanced by the emissions the voter projects for the gauge.
        IMetadexCLPool pool = IMetadexCLPool(IMetadexCLGauge(gauge).pool());
        uint256 rewardGrowthGlobalX128 = pool.rewardGrowthGlobalX128();
        {
            uint256 stakedLiquidity = pool.stakedLiquidity();
            if (stakedLiquidity > 0) {
                uint256 projected = ILeafVoter(leafVoter).projectedCumulativeRewardShare(gauge);
                uint256 last = IMetadexCLGauge(gauge).lastCumulativeRewardShare();
                if (projected > last) {
                    // Unchecked: projected exceeds last, and the reward growth can overflow, what matters is its delta.
                    unchecked {
                        rewardGrowthGlobalX128 += (projected - last).fullMulDiv(1 << 128, stakedLiquidity);
                    }
                }
            }
        }

        // Get the gauge's current block number.
        uint256 blockNumber = getBlockNumber(state.config.arbBlockNumber);

        // Add the hidden emissions of every staked side inside its penalty window, and the last window end.
        for (uint256 i; i < state.ranges.length; ++i) {
            Range storage range = RangesLib.unsafeAccess(state.ranges, i);
            if (range.stakedTokenId == 0) continue;
            {
                uint256 stakedBlock = range.stakedBlock;
                if (!isPenaltyWindowOpen(stakedBlock, config, blockNumber)) continue;
                windowEnd = uint48(FixedPointMathLib.max(windowEnd, stakedBlock + config.minStakeBlocks));
            }

            // Calculate the emissions the staked side accrued since its snapshot.
            uint256 accrued;
            // Unchecked: the reward growth can underflow, what matters is its delta since the staked side's snapshot.
            unchecked {
                accrued = (pool.getRewardGrowthInside(range.tickLower, range.tickUpper, rewardGrowthGlobalX128)
                        - IMetadexCLGauge(gauge).rewardGrowthInside(range.stakedTokenId))
                .fullMulDiv(range.stakedLiquidity, 1 << 128);
            }

            // Add the part the penalty hides, after the referral share.
            // Unchecked: accrued is a real emission amount, scaled by rates of at most MAX_PIPS.
            unchecked {
                uint256 visible = accrued - accrued * config.penaltyRate / MAX_PIPS;
                hidden += (accrued - accrued * share / MAX_PIPS) - (visible - visible * share / MAX_PIPS);
            }
        }
    }
}
