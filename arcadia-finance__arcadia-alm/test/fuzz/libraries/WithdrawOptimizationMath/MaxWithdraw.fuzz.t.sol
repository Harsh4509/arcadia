/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { PoolLogic } from "../../../../src/shared/libraries/logic/PoolLogic.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { RedeemOptimizationMath_Fuzz_Test } from "../RedeemOptimizationMath/_RedeemOptimizationMath.fuzz.t.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "maxWithdraw" of library "WithdrawOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract MaxWithdraw_WithdrawOptimizationMath_Fuzz_Test is RedeemOptimizationMath_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_maxWithdraw_ZeroBelowTheMargin(RedeemState memory state, uint64 bufferOut, uint256 shares)
        public
    {
        // Given: A core holding only tokenOut, shares of 1 wei of it at most, a pool.
        state.supply = uint128(bound(state.supply, 1, type(uint64).max));
        shares = bound(shares, 1, state.supply);
        bufferOut = uint64(bound(bufferOut, 0, FixedPointMathLib.min(uint256(state.supply) / shares, type(uint64).max)));
        (Snapshot memory snapshot, address pool) = givenBuffersOnly(state, bufferOut, 0, 1);

        // When: Calculating the most a withdraw of those shares pays.
        uint256 amountOut = withdrawMath.maxWithdraw(snapshot, pool, state.zeroForOne, shares);

        // Then: It is zero.
        assertEq(amountOut, 0);
    }

    function testFuzz_Success_maxWithdraw_ZeroWithoutActiveLiquidity(
        RedeemState memory state,
        uint64 bufferOut,
        uint64 bufferIn,
        uint256 shares
    ) public {
        // Given: A core with tokenIn idle, shares up to the supply, an inactive pool.
        bufferIn = uint64(bound(bufferIn, 1, type(uint64).max));
        (Snapshot memory snapshot, address pool) = givenBuffersOnly(state, bufferOut, bufferIn, 0);
        shares = bound(shares, 1, state.supply);

        // When: Calculating the most a withdraw of those shares pays.
        uint256 amountOut = withdrawMath.maxWithdraw(snapshot, pool, state.zeroForOne, shares);

        // Then: It is zero, the pool buying none of the tokenIn the burn releases.
        assertEq(amountOut, 0);
    }

    function testFuzz_Success_maxWithdraw_ItsWithdrawBurnsAtMostTheShares(
        RedeemState memory state,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A range around spot in its pool, and at most the supply in shares.
        (Snapshot memory snapshot, address pool) = givenValidState(state, range);
        shares = bound(shares, 1, state.supply);

        // When: Calculating the most a withdraw of those shares pays.
        uint256 amountOut = withdrawMath.maxWithdraw(snapshot, pool, state.zeroForOne, shares);

        // Then: A withdraw of it burns at most the shares.
        if (amountOut > 0) {
            uint256 burned = withdrawMath.previewWithdraw(snapshot, pool, state.zeroForOne, amountOut);
            assertLe(burned, shares);
        }
    }

    function testFuzz_Success_maxWithdraw_ItsWithdrawBurnsExactlyTheSharesOverTheMostSteps(
        uint256 liquidity,
        uint256 amountIn,
        uint256 amountOut,
        uint256 shares,
        uint24 fee
    ) public {
        // Given: A tick spacing of 10, spot mid tick 3, a word end at tick 0 below.
        uint160 sqrtPriceX96 = (TickMath.getSqrtPriceAtTick(3) + TickMath.getSqrtPriceAtTick(4)) / 2;

        // And: A swap cost limit 7 to 8 ticks below spot, past tick 0: two steps.
        fee = uint24(bound(fee, 0, Constants.MAX_POOL_FEE));
        mockMaxSwapCostBps(MOCK_CORE, fee / Constants.PIPS_PER_BPS + 8);

        // And: Pool liquidity a multiple of 2^96, each price unit whole token1.
        liquidity = bound(liquidity, 1, type(uint128).max >> 96) << 96;
        address pool = poolOf(10, uint128(liquidity), new PricedRange[](0));

        // And: A core of buffers only, its token1 in two whole halves.
        Snapshot memory snapshot = snapshotOf(new PricedRange[](0), 0, 0, 0, sqrtPriceX96, fee);
        snapshot.buffer1 = 2 * bound(amountOut, 1, Constants.MAX_FUZZED_AMOUNT / 2);

        // And: Half its token0 less two steps' margin sells past tick 0 within the limit.
        amountOut = SqrtPriceMath.getAmount0Delta(
                TickMath.getSqrtPriceAtTick(0), sqrtPriceX96, uint128(liquidity), true
            )
            .fullMulDivUp(1e6, 1e6 - fee) + snapshotLib.getRounding(snapshot, sqrtPriceX96, true);
        amountOut += (2 * (2e6 - uint256(fee))).divUp(1e6 - fee) + 1;
        liquidity = SqrtPriceMath.getAmount0Delta(
            snapshotLib.getSwapCostLimit(snapshot, true), sqrtPriceX96, uint128(liquidity), false
        );
        amountIn = bound(amountIn, amountOut, liquidity);
        snapshot.buffer0 = 2 * amountIn;

        // And: Half its supply in shares, each worth a wei of either token at least.
        shares = bound(shares, 1, FixedPointMathLib.min(amountIn, snapshot.buffer1 / 2));
        snapshot.supply = 2 * shares;

        // When: Calculating the most a withdraw of those shares pays.
        amountOut = withdrawMath.maxWithdraw(snapshot, pool, true, shares);

        // Then: A withdraw of it burns exactly the shares.
        assertEq(withdrawMath.previewWithdraw(snapshot, pool, true, amountOut), shares);
    }

    function testFuzz_Success_maxWithdraw_NeverAboveARedeemOfTheShares(
        RedeemState memory state,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A range around spot in its pool, and at most the supply in shares.
        (Snapshot memory snapshot, address pool) = givenValidState(state, range);
        shares = bound(shares, 1, state.supply);

        // When: Calculating the most a withdraw of those shares pays.
        uint256 amountOut = withdrawMath.maxWithdraw(snapshot, pool, state.zeroForOne, shares);

        // Then: It is at most what a redeem of the shares pays.
        assertLe(amountOut, redeemOf(snapshot, state, 1, shares, 0));
    }

    function testFuzz_Success_maxWithdraw_ItsSaleEndsAtOrBeforeTheSwapCostLimit(
        RedeemState memory state,
        RangeState memory range,
        uint256 maxSwapCostBps,
        uint256 shares
    ) public {
        // Given: A range around spot in its pool, and at most the supply in shares.
        (Snapshot memory snapshot, address pool) = givenValidState(state, range);
        shares = bound(shares, 1, state.supply);

        // And: A max swap cost above the pool's fee.
        maxSwapCostBps = bound(
            maxSwapCostBps,
            FixedPointMathLib.divUp(state.fee, Constants.PIPS_PER_BPS) + 1,
            ConfigLib.BPS_DENOMINATOR - 1
        );
        mockMaxSwapCostBps(MOCK_CORE, maxSwapCostBps);

        // When: Calculating the most a withdraw of those shares pays.
        uint256 amountOut = withdrawMath.maxWithdraw(snapshot, pool, state.zeroForOne, shares);

        // Then: The sale of what its burn does not pay ends at or before the limit.
        uint256 burned = withdrawMath.previewWithdraw(snapshot, pool, state.zeroForOne, amountOut);
        uint256 releasedOut;
        {
            (uint256 amount0, uint256 amount1,) =
                snapshotLib.getBurnAmounts(snapshot, state.sqrtPriceX96, burned, state.zeroForOne);
            releasedOut = state.zeroForOne ? amount1 : amount0;
        }
        uint160 sqrtPriceEnd = state.sqrtPriceX96;
        if (amountOut > releasedOut) {
            (sqrtPriceEnd,,) = swap(
                snapshot,
                burnedPoolOf(snapshot, 1, state.liquidity, burned),
                state.zeroForOne,
                int256(amountOut - releasedOut),
                PoolLogic.sqrtPriceLimit(state.zeroForOne)
            );
        }
        if (state.zeroForOne) assertGe(sqrtPriceEnd, snapshotLib.getSwapCostLimit(snapshot, true));
        else assertLe(sqrtPriceEnd, snapshotLib.getSwapCostLimit(snapshot, false));
    }

    function testFuzz_Success_maxWithdraw_OnATickReachedFromAboveWithAnEmptyBand(
        RedeemState memory state,
        int24 tick,
        uint64 bufferOut,
        uint256 maxSwapCostBps,
        uint256 shares
    ) public {
        // Given: Spot on a tick reached from above, the pool's tick below, only token1.
        state.zeroForOne = true;
        tick = int24(bound(tick, -Constants.BOUND_TICK, Constants.BOUND_TICK));
        state.sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);
        (Snapshot memory snapshot, address pool) = givenBuffersOnly(state, bufferOut, 0, 0);
        snapshot.tick = tick - 1;
        shares = bound(shares, 1, state.supply);

        // And: A max swap cost at most the pool's fee, an empty band.
        mockMaxSwapCostBps(MOCK_CORE, bound(maxSwapCostBps, 0, state.fee / Constants.PIPS_PER_BPS));

        // When: Calculating the most a withdraw of those shares pays.
        uint256 amountOut = withdrawMath.maxWithdraw(snapshot, pool, true, shares);

        // Then: The burn's token1 less the margin of one step, nothing to sell.
        (, uint256 released,) = snapshotLib.getBurnAmounts(snapshot, state.sqrtPriceX96, shares, true);
        uint256 roundingMarginOut = snapshotLib.getRounding(snapshot, state.sqrtPriceX96, false) + 1;
        assertEq(amountOut, released.zeroFloorSub(roundingMarginOut));
    }

    function testFuzz_Success_maxWithdraw_TheRedeemOfTheSharesLessTheMargin(
        RedeemState memory state,
        uint256 rangeCount,
        int24 tickSpacing,
        uint256 shares
    ) public {
        // Given: TokenIn worth 1 to 2^32 tokenOut, buffers, n empty ranges, shares.
        state.sqrtPriceX96 = state.zeroForOne
            ? uint160(bound(state.sqrtPriceX96, 1 << 96, Constants.MAX_SOLVER_SQRT_PRICE))
            : uint160(bound(state.sqrtPriceX96, Constants.MIN_SOLVER_SQRT_PRICE, 1 << 96));
        (Snapshot memory snapshot,) = givenBuffersOnly(state, state.idle0, state.idle1, 0);
        snapshot.ranges = new PricedRange[](bound(rangeCount, 0, ConfigLib.MAX_RANGE_CAP));
        for (uint256 i; i < snapshot.ranges.length; ++i) {
            snapshot.ranges[i].sqrtPriceLowerX96 = TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK);
            snapshot.ranges[i].sqrtPriceUpperX96 = TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK);
        }
        shares = bound(shares, 1, state.supply);

        // And: A tick spacing, and a pool of it, its reserves within a uint128.
        tickSpacing = int24(bound(tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));
        state.liquidity = uint128(
            bound(
                state.liquidity,
                1,
                type(uint128).max
                    / (FixedPointMathLib.max(state.sqrtPriceX96 >> 96, (1 << 96) / uint256(state.sqrtPriceX96)) + 1)
            )
        );
        address pool = poolOf(tickSpacing, state.liquidity, snapshot.ranges);

        // And: The shares a redeem may burn, capped pro rata at the tokenIn to the limit.
        uint256 redeemable = shares;
        {
            uint256[2] memory supplyIn;
            (supplyIn[0], supplyIn[1],) =
                snapshotLib.getBurnAmounts(snapshot, state.sqrtPriceX96, state.supply, state.zeroForOne);
            if (!state.zeroForOne) supplyIn[0] = supplyIn[1];
            if (supplyIn[0] != 0) {
                (, supplyIn[1],) = swap(
                    snapshot,
                    pool,
                    state.zeroForOne,
                    -type(int256).max,
                    snapshotLib.getSwapCostLimit(snapshot, state.zeroForOne)
                );
                redeemable = shares.min(supplyIn[1].fullMulDiv(state.supply, supplyIn[0] + 2 * snapshot.ranges.length));
            }
        }

        // And: The margins a withdraw is priced short by.
        uint256[2] memory margins;
        {
            uint256 steps;
            {
                // And: The most steps: one per spacing past the limit's tick, and one.
                uint160 sqrtPriceLimitX96 = snapshotLib.getSwapCostLimit(snapshot, state.zeroForOne);
                {
                    int24 tickLimit = TickMath.getTickAtSqrtPrice(sqrtPriceLimitX96);
                    uint256 ticks =
                        uint256(int256(state.zeroForOne ? snapshot.tick - tickLimit : tickLimit - snapshot.tick) + 1);
                    steps = ticks.zeroFloorSub(1).divUp(uint256(int256(tickSpacing))) + 1;
                }

                // And: TokenIn short: n to the limit, with fee, rounding, 2n, 2 + φ/step.
                margins[0] = (state.zeroForOne
                        ? SqrtPriceMath.getAmount0Delta(
                            sqrtPriceLimitX96, state.sqrtPriceX96, uint128(snapshot.ranges.length), true
                        )
                        : SqrtPriceMath.getAmount1Delta(
                            state.sqrtPriceX96, sqrtPriceLimitX96, uint128(snapshot.ranges.length), true
                        ))
                .fullMulDivUp(1e6, 1e6 - state.fee);
            }
            margins[0] += snapshotLib.getRounding(snapshot, state.sqrtPriceX96, state.zeroForOne) + 2
            * snapshot.ranges.length + ((2e6 - uint256(state.fee)) * steps).divUp(1e6 - state.fee);

            // And: The tokenOut short: the rounding, 1 per step and 2n.
            margins[1] = snapshotLib.getRounding(snapshot, state.sqrtPriceX96, !state.zeroForOne) + steps + 2
                * snapshot.ranges.length;
        }

        // When: Calculating the most a withdraw of those shares pays.
        uint256 amountOut = withdrawMath.maxWithdraw(snapshot, pool, state.zeroForOne, shares);

        // Then: It is their redeem, the tokenIn margin unsold, less the tokenOut margin.
        assertEq(amountOut, redeemOf(snapshot, state, tickSpacing, redeemable, margins[0]).zeroFloorSub(margins[1]));
    }
}
