/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Range } from "../../../src/core/types/Range.sol";
import { RewardAccount, Rewards, State } from "../../../src/core/types/State.sol";

contract RewardsLibExtension {
    address internal immutable REWARD_TOKEN;
    address internal immutable GAUGE;
    address internal immutable GAUGE_FACTORY;
    address internal immutable LEAF_VOTER;

    State internal state;

    constructor(address rewardToken, address gauge, address gaugeFactory, address leafVoter) {
        REWARD_TOKEN = rewardToken;
        GAUGE = gauge;
        GAUGE_FACTORY = gaugeFactory;
        LEAF_VOTER = leafVoter;
    }

    function pushRange(Range memory range) external {
        state.ranges.push(range);
    }

    function setProtocolEmissionFeeBps(uint16 protocolEmissionFeeBps) external {
        state.config.protocolEmissionFeeBps = protocolEmissionFeeBps;
    }

    function setRewards(
        uint128 rewardPerShare,
        uint128 highWater,
        uint128 claimedCumulative,
        uint128 lastRewardBalance,
        uint128 protocolFees
    ) external {
        Rewards storage rewards = state.rewards;
        (rewards.rewardPerShare, rewards.highWater, rewards.claimedCumulative) =
        (rewardPerShare, highWater, claimedCumulative);
        (rewards.lastRewardBalance, rewards.protocolFees) = (lastRewardBalance, protocolFees);
    }

    function getRewards()
        external
        view
        returns (
            uint128 rewardPerShare,
            uint128 highWater,
            uint128 claimedCumulative,
            uint128 lastRewardBalance,
            uint128 protocolFees
        )
    {
        Rewards storage rewards = state.rewards;
        (rewardPerShare, highWater, claimedCumulative) =
        (rewards.rewardPerShare, rewards.highWater, rewards.claimedCumulative);
        (lastRewardBalance, protocolFees) = (rewards.lastRewardBalance, rewards.protocolFees);
    }

    function getPreCredited() external view returns (uint128 preCredited) {
        preCredited = state.rewards.preCredited;
    }

    function getWindowEnd() external view returns (uint48 windowEnd) {
        windowEnd = state.config.windowEnd;
    }

    function setPreCredited(uint128 preCredited) external {
        state.rewards.preCredited = preCredited;
    }

    function setWindowEnd(uint48 windowEnd) external {
        state.config.windowEnd = windowEnd;
    }

    function getLastRewardBalance() external view returns (uint128 lastRewardBalance) {
        lastRewardBalance = state.rewards.lastRewardBalance;
    }

    function getProtocolFeesReward() external view returns (uint128 protocolFees) {
        protocolFees = state.rewards.protocolFees;
    }

    function getProtocolRewardPerSharePaid() external view returns (uint128 protocolRewardPerSharePaid) {
        protocolRewardPerSharePaid = state.rewards.protocolRewardPerSharePaid;
    }

    function setRewardAccount(address account, RewardAccount memory rewardAccount) external {
        state.rewards.rewardAccounts[account] = rewardAccount;
    }

    function getRewardAccount(address account) external view returns (RewardAccount memory rewardAccount) {
        rewardAccount = state.rewards.rewardAccounts[account];
    }

    function payReward(uint256 supply, address account, uint256 balance) external returns (uint256 amount) {
        amount = state.payReward(supply, REWARD_TOKEN, GAUGE, GAUGE_FACTORY, LEAF_VOTER, account, balance);
    }

    function pay(address to, uint256 amount) external {
        state.rewards.pay(REWARD_TOKEN, to, amount);
    }

    function payProtocolFees(uint256 supply, address recipient, uint256 balance) external returns (uint256 amount) {
        amount = state.payProtocolFees(supply, REWARD_TOKEN, GAUGE, GAUGE_FACTORY, LEAF_VOTER, recipient, balance);
    }

    function accrueBalanceReward(address account, uint256 shares) external {
        state.accrueBalanceReward(account, shares);
    }

    function getRewardPerShare(uint256 supply, uint256 total)
        external
        view
        returns (uint128 rewardPerShare, uint256 highWater, uint256 preCredited, uint48 windowEnd)
    {
        (rewardPerShare, highWater, preCredited, windowEnd) =
            state.getRewardPerShare(supply, total, GAUGE, GAUGE_FACTORY, LEAF_VOTER);
    }

    function setProtocolRewardPerSharePaid(uint128 protocolRewardPerSharePaid) external {
        state.rewards.protocolRewardPerSharePaid = protocolRewardPerSharePaid;
    }

    function claimGaugeEmissions() external returns (bool skipped) {
        skipped = state.claimGaugeEmissions(GAUGE, GAUGE_FACTORY);
    }

    function checkpoint(uint256 supply) external {
        state.checkpoint(supply, REWARD_TOKEN, GAUGE, GAUGE_FACTORY, LEAF_VOTER);
    }

    function getRewardTotals() external view returns (uint256 received, uint256 protocolFee, uint256 total) {
        (received, protocolFee, total) = state.getRewardTotals(REWARD_TOKEN, GAUGE);
    }
}
