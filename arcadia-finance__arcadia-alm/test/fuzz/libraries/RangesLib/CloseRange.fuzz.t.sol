/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import {
    INonfungiblePositionManager
} from "../../../utils/fixtures/metadex/interfaces/INonfungiblePositionManager.sol";
import { Constants } from "../../../utils/Constants.sol";
import { LiquidityAmounts } from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import { PoolTokens } from "../../../../src/core/types/State.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { RangesLib } from "../../../../src/core/libraries/state/RangesLib.sol";
import { RangesLib_Fuzz_Test } from "./_RangesLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "closeRange" of library "RangesLib".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract CloseRange_RangesLib_Fuzz_Test is RangesLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_closeRange_RangeStaked(PoolState memory poolState, Range memory held) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range with a staked side.
        held.stakedTokenId = uint80(bound(held.stakedTokenId, 1, type(uint80).max));
        rangesLib.pushRange(held);

        // When: Closing it.
        // Then: It reverts.
        vm.expectRevert(RangesLib.RangeStaked.selector);
        rangesLib.closeRange(0);
    }

    function testFuzz_Success_closeRange_ReleasesTheLastRange(PoolState memory poolState, RangeState memory range)
        public
    {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A single range holding an unstaked side only.
        range.liquidityStaked = 0;
        givenValidRangeState(range, poolState, false);
        pushRangeOf(range);

        // When: Closing it.
        (int24 tickLower, int24 tickUpper, uint128 liquidity, TokenDelta principal, TokenDelta fees) =
            rangesLib.closeRange(range.index);

        // Then: It returns its ticks and liquidity at the price rounded down, no fees.
        (uint256 expected0, uint256 expected1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96(pool),
            TickMath.getSqrtPriceAtTick(range.tickLower),
            TickMath.getSqrtPriceAtTick(range.tickUpper),
            range.liquidity
        );
        assertEq(tickLower, range.tickLower);
        assertEq(tickUpper, range.tickUpper);
        assertEq(liquidity, range.liquidity);
        assertEq(int256(principal.amount0()), int256(expected0));
        assertEq(int256(principal.amount1()), int256(expected1));
        assertEq(int256(fees.amount0()), 0);
        assertEq(int256(fees.amount1()), 0);

        // And: The ranges received it, and the range is gone.
        assertEq(token0.balanceOf(address(rangesLib)), expected0);
        assertEq(token1.balanceOf(address(rangesLib)), expected1);
        assertEq(rangesLib.getRangesLength(), 0);
    }

    function testFuzz_Success_closeRange_MovesTheLastRangeIntoTheGap(
        PoolState memory poolState,
        RangeState memory range,
        Range memory between,
        Range memory last,
        uint256 count
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range holding an unstaked side, followed by one or two other ranges.
        range.liquidityStaked = 0;
        givenValidRangeState(range, poolState, false);
        pushRangeOf(range);
        count = bound(count, 1, 2);
        if (count == 2) rangesLib.pushRange(between);
        rangesLib.pushRange(last);

        // When: Closing the first.
        rangesLib.closeRange(range.index);

        // Then: The last range took its index, and a range between stayed in place.
        assertEq(rangesLib.getRangesLength(), count);
        Range memory moved = rangesLib.getRange(0);
        assertEq(moved.stakedLiquidity, last.stakedLiquidity);
        assertEq(moved.tickLower, last.tickLower);
        assertEq(moved.tickUpper, last.tickUpper);
        assertEq(moved.unstakedTokenId, last.unstakedTokenId);
        assertEq(moved.stakedTokenId, last.stakedTokenId);
        assertEq(moved.stakedBlock, last.stakedBlock);
        if (count == 2) assertEq(rangesLib.getRange(1).tickLower, between.tickLower);
    }

    function testFuzz_Success_closeRange_NoLiquidityLeftCollectsWhatIsOwed(
        PoolState memory poolState,
        RangeState memory range
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range whose token id was drained to tokens owed.
        range.liquidityStaked = 0;
        givenValidRangeState(range, poolState, false);
        pushRangeOf(range);
        vm.prank(address(rangesLib));
        (uint256 owed0, uint256 owed1) = POSITION_MANAGER.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: range.unstakedTokenId,
                liquidity: range.liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: vm.getBlockTimestamp()
            })
        );

        // When: Closing it.
        (,, uint128 liquidity, TokenDelta principal, TokenDelta fees) = rangesLib.closeRange(range.index);

        // Then: No liquidity is left, and only what was owed is collected, as fees.
        assertEq(liquidity, 0);
        assertEq(int256(principal.amount0()), 0);
        assertEq(int256(principal.amount1()), 0);
        assertEq(int256(fees.amount0()), int256(owed0));
        assertEq(int256(fees.amount1()), int256(owed1));

        // And: No protocol fee accrues.
        PoolTokens memory poolTokens = rangesLib.getPoolTokens();
        assertEq(poolTokens.protocolFees.amount0, 0);
        assertEq(poolTokens.protocolFees.amount1, 0);
    }

    function testFuzz_Success_closeRange_ReturnsTheGrossFees(
        PoolState memory poolState,
        RangeState memory range,
        uint256 amountIn,
        uint16 bps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A protocol share of every collection.
        bps = uint16(bound(bps, 1, ConfigLib.MAX_FEE_BPS));
        rangesLib.setProtocolSwapFeeBps(bps);

        // And: A range around the price, a real share of the room, that earned swap fees.
        range.liquidityStaked = 0;
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));
        pushRangeOf(range);
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            feeEarningTrade(pool, range.liquidity, amountIn, true)
        );

        // And: What the side earned, from the pool's fee growth inside its ticks.
        (uint256 gross0, uint256 gross1) = positionFees(pool, range.unstakedTokenId);

        // And: The principal of its liquidity at the price after the trade, rounded down.
        (uint256 principal0, uint256 principal1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96(pool),
            TickMath.getSqrtPriceAtTick(range.tickLower),
            TickMath.getSqrtPriceAtTick(range.tickUpper),
            range.liquidity
        );

        // When: Closing it.
        (,,, TokenDelta principal, TokenDelta fees) = rangesLib.closeRange(range.index);

        // Then: The principal and fees are returned apart, fees before protocol share.
        assertEq(int256(principal.amount0()), int256(principal0));
        assertEq(int256(principal.amount1()), int256(principal1));
        assertEq(int256(fees.amount0()), int256(gross0));
        assertEq(int256(fees.amount1()), int256(gross1));

        // And: No protocol fee accrues.
        PoolTokens memory poolTokens = rangesLib.getPoolTokens();
        assertEq(poolTokens.protocolFees.amount0, 0);
        assertEq(poolTokens.protocolFees.amount1, 0);
    }
}
