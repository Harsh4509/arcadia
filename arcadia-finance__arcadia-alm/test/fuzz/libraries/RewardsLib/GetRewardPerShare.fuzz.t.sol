/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { RewardsLib_Fuzz_Test } from "./_RewardsLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "getRewardPerShare" of library "RewardsLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetRewardPerShare_RewardsLib_Fuzz_Test is RewardsLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(RewardsLib_Fuzz_Test) {
        RewardsLib_Fuzz_Test.setUp();
        setSpotPoolState();
        deployRewardsLib();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getRewardPerShare_NoWindow_CreditsTheRiseOverTheHighWater(
        uint128 rewardPerShare,
        uint128 highWater,
        uint128 preCredited,
        uint256 total,
        uint256 supply
    ) public {
        // Given: A reward state with no window open.
        rewardsLib.setRewards(rewardPerShare, highWater, 0, 0, 0);
        rewardsLib.setPreCredited(preCredited);

        // And: A supply, a lifetime reward at or above the high water, its step fitting.
        supply = bound(supply, 1, type(uint128).max);
        total = bound(total, highWater, highWater + FixedPointMathLib.fullMulDiv(supply, type(uint128).max, 1e18));

        // When: Getting the reward per share.
        (uint128 rewardPerShareAfter, uint256 highWaterAfter, uint256 preCreditedAfter, uint48 windowEnd) =
            rewardsLib.getRewardPerShare(supply, total);

        // Then: The rise over the high water is spread over the supply.
        uint128 step = uint128(FixedPointMathLib.fullMulDiv(total - highWater, 1e18, supply));
        unchecked {
            assertEq(rewardPerShareAfter, rewardPerShare + step);
        }

        // And: The high water is the lifetime reward, pre-credit and window untouched.
        assertEq(highWaterAfter, total);
        assertEq(preCreditedAfter, preCredited);
        assertEq(windowEnd, 0);
    }

    function testFuzz_Success_getRewardPerShare_NoWindow_TotalAtOrBelowTheHighWater(
        uint128 rewardPerShare,
        uint128 highWater,
        uint256 total,
        uint256 supply
    ) public {
        // Given: No window open, and a lifetime reward at or below the high water.
        rewardsLib.setRewards(rewardPerShare, highWater, 0, 0, 0);
        total = bound(total, 0, highWater);

        // When: Getting the reward per share.
        (uint128 rewardPerShareAfter, uint256 highWaterAfter,, uint48 windowEnd) =
            rewardsLib.getRewardPerShare(supply, total);

        // Then: Nothing is credited.
        assertEq(rewardPerShareAfter, rewardPerShare);
        assertEq(highWaterAfter, highWater);
        assertEq(windowEnd, 0);
    }

    function testFuzz_Success_getRewardPerShare_NoWindow_ZeroSupply(
        uint128 rewardPerShare,
        uint128 highWater,
        uint256 total
    ) public {
        // Given: No window open, and a lifetime reward above the high water.
        rewardsLib.setRewards(rewardPerShare, highWater, 0, 0, 0);
        total = bound(total, uint256(highWater) + 1, type(uint256).max);

        // When: Getting the reward per share with no supply.
        (uint128 rewardPerShareAfter, uint256 highWaterAfter,,) = rewardsLib.getRewardPerShare(0, total);

        // Then: The reward per share holds, the high water rises to the lifetime reward.
        assertEq(rewardPerShareAfter, rewardPerShare);
        assertEq(highWaterAfter, total);
    }

    function testFuzz_Success_getRewardPerShare_Window_PreCreditsTheHiddenRise(
        uint128 rewardPerShare,
        uint128 highWater,
        uint16 feeBps,
        uint256 supply,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A reward state with no pre-credit, an emission fee and a supply.
        rewardsLib.setRewards(rewardPerShare, highWater, 0, 0, 0);
        feeBps = uint16(bound(feeBps, 0, ConfigLib.MAX_FEE_BPS));
        rewardsLib.setProtocolEmissionFeeBps(feeBps);
        supply = bound(
            supply,
            FixedPointMathLib.fullMulDivUp(Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
            Constants.MAX_FUZZED_AMOUNT
        );

        // And: A staked range inside a full penalty window, with emissions accrued.
        uint256 hidden;
        uint256 stakedBlock;
        {
            minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
            setPenaltyConfig(minStakeBlocks, MAX_PIPS);
            liquidity = uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing())));
            Range memory range = stakeIntoRange(pool, gauge, users.liquidityProvider, TICK_LOWER, TICK_UPPER, liquidity);
            rewardsLib.pushRange(range);
            stakedBlock = range.stakedBlock;
            rewardsLib.setWindowEnd(uint48(stakedBlock + minStakeBlocks));
            accrueForBlocks(
                pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS)
            );
            uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = range.stakedTokenId;
            hidden = hiddenEmissions(gauge, users.liquidityProvider, tokenIds);
        }

        // When: Getting the reward per share at the high water.
        // Then: The high water holds, and the window ends where the stake's does.
        {
            (, uint256 highWaterAfter,, uint48 windowEnd) = rewardsLib.getRewardPerShare(supply, highWater);
            assertEq(highWaterAfter, highWater);
            assertEq(windowEnd, stakedBlock + minStakeBlocks);
        }

        // And: The hidden emissions net of the fee are pre-credited and spread.
        (uint128 rewardPerShareAfter,, uint256 preCredited,) = rewardsLib.getRewardPerShare(supply, highWater);
        hidden -= hidden * feeBps / ConfigLib.BPS_DENOMINATOR;
        assertEq(preCredited, hidden);
        unchecked {
            assertEq(rewardPerShareAfter, rewardPerShare + uint128(FixedPointMathLib.fullMulDiv(hidden, 1e18, supply)));
        }
    }

    function testFuzz_Success_getRewardPerShare_Window_FoldsAHiddenDropIntoTheHighWater(
        uint128 rewardPerShare,
        uint128 highWater,
        uint128 preCredited,
        uint256 total,
        uint256 supply,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 emissions
    ) public {
        // Given: A staked range inside its penalty window, with emissions accrued.
        uint256 hidden;
        {
            minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
            setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 1, MAX_PIPS));
            Range memory range = stakeIntoRange(
                pool, gauge, users.liquidityProvider, TICK_LOWER, TICK_UPPER, Constants.MIN_FUZZED_LIQUIDITY
            );
            rewardsLib.pushRange(range);
            rewardsLib.setWindowEnd(uint48(range.stakedBlock + minStakeBlocks));
            addEmissionsToGaugeCL(pool, gauge, bound(emissions, 1, Constants.MAX_EMISSIONS));
            uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = range.stakedTokenId;
            hidden = hiddenEmissions(gauge, users.liquidityProvider, tokenIds);
        }

        // And: A pre-credit above the hidden, a lifetime reward at most the high water.
        preCredited = uint128(bound(preCredited, hidden + 1, type(uint128).max));
        rewardsLib.setRewards(rewardPerShare, highWater, 0, 0, 0);
        rewardsLib.setPreCredited(preCredited);
        total = bound(total, 0, highWater);

        // When: Getting the reward per share.
        (uint128 rewardPerShareAfter, uint256 highWaterAfter, uint256 preCreditedAfter,) =
            rewardsLib.getRewardPerShare(supply, total);

        // Then: The drop is folded into the high water, nothing credited.
        assertEq(highWaterAfter, uint256(highWater) + preCredited - hidden);
        assertEq(preCreditedAfter, hidden);
        assertEq(rewardPerShareAfter, rewardPerShare);
    }
}
