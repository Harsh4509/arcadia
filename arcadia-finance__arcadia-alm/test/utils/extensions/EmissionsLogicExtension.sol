/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { EmissionsLogic } from "../../../src/core/libraries/logic/EmissionsLogic.sol";
import { IMetadexCLGaugeFactory } from "../../../src/interfaces/IMetadexCLGaugeFactory.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { State } from "../../../src/core/types/State.sol";

contract EmissionsLogicExtension {
    State internal state;

    function pushRange(Range memory range) external {
        state.ranges.push(range);
    }

    function getHiddenEmissions(address gauge, address gaugeFactory, address leafVoter)
        external
        view
        returns (uint256 hidden, uint48 windowEnd)
    {
        (hidden, windowEnd) = EmissionsLogic.getHiddenEmissions(state, gauge, gaugeFactory, leafVoter);
    }

    function isMintable(address leafVoter) external view returns (bool mintable) {
        mintable = EmissionsLogic.isMintable(leafVoter);
    }

    function getPenaltyConfig(address gaugeFactory, address gauge)
        external
        view
        returns (IMetadexCLGaugeFactory.PenaltyConfig memory config)
    {
        config = EmissionsLogic.getPenaltyConfig(gaugeFactory, gauge);
    }

    function isPenaltyWindowOpen(
        uint256 stakedBlock,
        IMetadexCLGaugeFactory.PenaltyConfig memory config,
        bool arbBlockNumber
    ) external view returns (bool open) {
        open = EmissionsLogic.isPenaltyWindowOpen(stakedBlock, config, EmissionsLogic.getBlockNumber(arbBlockNumber));
    }

    function getBlockNumber(bool arbBlockNumber) external view returns (uint256 blockNumber) {
        blockNumber = EmissionsLogic.getBlockNumber(arbBlockNumber);
    }
}
