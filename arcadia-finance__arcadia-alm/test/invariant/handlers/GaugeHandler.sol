/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreExtension } from "../../utils/extensions/ALMCoreExtension.sol";
import { ALMCoreHandler } from "./ALMCoreHandler.sol";
import { BaseHandler } from "./BaseHandler.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { ICLGauge } from "../../utils/fixtures/metadex/interfaces/ICLGauge.sol";
import { ICLGaugeFactory } from "../../utils/fixtures/metadex/interfaces/ICLGaugeFactory.sol";
import { ICLPool } from "../../utils/fixtures/metadex/interfaces/ICLPool.sol";
import { ILeafVoter } from "../../utils/fixtures/metadex/interfaces/ILeafVoter.sol";

/**
 * @notice Drives the gauge governance moves around "ALMCore" for the invariant suite.
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GaugeHandler is BaseHandler {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The longest penalty window and block advance, seven days of BLOCK_TIME blocks.
    uint256 public constant MAX_MIN_STAKE_BLOCKS = 302_400;

    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    ALMCoreExtension internal immutable ALM_CORE;
    ALMCoreHandler internal immutable CORE_HANDLER;
    ICLGaugeFactory internal immutable GAUGE_FACTORY;
    ILeafVoter internal immutable LEAF_VOTER;
    address internal immutable GAUGE;
    // The holder of the gauge factory's penalty and referral roles.
    address internal immutable GAUGE_ADMIN;
    // The holder of the voter's chain status role.
    address internal immutable CONFIG_ADMIN;
    // The pool the gauge settles emissions into.
    ICLPool internal immutable POOL;
    // The caller the voter takes allocations from.
    address internal immutable ORCHESTRATOR;
    // The voting power the gauge was allocated.
    uint128 internal immutable VOTING_POWER;
    // The emissions per unit of voting power the minter accrues against at most.
    uint256 internal immutable MAX_EMISSIONS_PER_VP;

    // The emission rounds the gauge settled.
    uint256 public ghostEmissionRounds;
    // The penalty, window and referral moves that went through.
    uint256 public ghostGaugeConfigMoves;
    // The drop, net of the protocol fee, the penalty, window and referral moves caused in what the core earned.
    uint256 public ghostGaugeConfigLoss;

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(
        ALMCoreExtension almCore,
        ALMCoreHandler coreHandler,
        ICLGaugeFactory gaugeFactory,
        ILeafVoter leafVoter,
        address gauge,
        address gaugeAdmin,
        address configAdmin,
        ICLPool pool,
        address orchestrator,
        uint128 votingPower,
        uint256 maxEmissionsPerVP
    ) {
        ALM_CORE = almCore;
        CORE_HANDLER = coreHandler;
        GAUGE_FACTORY = gaugeFactory;
        LEAF_VOTER = leafVoter;
        GAUGE = gauge;
        GAUGE_ADMIN = gaugeAdmin;
        CONFIG_ADMIN = configAdmin;
        POOL = pool;
        ORCHESTRATOR = orchestrator;
        VOTING_POWER = votingPower;
        MAX_EMISSIONS_PER_VP = maxEmissionsPerVP;
    }

    /* //////////////////////////////////////////////////////////////
                                 ACTIONS
    ////////////////////////////////////////////////////////////// */

    function setPenaltyConfig(uint256 minStakeBlocks, uint256 penaltyRate)
        external
        countCall(this.setPenaltyConfig.selector)
        advanceBlock
    {
        minStakeBlocks = bound(
            minStakeBlocks, 0, FixedPointMathLib.min(MAX_MIN_STAKE_BLOCKS, GAUGE_FACTORY.maxMinStakeBlocks())
        );
        penaltyRate = bound(penaltyRate, 0, GAUGE_FACTORY.MAX_PIPS());
        CORE_HANDLER.trackFairShares();
        (uint256 withoutPenaltyBefore, uint256 earnedBefore) = _earned();

        vm.prank(GAUGE_ADMIN);
        try GAUGE_FACTORY.setPenaltyConfig(minStakeBlocks, penaltyRate) {
            _countConfigMove(withoutPenaltyBefore, earnedBefore);
        } catch (bytes memory reason) {
            _recordRevert(this.setPenaltyConfig.selector, reason);
        }
    }

    function setMinStakeBlocks(uint256 minStakeBlocks)
        external
        countCall(this.setMinStakeBlocks.selector)
        advanceBlock
    {
        minStakeBlocks = bound(
            minStakeBlocks, 0, FixedPointMathLib.min(MAX_MIN_STAKE_BLOCKS, GAUGE_FACTORY.maxMinStakeBlocks())
        );
        CORE_HANDLER.trackFairShares();
        (uint256 withoutPenaltyBefore, uint256 earnedBefore) = _earned();

        vm.prank(GAUGE_ADMIN);
        try GAUGE_FACTORY.setMinStakeBlocks(GAUGE, minStakeBlocks) {
            _countConfigMove(withoutPenaltyBefore, earnedBefore);
        } catch (bytes memory reason) {
            _recordRevert(this.setMinStakeBlocks.selector, reason);
        }
    }

    function setReferralConfig(address referral, uint256 share)
        external
        countCall(this.setReferralConfig.selector)
        advanceBlock
    {
        share = referral == address(0) ? 0 : bound(share, 0, GAUGE_FACTORY.maxShareCap());
        CORE_HANDLER.trackFairShares();
        (uint256 withoutPenaltyBefore, uint256 earnedBefore) = _earned();

        vm.prank(GAUGE_ADMIN);
        try GAUGE_FACTORY.setReferralConfig(GAUGE, referral, share) {
            _countConfigMove(withoutPenaltyBefore, earnedBefore);
        } catch (bytes memory reason) {
            _recordRevert(this.setReferralConfig.selector, reason);
        }
    }

    function accrueEmissions(uint256 emissionsPerVP) external countCall(this.accrueEmissions.selector) advanceBlock {
        emissionsPerVP = bound(emissionsPerVP, 1, MAX_EMISSIONS_PER_VP);
        CORE_HANDLER.trackFairShares();
        if (!_setEmissionsPerVP(emissionsPerVP)) return;
        vm.warp(vm.getBlockTimestamp() + 1);
        if (!_setEmissionsPerVP(0)) return;

        vm.prank(GAUGE);
        try POOL.settleToBlock() {
            ghostEmissionRounds++;
        } catch (bytes memory reason) {
            _recordRevert(this.accrueEmissions.selector, reason);
        }
    }

    function advanceBlocks(uint256 blocks) external countCall(this.advanceBlocks.selector) advanceBlock {
        uint256 window = GAUGE_FACTORY.minStakeBlocks(GAUGE);
        blocks = bound(blocks, 1, FixedPointMathLib.min(window > 0 ? window : 1, MAX_MIN_STAKE_BLOCKS));
        CORE_HANDLER.trackFairShares();
        vm.roll(vm.getBlockNumber() + blocks);
        vm.warp(vm.getBlockTimestamp() + blocks * BLOCK_TIME);
    }

    function setChainStatus(uint256 status) external countCall(this.setChainStatus.selector) advanceBlock {
        status = bound(status, uint256(ILeafVoter.ChainStatus.Active), uint256(ILeafVoter.ChainStatus.Sunset));
        CORE_HANDLER.trackFairShares();

        vm.prank(CONFIG_ADMIN);
        try LEAF_VOTER.setChainStatus(ILeafVoter.ChainStatus(status)) { }
        catch (bytes memory reason) {
            _recordRevert(this.setChainStatus.selector, reason);
        }
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function _earned() internal returns (uint256 withoutPenalty, uint256 earned) {
        uint256[] memory tokenIds = ALM_CORE.stakedTokenIds();
        withoutPenalty = CORE_HANDLER.earnedWithoutPenalty(tokenIds);
        earned = ICLGauge(GAUGE).earned(address(ALM_CORE), tokenIds);
    }

    function _countConfigMove(uint256 withoutPenaltyBefore, uint256 earnedBefore) internal {
        (uint256 withoutPenaltyAfter, uint256 earnedAfter) = _earned();
        uint256 dropWithoutPenalty = withoutPenaltyBefore > withoutPenaltyAfter
            ? CORE_HANDLER.netOfTheEmissionFee(withoutPenaltyBefore - withoutPenaltyAfter)
            : 0;
        uint256 dropEarned =
            earnedBefore > earnedAfter ? CORE_HANDLER.netOfTheEmissionFee(earnedBefore - earnedAfter) : 0;

        ghostGaugeConfigMoves++;
        ghostGaugeConfigLoss += FixedPointMathLib.max(dropWithoutPenalty, dropEarned) + 1;
        CORE_HANDLER.rebaseFairShares();
    }

    function _afterAction() internal override {
        CORE_HANDLER.checkMonotone();
    }

    function _setEmissionsPerVP(uint256 emissionsPerVP) internal returns (bool applied) {
        ILeafVoter.TokenSnapshot memory snapshot =
            ILeafVoter.TokenSnapshot({ staked: VOTING_POWER, stakeEnd: 0, isPermanent: true });

        vm.prank(ORCHESTRATOR);
        try LEAF_VOTER.applyChainAllocation(uint256(uint160(GAUGE)), 0, emissionsPerVP, true, false, snapshot) {
            applied = true;
        } catch (bytes memory reason) {
            _recordRevert(this.accrueEmissions.selector, reason);
        }
    }
}
