/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ConfigLib } from "./ConfigLib.sol";
import { EmissionsLogic } from "../logic/EmissionsLogic.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../interfaces/IALMCoreEvents.sol";
import { IMetadexCLGauge } from "../../../interfaces/IMetadexCLGauge.sol";
import { Range } from "../../types/Range.sol";
import { RangesLib } from "./RangesLib.sol";
import { RewardAccount, Rewards, State } from "../../types/State.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";

/**
 * @title Rewards Library.
 * @author Pragma Labs
 * @notice The reward token the core's staked ranges earn, credited to aLP holders pro rata to their aLP.
 */
// forge-lint: disable-next-item(calls-loop, uninitialized-local, unsafe-typecast)
library RewardsLib {
    using FixedPointMathLib for uint256;
    using RangesLib for Range[];
    using SafeTransferLib for address;

    /* //////////////////////////////////////////////////////////////
                                PAYMENTS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Claims the core's emissions, then credits an account its reward and pays it out, up to the measured reward balance.
     * @param state The core state.
     * @param supply The aLP supply.
     * @param rewardToken The reward token.
     * @param gauge The CL gauge of the pool.
     * @param gaugeFactory The factory that created the gauge.
     * @param leafVoter The LeafVoter of the chain.
     * @param account The account whose reward is credited and paid.
     * @param shares The account's aLP balance.
     * @return amountReward The amount of reward token transferred.
     */
    function payReward(
        State storage state,
        uint256 supply,
        address rewardToken,
        address gauge,
        address gaugeFactory,
        address leafVoter,
        address account,
        uint256 shares
    ) internal returns (uint256 amountReward) {
        // If the chain mints, claim the core's emissions from the gauge, skipping ranges inside their penalty window.
        Rewards storage rewards = state.rewards;
        if (EmissionsLogic.isMintable(leafVoter)) claimGaugeEmissions(state, gauge, gaugeFactory);

        // Raise the reward per share to the latest emissions, net of the protocol share.
        checkpoint(state, supply, rewardToken, gauge, gaugeFactory, leafVoter);

        // Credit the account the reward its aLP balance earned so far.
        accrueBalanceReward(state, account, shares);

        // Update State.
        RewardAccount storage rewardAccount = rewards.rewardAccounts[account];
        amountReward = FixedPointMathLib.min(rewardAccount.rewardOwed, rewards.lastRewardBalance);
        // Unchecked: amountReward is at most rewardOwed.
        unchecked {
            rewardAccount.rewardOwed -= uint128(amountReward);
        }

        // Transfer the reward to the account.
        pay(rewards, rewardToken, account, amountReward);
    }

    /**
     * @notice Credits the core's aLP to the protocol and pays out protocol fees, up to the measured reward balance.
     * @param state The core state.
     * @param supply The aLP supply.
     * @param rewardToken The reward token.
     * @param gauge The CL gauge of the pool.
     * @param gaugeFactory The factory that created the gauge.
     * @param leafVoter The LeafVoter of the chain.
     * @param recipient The recipient of the protocol fees.
     * @param shares The core's own aLP balance.
     * @return amountReward The reward token paid.
     */
    function payProtocolFees(
        State storage state,
        uint256 supply,
        address rewardToken,
        address gauge,
        address gaugeFactory,
        address leafVoter,
        address recipient,
        uint256 shares
    ) internal returns (uint256 amountReward) {
        // Raise the reward per share to the latest emissions, net of the protocol share.
        Rewards storage rewards = state.rewards;
        checkpoint(state, supply, rewardToken, gauge, gaugeFactory, leafVoter);

        // Credit the protocol the reward the core's own aLP balance earned so far.
        accrueBalanceReward(state, address(this), shares);

        // Update State.
        amountReward = FixedPointMathLib.min(rewards.protocolFees, rewards.lastRewardBalance);
        // Unchecked: amountReward is at most protocolFees.
        unchecked {
            rewards.protocolFees -= uint128(amountReward);
        }

        // Transfer the protocol fees to the recipient.
        if (amountReward > 0) pay(rewards, rewardToken, recipient, amountReward);
    }

    /**
     * @notice Transfers reward token out and lowers the measured balance by it.
     * @param rewards The reward accounting.
     * @param rewardToken The reward token.
     * @param to The account paid.
     * @param amountReward The amount transferred.
     */
    function pay(Rewards storage rewards, address rewardToken, address to, uint256 amountReward) internal {
        // Update State.
        rewards.lastRewardBalance -= uint128(amountReward);

        // Transfer the reward token to the account paid.
        rewardToken.safeTransfer(to, amountReward);
    }

    /* //////////////////////////////////////////////////////////////
                               ACCUMULATOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Accrues the reward received since the last checkpoint and raises the reward per share.
     * @param state The core state.
     * @param supply The aLP supply.
     * @param rewardToken The reward token.
     * @param gauge The CL gauge of the pool.
     * @param gaugeFactory The factory that created the gauge.
     * @param leafVoter The LeafVoter of the chain.
     */
    function checkpoint(
        State storage state,
        uint256 supply,
        address rewardToken,
        address gauge,
        address gaugeFactory,
        address leafVoter
    ) internal {
        // Get the reward token received, its protocol share and the lifetime reward.
        Rewards storage rewards = state.rewards;
        uint256 total;
        {
            uint256 received;
            uint256 protocolFee;
            (received, protocolFee, total) = getRewardTotals(state, rewardToken, gauge);

            // If reward token was received, add it to the measured balance and split it over protocol fees and claims.
            if (received > 0) {
                // Unchecked: amounts stay below 2^128, the protocol fee at most half of what was received.
                unchecked {
                    rewards.lastRewardBalance += SafeCastLib.toUint128(received);
                    rewards.protocolFees += SafeCastLib.toUint128(protocolFee);
                    rewards.claimedCumulative += SafeCastLib.toUint128(received - protocolFee);
                }
            }
        }

        // Calculate the reward per share, the high water, the pre-credit and the window end at this block.
        (uint128 rewardPerShare, uint256 highWater, uint256 preCredited, uint48 windowEnd) =
            getRewardPerShare(state, supply, total, gauge, gaugeFactory, leafVoter);

        // Update State.
        if (preCredited != rewards.preCredited) rewards.preCredited = SafeCastLib.toUint128(preCredited);
        if (windowEnd != state.config.windowEnd) state.config.windowEnd = windowEnd;
        if (rewardPerShare != rewards.rewardPerShare) {
            rewards.rewardPerShare = rewardPerShare;

            // forge-lint: disable-next-line(reentrancy-events)
            emit IALMCoreEvents.RewardPerShareUpdated(rewardPerShare);
        }
        if (highWater != rewards.highWater) rewards.highWater = SafeCastLib.toUint128(highWater);
    }

    /**
     * @notice Claims the core's emissions from the gauge, skipping staked ranges inside their penalty window.
     * @param state The core state.
     * @param gauge The CL gauge of the pool.
     * @param gaugeFactory The factory that created the gauge.
     * @return skipped True when a staked range inside its penalty window was skipped.
     */
    function claimGaugeEmissions(State storage state, address gauge, address gaugeFactory)
        internal
        returns (bool skipped)
    {
        uint256[] memory tokenIds;
        (tokenIds, skipped) = state.ranges
            .claimableTokenIds(gauge, gaugeFactory, EmissionsLogic.getBlockNumber(state.config.arbBlockNumber));
        if (tokenIds.length != 0 || IMetadexCLGauge(gauge).deferredEmissions(address(this)) != 0) {
            IMetadexCLGauge(gauge).claimEmissions(address(this), address(this), tokenIds);
        }
    }

    /* //////////////////////////////////////////////////////////////
                                 CREDITS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Credits an account the reward its aLP earned since its last credit.
     * @param state The core state.
     * @param account The account to credit.
     * @param shares The account's aLP balance.
     */
    function accrueBalanceReward(State storage state, address account, uint256 shares) internal {
        // Cache whether the account is the core, the reward per share it was last credited at and the current one.
        Rewards storage rewards = state.rewards;
        bool isCore = account == address(this);
        uint128 rewardPerSharePaid =
            isCore ? rewards.protocolRewardPerSharePaid : rewards.rewardAccounts[account].rewardPerSharePaid;
        uint128 accumulator = rewards.rewardPerShare;

        // Checks.
        if (accumulator == rewardPerSharePaid) return;

        // Calculate the reward the balance earned since the account's last credit.
        uint256 amountReward;
        // Unchecked: rewardPerShare can underflow, what matters is the delta in rewardPerShare between two interactions.
        unchecked {
            amountReward = shares.fullMulDiv(accumulator - rewardPerSharePaid, 1e18);
        }

        // Update State.
        if (isCore) {
            rewards.protocolFees += SafeCastLib.toUint128(amountReward);
            rewards.protocolRewardPerSharePaid = accumulator;
        } else {
            RewardAccount storage rewardAccount = rewards.rewardAccounts[account];
            rewardAccount.rewardOwed += SafeCastLib.toUint128(amountReward);
            rewardAccount.rewardPerSharePaid = accumulator;
        }
    }

    /* //////////////////////////////////////////////////////////////
                               VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The reward per share a checkpoint at this block reaches, with the high water, pre-credit and window end.
     * @param state The core state.
     * @param supply The aLP supply.
     * @param total The lifetime reward, net of the protocol share.
     * @param gauge The CL gauge of the pool.
     * @param gaugeFactory The factory that created the gauge.
     * @param leafVoter The LeafVoter of the chain.
     * @return rewardPerShare The reward per share.
     * @return highWater The lifetime reward credited.
     * @return preCredited The hidden emissions credited ahead.
     * @return windowEnd The first block at which no staked side is inside its penalty window, zero when none is.
     */
    function getRewardPerShare(
        State storage state,
        uint256 supply,
        uint256 total,
        address gauge,
        address gaugeFactory,
        address leafVoter
    ) internal view returns (uint128 rewardPerShare, uint256 highWater, uint256 preCredited, uint48 windowEnd) {
        // Cache the high water, the pre-credit and the window end.
        (highWater, preCredited, windowEnd) =
        (state.rewards.highWater, state.rewards.preCredited, state.config.windowEnd);

        // If a window may be open, fold a drop in the hidden emissions or pre-credit a rise.
        uint256 credit;
        if (windowEnd != 0) {
            uint256 hidden;
            (hidden, windowEnd) = EmissionsLogic.getHiddenEmissions(state, gauge, gaugeFactory, leafVoter);

            // Calculate the hidden emissions net of the protocol share.
            // Unchecked: the protocol fee is at most half of the hidden emissions.
            unchecked {
                hidden -= hidden.fullMulDiv(state.config.protocolEmissionFeeBps, ConfigLib.BPS_DENOMINATOR);
            }

            // If the hidden emissions dropped, fold the drop into the high water, else pre-credit the rise.
            // Unchecked: the high water and the pre-credit are uint128 values.
            unchecked {
                if (hidden < preCredited) highWater += preCredited - hidden;
                else credit = hidden - preCredited;
            }
            preCredited = hidden;
        }

        // If the lifetime reward exceeds the high water, add the excess to the credit.
        if (total > highWater) {
            // Unchecked: the check above bounds the subtraction, and the sum of two reward token amounts cannot overflow.
            unchecked {
                credit += total - highWater;
            }
            highWater = total;
        }

        // Spread the credit over the aLP supply as reward per share.
        rewardPerShare = state.rewards.rewardPerShare;
        if (credit > 0 && supply > 0) {
            // Unchecked: rewardPerShare can overflow, what matters is the delta in rewardPerShare between two interactions.
            unchecked {
                rewardPerShare = rewardPerShare + SafeCastLib.toUint128(credit.fullMulDiv(1e18, supply));
            }
        }
    }

    /**
     * @notice The reward token received since the last checkpoint, its protocol share and the lifetime reward.
     * @param state The core state.
     * @param rewardToken The reward token.
     * @param gauge The CL gauge of the pool.
     * @return received The reward token received since the last checkpoint.
     * @return protocolFee The protocol share of what was received.
     * @return total The lifetime reward, net of the protocol share.
     */
    function getRewardTotals(State storage state, address rewardToken, address gauge)
        internal
        view
        returns (uint256 received, uint256 protocolFee, uint256 total)
    {
        // Calculate the reward token received since the last checkpoint, less the pool token reserve when it is one.
        Rewards storage rewards = state.rewards;
        received = rewardToken.balanceOf(address(this));
        {
            uint256 rewardPoolToken = state.config.rewardPoolToken;
            if (rewardPoolToken != 0) {
                (uint256 reserve0, uint256 reserve1) = state.poolTokens.getReserves();
                received -= rewardPoolToken == 1 ? reserve0 : reserve1;
            }
        }
        received -= rewards.lastRewardBalance;

        // Calculate the protocol share of the received reward token.
        uint256 bps = state.config.protocolEmissionFeeBps;
        protocolFee = received.fullMulDiv(bps, ConfigLib.BPS_DENOMINATOR);

        // Get the emissions the core earned at the gauge and has not claimed yet.
        uint256[] memory tokenIds = state.ranges.stakedTokenIds();
        uint256 earnedAtGauge = tokenIds.length == 0
            ? IMetadexCLGauge(gauge).deferredEmissions(address(this))
            : IMetadexCLGauge(gauge).earned(address(this), tokenIds);

        // Calculate the lifetime reward (claimed, received and earned, net of the protocol share).
        uint256 earnedFee = earnedAtGauge.fullMulDiv(bps, ConfigLib.BPS_DENOMINATOR);
        uint256 netReceived;
        // Unchecked: each protocol fee is at most half of the amount it is taken from.
        unchecked {
            netReceived = received - protocolFee;
            earnedAtGauge -= earnedFee;
        }
        total = rewards.claimedCumulative + netReceived + earnedAtGauge;
    }
}
