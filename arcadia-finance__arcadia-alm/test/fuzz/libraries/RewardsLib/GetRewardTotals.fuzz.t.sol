/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IMetadexCLGauge } from "../../../../src/interfaces/IMetadexCLGauge.sol";
import { RewardsLib_Fuzz_Test } from "./_RewardsLib.fuzz.t.sol";
import { stdError } from "@forge-std/StdError.sol";

/**
 * @notice Fuzz tests for the function "getRewardTotals" of library "RewardsLib".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract GetRewardTotals_RewardsLib_Fuzz_Test is RewardsLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getRewardTotals_BalanceBelowMeasured(
        PoolState memory poolState,
        uint128 measured,
        uint256 balance
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A reward balance below the balance last measured.
        deployRewardsLib();
        measured = uint128(bound(measured, 1, type(uint128).max));
        rewardsLib.setRewards(0, 0, 0, measured, 0);
        deal(almCore.REWARD_TOKEN_(), address(rewardsLib), bound(balance, 0, uint256(measured) - 1));

        // When: Reading the totals.
        // Then: It reverts on the underflow.
        vm.expectRevert(stdError.arithmeticError);
        rewardsLib.getRewardTotals();
    }

    function testFuzz_Success_getRewardTotals_RewardNetOfTheFee(
        PoolState memory poolState,
        uint128 claimed,
        uint128 measured,
        uint128 received,
        uint16 feeBps,
        uint256 status
    ) public {
        // Given: A pool with depth at a fuzzed price, on a chain the gauge mints on.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        setMintableStatus(status);

        // And: A core with no ranges, at an emission fee within the ceiling.
        deployRewardsLib();
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        rewardsLib.setProtocolEmissionFeeBps(feeBps);

        // And: A reward balance that grew since it was last measured.
        rewardsLib.setRewards(0, 0, claimed, measured, 0);
        deal(almCore.REWARD_TOKEN_(), address(rewardsLib), uint256(measured) + received);

        // When: Reading the totals.
        (uint256 receivedRead, uint256 protocolFee, uint256 total) = rewardsLib.getRewardTotals();

        // Then: The reward is measured and the protocol's fee on it rounds down.
        uint256 fee = uint256(received) * feeBps / 10_000;
        assertEq(receivedRead, received);
        assertEq(protocolFee, fee);

        // And: The lifetime reward adds the net reward, the gauge owing nothing.
        assertEq(total, uint256(claimed) + received - fee);
    }

    function testFuzz_Success_getRewardTotals_UnstakedReadsTheDeferredEmissions(
        PoolState memory poolState,
        uint128 claimed,
        uint128 deferred,
        uint16 feeBps,
        uint256 status
    ) public {
        // Given: A pool with depth at a fuzzed price, on any chain status.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        setAnyStatus(status);

        // And: A core with no staked range and no new reward, at a capped emission fee.
        deployRewardsLib();
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        rewardsLib.setProtocolEmissionFeeBps(feeBps);
        rewardsLib.setRewards(0, 0, claimed, 0, 0);

        // And: The gauge reporting deferred emissions for the core.
        vm.mockCall(
            address(gauge),
            abi.encodeWithSelector(IMetadexCLGauge.deferredEmissions.selector, address(rewardsLib)),
            abi.encode(deferred)
        );

        // When: Reading the totals.
        (,, uint256 total) = rewardsLib.getRewardTotals();

        // Then: The lifetime reward adds the deferred emissions net of fee, rounded down.
        assertEq(total, uint256(claimed) + deferred - uint256(deferred) * feeBps / 10_000);
    }

    function testFuzz_Success_getRewardTotals_MatchesThePostCheckpointTotal(
        PoolState memory poolState,
        uint128 claimed,
        uint128 measured,
        uint128 received,
        uint256 bps,
        uint256 supply,
        uint256 status
    ) public {
        // Given: A pool with depth at a fuzzed price, on any chain status.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        setAnyStatus(status);

        // And: A core with no ranges, at an odd emission fee within the ceiling.
        deployRewardsLib();
        bps = bound(bps, 0, (ConfigLib.MAX_FEE_BPS - 1) / 2) * 2 + 1;
        rewardsLib.setProtocolEmissionFeeBps(uint16(bps));

        // And: A reward balance grown since last measured, the totals fitting a uint128.
        received = uint128(bound(received, 0, type(uint128).max));
        measured = uint128(bound(measured, 0, type(uint128).max - received));
        claimed = uint128(bound(claimed, 0, type(uint128).max - received));
        rewardsLib.setRewards(0, 0, claimed, measured, 0);
        deal(almCore.REWARD_TOKEN_(), address(rewardsLib), uint256(measured) + received);

        // And: The totals read before the checkpoint.
        (, uint256 protocolFee, uint256 total) = rewardsLib.getRewardTotals();

        // When: Checkpointing at a supply the reward per share fits.
        rewardsLib.checkpoint(
            bound(
                supply,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(uint256(claimed) + received, 1e18, type(uint128).max), 1
                ),
                type(uint128).max
            )
        );

        // Then: The checkpoint reaches the total read to the wei, and accrues the fee.
        (, uint128 highWater, uint128 claimedAfter,, uint128 protocolFees) = rewardsLib.getRewards();
        assertEq(claimedAfter, total);
        assertEq(highWater, total);
        assertEq(protocolFees, protocolFee);
    }

    function testFuzz_Success_getRewardTotals_InWindowTokensReadPenalised(
        PoolState memory poolState,
        uint16 feeBps,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee within the ceiling, a full penalty over a fuzzed window.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked range inside its penalty window, with emissions accrued.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 credited = earnedWithoutPenalty(gauge, address(almCore), tokenIds);
        // And: Two wei or more credited, a hole for accruals too small to credit them.
        vm.assume(credited >= 2);

        // And: A penalty rate that hides at least two wei of them.
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, FixedPointMathLib.divUp(2 * MAX_PIPS, credited), MAX_PIPS));
        uint256 earned = gauge.earned(address(almCore), tokenIds);

        // When: Reading the totals.
        (,, uint256 total) = almCore.getRewardTotals();

        // Then: The lifetime reward reads the penalised earned amount, net of the fee.
        assertEq(total, earned - earned * feeBps / 10_000);
        assertLt(total, credited - credited * feeBps / 10_000);
    }
}
