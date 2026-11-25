/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { EmissionsLogic_Fuzz_Test } from "./_EmissionsLogic.fuzz.t.sol";
import { ILeafVoter } from "../../../../src/interfaces/ILeafVoter.sol";
import { IMetadexCLGauge } from "../../../../src/interfaces/IMetadexCLGauge.sol";
import { Range } from "../../../../src/core/types/Range.sol";

/**
 * @notice Fuzz tests for the function "getHiddenEmissions" of library "EmissionsLogic".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetHiddenEmissions_EmissionsLogic_Fuzz_Test is EmissionsLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(EmissionsLogic_Fuzz_Test) {
        EmissionsLogic_Fuzz_Test.setUp();
        deployStakedPool();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getHiddenEmissions_MatchesGaugeEarnedWithoutThePenalty(
        uint128 fullLiquidity,
        uint128 narrowLiquidity,
        int24 tickLower,
        int24 tickUpper,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A live penalty config.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: A full-range range and a range around the price, staked in one block.
        uint128 maxLiquidity = tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()) / 2;
        tickLower = int24(bound(tickLower, TICK_LOWER / TICK_SPACING, -1)) * TICK_SPACING;
        tickUpper = int24(bound(tickUpper, 1, TICK_UPPER / TICK_SPACING)) * TICK_SPACING;
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = stakeIntoRange(TICK_LOWER, TICK_UPPER, uint128(bound(fullLiquidity, 1, maxLiquidity)));
        tokenIds[1] = stakeIntoRange(tickLower, tickUpper, uint128(bound(narrowLiquidity, 1, maxLiquidity)));

        // And: Emissions settled into the pool inside the window.
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 2, Constants.MAX_EMISSIONS));

        // When: Reading the hidden emissions.
        (uint256 hidden, uint48 windowEnd) =
            emissionsLogic.getHiddenEmissions(address(gauge), address(clGaugeFactory), address(leafVoter));

        // Then: They are the gauge's earnings without the penalty minus those with it.
        assertEq(hidden, hiddenEmissions(gauge, users.liquidityProvider, tokenIds));

        // And: The window ends where the stakes' window does.
        assertEq(windowEnd, gauge.depositBlock(tokenIds[0]) + minStakeBlocks);
    }

    function testFuzz_Success_getHiddenEmissions_ProjectsTheVoterShare(
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 emissions
    ) public {
        // Given: A full penalty over a fuzzed window.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked full-range range.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(
            TICK_LOWER, TICK_UPPER, uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing())))
        );

        // And: Emissions the voter holds for the gauge, not settled into the pool.
        uint256 growth = pool.rewardGrowthGlobalX128();
        addEmissionsToGauge(address(gauge), bound(emissions, 2, Constants.MAX_EMISSIONS));

        // When: Reading the hidden emissions.
        (uint256 hidden,) =
            emissionsLogic.getHiddenEmissions(address(gauge), address(clGaugeFactory), address(leafVoter));

        // Then: They match the gauge's own projection and are not zero.
        assertEq(hidden, hiddenEmissions(gauge, users.liquidityProvider, tokenIds));
        assertGt(hidden, 0);

        // And: The pool's reward growth never moved.
        assertEq(pool.rewardGrowthGlobalX128(), growth);
    }

    function testFuzz_Success_getHiddenEmissions_ProjectsTheVoterShareAboveTheSettledShare(
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 settled,
        uint256 emissions
    ) public {
        // Given: A full penalty over a fuzzed window.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked full-range range, with emissions settled into the pool.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(
            TICK_LOWER, TICK_UPPER, uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing())))
        );
        addEmissionsToGaugeCL(pool, gauge, bound(settled, 2, Constants.MAX_EMISSIONS));

        // And: More emissions the voter holds for the gauge, not settled into the pool.
        addEmissionsToGauge(address(gauge), bound(emissions, 2, Constants.MAX_EMISSIONS));

        // When: Reading the hidden emissions.
        (uint256 hidden,) =
            emissionsLogic.getHiddenEmissions(address(gauge), address(clGaugeFactory), address(leafVoter));

        // Then: They match the gauge's own projection.
        assertEq(hidden, hiddenEmissions(gauge, users.liquidityProvider, tokenIds));

        // And: The projection started from a settled share and growth.
        assertGt(IMetadexCLGauge(address(gauge)).lastCumulativeRewardShare(), 0);
        assertGt(pool.rewardGrowthGlobalX128(), 0);
    }

    function testFuzz_Success_getHiddenEmissions_AProjectionBelowTheSettledShareAddsNothing(
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 settled,
        uint256 projected
    ) public {
        // Given: A full penalty over a fuzzed window.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked full-range range, with emissions settled into the pool.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(
            TICK_LOWER, TICK_UPPER, uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing())))
        );
        addEmissionsToGaugeCL(pool, gauge, bound(settled, 2, Constants.MAX_EMISSIONS));
        uint256 hiddenSettled = hiddenEmissions(gauge, users.liquidityProvider, tokenIds);

        // And: A voter projecting below the settled share, as for an unregistered gauge.
        uint256 last = IMetadexCLGauge(address(gauge)).lastCumulativeRewardShare();
        vm.mockCall(
            address(leafVoter),
            abi.encodeCall(ILeafVoter.projectedCumulativeRewardShare, (address(gauge))),
            abi.encode(bound(projected, 0, last - 1))
        );

        // When: Reading the hidden emissions.
        (uint256 hidden,) =
            emissionsLogic.getHiddenEmissions(address(gauge), address(clGaugeFactory), address(leafVoter));

        // Then: They are those of the settled growth alone, as the gauge sees them.
        assertEq(hidden, hiddenSettled);
        assertEq(hidden, hiddenEmissions(gauge, users.liquidityProvider, tokenIds));
    }

    function testFuzz_Success_getHiddenEmissions_ZeroOutsideTheWindow(
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 emissions,
        uint256 blocksPassed
    ) public {
        // Given: A live penalty config.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: A staked full-range range, with emissions settled inside its window.
        stakeIntoRange(
            TICK_LOWER, TICK_UPPER, uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing())))
        );
        addEmissionsToGaugeCL(pool, gauge, bound(emissions, 2, Constants.MAX_EMISSIONS));

        // And: At least the window has passed.
        vm.roll(vm.getBlockNumber() + bound(blocksPassed, minStakeBlocks, type(uint32).max));

        // And: A drained range, its staked side burned in this block.
        emissionsLogic.pushRange(
            Range({
                stakedLiquidity: 0,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                unstakedTokenId: 0,
                stakedTokenId: 0,
                stakedBlock: uint48(vm.getBlockNumber())
            })
        );

        // When: Reading the hidden emissions.
        (uint256 hidden, uint48 windowEnd) =
            emissionsLogic.getHiddenEmissions(address(gauge), address(clGaugeFactory), address(leafVoter));

        // Then: Nothing is hidden and no window is open.
        assertEq(hidden, 0);
        assertEq(windowEnd, 0);
    }

    function testFuzz_Success_getHiddenEmissions_ExcludesDeferredEmissions(
        uint128 deferredLiquidity,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 deferred,
        uint256 blocks,
        uint256 emissions,
        uint256 pick
    ) public {
        // Given: A full penalty over a fuzzed window.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A first staked full range past its window, with emissions settled.
        uint128 maxLiquidity = tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()) / 2;
        (uint256 deferredId,) = mintPosition(
            pool, users.liquidityProvider, TICK_LOWER, TICK_UPPER, uint128(bound(deferredLiquidity, 1, maxLiquidity))
        );
        stake(gauge, users.liquidityProvider, deferredId);
        closePenaltyWindow(gauge);
        addEmissionsToGaugeCL(pool, gauge, bound(deferred, 2, Constants.MAX_EMISSIONS));

        // And: The first range withdrawn while the chain does not mint, deferring.
        setNotMintableStatus(pick);
        vm.prank(users.liquidityProvider);
        gauge.withdraw(deferredId);
        setMintableStatus(pick);

        // And: A second staked full range, with emissions settled inside its window.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(TICK_LOWER, TICK_UPPER, uint128(bound(liquidity, 1, maxLiquidity)));
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 2, Constants.MAX_EMISSIONS));

        // When: Reading the hidden emissions.
        (uint256 hidden,) =
            emissionsLogic.getHiddenEmissions(address(gauge), address(clGaugeFactory), address(leafVoter));

        // Then: They match the gauge's own math.
        assertEq(hidden, hiddenEmissions(gauge, users.liquidityProvider, tokenIds));

        // And: The deferred emissions are not part of them.
        uint256 deferredEmissions = gauge.deferredEmissions(users.liquidityProvider);
        assertGt(deferredEmissions, 0);
        assertEq(hidden, earnedWithoutPenalty(gauge, users.liquidityProvider, tokenIds) - deferredEmissions);
    }

    function testFuzz_Success_getHiddenEmissions_ReferralAppliedAfterThePenalty(
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        address referral,
        uint256 share,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A live penalty config.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: A referral taking a share of what the gauge pays.
        vm.assume(referral != address(0));
        clGaugeFactory.setMaxShareCap(MAX_PIPS);
        setReferralConfig(gauge, referral, bound(share, 1, MAX_PIPS));

        // And: A staked full-range range, with emissions settled inside its window.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(
            TICK_LOWER, TICK_UPPER, uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing())))
        );
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 2, Constants.MAX_EMISSIONS));

        // When: Reading the hidden emissions.
        (uint256 hidden,) =
            emissionsLogic.getHiddenEmissions(address(gauge), address(clGaugeFactory), address(leafVoter));

        // Then: They match the gauge's math, the referral cut taken after the penalty.
        assertEq(hidden, hiddenEmissions(gauge, users.liquidityProvider, tokenIds));
    }

    function testFuzz_Success_getHiddenEmissions_PartialPenaltyHidesOnlyTheRate(
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A partial penalty over a fuzzed window.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS - 1);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: A staked full-range range, with emissions settled inside its window.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(
            TICK_LOWER, TICK_UPPER, uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing())))
        );
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 2, Constants.MAX_EMISSIONS));

        // When: Reading the hidden emissions.
        (uint256 hidden,) =
            emissionsLogic.getHiddenEmissions(address(gauge), address(clGaugeFactory), address(leafVoter));

        // Then: Only the penalty rate of the accrued emissions is hidden.
        assertEq(hidden, earnedWithoutPenalty(gauge, users.liquidityProvider, tokenIds) * penaltyRate / MAX_PIPS);
        assertEq(hidden, hiddenEmissions(gauge, users.liquidityProvider, tokenIds));
    }

    function testFuzz_Success_getHiddenEmissions_WindowEndIsTheLatestStakeWhateverTheOrder(
        uint128 earlyLiquidity,
        uint128 lateLiquidity,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocksBetween,
        uint256 emissions
    ) public {
        // Given: A live penalty config, its window at least two blocks long.
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: A range staked first, its window still open when the second is staked.
        uint128 maxLiquidity = tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()) / 2;
        (uint256 earlyTokenId, uint128 earlyLiquidityMinted) = mintPosition(
            pool, users.liquidityProvider, TICK_LOWER, TICK_UPPER, uint128(bound(earlyLiquidity, 1, maxLiquidity))
        );
        stake(gauge, users.liquidityProvider, earlyTokenId);

        // And: A range staked later inside that window, pushed at the lower index.
        vm.roll(vm.getBlockNumber() + bound(blocksBetween, 1, minStakeBlocks - 1));
        uint256 lateTokenId = stakeIntoRange(TICK_LOWER, TICK_UPPER, uint128(bound(lateLiquidity, 1, maxLiquidity)));

        // And: The earlier range pushed after it, so its stake has a higher index.
        emissionsLogic.pushRange(
            Range({
                stakedLiquidity: earlyLiquidityMinted,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                unstakedTokenId: 0,
                stakedTokenId: uint80(earlyTokenId),
                stakedBlock: uint48(gauge.depositBlock(earlyTokenId))
            })
        );

        // And: Emissions settled into the pool.
        addEmissionsToGaugeCL(pool, gauge, bound(emissions, 2, Constants.MAX_EMISSIONS));

        // When: Reading the hidden emissions.
        (uint256 hidden, uint48 windowEnd) =
            emissionsLogic.getHiddenEmissions(address(gauge), address(clGaugeFactory), address(leafVoter));

        // Then: The window ends with the later stake's window, not the last pushed range.
        assertEq(windowEnd, gauge.depositBlock(lateTokenId) + minStakeBlocks);

        // And: The hidden emissions match the gauge's own math.
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = lateTokenId;
        tokenIds[1] = earlyTokenId;
        assertEq(hidden, hiddenEmissions(gauge, users.liquidityProvider, tokenIds));
    }

    function testFuzz_Success_getHiddenEmissions_NoStakedLiquidityInPoolSkipsTheProjection(
        uint128 liquidity,
        int24 tickLower,
        int24 tickUpper,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 emissions
    ) public {
        // Given: A live penalty config.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: A staked range above the price, so the pool holds no staked liquidity.
        tickLower = int24(bound(tickLower, 1, TICK_UPPER / TICK_SPACING - 1)) * TICK_SPACING;
        tickUpper = int24(bound(tickUpper, tickLower / TICK_SPACING + 1, TICK_UPPER / TICK_SPACING)) * TICK_SPACING;
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(
            tickLower, tickUpper, uint128(bound(liquidity, 2, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing())))
        );

        // And: Emissions the voter holds for the gauge, not settled into the pool.
        addEmissionsToGauge(address(gauge), bound(emissions, 2, Constants.MAX_EMISSIONS));

        // When: Reading the hidden emissions.
        (uint256 hidden, uint48 windowEnd) =
            emissionsLogic.getHiddenEmissions(address(gauge), address(clGaugeFactory), address(leafVoter));

        // Then: Nothing is hidden, as the gauge sees it.
        assertEq(hidden, 0);
        assertEq(hidden, hiddenEmissions(gauge, users.liquidityProvider, tokenIds));

        // And: The range's window is still open.
        assertEq(windowEnd, gauge.depositBlock(tokenIds[0]) + minStakeBlocks);

        // And: The pool holds no staked liquidity.
        assertEq(pool.stakedLiquidity(), 0);
    }

    function testFuzz_Success_getHiddenEmissions_NotMintable(
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocks,
        uint256 emissions,
        uint256 pick
    ) public {
        // Given: A live penalty config.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: A staked full-range range, with emissions settled inside its window.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(
            TICK_LOWER, TICK_UPPER, uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing())))
        );
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 2, Constants.MAX_EMISSIONS));
        uint256 hiddenMintable = hiddenEmissions(gauge, users.liquidityProvider, tokenIds);

        // And: A chain that does not mint.
        setNotMintableStatus(pick);

        // When: Reading the hidden emissions.
        (uint256 hidden, uint48 windowEnd) =
            emissionsLogic.getHiddenEmissions(address(gauge), address(clGaugeFactory), address(leafVoter));

        // Then: They match the gauge's own math, as on a chain that mints.
        assertEq(hidden, hiddenEmissions(gauge, users.liquidityProvider, tokenIds));
        assertEq(hidden, hiddenMintable);

        // And: The window ends where the stake's window does.
        assertEq(windowEnd, gauge.depositBlock(tokenIds[0]) + minStakeBlocks);
    }
}
