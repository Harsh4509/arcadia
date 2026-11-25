/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IMetadexCLGaugeFactory } from "../../../../src/interfaces/IMetadexCLGaugeFactory.sol";
import { LiquidityAmounts } from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { RangesLib_Fuzz_Test } from "./_RangesLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "removeLiquidity" of library "RangesLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract RemoveLiquidity_RangesLib_Fuzz_Test is RangesLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_removeLiquidity_SkipsARangeOwingNothing(
        PoolState memory poolState,
        RangeState memory held,
        uint256 shares,
        uint128 supply
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core with a range holding staked liquidity only.
        deployRangesLib();
        givenValidRangeState(held, poolState, false);
        held.liquidity = 0;
        held.liquidityStaked = uint128(
            bound(
                held.liquidityStaked,
                1,
                liquidityCeiling(held.tickLower, held.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(held);

        // And: Too few shares of the supply to claim a unit of the range's liquidity.
        supply = uint128(bound(supply, 1, type(uint128).max));
        shares = bound(shares, 0, (uint256(supply) - 1) / held.liquidityStaked);

        // When: Releasing the shares.
        (TokenDelta principal, TokenDelta fees) = rangesLib.removeLiquidity(shares, supply);

        // Then: Nothing is released or collected and the range is untouched.
        assertEq(int256(principal.amount0()), 0);
        assertEq(int256(principal.amount1()), 0);
        assertEq(int256(fees.amount0()), 0);
        assertEq(int256(fees.amount1()), 0);
        assertEq(positionLiquidity(rangesLib.getRange(0).unstakedTokenId), 0);
        assertEq(rangesLib.getRange(0).stakedLiquidity, held.liquidityStaked);
    }

    function testFuzz_Success_removeLiquidity_CollectsTheFeesOfAnUntouchedRange(
        PoolState memory poolState,
        RangeState memory range,
        uint256 amountIn,
        uint256 shares,
        uint128 supply
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core with an unstaked range around spot that has earned swap fees.
        deployRangesLib();
        range.liquidityStaked = 0;
        givenValidRangeState(range, poolState, false);
        pushRangeOf(range);
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            feeEarningTrade(pool, range.liquidity, amountIn, true)
        );
        (uint256 gross0, uint256 gross1) = positionFees(pool, rangesLib.getRange(0).unstakedTokenId);

        // And: Too few shares of the supply to claim a unit of the range's liquidity.
        supply = uint128(bound(supply, range.liquidity, type(uint128).max));
        shares = bound(shares, 0, (uint256(supply) - 1) / range.liquidity);

        // When: Releasing the shares.
        (TokenDelta principal, TokenDelta fees) = rangesLib.removeLiquidity(shares, supply);

        // Then: No principal is released and the range keeps its liquidity.
        assertEq(int256(principal.amount0()), 0);
        assertEq(int256(principal.amount1()), 0);
        assertEq(positionLiquidity(rangesLib.getRange(0).unstakedTokenId), range.liquidity);
        assertEq(positionLiquidity(rangesLib.getRange(0).unstakedTokenId), range.liquidity);

        // And: The range's accrued fees are collected.
        assertEq(int256(fees.amount0()), int256(gross0));
        assertEq(int256(fees.amount1()), int256(gross1));
    }

    function testFuzz_Success_removeLiquidity_UnstakedSideFirst(
        PoolState memory poolState,
        RangeState memory range,
        uint256 shares,
        uint128 supply
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core with a range holding both sides.
        deployRangesLib();
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(range);

        // And: Shares claiming no more of the range than its unstaked side holds.
        supply = uint128(bound(supply, 1, type(uint128).max));
        uint256 total = uint256(range.liquidity) + range.liquidityStaked;
        shares = bound(shares, 0, uint256(range.liquidity) * supply / total);

        // When: Releasing the shares.
        (TokenDelta principal,) = rangesLib.removeLiquidity(shares, supply);

        // Then: Only the unstaked side gave up the claim.
        uint128 owed = uint128(total * shares / supply);
        assertEq(positionLiquidity(rangesLib.getRange(0).unstakedTokenId), range.liquidity - owed);
        assertEq(rangesLib.getRange(0).stakedLiquidity, range.liquidityStaked);

        // And: The claim's principal at the current price, rounded down, is released.
        (uint256 expected0, uint256 expected1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96(pool),
            TickMath.getSqrtPriceAtTick(range.tickLower),
            TickMath.getSqrtPriceAtTick(range.tickUpper),
            owed
        );
        assertEq(int256(principal.amount0()), int256(expected0));
        assertEq(int256(principal.amount1()), int256(expected1));
    }

    function testFuzz_Success_removeLiquidity_StakedRemainderOutsideTheWindow(
        PoolState memory poolState,
        RangeState memory range,
        uint128 supply
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core with a range whose staked side has sat out its penalty window.
        deployRangesLib();
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(range);
        closePenaltyWindow(gauge);
        supply = uint128(bound(supply, 1, type(uint128).max));

        // When: Releasing the whole supply.
        (TokenDelta principal, TokenDelta fees) = rangesLib.removeLiquidity(supply, supply);

        // Then: Both sides are drained and the staked token id is burned.
        Range memory drained = rangesLib.getRange(0);
        assertEq(positionLiquidity(drained.unstakedTokenId), 0);
        assertEq(drained.stakedLiquidity, 0);
        assertEq(drained.stakedTokenId, 0);

        // And: Everything the core received was released as principal, no fees collected.
        assertEq(int256(principal.amount0()), int256(token0.balanceOf(address(rangesLib))));
        assertEq(int256(principal.amount1()), int256(token1.balanceOf(address(rangesLib))));
        assertEq(int256(fees.amount0()), 0);
        assertEq(int256(fees.amount1()), 0);
    }

    function testFuzz_Success_removeLiquidity_InsideThePenaltyWindow(
        PoolState memory poolState,
        RangeState memory range,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocks,
        uint256 emissions,
        uint128 supply
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A live penalty config.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: A core with a range whose staked side was just deposited, its window open.
        deployRangesLib();
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(range);
        supply = uint128(bound(supply, 1, type(uint128).max));

        // And: Emissions settled into the pool inside the window.
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 2, Constants.MAX_EMISSIONS));
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = range.stakedTokenId;
        uint256 earned = gauge.earned(address(rangesLib), tokenIds);

        // When: Releasing the whole supply, into the staked side.
        rangesLib.removeLiquidity(supply, supply);

        // Then: Both sides are drained.
        Range memory drained = rangesLib.getRange(0);
        assertEq(positionLiquidity(drained.unstakedTokenId), 0);
        assertEq(drained.stakedLiquidity, 0);
        assertEq(drained.stakedTokenId, 0);

        // And: The staked side was paid only its emissions net of the penalty.
        assertEq(ERC20(receiptToken).balanceOf(address(rangesLib)), earned);
    }

    function testFuzz_Success_removeLiquidity_StakedOnlyRange(
        PoolState memory poolState,
        RangeState memory range,
        uint128 supply
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core with a range holding only a staked side, out of its penalty window.
        deployRangesLib();
        givenValidRangeState(range, poolState, false);
        range.liquidity = 0;
        pushRangeOf(range);
        closePenaltyWindow(gauge);
        supply = uint128(bound(supply, 1, type(uint128).max));

        // When: Releasing the whole supply.
        (TokenDelta principal,) = rangesLib.removeLiquidity(supply, supply);

        // Then: The staked side is drained and its token id burned.
        Range memory drained = rangesLib.getRange(0);
        assertEq(drained.stakedLiquidity, 0);
        assertEq(drained.stakedTokenId, 0);

        // And: Its principal at the current price, rounded down, is released.
        (uint256 expected0, uint256 expected1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96(pool),
            TickMath.getSqrtPriceAtTick(range.tickLower),
            TickMath.getSqrtPriceAtTick(range.tickUpper),
            range.liquidityStaked
        );
        assertEq(int256(principal.amount0()), int256(expected0));
        assertEq(int256(principal.amount1()), int256(expected1));
    }

    function testFuzz_Success_removeLiquidity_ReadsThePenaltyOnce(
        PoolState memory poolState,
        RangeState memory first,
        RangeState memory second,
        uint128 supply
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core with two ranges with staked sides, both past their penalty windows.
        deployRangesLib();
        givenValidRangeState(first, poolState, false);
        first.liquidityStaked = uint128(
            bound(
                first.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(first.tickLower, first.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(first);
        givenValidRangeState(second, poolState, false);
        second.liquidityStaked = uint128(
            bound(
                second.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(second.tickLower, second.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        second.index = 1;
        rangesLib.pushRange(stageRange(address(rangesLib), second));
        closePenaltyWindow(gauge);
        supply = uint128(bound(supply, 1, type(uint128).max));

        // When: Releasing the whole supply.
        vm.expectCall(
            address(clGaugeFactory),
            abi.encodeWithSelector(IMetadexCLGaugeFactory.effectivePenaltyConfig.selector, address(gauge)),
            3
        );
        rangesLib.removeLiquidity(supply, supply);

        // Then: Both staked sides are drained, the penalty read once, two gauge reads.
        assertEq(rangesLib.getRange(0).stakedLiquidity, 0);
        assertEq(rangesLib.getRange(1).stakedLiquidity, 0);
    }

    function testFuzz_Success_removeLiquidity_RestakePushesWindowEnd(
        PoolState memory poolState,
        RangeState memory range,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocksPassed,
        uint256 shares,
        uint128 supply
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A live penalty config.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: A core with a range holding both sides, the window end its stake's.
        deployRangesLib();
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(range);
        rangesLib.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));

        // And: The staked side has sat out its penalty window.
        vm.roll(vm.getBlockNumber() + bound(blocksPassed, minStakeBlocks, type(uint32).max));

        // And: Shares claiming all of the unstaked side and part of the staked side.
        uint256 total = uint256(range.liquidity) + range.liquidityStaked;
        supply = uint128(bound(supply, total, type(uint128).max));
        shares = bound(shares, FixedPointMathLib.fullMulDivUp(uint256(range.liquidity) + 1, supply, total), supply - 1);

        // When: Releasing the shares.
        rangesLib.removeLiquidity(shares, supply);

        // Then: The staked side was restaked in this block.
        Range memory restaked = rangesLib.getRange(0);
        assertEq(restaked.stakedTokenId, range.stakedTokenId);
        assertEq(restaked.stakedBlock, vm.getBlockNumber());

        // And: The window end moved to the restake's.
        assertEq(rangesLib.getWindowEnd(), vm.getBlockNumber() + minStakeBlocks);
    }

    function testFuzz_Success_removeLiquidity_InsideThePenaltyWindowForfeitsOnlyThatToken(
        PoolState memory poolState,
        RangeState memory forfeited,
        RangeState memory kept,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocks,
        uint256 emissions,
        uint256 shares,
        uint128 supply
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A live penalty config.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: A staked-only range, a range staked no more than unstaked, in one block.
        deployRangesLib();
        givenValidRangeState(forfeited, poolState, false);
        forfeited.liquidity = 0;
        forfeited.liquidityStaked = uint128(
            bound(
                forfeited.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(forfeited.tickLower, forfeited.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(forfeited);
        givenValidRangeState(kept, poolState, false);
        kept.liquidityStaked = uint128(bound(kept.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, kept.liquidity));
        pushRangeOf(kept);

        // And: Emissions settled into the pool inside the windows.
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 2, Constants.MAX_EMISSIONS));

        // And: Shares the second's unstaked side covers, part of the first's staked.
        uint256 total = uint256(kept.liquidity) + kept.liquidityStaked;
        supply = uint128(bound(supply, total, type(uint128).max));
        shares = bound(
            shares,
            FixedPointMathLib.divUp(supply, forfeited.liquidityStaked),
            FixedPointMathLib.fullMulDiv(kept.liquidity, supply, total)
        );
        uint256[] memory forfeitedIds = new uint256[](1);
        forfeitedIds[0] = forfeited.stakedTokenId;
        uint256[] memory keptIds = new uint256[](1);
        keptIds[0] = kept.stakedTokenId;
        uint256 earned = gauge.earned(address(rangesLib), forfeitedIds);
        uint256 hidden = hiddenEmissions(gauge, address(rangesLib), keptIds);
        uint256 depositBlock = gauge.depositBlock(kept.stakedTokenId);

        // When: Releasing the shares.
        rangesLib.removeLiquidity(shares, supply);

        // Then: The first range was paid its earned emissions, its hidden ones are gone.
        assertEq(ERC20(receiptToken).balanceOf(address(rangesLib)), earned);
        assertEq(hiddenEmissions(gauge, address(rangesLib), forfeitedIds), 0);

        // And: The second range kept its staked side, window and hidden emissions.
        assertEq(rangesLib.getRange(1).stakedLiquidity, kept.liquidityStaked);
        assertEq(gauge.depositBlock(kept.stakedTokenId), depositBlock);
        assertEq(hiddenEmissions(gauge, address(rangesLib), keptIds), hidden);
    }

    function testFuzz_Success_removeLiquidity_RestakeInsideWindowLeavesPreCreditToNextCheckpoint(
        PoolState memory poolState,
        RangeState memory range,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocks,
        uint256 emissions,
        uint128 preCredited,
        uint256 shares,
        uint128 supply
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A live penalty config.
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: A range holding both sides, the stake's window end, pre-credit.
        deployRangesLib();
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(range);
        rangesLib.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));
        rangesLib.setPreCredited(preCredited);

        // And: Emissions settled into the pool, later inside the window.
        accrueForBlocks(pool, gauge, bound(blocks, 1, minStakeBlocks - 1), bound(emissions, 2, Constants.MAX_EMISSIONS));

        // And: Shares claiming all of the unstaked side and part of the staked side.
        uint256 total = uint256(range.liquidity) + range.liquidityStaked;
        supply = uint128(bound(supply, total, type(uint128).max));
        shares = bound(shares, FixedPointMathLib.fullMulDivUp(uint256(range.liquidity) + 1, supply, total), supply - 1);

        // When: Releasing the shares.
        rangesLib.removeLiquidity(shares, supply);

        // Then: The staked side was restaked in this block.
        assertEq(rangesLib.getRange(0).stakedBlock, vm.getBlockNumber());

        // And: The restake only moved the window end to its own.
        assertEq(rangesLib.getWindowEnd(), vm.getBlockNumber() + minStakeBlocks);

        // And: The pre-credit is left to the next checkpoint.
        assertEq(rangesLib.getPreCredited(), preCredited);
    }
}
