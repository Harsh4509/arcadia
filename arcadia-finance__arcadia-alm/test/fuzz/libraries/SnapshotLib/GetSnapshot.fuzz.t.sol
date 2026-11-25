/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "../../ALMCore/_ALMCore.fuzz.t.sol";
import { Constants } from "../../../utils/Constants.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { ReentrancyLock } from "../../../../src/shared/abstracts/mixins/ReentrancyLock.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SnapshotLibExtension } from "../../../utils/extensions/SnapshotLibExtension.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getSnapshot" of library "SnapshotLib".
 */
// forge-lint: disable-next-item(unused-return)
contract GetSnapshot_SnapshotLib_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    SnapshotLibExtension internal snapshotLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        snapshotLib = new SnapshotLibExtension();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getSnapshot_Reentrancy(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: The core's lock is held.
        almCore.lock_();

        // When: Reading the snapshot.
        // Then: It reverts on the core's lock.
        vm.expectRevert(ReentrancyLock.Reentrancy.selector);
        snapshotLib.getSnapshot(address(almCore), address(pool), address(this));
    }

    function testFuzz_Success_getSnapshot(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory neighbour,
        uint256 amountIn
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range and a neighbour, with swap fees.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        givenValidRangeState(neighbour, poolState, false);
        setRangeState(neighbour);
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            feeEarningTrade(pool, range.liquidity, amountIn, true)
        );

        // When: Reading the snapshot.
        Snapshot memory snapshot = snapshotLib.getSnapshot(address(almCore), address(pool), address(this));

        // Then: It holds the buffer, fees, supply, core, and the pool's price and tick.
        (uint256 fees0, uint256 fees1,) = almCore.getUnstakedPositions();
        assertEq(snapshot.buffer0, almCore.bufferAmount0());
        assertEq(snapshot.buffer1, almCore.bufferAmount1());
        assertEq(snapshot.fees0, fees0);
        assertEq(snapshot.fees1, fees1);
        assertEq(snapshot.supply, almCore.totalSupply());
        assertEq(snapshot.sqrtPriceX96, sqrtPriceX96(pool));
        assertEq(snapshot.tick, currentTick(pool));
        assertEq(address(snapshot.core), address(almCore));

        // And: Every range priced at its ticks, with its liquidity summed.
        uint256 length = almCore.getRangesLength();
        assertEq(snapshot.ranges.length, length);
        for (uint256 i; i < length; ++i) {
            Range memory stored = almCore.getRange(i);
            assertEq(
                snapshot.ranges[i].liquidity,
                uint256(positionLiquidity(stored.unstakedTokenId)) + stored.stakedLiquidity
            );
            assertEq(snapshot.ranges[i].sqrtPriceLowerX96, TickMath.getSqrtPriceAtTick(stored.tickLower));
            assertEq(snapshot.ranges[i].sqrtPriceUpperX96, TickMath.getSqrtPriceAtTick(stored.tickUpper));
        }
    }

    function testFuzz_Success_getSnapshot_ExcludesEscrowAndProtocolFees(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 escrowed0,
        uint256 escrowed1,
        uint256 fee0,
        uint256 fee1
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Snapshot memory before = snapshotLib.getSnapshot(address(almCore), address(pool), address(this));

        // And: Escrowed amounts and protocol fees.
        escrowed0 = bound(escrowed0, 1, Constants.MAX_FUZZED_AMOUNT);
        escrowed1 = bound(escrowed1, 1, Constants.MAX_FUZZED_AMOUNT);
        fee0 = bound(fee0, 1, Constants.MAX_FUZZED_AMOUNT);
        fee1 = bound(fee1, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: Escrowing tokens for queued requests and accruing protocol fees.
        almCore.setEscrowed(escrowed0, escrowed1);
        almCore.setFeesOwed(fee0, fee1, 0);

        // Then: Neither the buffer nor the uncollected fees move.
        Snapshot memory snapshot = snapshotLib.getSnapshot(address(almCore), address(pool), address(this));
        assertEq(snapshot.buffer0, before.buffer0);
        assertEq(snapshot.buffer1, before.buffer1);
        assertEq(snapshot.fees0, before.fees0);
        assertEq(snapshot.fees1, before.fees1);
    }

    function testFuzz_Success_getSnapshot_MatchesFullSupplyWithdraw(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range
    ) public {
        // Given: A seeded vault.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // When: Comparing the snapshot's amounts with a whole-supply withdraw.
        Snapshot memory snapshot = snapshotLib.getSnapshot(address(almCore), address(pool), address(this));
        (uint256 total0, uint256 total1) = snapshotLib.getAmountsAt(snapshot, sqrtPriceX96(pool));
        (uint256 preview0, uint256 preview1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        (uint256 staked0, uint256 staked1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked);
        preview0 += staked0 + almCore.bufferAmount0();
        preview1 += staked1 + almCore.bufferAmount1();

        // Then: The withdraw reaches the totals, short by at most a floored wei a side.
        assertLe(preview0, total0);
        assertLe(preview1, total1);
        assertApproxEqAbs(preview0, total0, almCore.getRangesLength());
        assertApproxEqAbs(preview1, total1, almCore.getRangesLength());
    }
}
