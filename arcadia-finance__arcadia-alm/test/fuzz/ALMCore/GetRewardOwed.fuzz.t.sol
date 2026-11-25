/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { Plan } from "../../utils/Plan.sol";

/**
 * @notice Fuzz tests for the function "getRewardOwed" of contract "ALMCore".
 */
contract GetRewardOwed_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    using FixedPointMathLib for uint256;
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getRewardOwed_EqualsTheClaim(
        PoolState memory poolState,
        uint16 feeBps,
        uint96 shares,
        uint96 received,
        uint256 seedShares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee within the ceiling.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);

        // And: A holder beside a seed keeping the reward per share a uint128, and reward.
        shares = uint96(bound(shares, 1, type(uint96).max));
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(
                uint256(type(uint96).max).fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES
            ) + 1,
            type(uint96).max
        );
        almCore.mintShares(deadAddress, seedShares);
        almCore.mintShares(accountA, shares);
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);

        // When: Reading what the holder is owed.
        uint256 owed = almCore.getRewardOwed(accountA);

        // Then: It is the holder's part of the net reward, spread over the supply.
        uint256 net = uint256(received) - uint256(received).fullMulDiv(feeBps, ConfigLib.BPS_DENOMINATOR);
        uint256 rewardPerShare = net.fullMulDiv(1e18, seedShares + shares);
        assertEq(owed, uint256(shares).fullMulDiv(rewardPerShare, 1e18));

        // And: It is what a claim pays.
        assertEq(owed, almCore.claimEmissions(accountA));
    }

    function testFuzz_Success_getRewardOwed_AddsTheAccrualToTheCredited(
        PoolState memory poolState,
        uint96 shares,
        uint96 received,
        uint96 receivedLater,
        uint256 seedShares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A holder beside a seed keeping the reward per share a uint128, and reward.
        shares = uint96(bound(shares, 1, type(uint96).max));
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(
                uint256(type(uint96).max).fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES
            ) + 1,
            type(uint96).max
        );
        almCore.mintShares(deadAddress, seedShares);
        almCore.mintShares(accountA, shares);
        received = uint96(bound(received, 0, type(uint96).max - 1));
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);

        // And: The reward credited by a transfer under an open cap, then more reward.
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        vm.prank(accountA);
        almCore.transfer(deadAddress, 0);
        receivedLater = uint96(bound(receivedLater, 1, type(uint96).max - received));
        deal(almCore.REWARD_TOKEN_(), address(almCore), uint256(received) + receivedLater);

        // When: Reading what the holder is owed.
        uint256 owed = almCore.getRewardOwed(accountA);

        // Then: It is what a claim pays.
        assertEq(owed, almCore.claimEmissions(accountA));
    }

    function testFuzz_Success_getRewardOwed_CountsTheGaugesEarned(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint16 feeBps,
        uint96 shares,
        uint256 blocks,
        uint256 emissions,
        uint256 pick
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee within the ceiling.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);

        // And: A range around the price with a staked leg.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A vault holding it, a uint96 supply keeping the reward per share in range.
        givenValidCoreState(
            coreState,
            poolState,
            range,
            FixedPointMathLib.max(
                    uint256(type(uint96).max).fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES
                ) + 1,
            0,
            0
        );
        coreState.supply = FixedPointMathLib.min(coreState.supply, type(uint96).max);
        setCoreState(coreState);
        setRangeState(range);

        // And: A holder of at least half the supply.
        shares = uint96(bound(shares, coreState.supply, type(uint96).max));
        almCore.mintShares(accountA, shares);

        // And: The leg outside its window, with emissions owing the holder a reward.
        closePenaltyWindow(gauge);
        emissions = bound(emissions, 4 * uint256(shares).divUp(1e18) + 5, Constants.MAX_EMISSIONS);
        accrueForBlocks(pool, gauge, bound(blocks, 1, type(uint32).max), emissions);

        // And: A chain the gauge mints on, and what the leg earned.
        setMintableStatus(pick);
        uint256 earned = gauge.earned(address(almCore), almCore.stakedTokenIds());

        // When: Reading what the holder is owed.
        uint256 owed = almCore.getRewardOwed(accountA);

        // Then: It is the holder's part of the net earned, spread over the supply.
        uint256 rewardPerShare =
            (earned - earned.fullMulDiv(feeBps, ConfigLib.BPS_DENOMINATOR)).fullMulDiv(1e18, coreState.supply + shares);
        assertEq(owed, uint256(shares).fullMulDiv(rewardPerShare, 1e18));
        assertGt(owed, 0);

        // And: It is what a claim pays, the gauge claimed first.
        assertEq(owed, almCore.claimEmissions(accountA));
    }

    function testFuzz_Success_getRewardOwed_ExcludesAPendingRedeem(
        PoolState memory poolState,
        uint96 shares,
        uint96 redeemed,
        uint96 received,
        uint256 seedShares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A holder beside the supply seed, part of its aLP in a pending redeem.
        shares = uint96(bound(shares, 1, type(uint96).max));
        redeemed = uint96(bound(redeemed, 1, type(uint96).max));
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(
                uint256(type(uint96).max).fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES
            ) + 1,
            type(uint96).max
        );
        almCore.mintShares(deadAddress, seedShares);
        almCore.mintShares(accountA, shares);
        recordRedeemAt(asyncVault0, accountA, redeemed);

        // And: Reward token arrived, its fee and the reward per share of the rest.
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);
        uint256 protocolFee = uint256(received) * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        uint256 rewardPerShare = (received - protocolFee).fullMulDiv(1e18, seedShares + uint256(shares) + redeemed);

        // When: Reading what the holder is owed.
        uint256 owed = almCore.getRewardOwed(accountA);

        // Then: It is what the holder's own balance earned, the redeemed aLP left out.
        assertEq(owed, uint256(shares).fullMulDiv(rewardPerShare, 1e18));

        // And: It is what the holder is paid once the redeem is cancelled back to it.
        vm.prank(asyncVault0);
        almCore.cancelRedeemRequest(0, accountA, accountA);
        assertEq(almCore.claimEmissions(accountA), owed);

        // And: The protocol took its fee and what the redeemed aLP earned in escrow.
        assertEq(almCore.getProtocolFeesReward(), protocolFee + uint256(redeemed).fullMulDiv(rewardPerShare, 1e18));
    }

    function testFuzz_Success_getRewardOwed_ExcludesASettledRedeem(
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        uint96 receivedBefore,
        uint96 receivedAfter
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No ranges, a supply keeping the reward per share a uint128 past the burn.
        RangeState memory none;
        givenValidCoreState(
            coreState,
            poolState,
            none,
            2
                * FixedPointMathLib.max(
                    uint256(type(uint96).max).fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES
                ),
            0,
            0
        );

        // And: Its token1 worth no more than its token0.
        coreState.buffer1 = bound(
            coreState.buffer1, 1, FixedPointMathLib.max(token0ToToken1(poolState.sqrtPrice, coreState.buffer0), 1)
        );
        setCoreState(coreState);

        // And: A holder whose aLP sits in a pending token0 redeem, the only request.
        givenValidQueueState(queueState, 0, 0);
        queueState.redeem0 = bound(queueState.redeem0, 1, almCore.balanceOf(users.steward) / 2);
        (queueState.deposit0, queueState.deposit1, queueState.redeem1) = (0, 0, 0);
        setQueueState(queueState);
        uint256 balance = almCore.balanceOf(controller);
        uint256 supply = almCore.totalSupply();

        // And: Reward token arrived before and after the keeper settled the redeem.
        deal(almCore.REWARD_TOKEN_(), address(almCore), receivedBefore);
        runPlan(Plan.init().clearAllRequests(true, false).settleRequests());
        deal(almCore.REWARD_TOKEN_(), address(almCore), uint256(receivedBefore) + receivedAfter);

        // And: The fee on each, and the reward per share before and after the burn.
        uint256 fees = uint256(receivedBefore) * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        uint256 rewardPerShareAtBurn = (receivedBefore - fees).fullMulDiv(1e18, supply);
        uint256 feeAfter = uint256(receivedAfter) * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        uint256 rewardPerShare =
            rewardPerShareAtBurn + (receivedAfter - feeAfter).fullMulDiv(1e18, supply - queueState.redeem0);
        fees += feeAfter;

        // When: Reading what the holder is owed.
        uint256 owed = almCore.getRewardOwed(controller);

        // Then: It is what the holder's own balance earned, the redeemed aLP left out.
        assertEq(owed, balance.fullMulDiv(rewardPerShare, 1e18));

        // And: It is what the holder is paid once the redeem is claimed.
        vm.prank(asyncVault0);
        almCore.claimRedeemRequest(controller, queueState.redeem0, type(uint256).max, controller);
        assertEq(almCore.claimEmissions(controller), owed);

        // And: The protocol took its fees and the escrowed aLP's earnings to the burn.
        assertEq(almCore.getProtocolFeesReward(), fees + queueState.redeem0.fullMulDiv(rewardPerShareAtBurn, 1e18));
    }

    function testFuzz_Success_getRewardOwed_ExcludesASettledDeposit(
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        uint96 received
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault with no ranges, its supply keeping the reward per share a uint128.
        RangeState memory none;
        givenValidCoreState(
            coreState,
            poolState,
            none,
            FixedPointMathLib.max(
                    uint256(type(uint96).max).fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES
                ) + 1,
            0,
            0
        );
        setCoreState(coreState);

        // And: A holder whose token0 deposit, the only request, the keeper settled.
        givenValidQueueState(queueState, 1, 0);
        (queueState.deposit1, queueState.redeem0, queueState.redeem1) = (0, 0, 0);
        setQueueState(queueState);
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());
        uint256 balance = almCore.balanceOf(accountB);
        uint256 minted = almCore.depositEpoch(asyncVault0, 0).amountOut;

        // And: Reward token arrived after the settle, its fee and the reward per share.
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);
        uint256 protocolFee = uint256(received) * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        uint256 rewardPerShare = (received - protocolFee).fullMulDiv(1e18, almCore.totalSupply());

        // When: Reading what the holder is owed.
        uint256 owed = almCore.getRewardOwed(accountB);

        // Then: It is what the holder's own balance earned, the settled aLP left out.
        assertEq(owed, balance.fullMulDiv(rewardPerShare, 1e18));

        // And: It is what the holder is paid once the deposit is claimed.
        vm.prank(asyncVault0);
        almCore.claimDepositRequest(accountB, queueState.deposit0, type(uint256).max, accountB);
        assertEq(almCore.claimEmissions(accountB), owed);

        // And: The protocol took its fee and what the settled aLP earned in escrow.
        assertEq(almCore.getProtocolFeesReward(), protocolFee + minted.fullMulDiv(rewardPerShare, 1e18));
    }
}
