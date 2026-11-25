/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { IArbSys } from "../../../../src/interfaces/IArbSys.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { RangesLib_Fuzz_Test } from "./_RangesLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "stake" of library "RangesLib".
 */
contract Stake_RangesLib_Fuzz_Test is RangesLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_stake_DepositsInTheGaugeAndStartsTheWindow(
        PoolState memory poolState,
        RangeState memory range,
        uint32 blocks
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A position the ranges hold, at the ticks of a range with no staked side.
        givenValidRangeState(range, poolState, false);
        (uint256 tokenId,) = mintPositionFor(
            pool, users.liquidityProvider, address(rangesLib), range.tickLower, range.tickUpper, range.liquidity
        );
        Range memory held;
        (held.tickLower, held.tickUpper) = (range.tickLower, range.tickUpper);
        rangesLib.pushRange(held);
        vm.roll(vm.getBlockNumber() + blocks);

        // When: Staking the position for the range.
        rangesLib.stake(0, tokenId);

        // Then: The gauge holds it and the range's window starts this block.
        assertTrue(gauge.stakedContains(address(rangesLib), tokenId));
        assertEq(rangesLib.getRange(0).stakedBlock, vm.getBlockNumber());
    }

    function testFuzz_Success_stake_SetsWindowEndToTheLaterOf(
        PoolState memory poolState,
        RangeState memory range,
        uint32 blocks,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint48 windowEnd
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A position the ranges hold, at the ticks of a range with no staked side.
        givenValidRangeState(range, poolState, false);
        (uint256 tokenId,) = mintPositionFor(
            pool, users.liquidityProvider, address(rangesLib), range.tickLower, range.tickUpper, range.liquidity
        );
        Range memory held;
        (held.tickLower, held.tickUpper) = (range.tickLower, range.tickUpper);
        rangesLib.pushRange(held);
        vm.roll(vm.getBlockNumber() + blocks);

        // And: A live penalty config, its window ending below the largest uint48.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint48).max - vm.getBlockNumber());
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: A window end already stored.
        rangesLib.setWindowEnd(windowEnd);

        // When: Staking the position for the range.
        rangesLib.stake(0, tokenId);

        // Then: The window end is the later of the stored one and this stake's.
        uint256 stakeEnd = vm.getBlockNumber() + minStakeBlocks;
        assertEq(rangesLib.getWindowEnd(), windowEnd > stakeEnd ? windowEnd : stakeEnd);
    }

    function testFuzz_Success_stake_SameBlockStakesShareWindowEnd(
        PoolState memory poolState,
        RangeState memory first,
        RangeState memory second,
        uint32 blocks,
        uint256 minStakeBlocks,
        uint256 penaltyRate
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: Two positions the ranges hold, at the ticks of two unstaked ranges.
        givenValidRangeState(first, poolState, false);
        (uint256 firstId,) = mintPositionFor(
            pool, users.liquidityProvider, address(rangesLib), first.tickLower, first.tickUpper, first.liquidity
        );
        givenValidRangeState(second, poolState, false);
        (uint256 secondId,) = mintPositionFor(
            pool, users.liquidityProvider, address(rangesLib), second.tickLower, second.tickUpper, second.liquidity
        );
        Range memory held;
        (held.tickLower, held.tickUpper) = (first.tickLower, first.tickUpper);
        rangesLib.pushRange(held);
        (held.tickLower, held.tickUpper) = (second.tickLower, second.tickUpper);
        rangesLib.pushRange(held);
        vm.roll(vm.getBlockNumber() + blocks);

        // And: A live penalty config, its window ending below the largest uint48.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint48).max - vm.getBlockNumber());
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // When: Staking both positions in one block.
        rangesLib.stake(0, firstId);
        uint48 firstEnd = rangesLib.getWindowEnd();
        rangesLib.stake(1, secondId);

        // Then: Both stakes end their windows at the same block.
        assertEq(firstEnd, vm.getBlockNumber() + minStakeBlocks);
        assertEq(rangesLib.getWindowEnd(), firstEnd);
        assertEq(rangesLib.getRange(0).stakedBlock, vm.getBlockNumber());
        assertEq(rangesLib.getRange(1).stakedBlock, vm.getBlockNumber());
    }

    function testFuzz_Success_stake_NoWindowEndWithoutAPenalty(
        PoolState memory poolState,
        RangeState memory range,
        uint32 blocks,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint48 windowEnd
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A position the ranges hold, at the ticks of a range with no staked side.
        givenValidRangeState(range, poolState, false);
        (uint256 tokenId,) = mintPositionFor(
            pool, users.liquidityProvider, address(rangesLib), range.tickLower, range.tickUpper, range.liquidity
        );
        Range memory held;
        (held.tickLower, held.tickUpper) = (range.tickLower, range.tickUpper);
        rangesLib.pushRange(held);
        vm.roll(vm.getBlockNumber() + blocks);

        // And: A gauge that does not penalise, by a zero window or a zero rate.
        minStakeBlocks = bound(minStakeBlocks, 0, MAX_MIN_STAKE_BLOCKS);
        penaltyRate = minStakeBlocks == 0 ? bound(penaltyRate, 0, MAX_PIPS) : 0;
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: A window end already stored.
        rangesLib.setWindowEnd(windowEnd);

        // When: Staking the position for the range.
        rangesLib.stake(0, tokenId);

        // Then: The range's window starts this block, the stored window end is untouched.
        assertEq(rangesLib.getRange(0).stakedBlock, vm.getBlockNumber());
        assertEq(rangesLib.getWindowEnd(), windowEnd);
    }

    function testFuzz_Success_stake_NoWindowEndWithAZeroWindow(
        PoolState memory poolState,
        RangeState memory range,
        uint32 blocks,
        uint256 penaltyRate
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A position the ranges hold, at the ticks of a range with no staked side.
        givenValidRangeState(range, poolState, false);
        (uint256 tokenId,) = mintPositionFor(
            pool, users.liquidityProvider, address(rangesLib), range.tickLower, range.tickUpper, range.liquidity
        );
        Range memory held;
        (held.tickLower, held.tickUpper) = (range.tickLower, range.tickUpper);
        rangesLib.pushRange(held);
        vm.roll(vm.getBlockNumber() + blocks);

        // And: A live penalty rate with a zero window on the factory default.
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        setPenaltyConfig(0, penaltyRate);
        assertEq(clGaugeFactory.effectivePenaltyConfig(address(gauge)).minStakeBlocks, 0);

        // When: Staking the position for the range.
        rangesLib.stake(0, tokenId);

        // Then: The range's window starts this block and the window end stays at zero.
        assertEq(rangesLib.getRange(0).stakedBlock, vm.getBlockNumber());
        assertEq(rangesLib.getWindowEnd(), 0);
    }

    function testFuzz_Success_stake_StartsTheWindowAtTheArbBlock(
        PoolState memory poolState,
        RangeState memory range,
        uint48 arbBlockNumber
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A chain whose gauges count blocks with ArbSys.arbBlockNumber.
        rangesLib.setArbBlockNumber(true);
        vm.etch(address(0x64), hex"00");
        vm.mockCall(address(0x64), abi.encodeCall(IArbSys.arbBlockNumber, ()), abi.encode(arbBlockNumber));

        // And: A position the ranges hold, at the ticks of a range with no staked side.
        givenValidRangeState(range, poolState, false);
        (uint256 tokenId,) = mintPositionFor(
            pool, users.liquidityProvider, address(rangesLib), range.tickLower, range.tickUpper, range.liquidity
        );
        Range memory held;
        (held.tickLower, held.tickUpper) = (range.tickLower, range.tickUpper);
        rangesLib.pushRange(held);

        // When: Staking the position for the range.
        rangesLib.stake(0, tokenId);

        // Then: The range's window starts at the gauge's block.
        assertEq(rangesLib.getRange(0).stakedBlock, arbBlockNumber);
    }
}
