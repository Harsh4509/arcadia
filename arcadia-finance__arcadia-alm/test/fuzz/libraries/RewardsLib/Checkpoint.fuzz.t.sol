/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../../src/interfaces/IALMCoreEvents.sol";
import { Plan } from "../../../utils/Plan.sol";
import { RewardsLib_Fuzz_Test } from "./_RewardsLib.fuzz.t.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { stdError } from "@forge-std/StdError.sol";

/**
 * @notice Fuzz tests for the function "checkpoint" of library "RewardsLib".
 */
// forge-lint: disable-next-item(unsafe-typecast, uninitialized-local, calls-loop, erc20-unchecked-transfer)
contract Checkpoint_RewardsLib_Fuzz_Test is RewardsLib_Fuzz_Test {
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_checkpoint_RewardPoolTokenBelowTheReserve(
        PoolState memory poolState,
        bool isToken0,
        uint96 reserve,
        uint256 balance
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The reward token is a pool token, with a buffer of it.
        reserve = uint96(bound(reserve, 1, type(uint96).max));
        almCore.setRewardPoolToken(isToken0 ? 1 : 2);
        almCore.setBuffers(isToken0 ? reserve : 0, isToken0 ? 0 : reserve);

        // And: A reward token balance under that buffer.
        deal(almCore.REWARD_TOKEN_(), address(almCore), bound(balance, 0, uint256(reserve) - 1));

        // When: Checkpointing.
        // Then: It reverts on the underflow.
        vm.expectRevert(stdError.arithmeticError);
        almCore.checkpoint_();
    }

    function testFuzz_Revert_checkpoint_Overflow_Reward(
        PoolState memory poolState,
        uint16 feeBps,
        uint96 shares,
        uint256 received
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee within the ceiling and a supply.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);
        almCore.mintShares(accountA, bound(shares, 1, type(uint96).max));

        // And: More reward token arrived than a uint128 holds.
        deal(
            almCore.REWARD_TOKEN_(),
            address(almCore),
            bound(received, uint256(type(uint128).max) + 1, type(uint256).max)
        );

        // When: Checkpointing.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        almCore.checkpoint_();
    }

    function testFuzz_Revert_checkpoint_Overflow_HighWater(
        PoolState memory poolState,
        uint16 feeBps,
        uint96 shares,
        uint256 earned,
        uint256 status
    ) public {
        // Given: A pool with depth at a fuzzed price, on a chain the gauge mints on.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        setMintableStatus(status);

        // And: An emission fee within the ceiling and a supply.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);
        almCore.mintShares(accountA, bound(shares, 1, type(uint96).max));

        // And: Earned emissions whose net part passes a uint128, spread within 256 bits.
        earned = bound(
            earned,
            FixedPointMathLib.fullMulDivUp(
                uint256(type(uint128).max) + 1, ConfigLib.BPS_DENOMINATOR, ConfigLib.BPS_DENOMINATOR - feeBps
            ),
            type(uint256).max / 1e18
        );
        mockEarned(gauge, address(almCore), earned);

        // When: Checkpointing.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        almCore.checkpoint_();
    }

    function testFuzz_Revert_checkpoint_Overflow_RewardPerShare(
        PoolState memory poolState,
        uint96 shares,
        uint96 received
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee, a supply small enough for a 2^128 step per share.
        uint256 least = FixedPointMathLib.fullMulDivUp(almCore.DEAD_SHARES_() + 1, type(uint128).max, 1e18);
        received = uint96(bound(received, least, type(uint96).max));
        uint256 ceiling = FixedPointMathLib.fullMulDiv(received, 1e18, type(uint128).max);
        shares = uint96(bound(shares, almCore.DEAD_SHARES_(), ceiling - 1));
        almCore.mintShares(accountA, shares);

        // And: Reward token arrived since the last interaction.
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);

        // When: Checkpointing.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        almCore.checkpoint_();
    }

    function testFuzz_Success_checkpoint_EarnedFallsFreezesAccumulator(
        PoolState memory poolState,
        uint16 feeBps,
        uint96 shares,
        uint96 earnedHigh,
        uint96 earnedLow
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee within the ceiling and a supply the reward per share fits.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);
        uint256 supply = bound(
            shares,
            FixedPointMathLib.max(
                FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max), Constants.DEAD_SHARES
            ),
            Constants.MAX_FUZZED_AMOUNT
        );
        almCore.mintShares(accountA, supply);

        // And: A positive earned amount checkpointed, its net spread over the supply.
        earnedHigh = uint96(bound(earnedHigh, 1, type(uint96).max));
        mockEarned(gauge, address(almCore), earnedHigh);
        almCore.checkpoint_();
        uint256 highWaterAtPeak = earnedHigh - uint256(earnedHigh) * feeBps / 10_000;
        uint256 accumulatorAtPeak = FixedPointMathLib.fullMulDiv(highWaterAtPeak, 1e18, supply);

        // And: Earned falls back.
        mockEarned(gauge, address(almCore), bound(earnedLow, 0, earnedHigh - 1));

        // When: Checkpointing again.
        almCore.checkpoint_();

        // Then: Neither the accumulator nor the high-water mark moves.
        assertEq(almCore.rewardPerShare_(), accumulatorAtPeak);
        assertEq(almCore.getRewardHighWater(), highWaterAtPeak);
    }

    function testFuzz_Success_checkpoint_EarnedRecoversResumesAccumulator(
        PoolState memory poolState,
        uint16 feeBps,
        uint96 shares,
        uint96 earnedHigh,
        uint96 earnedRecovered
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee within the ceiling and a supply.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max), Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);

        // And: A peak earned amount was checkpointed and then fell to zero.
        earnedHigh = uint96(bound(earnedHigh, 1, type(uint96).max - 1));
        mockEarned(gauge, address(almCore), earnedHigh);
        almCore.checkpoint_();
        mockEarned(gauge, address(almCore), 0);
        almCore.checkpoint_();

        // And: Earned recovers above the peak.
        earnedRecovered = uint96(bound(earnedRecovered, earnedHigh + 1, type(uint96).max));
        mockEarned(gauge, address(almCore), earnedRecovered);

        // When: Checkpointing again.
        almCore.checkpoint_();

        // Then: The high-water mark catches up to the recovered amount net of the fee.
        uint256 peak = earnedHigh - uint256(earnedHigh) * feeBps / 10_000;
        uint256 recovered = earnedRecovered - uint256(earnedRecovered) * feeBps / 10_000;
        assertEq(almCore.getRewardHighWater(), recovered);

        // And: Only the increment over the peak accrues.
        assertEq(
            almCore.rewardPerShare_(),
            FixedPointMathLib.fullMulDiv(peak, 1e18, shares)
                + FixedPointMathLib.fullMulDiv(recovered - peak, 1e18, shares)
        );
    }

    function testFuzz_Success_checkpoint_NotMintableCountsTheEarned(
        PoolState memory poolState,
        uint16 feeBps,
        uint96 shares,
        uint96 earned
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee within the ceiling and a supply the reward per share fits.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);
        earned = uint96(bound(earned, 1, type(uint96).max));
        shares = uint96(
            bound(
                shares, FixedPointMathLib.fullMulDivUp(earned, 1e18, type(uint128).max) + 1, Constants.MAX_FUZZED_AMOUNT
            )
        );
        almCore.mintShares(accountA, shares);

        // And: The gauge reports a positive earned amount while the chain cannot mint.
        mockEarned(gauge, address(almCore), earned);
        setMintable(false);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The earned amount is counted net of the fee.
        uint256 net = earned - uint256(earned) * feeBps / ConfigLib.BPS_DENOMINATOR;
        assertEq(almCore.rewardPerShare_(), FixedPointMathLib.fullMulDiv(net, 1e18, shares));
        assertEq(almCore.getRewardHighWater(), net);
    }

    function testFuzz_Success_checkpoint_AccumulatorWrapsPastItsWidth(
        PoolState memory poolState,
        uint64 sharesA,
        uint64 sharesB,
        uint64 sharesCore,
        uint64 headroom,
        uint128 received
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee and a supply held by two accounts and the core.
        sharesA = uint64(bound(sharesA, almCore.DEAD_SHARES_(), type(uint64).max));
        sharesB = uint64(bound(sharesB, 1, type(uint64).max));
        sharesCore = uint64(bound(sharesCore, 1, type(uint64).max));
        almCore.mintShares(accountA, sharesA);
        almCore.mintShares(accountB, sharesB);
        almCore.mintShares(address(almCore), sharesCore);
        uint256 supply = almCore.totalSupply();

        // And: An accumulator a fuzzed headroom below its width, every account paid up.
        headroom = uint64(bound(headroom, 0, type(uint64).max));
        uint256 accumulatorBefore = type(uint128).max - uint256(headroom);
        almCore.setRewardAccounting(accumulatorBefore, 0, 0, 0);
        almCore.setRewardSnapshot(accountA, accumulatorBefore);
        almCore.setRewardSnapshot(accountB, accumulatorBefore);
        almCore.setProtocolRewardSnapshot(accumulatorBefore);

        // And: A reward whose step per share passes the headroom and stays below 2^128.
        received = uint128(
            bound(
                received,
                FixedPointMathLib.fullMulDivUp(uint256(headroom) + 1, supply, 1e18),
                FixedPointMathLib.min(FixedPointMathLib.fullMulDiv(type(uint128).max, supply, 1e18), type(uint128).max)
            )
        );
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);
        uint256 step = FixedPointMathLib.fullMulDiv(received, 1e18, supply);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The accumulator wraps to the step less the headroom it had.
        assertEq(almCore.rewardPerShare_(), step - headroom - 1);

        // And: A later accrual credits each account and the protocol its share of it.
        almCore.accrueBalanceReward(accountA);
        almCore.accrueBalanceReward(accountB);
        almCore.accrueBalanceReward(address(almCore));
        assertEq(almCore.getPendingReward(accountA), FixedPointMathLib.fullMulDiv(sharesA, step, 1e18));
        assertEq(almCore.getPendingReward(accountB), FixedPointMathLib.fullMulDiv(sharesB, step, 1e18));
        assertEq(almCore.getProtocolFeesReward(), FixedPointMathLib.fullMulDiv(sharesCore, step, 1e18));
    }

    function testFuzz_Success_checkpoint_RewardAccruesFeeAndCredits(
        PoolState memory poolState,
        uint16 feeBps,
        uint96 shares,
        uint96 received
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee within the ceiling and a supply.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(received, 1e18, type(uint128).max), Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);

        // And: Reward token arrived since the last interaction.
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The protocol share, rounded down, goes to the protocol, rest to holders.
        uint256 fee = uint256(received) * feeBps / 10_000;
        assertEq(almCore.getProtocolFeesReward(), fee);
        assertEq(almCore.getClaimedCumulative(), received - fee);
        assertEq(almCore.getRewardHighWater(), received - fee);
        assertEq(almCore.getLastRewardBalance(), received);
        assertEq(almCore.rewardPerShare_(), FixedPointMathLib.fullMulDiv(received - fee, 1e18, shares));
    }

    function testFuzz_Success_checkpoint_ASecondRewardAddsToTheMeasuredBalanceAndTheFees(
        PoolState memory poolState,
        uint16 feeBps,
        uint96 shares,
        uint96 receivedFirst,
        uint96 receivedSecond
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A non-zero emission fee within the ceiling, and rewards it takes a fee of.
        feeBps = uint16(bound(feeBps, 1, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);
        receivedFirst = uint96(bound(receivedFirst, ConfigLib.BPS_DENOMINATOR, type(uint96).max));
        receivedSecond = uint96(bound(receivedSecond, ConfigLib.BPS_DENOMINATOR, type(uint96).max));
        uint256 received = uint256(receivedFirst) + receivedSecond;

        // And: A supply.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(received, 1e18, type(uint128).max), Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);

        // And: A first reward, checkpointed.
        deal(almCore.REWARD_TOKEN_(), address(almCore), receivedFirst);
        almCore.checkpoint_();

        // When: Checkpointing a second reward.
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);
        almCore.checkpoint_();

        // Then: Both rewards are measured, their protocol shares added up.
        uint256 fee = uint256(receivedFirst) * feeBps / 10_000 + uint256(receivedSecond) * feeBps / 10_000;
        assertEq(almCore.getLastRewardBalance(), received);
        assertEq(almCore.getProtocolFeesReward(), fee);
        assertEq(almCore.getClaimedCumulative(), received - fee);
    }

    function testFuzz_Success_checkpoint_WithoutAWindowEndReadsNoHiddenEmissions(
        PoolState memory poolState,
        uint96 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 blocksInside,
        uint256 emissions,
        uint256 status
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee, a supply and a full penalty over a fuzzed window.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked range in its window, no window end stored, as after a raise.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));

        // And: Emissions accrued inside the window, hidden by the penalty.
        accrueForBlocks(
            pool,
            gauge,
            bound(blocksInside, 0, minStakeBlocks - 1),
            bound(emissions, MAX_PIPS + 1, Constants.MAX_EMISSIONS)
        );
        assertGt(hiddenEmissions(gauge, address(almCore), tokenIds), 0);

        // And: Any chain status.
        setAnyStatus(status);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: Nothing is pre-credited, spread or given a window end.
        assertEq(almCore.getPreCredited(), 0);
        assertEq(almCore.rewardPerShare_(), 0);
        assertEq(almCore.getWindowEnd(), 0);
    }

    function testFuzz_Success_checkpoint_EmitsRewardPerShareUpdated(
        PoolState memory poolState,
        uint16 feeBps,
        uint96 shares,
        uint96 received
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee within the ceiling, and a reward net of it.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);
        received = uint96(bound(received, 1, type(uint96).max));
        uint256 net = received - uint256(received) * feeBps / 10_000;

        // And: A supply the net reward raises the reward per share of.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(received, 1e18, type(uint128).max), Constants.DEAD_SHARES
                ),
                FixedPointMathLib.min(net * 1e18, type(uint96).max)
            )
        );
        almCore.mintShares(accountA, shares);

        // And: Reward token arrived since the last interaction.
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);

        // When: Checkpointing.
        // Then: It reports the raised reward per share.
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.RewardPerShareUpdated(FixedPointMathLib.fullMulDiv(net, 1e18, shares));
        almCore.checkpoint_();
    }

    function testFuzz_Success_checkpoint_NoNewRewardLeavesTheAccounting(
        PoolState memory poolState,
        uint96 shares,
        uint96 received
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A supply, and a reward already checkpointed.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(received, 1e18, type(uint128).max), Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);
        almCore.checkpoint_();

        uint256 rewardPerShare = almCore.rewardPerShare_();
        uint256 highWater = almCore.getRewardHighWater();

        // When: Checkpointing again without new reward, logging no update.
        vm.expectEmit(false, false, false, false, address(almCore), 0);
        emit IALMCoreEvents.RewardPerShareUpdated(0);
        almCore.checkpoint_();

        // Then: The reward per share and the high water hold.
        assertEq(almCore.rewardPerShare_(), rewardPerShare);
        assertEq(almCore.getRewardHighWater(), highWater);

        // And: The measured balance is the reward received.
        assertEq(almCore.getLastRewardBalance(), received);
    }

    function testFuzz_Success_checkpoint_SupplyChangeBetweenAccruals(
        PoolState memory poolState,
        uint96 sharesFirst,
        uint96 sharesSecond
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A first holder and an accrual against that supply.
        sharesFirst = uint96(
            bound(
                sharesFirst,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(2 * Constants.MAX_FUZZED_AMOUNT, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, sharesFirst);
        mockEarned(gauge, address(almCore), Constants.MAX_FUZZED_AMOUNT);
        almCore.checkpoint_();

        // And: A second holder joins, which credits nothing to the first.
        sharesSecond = uint96(bound(sharesSecond, almCore.DEAD_SHARES_(), type(uint96).max));
        almCore.mintShares(accountB, sharesSecond);

        // When: A further accrual is checkpointed against the larger supply.
        mockEarned(gauge, address(almCore), 2 * Constants.MAX_FUZZED_AMOUNT);
        almCore.updateRewards(accountA);
        almCore.updateRewards(accountB);

        // Then: The second accrual, net of the fee, is split over the larger supply.
        uint256 feeBps = almCore.protocolEmissionFeeBps_();
        uint256 first = Constants.MAX_FUZZED_AMOUNT - Constants.MAX_FUZZED_AMOUNT * feeBps / 10_000;
        uint256 second = 2 * Constants.MAX_FUZZED_AMOUNT - 2 * Constants.MAX_FUZZED_AMOUNT * feeBps / 10_000 - first;
        uint256 firstPerShare = FixedPointMathLib.fullMulDiv(first, 1e18, sharesFirst);
        uint256 secondPerShare = FixedPointMathLib.fullMulDiv(second, 1e18, uint256(sharesFirst) + sharesSecond);
        assertEq(
            almCore.getPendingReward(accountA),
            FixedPointMathLib.fullMulDiv(sharesFirst, firstPerShare + secondPerShare, 1e18)
        );
        assertEq(almCore.getPendingReward(accountB), FixedPointMathLib.fullMulDiv(sharesSecond, secondPerShare, 1e18));
    }

    function testFuzz_Success_checkpoint_ZeroSupplyAbsorbsDonation(
        PoolState memory poolState,
        uint96 donation,
        uint96 earned
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No supply yet, reward token donated to the vault before the first mint.
        donation = uint96(bound(donation, 1, type(uint96).max));
        deal(almCore.REWARD_TOKEN_(), address(almCore), donation);
        mockEarned(gauge, address(almCore), earned);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The high-water mark absorbed it and nothing accrued per share.
        assertEq(almCore.rewardPerShare_(), 0);
        assertEq(almCore.getRewardHighWater(), uint256(donation) + earned);
        assertEq(almCore.getClaimedCumulative(), donation);
        assertEq(almCore.getLastRewardBalance(), donation);
    }

    function testFuzz_Success_checkpoint_ZeroSupplyDonationDoesNotBrickTheFirstMint(
        PoolState memory poolState,
        uint96 donation,
        uint96 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Reward token donated to the vault before any share exists.
        deal(almCore.REWARD_TOKEN_(), address(almCore), bound(donation, 1, Constants.MAX_FUZZED_AMOUNT));
        shares = uint96(bound(shares, 1, type(uint96).max));

        // When: The first shares are minted, which checkpoints at zero supply.
        almCore.mintShares(deadAddress, shares);

        // Then: The mint went through and the donation is credited to nobody.
        assertEq(almCore.totalSupply(), shares);
        assertEq(almCore.getPendingReward(deadAddress), 0);
        assertEq(almCore.rewardPerShare_(), 0);
    }

    function testFuzz_Success_checkpoint_ZeroSupplyDonationStaysWithTheVault(
        PoolState memory poolState,
        uint96 donation,
        uint96 received,
        uint256 seedShares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A donation absorbed at zero supply.
        donation = uint96(bound(donation, 1, type(uint96).max));
        deal(almCore.REWARD_TOKEN_(), address(almCore), donation);

        // And: A first holder whose supply keeps the accumulator below its uint128 cap.
        received = uint96(bound(received, 1, type(uint96).max));
        uint256 floor = uint256(received) * 1e18 / type(uint128).max + 1;
        seedShares = bound(
            seedShares, floor > almCore.DEAD_SHARES_() + 1 ? floor : almCore.DEAD_SHARES_() + 1, type(uint96).max
        );
        almCore.mintShares(accountA, seedShares);

        // When: A later reward arrives against a live supply.
        deal(almCore.REWARD_TOKEN_(), address(almCore), uint256(donation) + received);
        almCore.updateRewards(accountA);

        // Then: Only the later reward reached the holder, through the accumulator.
        assertEq(
            almCore.getPendingReward(accountA),
            FixedPointMathLib.fullMulDiv(seedShares, FixedPointMathLib.fullMulDiv(received, 1e18, seedShares), 1e18)
        );
    }

    function testFuzz_Success_checkpoint_ZeroSupplyNeverLowersTheHighWaterMark(
        PoolState memory poolState,
        uint96 shares,
        uint96 earned,
        uint96 dropped
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A supply the reward per share fits, accrued against an earned amount.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max), Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        earned = uint96(bound(earned, 2, type(uint96).max));
        almCore.mintShares(accountA, shares);
        mockEarned(gauge, address(almCore), earned);
        almCore.checkpoint_();
        uint256 highWater = almCore.getRewardHighWater();

        // And: The supply is emptied and the earned amount falls.
        almCore.burnShares(accountA, shares);
        mockEarned(gauge, address(almCore), bound(dropped, 0, earned - 1));

        // When: Checkpointing at zero supply.
        almCore.checkpoint_();

        // Then: The high-water mark held.
        assertEq(almCore.getRewardHighWater(), highWater);
    }

    function testFuzz_Success_checkpoint_ClaimEmissionsCreditsTheEarnedAmountOnce(
        uint16 feeBps,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 emissions
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

        // And: A seeded vault holding it, past its window, emissions up to the ceiling.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        addEmissionsToGaugeCL(pool, gauge, bound(emissions, 2, Constants.MAX_EMISSIONS));
        closePenaltyWindow(gauge);
        uint256 earned = gauge.earned(address(almCore));

        // When: The vault claims and checkpoints.
        almCore.claimGaugeEmissions_();
        almCore.checkpoint_();

        // Then: The earned amount is credited once, net of the protocol fee rounded down.
        uint256 fee = earned * feeBps / 10_000;
        assertEq(almCore.getProtocolFeesReward(), fee);
        assertEq(almCore.getClaimedCumulative(), earned - fee);
        assertEq(almCore.getRewardHighWater(), earned - fee);

        // And: It is spread over the supply.
        assertEq(almCore.rewardPerShare_(), FixedPointMathLib.fullMulDiv(earned - fee, 1e18, coreState.supply));
    }

    function testFuzz_Success_checkpoint_PreCreditsHiddenEmissions(
        PoolState memory poolState,
        uint96 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee, a supply and a full penalty over a fuzzed window.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked range inside its penalty window.
        uint256 stakedBlock = vm.getBlockNumber();
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(stakedBlock + minStakeBlocks));

        // And: Emissions accrued inside the window, which the penalty hides.
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 hidden = hiddenEmissions(gauge, address(almCore), tokenIds);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The hidden emissions are pre-credited and spread over the supply.
        assertEq(almCore.getPreCredited(), hidden);
        assertEq(almCore.rewardPerShare_(), FixedPointMathLib.fullMulDiv(hidden, 1e18, shares));

        // And: The high water and the window end hold.
        assertEq(almCore.getRewardHighWater(), 0);
        assertEq(almCore.getWindowEnd(), stakedBlock + minStakeBlocks);
    }

    function testFuzz_Success_checkpoint_PreCreditIsNetOfTheEmissionFee(
        PoolState memory poolState,
        uint16 feeBps,
        uint96 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A fee within the ceiling, a supply, a full penalty, fuzzed window.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked range inside its penalty window.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));

        // And: Emissions accrued inside the window, which the penalty hides.
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 hidden = hiddenEmissions(gauge, address(almCore), tokenIds);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The hidden emissions are pre-credited net of the fee, rounded down.
        uint256 preCredit = hidden - hidden * feeBps / 10_000;
        assertEq(almCore.getPreCredited(), preCredit);
        assertEq(almCore.rewardPerShare_(), FixedPointMathLib.fullMulDiv(preCredit, 1e18, shares));
    }

    function testFuzz_Success_checkpoint_PreCreditAppliesTheReferral(
        PoolState memory poolState,
        uint96 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 referralShare,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee, a supply and a full penalty over a fuzzed window.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A referral taking a share of the gauge's emissions.
        setReferralConfig(gauge, makeAddr("referral"), bound(referralShare, 1, clGaugeFactory.maxShareCap()));

        // And: A staked range inside its penalty window.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));

        // And: Emissions accrued inside the window, which the penalty hides.
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 hidden = hiddenEmissions(gauge, address(almCore), tokenIds);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The pre-credit is the gauge's hidden emissions after the referral.
        assertEq(almCore.getPreCredited(), hidden);
        assertEq(almCore.rewardPerShare_(), FixedPointMathLib.fullMulDiv(hidden, 1e18, shares));
    }

    function testFuzz_Success_checkpoint_PenaltyRateBelowFull(
        PoolState memory poolState,
        uint96 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee, a supply and a partial penalty over a fuzzed window.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 1, MAX_PIPS - 1));

        // And: A staked range inside its penalty window.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));

        // And: Emissions accrued inside the window, part of them hidden by the penalty.
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 hidden = hiddenEmissions(gauge, address(almCore), tokenIds);
        uint256 earned = gauge.earned(address(almCore), tokenIds);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: Only the hidden part is pre-credited, the visible part is in high water.
        assertEq(almCore.getPreCredited(), hidden);
        assertEq(almCore.getRewardHighWater(), earned);

        // And: Both parts are spread over the supply in one step.
        assertEq(almCore.rewardPerShare_(), FixedPointMathLib.fullMulDiv(hidden + earned, 1e18, shares));
    }

    function testFuzz_Success_checkpoint_FoldsBeforeTheSpreadAtTheClose(
        PoolState memory poolState,
        uint96 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 blocks,
        uint256 emissionsInside,
        uint256 emissionsAfter
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee, a supply and a full penalty over a fuzzed window.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(2 * Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked range inside its penalty window.
        uint256 stakedBlock = vm.getBlockNumber();
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(stakedBlock + minStakeBlocks));

        // And: Emissions accrued inside the window, pre-credited.
        accrueForBlocks(
            pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissionsInside, 1, Constants.MAX_EMISSIONS)
        );
        uint256 hidden = hiddenEmissions(gauge, address(almCore), tokenIds);
        almCore.checkpoint_();

        // And: The window closed, with further emissions accrued.
        accrueForBlocks(
            pool,
            gauge,
            stakedBlock + minStakeBlocks - vm.getBlockNumber(),
            bound(emissionsAfter, 1, Constants.MAX_EMISSIONS)
        );
        uint256 earned = gauge.earned(address(almCore), tokenIds);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The pre-credit is folded into the high water, which reaches the visible.
        assertEq(almCore.getPreCredited(), 0);
        assertEq(almCore.getRewardHighWater(), earned);
        assertEq(almCore.getWindowEnd(), 0);

        // And: Only the emissions beyond the pre-credit are spread.
        assertEq(
            almCore.rewardPerShare_(),
            FixedPointMathLib.fullMulDiv(hidden, 1e18, shares)
                + FixedPointMathLib.fullMulDiv(earned - hidden, 1e18, shares)
        );
    }

    function testFuzz_Success_checkpoint_OneTokenClosesWhileAnotherGrows(
        PoolState memory poolState,
        uint96 shares,
        uint128 liquidityFirst,
        uint128 liquiditySecond,
        uint256 minStakeBlocks,
        uint256 blocksBetween,
        uint256 blocksInside,
        uint256 emissionsInside,
        uint256 emissionsAfter
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee, a supply, and a full penalty over a window of 2+ blocks.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(2 * Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A first staked range, and a second staked inside the first's window.
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] =
            stakeIntoRange(uint128(bound(liquidityFirst, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()) / 2)));
        vm.roll(vm.getBlockNumber() + bound(blocksBetween, 1, minStakeBlocks - 1));
        tokenIds[1] = stakeIntoRange(
            uint128(bound(liquiditySecond, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()) / 2))
        );
        almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));

        // And: Emissions accrued while both are inside their window, pre-credited.
        accrueForBlocks(
            pool,
            gauge,
            bound(blocksInside, 0, gauge.depositBlock(tokenIds[0]) + minStakeBlocks - 1 - vm.getBlockNumber()),
            bound(emissionsInside, 1, Constants.MAX_EMISSIONS)
        );
        uint256[3] memory amounts;
        amounts[0] = hiddenEmissions(gauge, address(almCore), tokenIds);
        almCore.checkpoint_();

        // And: The first window closed, the second open, and more emissions accrued.
        accrueForBlocks(
            pool,
            gauge,
            gauge.depositBlock(tokenIds[0]) + minStakeBlocks - vm.getBlockNumber(),
            bound(emissionsAfter, 1, Constants.MAX_EMISSIONS)
        );
        amounts[1] = hiddenEmissions(gauge, address(almCore), tokenIds);
        amounts[2] = earnedWithoutPenalty(gauge, address(almCore), tokenIds);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: Only the open window's emissions stay pre-credited, its end is kept.
        assertEq(almCore.getPreCredited(), amounts[1]);
        assertEq(almCore.getWindowEnd(), gauge.depositBlock(tokenIds[1]) + minStakeBlocks);

        // And: The high water reaches the closed window's emissions.
        assertEq(almCore.getRewardHighWater(), amounts[2] - amounts[1]);

        // And: Every emission accrued is spread once.
        assertEq(
            almCore.rewardPerShare_(),
            FixedPointMathLib.fullMulDiv(amounts[0], 1e18, shares)
                + FixedPointMathLib.fullMulDiv(amounts[2] - amounts[0], 1e18, shares)
        );
    }

    function testFuzz_Success_checkpoint_OverlappingWindowsSplitFairly(
        PoolState memory poolState,
        uint96 sharesA,
        uint96 sharesB,
        uint128 liquidityFirst,
        uint128 liquiditySecond,
        uint256 minStakeBlocks,
        uint256 blocks,
        uint256 emissionsFirst,
        uint256 emissionsBoth
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee, a first holder, a full penalty over two blocks or more.
        uint256 floor = FixedPointMathLib.max(
            FixedPointMathLib.fullMulDivUp(2 * Constants.MAX_EMISSIONS, 1e18, type(uint128).max), Constants.DEAD_SHARES
        );
        sharesA = uint96(bound(sharesA, floor, type(uint96).max));
        sharesB = uint96(bound(sharesB, floor, type(uint96).max));
        almCore.mintShares(accountA, sharesA);
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A first staked range inside its penalty window, with emissions accrued.
        uint256 hiddenFirst;
        uint256[] memory bothTokens = new uint256[](2);
        {
            uint256[] memory firstToken = new uint256[](1);
            firstToken[0] = stakeIntoRange(
                uint128(bound(liquidityFirst, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()) / 2))
            );
            bothTokens[0] = firstToken[0];
            almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));
            accrueForBlocks(
                pool, gauge, bound(blocks, 1, minStakeBlocks - 1), bound(emissionsFirst, 1, Constants.MAX_EMISSIONS)
            );
            hiddenFirst = hiddenEmissions(gauge, address(almCore), firstToken);
        }

        // And: A second holder joins inside the window.
        almCore.mintShares(accountB, sharesB);

        // And: A second range staked inside the first's window, emissions on both.
        bothTokens[1] = stakeIntoRange(
            uint128(bound(liquiditySecond, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()) / 2))
        );
        almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));
        accrueForBlocks(pool, gauge, 0, bound(emissionsBoth, 1, Constants.MAX_EMISSIONS));
        uint256 rewardPerShare = FixedPointMathLib.fullMulDiv(
            hiddenEmissions(gauge, address(almCore), bothTokens) - hiddenFirst, 1e18, uint256(sharesA) + sharesB
        );
        almCore.checkpoint_();

        // And: Both windows closed.
        closePenaltyWindow(gauge);

        // When: Both holders are credited.
        almCore.updateRewards(accountA);
        almCore.updateRewards(accountB);

        // Then: The second holder earned only its part of the credit after it joined.
        assertEq(almCore.getPendingReward(accountB), FixedPointMathLib.fullMulDiv(sharesB, rewardPerShare, 1e18));

        // And: The first holder earned the first credit alone and its part of the later.
        rewardPerShare += FixedPointMathLib.fullMulDiv(hiddenFirst, 1e18, sharesA);
        assertEq(almCore.getPendingReward(accountA), FixedPointMathLib.fullMulDiv(sharesA, rewardPerShare, 1e18));
    }

    function testFuzz_Success_checkpoint_ForfeitFoldsTheLostPreCredit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee and a penalty over a fuzzed window.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 1, MAX_PIPS));

        // And: A range around the price with a staked leg.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A seeded vault holding it, staked through the core, inside its window.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = range.stakedTokenId;

        // And: Emissions accrued inside the window, checkpointed.
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 hidden = hiddenEmissions(gauge, address(almCore), tokenIds);
        uint256 earned = gauge.earned(address(almCore), tokenIds);
        almCore.checkpoint_();

        // And: The keeper drains the staked side, accepting the penalty.
        runPlan(Plan.init().unstake(range.index, range.stakedTokenId, range.liquidityStaked, 0, 0, true));

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The forfeited pre-credit folds into the high water, above the visible.
        assertEq(almCore.getRewardHighWater(), earned + hidden);
        assertEq(almCore.getPreCredited(), 0);
        assertEq(almCore.getWindowEnd(), 0);

        // And: Nothing new is spread.
        assertEq(almCore.rewardPerShare_(), FixedPointMathLib.fullMulDiv(earned + hidden, 1e18, coreState.supply));
    }

    function testFuzz_Success_checkpoint_PenaltyRateLoweredFoldsThenSpreads(
        PoolState memory poolState,
        uint96 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 loweredRate,
        uint256 blocks,
        uint256 emissionsInside,
        uint256 emissionsAfter
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee, a supply, a penalty above the least rate, fuzzed window.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(2 * Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        penaltyRate = bound(penaltyRate, 2, MAX_PIPS);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: A staked range inside its penalty window.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));

        // And: Emissions accrued inside the window, checkpointed.
        accrueForBlocks(
            pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissionsInside, 1, Constants.MAX_EMISSIONS)
        );
        uint256 creditedBefore = earnedWithoutPenalty(gauge, address(almCore), tokenIds);
        almCore.checkpoint_();

        // And: The penalty rate is lowered inside the window, and more emissions accrue.
        setPenaltyConfig(minStakeBlocks, bound(loweredRate, 1, penaltyRate - 1));
        accrueForBlocks(pool, gauge, 0, bound(emissionsAfter, 1, Constants.MAX_EMISSIONS));
        uint256 hidden = hiddenEmissions(gauge, address(almCore), tokenIds);
        uint256 credited = earnedWithoutPenalty(gauge, address(almCore), tokenIds);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The pre-credit follows the hidden emissions, the rest is in high water.
        assertEq(almCore.getPreCredited(), hidden);
        assertEq(almCore.getRewardHighWater(), credited - hidden);

        // And: Only the emissions accrued since the first checkpoint are spread.
        uint256 rewardPerShare = FixedPointMathLib.fullMulDiv(creditedBefore, 1e18, shares);
        rewardPerShare += FixedPointMathLib.fullMulDiv(credited - creditedBefore, 1e18, shares);
        assertEq(almCore.rewardPerShare_(), rewardPerShare);
    }

    function testFuzz_Success_checkpoint_MinStakeBlocksRaisedPushesWindowEnd(
        PoolState memory poolState,
        uint96 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 raisedBlocks,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee, a supply and a full penalty over a fuzzed gauge window.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max - 1);
        setMinStakeBlocks(gauge, minStakeBlocks);

        // And: A staked range inside its penalty window.
        uint256 stakedBlock = vm.getBlockNumber();
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(stakedBlock + minStakeBlocks));

        // And: The gauge's window is raised.
        raisedBlocks = bound(raisedBlocks, minStakeBlocks + 1, type(uint32).max);
        setMinStakeBlocks(gauge, raisedBlocks);

        // And: Emissions accrued past the old window end, inside the new one.
        accrueForBlocks(
            pool, gauge, bound(blocks, minStakeBlocks, raisedBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS)
        );
        uint256 hidden = hiddenEmissions(gauge, address(almCore), tokenIds);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The window end moves to the raised window, hidden emissions pre-credited.
        assertEq(almCore.getWindowEnd(), stakedBlock + raisedBlocks);
        assertEq(almCore.getPreCredited(), hidden);
    }

    function testFuzz_Success_checkpoint_MinStakeBlocksLoweredFoldsEveryToken(
        PoolState memory poolState,
        uint96 shares,
        uint128 liquidityFirst,
        uint128 liquiditySecond,
        uint256 minStakeBlocks,
        uint256 loweredBlocks,
        uint256 blocksBetween,
        uint256 blocksInside,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee, a supply and a full penalty over at least two blocks.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        setMinStakeBlocks(gauge, minStakeBlocks);

        // And: Two staked ranges, the second staked inside the first's window.
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] =
            stakeIntoRange(uint128(bound(liquidityFirst, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()) / 2)));
        vm.roll(vm.getBlockNumber() + bound(blocksBetween, 0, minStakeBlocks - 2));
        tokenIds[1] = stakeIntoRange(
            uint128(bound(liquiditySecond, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()) / 2))
        );
        almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));

        // And: Emissions accrued while both are inside their window, pre-credited.
        accrueForBlocks(
            pool,
            gauge,
            bound(blocksInside, 1, gauge.depositBlock(tokenIds[0]) + minStakeBlocks - 1 - vm.getBlockNumber()),
            bound(emissions, 1, Constants.MAX_EMISSIONS)
        );
        uint256 hidden = hiddenEmissions(gauge, address(almCore), tokenIds);
        almCore.checkpoint_();

        // And: The gauge's window is lowered so that both windows have closed.
        setMinStakeBlocks(gauge, bound(loweredBlocks, 1, vm.getBlockNumber() - gauge.depositBlock(tokenIds[1])));

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: Every token's pre-credit is folded into the high water, the end cleared.
        assertEq(almCore.getPreCredited(), 0);
        assertEq(almCore.getWindowEnd(), 0);
        assertEq(almCore.getRewardHighWater(), hidden);

        // And: Nothing new is spread.
        assertEq(almCore.rewardPerShare_(), FixedPointMathLib.fullMulDiv(hidden, 1e18, shares));
    }

    function testFuzz_Success_checkpoint_WindowEndKeptWhileATokenEarnsNothingWithoutEmissions(
        PoolState memory poolState,
        uint96 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 blocks
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A supply and a full penalty over a fuzzed window.
        almCore.mintShares(accountA, bound(shares, almCore.DEAD_SHARES_(), type(uint96).max));
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked range inside its penalty window, the gauge streaming nothing.
        uint256 stakedBlock = vm.getBlockNumber();
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(stakedBlock + minStakeBlocks));
        vm.roll(vm.getBlockNumber() + bound(blocks, 0, minStakeBlocks - 1));

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The window end is kept while nothing is hidden or credited.
        assertEq(almCore.getWindowEnd(), stakedBlock + minStakeBlocks);
        assertEq(almCore.getPreCredited(), hiddenEmissions(gauge, address(almCore), tokenIds));
        assertEq(almCore.getPreCredited(), 0);
        assertEq(almCore.rewardPerShare_(), 0);
    }

    function testFuzz_Success_checkpoint_WindowEndKeptWhileATokenEarnsNothingOutOfRange(
        PoolState memory poolState,
        uint96 shares,
        uint128 liquidity,
        uint256 width,
        uint256 minStakeBlocks,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A supply and a full penalty over a fuzzed window.
        almCore.mintShares(accountA, bound(shares, almCore.DEAD_SHARES_(), type(uint96).max));
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked range above the price inside the band, inside its penalty window.
        int24 tickLower = (poolState.tickCurrent / poolState.tickSpacing + 1) * poolState.tickSpacing;
        width = bound(width, 1, uint24((bandTick(poolState.tickSpacing) - tickLower) / poolState.tickSpacing - 1));
        int24 tickUpper = tickLower + int24(int256(width)) * poolState.tickSpacing;
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(
            tickLower,
            tickUpper,
            uint128(
                bound(
                    liquidity,
                    Constants.MIN_FUZZED_LIQUIDITY,
                    liquidityCeiling(tickLower, tickUpper, Constants.MIN_FUZZED_LIQUIDITY)
                )
            )
        );
        almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));

        // And: Emissions streamed inside the window while the range is out of range.
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The window end is kept while nothing is hidden or credited.
        assertEq(almCore.getWindowEnd(), gauge.depositBlock(tokenIds[0]) + minStakeBlocks);
        assertEq(almCore.getPreCredited(), hiddenEmissions(gauge, address(almCore), tokenIds));
        assertEq(almCore.getPreCredited(), 0);
        assertEq(almCore.rewardPerShare_(), 0);
    }

    function testFuzz_Success_checkpoint_WindowEndClearedWhenNoTokenIsInside(
        PoolState memory poolState,
        uint96 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 blocks
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A supply and a full penalty over a fuzzed window.
        almCore.mintShares(accountA, bound(shares, almCore.DEAD_SHARES_(), type(uint96).max));
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked range whose penalty window closed after its end was written.
        stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));
        vm.roll(vm.getBlockNumber() + bound(blocks, minStakeBlocks, uint256(minStakeBlocks) + type(uint32).max));

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The window end is cleared and nothing is pre-credited.
        assertEq(almCore.getWindowEnd(), 0);
        assertEq(almCore.getPreCredited(), 0);
    }

    function testFuzz_Success_checkpoint_AnyStatusKeepsThePreCreditInsideTheWindow(
        PoolState memory poolState,
        uint96 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 blocksInside,
        uint256 blocksAfter,
        uint256 emissions,
        uint256 status
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee, a supply and a full penalty over a fuzzed window.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked range inside its penalty window.
        uint256 stakedBlock = vm.getBlockNumber();
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(stakedBlock + minStakeBlocks));

        // And: Emissions accrued inside the window, pre-credited.
        blocksInside = bound(blocksInside, 0, minStakeBlocks - 1);
        accrueForBlocks(pool, gauge, blocksInside, bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 hidden = hiddenEmissions(gauge, address(almCore), tokenIds);
        almCore.checkpoint_();

        // And: The chain status changes, still inside the window.
        setAnyStatus(status);
        vm.roll(vm.getBlockNumber() + bound(blocksAfter, 0, minStakeBlocks - 1 - blocksInside));

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The pre-credit and the window end are untouched.
        assertEq(almCore.getPreCredited(), hidden);
        assertEq(almCore.getWindowEnd(), stakedBlock + minStakeBlocks);

        // And: Nothing is folded or spread.
        assertEq(almCore.getRewardHighWater(), 0);
        assertEq(almCore.rewardPerShare_(), FixedPointMathLib.fullMulDiv(hidden, 1e18, shares));
    }

    function testFuzz_Success_checkpoint_ZeroSupplySetsThePreCreditWithoutARaise(
        PoolState memory poolState,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price, and no supply.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee and a full penalty over a fuzzed window.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked range inside its penalty window.
        uint256 stakedBlock = vm.getBlockNumber();
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(stakedBlock + minStakeBlocks));

        // And: Emissions accrued inside the window.
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 hidden = hiddenEmissions(gauge, address(almCore), tokenIds);

        // When: Checkpointing at zero supply.
        almCore.checkpoint_();

        // Then: The pre-credit is written while the accumulator stays.
        assertEq(almCore.getPreCredited(), hidden);
        assertEq(almCore.rewardPerShare_(), 0);
        assertEq(almCore.getRewardHighWater(), 0);
        assertEq(almCore.getWindowEnd(), stakedBlock + minStakeBlocks);
    }

    function testFuzz_Success_checkpoint_PreCreditWrapsTheAccumulator(
        PoolState memory poolState,
        uint64 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 blocks,
        uint256 emissions,
        uint256 headroom
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee and a full penalty over a fuzzed window.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked range inside its penalty window.
        uint256 stakedBlock = vm.getBlockNumber();
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));

        // And: Emissions accrued inside the window.
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 hidden = hiddenEmissions(gauge, address(almCore), tokenIds);
        // And: A wei or more hidden, a hole for accruals too small to hide one.
        vm.assume(hidden > 0);

        // And: A supply the hidden emissions cover at 1+ wei per share, window open.
        shares = uint64(bound(shares, almCore.DEAD_SHARES_(), FixedPointMathLib.min(type(uint64).max, hidden * 1e18)));
        almCore.mintShares(accountA, shares);
        almCore.setWindowEnd(uint48(stakedBlock + minStakeBlocks));

        // And: An accumulator closer to its width than the pre-credit's spread.
        uint256 spread = FixedPointMathLib.fullMulDiv(hidden, 1e18, shares);
        headroom = bound(headroom, 0, spread - 1);
        almCore.setRewardAccounting(type(uint128).max - headroom, 0, 0, 0);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The accumulator wraps to the spread less its headroom, pre-credit set.
        assertEq(almCore.rewardPerShare_(), spread - headroom - 1);
        assertEq(almCore.getPreCredited(), hidden);
    }

    function testFuzz_Success_checkpoint_CreditedNeverExceedsHighWaterPlusPreCredit(
        PoolState memory poolState,
        uint16 feeBps,
        uint96 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint8[8] memory actions,
        uint32[8] memory blocks,
        uint96[8] memory emissions,
        uint32[8] memory windows,
        uint24[8] memory rates
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A fee within the ceiling, a supply, a full penalty, fuzzed window.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(8 * Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked range inside its penalty window.
        stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));

        // When: The gauge accrues, its config moves and blocks pass, checkpointing each.
        address referral = makeAddr("referral");
        for (uint256 i; i < actions.length; ++i) {
            if (actions[i] % 4 == 0) {
                accrueForBlocks(pool, gauge, blocks[i], bound(emissions[i], 1, Constants.MAX_EMISSIONS));
            } else if (actions[i] % 4 == 1) {
                setPenaltyConfig(bound(windows[i], 1, type(uint32).max), bound(rates[i], 0, MAX_PIPS));
            } else if (actions[i] % 4 == 2) {
                setReferralConfig(gauge, referral, bound(rates[i], 0, clGaugeFactory.maxShareCap()));
            } else {
                vm.roll(vm.getBlockNumber() + blocks[i]);
            }
            almCore.checkpoint_();

            // Then: The credit spread never exceeds the high water plus the pre-credit.
            assertLe(
                FixedPointMathLib.fullMulDiv(almCore.rewardPerShare_(), shares, 1e18),
                almCore.getRewardHighWater() + almCore.getPreCredited()
            );
        }
    }

    function testFuzz_Success_checkpoint_OutOfRangeWindowTokenKeepsItsPreCredit(
        PoolState memory poolState,
        uint96 shares,
        RangeState memory range,
        uint256 minStakeBlocks,
        uint256[3] memory blocks,
        uint256[3] memory emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee, a supply and a full penalty over a fuzzed window.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(3 * Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked range two spacings under the band's top, inside its window.
        givenValidRangeState(range, poolState, true);
        range.tickUpper = int24(
            FixedPointMathLib.min(range.tickUpper, bandTick(poolState.tickSpacing) - 2 * poolState.tickSpacing)
        );
        uint256[3] memory values;
        values[0] = vm.getBlockNumber();
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(range.tickLower, range.tickUpper, range.liquidity);
        almCore.setWindowEnd(uint48(values[0] + minStakeBlocks));

        // And: Emissions accrued in range, pre-credited.
        accrueForBlocks(
            pool, gauge, bound(blocks[0], 0, (minStakeBlocks - 1) / 3), bound(emissions[0], 1, Constants.MAX_EMISSIONS)
        );
        values[1] = hiddenEmissions(gauge, address(almCore), tokenIds);
        almCore.checkpoint_();

        // And: The price leaves the range and emissions stream while it is out.
        parkAtTick(pool, users.unprivilegedAddress, range.tickUpper + poolState.tickSpacing);
        accrueForBlocks(
            pool, gauge, bound(blocks[1], 0, (minStakeBlocks - 1) / 3), bound(emissions[1], 1, Constants.MAX_EMISSIONS)
        );

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The pre-credit, the window end and the accumulator hold.
        assertEq(almCore.getPreCredited(), values[1]);
        assertEq(almCore.getWindowEnd(), values[0] + minStakeBlocks);
        assertEq(almCore.rewardPerShare_(), FixedPointMathLib.fullMulDiv(values[1], 1e18, shares));

        // And: Once the range earns again, the pre-credit follows the hidden part.
        parkAtTick(pool, users.unprivilegedAddress, range.tickLower + poolState.tickSpacing);
        accrueForBlocks(
            pool, gauge, bound(blocks[2], 0, (minStakeBlocks - 1) / 3), bound(emissions[2], 1, Constants.MAX_EMISSIONS)
        );
        values[2] = hiddenEmissions(gauge, address(almCore), tokenIds);
        // And: More hidden than before, a hole for accruals too small to add a wei.
        vm.assume(values[2] > values[1]);
        almCore.checkpoint_();
        assertEq(almCore.getPreCredited(), values[2]);
    }

    function testFuzz_Success_checkpoint_CrossingMovesTheHiddenPartToTheInRangeToken(
        PoolState memory poolState,
        uint96 shares,
        RangeState memory narrow,
        uint128 liquidityFull,
        uint256 minStakeBlocks,
        uint256 blocksInRange,
        uint256 blocksOut,
        uint256 emissionsInRange,
        uint256 emissionsOut
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee, a supply and a full penalty over a fuzzed window.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(2 * Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A range around the price and a full range, staked in one block.
        givenValidRangeState(narrow, poolState, true);
        uint256[][3] memory tokenIds = [new uint256[](1), new uint256[](1), new uint256[](2)];
        tokenIds[0][0] = stakeIntoRange(narrow.tickLower, narrow.tickUpper, narrow.liquidity);
        tokenIds[1][0] =
            stakeIntoRange(uint128(bound(liquidityFull, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        (tokenIds[2][0], tokenIds[2][1]) = (tokenIds[0][0], tokenIds[1][0]);
        almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));

        // And: Emissions accrued while both are in range, pre-credited.
        accrueForBlocks(
            pool,
            gauge,
            bound(blocksInRange, 0, (minStakeBlocks - 1) / 2),
            bound(emissionsInRange, 1, Constants.MAX_EMISSIONS)
        );
        uint256[4] memory hidden;
        hidden[0] = hiddenEmissions(gauge, address(almCore), tokenIds[0]);
        hidden[1] = hiddenEmissions(gauge, address(almCore), tokenIds[1]);
        hidden[2] = hiddenEmissions(gauge, address(almCore), tokenIds[2]);
        almCore.checkpoint_();

        // And: The price leaves the narrow range, not the full one, and emissions accrue.
        parkAtTick(pool, users.unprivilegedAddress, narrow.tickUpper + poolState.tickSpacing);
        accrueForBlocks(
            pool, gauge, bound(blocksOut, 0, (minStakeBlocks - 1) / 2), bound(emissionsOut, 1, Constants.MAX_EMISSIONS)
        );
        hidden[3] = hiddenEmissions(gauge, address(almCore), tokenIds[2]);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The pre-credit follows the hidden emissions of both ranges.
        assertEq(almCore.getPreCredited(), hidden[3]);

        // And: The narrow range's hidden part holds, the full range carries the new lump.
        assertEq(hiddenEmissions(gauge, address(almCore), tokenIds[0]), hidden[0]);
        assertEq(hiddenEmissions(gauge, address(almCore), tokenIds[1]) - hidden[1], hidden[3] - hidden[2]);
    }

    function testFuzz_Success_checkpoint_ReferralShareRaisedMidWindowFolds(
        PoolState memory poolState,
        uint16 feeBps,
        uint96 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 referralShare,
        uint256 raisedShare,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A fee within the ceiling, a supply, a full penalty, fuzzed window.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A referral share below the cap.
        referralShare = bound(referralShare, 0, clGaugeFactory.maxShareCap() - 1);
        setReferralConfig(gauge, makeAddr("referral"), referralShare);

        // And: A staked range inside its penalty window.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));

        // And: Emissions accrued inside the window, pre-credited.
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256[3] memory credits;
        credits[0] = earnedWithoutPenalty(gauge, address(almCore), tokenIds);
        almCore.checkpoint_();

        // And: The referral share is raised inside the window.
        setReferralConfig(
            gauge, makeAddr("referral"), bound(raisedShare, referralShare + 1, clGaugeFactory.maxShareCap())
        );
        credits[1] = credits[0] - earnedWithoutPenalty(gauge, address(almCore), tokenIds);
        credits[2] = hiddenEmissions(gauge, address(almCore), tokenIds);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The fold is the drop of the net hidden emissions.
        assertEq(
            almCore.getRewardHighWater(),
            credits[0] - credits[0] * feeBps / 10_000 - (credits[2] - credits[2] * feeBps / 10_000)
        );
        assertEq(almCore.getPreCredited(), credits[2] - credits[2] * feeBps / 10_000);

        // And: Nothing new is spread.
        assertEq(
            almCore.rewardPerShare_(),
            FixedPointMathLib.fullMulDiv(credits[0] - credits[0] * feeBps / 10_000, 1e18, shares)
        );
    }

    function testFuzz_Success_checkpoint_PenaltyRateRaisedRepaysFromFutureEmissions(
        PoolState memory poolState,
        uint16 feeBps,
        uint96 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 raisedRate,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee within the ceiling, a supply and a partial penalty.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS - 1);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: A staked range inside its penalty window.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));

        // And: Emissions accrued inside the window, checkpointed.
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        almCore.checkpoint_();

        // And: The penalty rate is raised inside the window and checkpointed.
        uint256 earned = gauge.earned(address(almCore), tokenIds);
        setPenaltyConfig(minStakeBlocks, bound(raisedRate, penaltyRate + 1, MAX_PIPS));
        uint256 hidden = hiddenEmissions(gauge, address(almCore), tokenIds);
        almCore.checkpoint_();

        // And: The window closed.
        closePenaltyWindow(gauge);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: The high water is the net earned before the raise plus the net hidden.
        assertEq(almCore.getRewardHighWater(), earned - earned * feeBps / 10_000 + hidden - hidden * feeBps / 10_000);

        // And: The window state is cleared.
        assertEq(almCore.getPreCredited(), 0);
        assertEq(almCore.getWindowEnd(), 0);
    }

    function testFuzz_Success_checkpoint_RewardPoolTokenNetOfTheReserve(
        PoolState memory poolState,
        bool isToken0,
        uint96 shares,
        uint96 reserve,
        uint96 received
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A supply.
        shares = uint96(
            bound(
                shares,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(received, 1e18, type(uint128).max), Constants.DEAD_SHARES
                ),
                type(uint96).max
            )
        );
        almCore.mintShares(accountA, shares);

        // And: The reward token is a pool token, with a buffer of it.
        almCore.setRewardPoolToken(isToken0 ? 1 : 2);
        almCore.setBuffers(isToken0 ? reserve : 0, isToken0 ? 0 : reserve);

        // And: Reward token arrived beside the buffer.
        deal(almCore.REWARD_TOKEN_(), address(almCore), uint256(reserve) + received);

        // When: Checkpointing.
        almCore.checkpoint_();

        // Then: Only the reward token beyond the buffer is measured and credited.
        assertEq(almCore.getLastRewardBalance(), received);
        assertEq(almCore.getClaimedCumulative(), received);
    }
}
