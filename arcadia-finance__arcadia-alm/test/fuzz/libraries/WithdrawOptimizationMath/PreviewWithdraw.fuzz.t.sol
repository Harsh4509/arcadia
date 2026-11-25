/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../../utils/Constants.sol";
import { EquivalentPositionMath } from "../../../../src/vaults/libraries/math/EquivalentPositionMath.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { PoolLogic } from "../../../../src/shared/libraries/logic/PoolLogic.sol";
import { PoolMock } from "../../../utils/mocks/PoolMock.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { QuadraticMath } from "../../../../src/vaults/libraries/math/QuadraticMath.sol";
import { RedeemOptimizationMath } from "../../../../src/vaults/libraries/math/RedeemOptimizationMath.sol";
import { RedeemOptimizationMath_Fuzz_Test } from "../RedeemOptimizationMath/_RedeemOptimizationMath.fuzz.t.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { StepComputations, SwapState, SwapStateLib } from "../../../../src/vaults/types/SwapState.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "previewWithdraw" of library "WithdrawOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract PreviewWithdraw_WithdrawOptimizationMath_Fuzz_Test is RedeemOptimizationMath_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_previewWithdraw_ZeroForNothing(RedeemState memory state, RangeState memory range) public {
        // Given: A range around spot, in a pool with its liquidity.
        (Snapshot memory snapshot, address pool) = givenValidState(state, range);

        // When: Previewing a withdraw of nothing.
        uint256 shares = withdrawMath.previewWithdraw(snapshot, pool, state.zeroForOne, 0);

        // Then: It burns no shares.
        assertEq(shares, 0);
    }

    function testFuzz_Success_previewWithdraw_TheBurnAlonePaysWithoutTokenIn(
        RedeemState memory state,
        uint64 bufferOut,
        uint256 amountOut
    ) public {
        // Given: A core holding only tokenOut, at most half of it, and an active pool.
        bufferOut = uint64(bound(bufferOut, 2, type(uint64).max));
        amountOut = bound(amountOut, 1, bufferOut / 2);
        (Snapshot memory snapshot, address pool) = givenBuffersOnly(state, bufferOut, 0, 1);

        // When: Previewing the withdraw.
        uint256 shares = withdrawMath.previewWithdraw(snapshot, pool, state.zeroForOne, amountOut);

        // Then: It burns the shares of the amount and the burn's rounding of 1 wei.
        assertEq(shares, (amountOut + 1).fullMulDivUp(state.supply, bufferOut));
    }

    function testFuzz_Success_previewWithdraw_TheBurnAloneWithoutActiveLiquidity(
        RedeemState memory state,
        uint64 bufferOut,
        uint64 bufferIn,
        uint256 amountOut
    ) public {
        // Given: A core holding both tokens, half its tokenOut at most, an inactive pool.
        bufferOut = uint64(bound(bufferOut, 2, type(uint64).max));
        bufferIn = uint64(bound(bufferIn, 1, type(uint64).max));
        amountOut = bound(amountOut, 1, bufferOut / 2);
        (Snapshot memory snapshot, address pool) = givenBuffersOnly(state, bufferOut, bufferIn, 0);

        // When: Previewing the withdraw.
        uint256 shares = withdrawMath.previewWithdraw(snapshot, pool, state.zeroForOne, amountOut);

        // Then: It burns the shares of the amount and the burn's rounding of 1 wei.
        assertEq(shares, (amountOut + 1).fullMulDivUp(state.supply, bufferOut));
    }

    function testFuzz_Success_previewWithdraw_TheBurnAndThePoolsSalePayTheAmount(
        RedeemState memory state,
        RangeState memory range,
        uint256 amountOut
    ) public {
        // Given: A range around spot, in a pool with its liquidity.
        (Snapshot memory snapshot, address pool) = givenValidState(state, range);

        // And: An amount of at most half what a redeem of the supply pays.
        {
            uint256 most = RedeemOptimizationMath.previewRedeem(snapshot, pool, state.zeroForOne, state.supply, 0);
            amountOut = bound(amountOut, 1, most / 2);
        }

        // When: Previewing the withdraw.
        uint256 shares = withdrawMath.previewWithdraw(snapshot, pool, state.zeroForOne, amountOut);

        // Then: It burns at most the supply.
        assertLe(shares, state.supply);

        // And: The burn's tokenOut and the pool's sale of the rest pay the amount.
        (uint256 releasedOut, uint256 releasedIn,) =
            snapshotLib.getBurnAmounts(snapshot, state.sqrtPriceX96, shares, state.zeroForOne);
        if (state.zeroForOne) (releasedOut, releasedIn) = (releasedIn, releasedOut);
        if (releasedOut < amountOut) {
            pool = burnedPoolOf(snapshot, 1, state.liquidity, shares);
            (, uint256 paid, uint256 received) = swap(
                snapshot,
                pool,
                state.zeroForOne,
                int256(amountOut - releasedOut),
                PoolLogic.sqrtPriceLimit(state.zeroForOne)
            );
            assertEq(received, amountOut - releasedOut);

            // And: The sale costs at most the burn's tokenIn.
            assertLe(paid, releasedIn);
        }
    }

    function testFuzz_Success_previewWithdraw_SellsForACoreWithoutTokenOut(
        RedeemState memory state,
        RangeState memory range,
        uint64 bufferOut,
        uint256 amountOut
    ) public {
        // Given: A price from 2^-32 to 2^32.
        state.sqrtPriceX96 =
            uint160(bound(state.sqrtPriceX96, Constants.MIN_SOLVER_SQRT_PRICE, Constants.MAX_SOLVER_SQRT_PRICE));
        state.supply = uint128(bound(state.supply, 1, type(uint128).max));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));

        // And: A range near spot on the tokenIn side, worth 2^60 of tokenOut at least.
        int24 tick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);
        if (state.zeroForOne) {
            range.tickLower = int24(bound(range.tickLower, tick + 1, tick + Constants.MAX_NEAR_SPOT_TICKS));
            range.tickUpper =
                int24(bound(range.tickUpper, range.tickLower + 1, range.tickLower + Constants.MAX_NEAR_SPOT_TICKS));
        } else {
            range.tickUpper = int24(bound(range.tickUpper, tick - Constants.MAX_NEAR_SPOT_TICKS, tick));
            range.tickLower =
                int24(bound(range.tickLower, range.tickUpper - Constants.MAX_NEAR_SPOT_TICKS, range.tickUpper - 1));
        }
        range.liquidity =
            uint128(bound(range.liquidity, Constants.MIN_SOLVER_RANGE_LIQUIDITY, Constants.MAX_RANGE_LIQUIDITY));
        range.liquidityStaked = 0;

        // And: A pool at least as deep as the range.
        state.liquidity = uint128(bound(state.liquidity, range.liquidity, Constants.MAX_RANGE_LIQUIDITY));

        // And: A buffer of tokenOut.
        Snapshot memory snapshot;
        {
            RangeState[] memory ranges = new RangeState[](1);
            ranges[0] = range;
            snapshot = snapshotOf(
                pricedOf(ranges),
                state.zeroForOne ? 0 : bufferOut,
                state.zeroForOne ? bufferOut : 0,
                state.supply,
                state.sqrtPriceX96,
                state.fee
            );
        }
        address pool = poolOf(1, state.liquidity, snapshot.ranges);

        // And: Past the buffer if it fits, half a redeem and a quarter of the reserve.
        {
            uint256 most = RedeemOptimizationMath.previewRedeem(snapshot, pool, state.zeroForOne, state.supply, 0);
            uint256 reserveOut = state.zeroForOne
                ? uint256(state.liquidity).fullMulDiv(state.sqrtPriceX96, 1 << 96)
                : uint256(state.liquidity).fullMulDiv(1 << 96, state.sqrtPriceX96);
            most = FixedPointMathLib.min(most / 2, reserveOut / 4);
            amountOut = bound(amountOut, FixedPointMathLib.min(uint256(bufferOut) + 1, most), most);
        }

        // When: Previewing the withdraw.
        uint256 shares = withdrawMath.previewWithdraw(snapshot, pool, state.zeroForOne, amountOut);

        // Then: It burns at most the supply.
        assertLe(shares, state.supply);
    }

    function testFuzz_Success_previewWithdraw_OnTheUpperTickOfARangeTheSaleReenters(
        RedeemState memory state,
        RangeState memory range,
        uint256 amountOut
    ) public {
        // Given: Spot on a range's upper tick reached from below, the pool without it.
        range.tickUpper = int24(bound(range.tickUpper, -Constants.BOUND_TICK + 1, Constants.BOUND_TICK));
        range.tickLower = int24(bound(range.tickLower, -Constants.BOUND_TICK, range.tickUpper - 1));
        range.liquidityStaked = 0;
        state.sqrtPriceX96 = TickMath.getSqrtPriceAtTick(range.tickUpper);
        uint256 width = state.sqrtPriceX96 - TickMath.getSqrtPriceAtTick(range.tickLower);
        uint256 rounding = 2 * (uint256(state.sqrtPriceX96).divUp(1 << 96) + 2) + 1;

        // And: A range whose token1 is over twice the burn's rounding, n = 2.
        range.liquidity =
            uint128(bound(range.liquidity, ((2 * rounding + 4) << 96).divUp(width), Constants.MAX_RANGE_LIQUIDITY));
        state.liquidity = uint128(bound(state.liquidity, 1, range.liquidity));
        state.supply = uint128(bound(state.supply, 3, type(uint128).max));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));

        // And: A dust range at the same ticks, which a burn short of the supply leaves.
        Snapshot memory snapshot;
        address pool;
        {
            RangeState[] memory ranges = new RangeState[](2);
            ranges[0] = range;
            ranges[1] = RangeState(0, range.tickLower, range.tickUpper, 1, 0, 0, 0);
            snapshot =
                snapshotOf(pricedOf(ranges), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
            pool = poolOf(1, state.liquidity, snapshot.ranges);
        }

        // And: The core's token1 less n, and the burn's rounding of token1, n = 2.
        uint256 holdingsOut = uint256(range.liquidity).fullMulDiv(width, 1 << 96) + width / (1 << 96) + state.idle1 - 2;

        // And: An amount of token1 whose burn alone takes at most half the supply.
        amountOut = bound(amountOut, 1, holdingsOut / 2 - rounding);

        // When: Previewing a withdraw of token1.
        uint256 shares = withdrawMath.previewWithdraw(snapshot, pool, true, amountOut);

        // Then: It burns at most the shares of the burn alone.
        assertLe(shares, (amountOut + rounding).fullMulDivUp(state.supply, holdingsOut));
    }

    function testFuzz_Success_previewWithdraw_OnTheLowerTickOfARangeTheSaleReenters(
        RedeemState memory state,
        RangeState memory range,
        uint256 amountOut
    ) public {
        // Given: Spot on a lower tick reached from above, the pool below it, without it.
        range.tickLower = int24(bound(range.tickLower, -Constants.BOUND_TICK + 1, Constants.BOUND_TICK - 1));
        range.tickUpper = int24(bound(range.tickUpper, range.tickLower + 1, Constants.BOUND_TICK));
        range.liquidity = uint128(bound(range.liquidity, 1, Constants.MAX_RANGE_LIQUIDITY));
        range.liquidityStaked = 0;
        state.sqrtPriceX96 = TickMath.getSqrtPriceAtTick(range.tickLower);
        state.liquidity = uint128(bound(state.liquidity, 1, range.liquidity));
        state.supply = uint128(bound(state.supply, 3, type(uint128).max));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));
        amountOut = bound(amountOut, 1, Constants.MAX_FUZZED_AMOUNT);

        // And: A dust range at the same ticks, which a burn short of the supply leaves.
        RangeState[] memory ranges = new RangeState[](2);
        ranges[0] = range;
        ranges[1] = RangeState(0, range.tickLower, range.tickUpper, 1, 0, 0, 0);
        Snapshot memory snapshot =
            snapshotOf(pricedOf(ranges), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
        snapshot.tick = range.tickLower - 1;

        // When: Previewing a withdraw of token0.
        uint256 shares =
            withdrawMath.previewWithdraw(snapshot, poolOf(1, state.liquidity, snapshot.ranges), false, amountOut);

        // Then: It burns the shares of the pool on the lower tick, with the ranges.
        snapshot.tick = range.tickLower;
        assertEq(
            shares,
            withdrawMath.previewWithdraw(
                snapshot, poolOf(1, state.liquidity + range.liquidity + 1, snapshot.ranges), false, amountOut
            )
        );
    }

    function testFuzz_Success_previewWithdraw_TheSaleInsideTheFirstStepForACoreWithoutToken1(
        RedeemState memory state,
        RangeState memory range,
        uint256 bufferIn,
        uint256 amountOut
    ) public {
        // Given: A range in the band, and the most rounding of token1 in its lower tick.
        range.tickLower = int24(bound(range.tickLower, -Constants.BOUND_TICK, Constants.BOUND_TICK - 1));
        range.tickUpper = int24(bound(range.tickUpper, range.tickLower + 1, Constants.BOUND_TICK));
        range.liquidityStaked = 0;
        uint256 sqrtPriceLowerX96 = TickMath.getSqrtPriceAtTick(range.tickLower);
        {
            uint256 roundingMost = uint256(TickMath.getSqrtPriceAtTick(range.tickLower + 1)).divUp(1 << 96) + 3;

            // And: Spot in the lower tick, where a uint64 liquidity's step pays rounding.
            uint256 distanceLeast = ((roundingMost + 2) << 96).divUp(Constants.MAX_SOLVER_LIQUIDITY);
            range.liquidity = uint128(bound(range.liquidity, 1, ((1 << 96) - 1) / distanceLeast));
            state.sqrtPriceX96 = uint160(
                bound(
                    state.sqrtPriceX96,
                    sqrtPriceLowerX96 + distanceLeast,
                    FixedPointMathLib.min(
                        TickMath.getSqrtPriceAtTick(range.tickLower + 1) - 1,
                        sqrtPriceLowerX96 + ((1 << 96) - 1) / range.liquidity
                    )
                )
            );

            // And: A pool holding the range, its step to the lower tick paying rounding.
            state.liquidity = uint128(
                bound(
                    state.liquidity,
                    FixedPointMathLib.max(
                        range.liquidity, ((roundingMost + 2) << 96).divUp(state.sqrtPriceX96 - sqrtPriceLowerX96)
                    ),
                    Constants.MAX_SOLVER_LIQUIDITY
                )
            );
        }
        state.supply = uint128(bound(state.supply, 1, type(uint128).max));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));

        // And: An amount of token1 that step pays, with the burn's rounding of token1.
        {
            uint256 rounding = uint256(state.sqrtPriceX96).divUp(1 << 96) + 3;
            amountOut = bound(
                amountOut,
                1,
                uint256(state.liquidity).fullMulDiv(state.sqrtPriceX96 - sqrtPriceLowerX96, 1 << 96) - rounding - 1
            );

            // And: Token0 idle over the step's cost, under where the range's part shows.
            bufferIn = bound(
                bufferIn,
                SqrtPriceMath.getAmount0Delta(uint160(sqrtPriceLowerX96), state.sqrtPriceX96, state.liquidity + 1, true)
                        .fullMulDivUp(1e6, 1e6 - state.fee) + uint256(1 << 96).divUp(state.sqrtPriceX96) + 8,
                FixedPointMathLib.min(
                    ((amountOut + rounding + 1) * range.liquidity).fullMulDiv(1 << 191, state.sqrtPriceX96),
                    type(uint256).max >> 97
                )
            );
        }
        Snapshot memory snapshot;
        address pool;
        {
            RangeState[] memory ranges = new RangeState[](1);
            ranges[0] = range;
            snapshot = snapshotOf(pricedOf(ranges), bufferIn, 0, state.supply, state.sqrtPriceX96, state.fee);
            pool = poolOf(1, state.liquidity, snapshot.ranges);
        }

        // When: Previewing a withdraw of token1.
        uint256 shares = withdrawMath.previewWithdraw(snapshot, pool, true, amountOut);

        // Then: It burns at most the supply.
        assertLe(shares, state.supply);

        // And: The burn's token1 and the pool's sale of the rest pay the amount.
        (uint256 amount0, uint256 amount1,) = snapshotLib.getBurnAmounts(snapshot, state.sqrtPriceX96, shares, true);
        if (amount1 < amountOut) {
            pool = burnedPoolOf(snapshot, 1, state.liquidity, shares);
            (, uint256 paid, uint256 received) =
                swap(snapshot, pool, true, int256(amountOut - amount1), PoolLogic.sqrtPriceLimit(true));
            assertEq(received, amountOut - amount1);

            // And: The sale costs at most the burn's token0.
            assertLe(paid, amount0);
        }
    }

    function testFuzz_Success_previewWithdraw_TheBurnAloneAboveTheCoresTokenOut(
        RedeemState memory state,
        RangeState memory range,
        uint256 amountOut
    ) public {
        // Given: A price of 2^-32 to 2^32, and a range near spot on each side of it.
        state.sqrtPriceX96 =
            uint160(bound(state.sqrtPriceX96, Constants.MIN_SOLVER_SQRT_PRICE, Constants.MAX_SOLVER_SQRT_PRICE));
        state.supply = uint128(bound(state.supply, 1, type(uint128).max));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));
        int24 tick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);
        range.tickLower = int24(bound(range.tickLower, tick - Constants.MAX_NEAR_SPOT_TICKS, tick - 1));
        range.tickUpper = int24(bound(range.tickUpper, tick + 1, tick + Constants.MAX_NEAR_SPOT_TICKS));

        // And: The range's liquidity as the pool's only liquidity.
        range.liquidity = uint128(bound(range.liquidity, 1, Constants.MAX_RANGE_LIQUIDITY));
        range.liquidityStaked = 0;
        state.liquidity = range.liquidity;
        Snapshot memory snapshot;
        {
            RangeState[] memory ranges = new RangeState[](1);
            ranges[0] = range;
            snapshot = snapshotOf(pricedOf(ranges), 0, 0, state.supply, state.sqrtPriceX96, state.fee);
        }
        address pool = poolOf(1, state.liquidity, snapshot.ranges);

        // And: An amount of one to two times the core's tokenOut.
        {
            (uint256 amount0, uint256 amount1,) =
                snapshotLib.getBurnAmounts(snapshot, state.sqrtPriceX96, state.supply, false);
            uint256 holdingsOut = state.zeroForOne ? amount1 : amount0;
            amountOut = bound(amountOut, holdingsOut.max(1), (2 * holdingsOut).max(1));
        }

        // When: Previewing the withdraw.
        uint256 shares = withdrawMath.previewWithdraw(snapshot, pool, state.zeroForOne, amountOut);

        // Then: The sale takes the core's tokenOut too, so it burns more than the supply.
        assertGt(shares, state.supply);
    }

    function testFuzz_Success_previewWithdraw_NoneWhenThePoolsWholeReserveDoesNotPay(
        RedeemState memory state,
        uint64 bufferIn,
        int24 tickSpacing,
        uint256 amountOut
    ) public {
        // Given: A core holding only tokenIn, and an active pool without ticks.
        bufferIn = uint64(bound(bufferIn, 1, type(uint64).max));
        state.liquidity = uint128(bound(state.liquidity, 1, Constants.MAX_SOLVER_LIQUIDITY));
        (Snapshot memory snapshot,) = givenBuffersOnly(state, 0, bufferIn, 1);
        address pool = poolOf(
            int24(bound(tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING)),
            state.liquidity,
            snapshot.ranges
        );

        // And: An amount above the pool's whole tokenOut reserve.
        amountOut = bound(
            amountOut,
            (state.zeroForOne
                        ? uint256(state.liquidity).fullMulDiv(state.sqrtPriceX96, 1 << 96)
                        : uint256(state.liquidity).fullMulDiv(1 << 96, state.sqrtPriceX96)) + 1,
            type(uint128).max
        );

        // When: Previewing the withdraw.
        uint256 shares = withdrawMath.previewWithdraw(snapshot, pool, state.zeroForOne, amountOut);

        // Then: No shares pay it, the sale reaching the pool's price limit.
        assertEq(shares, type(uint256).max);
    }

    function testFuzz_Success_previewWithdraw_TheFewestSharesAtTheFirstStepsRootAndNeighbour(
        RedeemState memory state,
        uint256 rangeCount,
        uint256 amountOut
    ) public {
        // Given: A price of 2^-32 to 2^32 mid tick, a supply, a fee.
        {
            state.sqrtPriceX96 =
                uint160(bound(state.sqrtPriceX96, Constants.MIN_SOLVER_SQRT_PRICE, Constants.MAX_SOLVER_SQRT_PRICE));
            int24 tick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);
            uint256 sqrtPriceLowerX96 = TickMath.getSqrtPriceAtTick(tick);
            uint256 quarter = (TickMath.getSqrtPriceAtTick(tick + 1) - sqrtPriceLowerX96) / 4;
            state.sqrtPriceX96 =
                uint160(bound(state.sqrtPriceX96, sqrtPriceLowerX96 + quarter, sqrtPriceLowerX96 + 3 * quarter));
        }
        state.supply = uint128(bound(state.supply, 1, type(uint128).max));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));

        // And: n empty ranges, a pool without ticks, its first step to the word's end.
        Snapshot memory snapshot = snapshotOf(
            new PricedRange[](bound(rangeCount, 1, ConfigLib.MAX_RANGE_CAP)),
            0,
            0,
            state.supply,
            state.sqrtPriceX96,
            state.fee
        );
        for (uint256 i; i < snapshot.ranges.length; ++i) {
            snapshot.ranges[i].sqrtPriceLowerX96 = TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK);
            snapshot.ranges[i].sqrtPriceUpperX96 = TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK);
        }
        state.liquidity =
            uint128(bound(state.liquidity, Constants.MIN_SOLVER_STEP_LIQUIDITY, Constants.MAX_SOLVER_LIQUIDITY));
        SwapState memory swapState;
        StepComputations memory step;
        uint256[3] memory amounts;
        uint256 shares;
        {
            address pool = poolOf(1, state.liquidity, snapshot.ranges);
            swapState = SwapStateLib.getSwapState(snapshot, pool, state.zeroForOne);
            SwapStateLib.setNextTick(
                step, swapState, pool, state.zeroForOne, PoolLogic.sqrtPriceLimit(state.zeroForOne)
            );

            // And: C of the roundings, and the step's cost and output, at 2^96.
            uint256 cost = (snapshotLib.getRounding(snapshot, state.sqrtPriceX96, state.zeroForOne) << 96)
                + ((2e6 - uint256(state.fee)) << 96).divUp(1e6 - uint256(state.fee));
            swapState.amountIn = cost;
            (,,,, StepComputations memory stepFull) = withdrawMath.getSharesForAmounts(
                snapshot, state.zeroForOne, 0, 0, 0, swapState, step, swapState.amountIn
            );

            // And: TokenIn above C within the step's cost, tokenOut, n more for floors.
            state.idle1 = uint64(bound(state.idle1, 1 + snapshot.ranges.length, type(uint64).max));
            state.idle0 = uint64(
                bound(
                    state.idle0,
                    (cost >> 96) + 1 + snapshot.ranges.length,
                    ((cost + stepFull.amountIn) >> 96) + snapshot.ranges.length
                )
            );
            (snapshot.buffer0, snapshot.buffer1) =
                state.zeroForOne ? (state.idle0, state.idle1) : (state.idle1, state.idle0);
            swapState = SwapStateLib.getSwapState(snapshot, pool, state.zeroForOne);
            swapState.amountIn = cost;

            // And: The holdings B and A less n, at 2^96.
            (amounts[0], amounts[1]) =
                EquivalentPositionMath.amountsAt(swapState.position, state.sqrtPriceX96, state.zeroForOne);
            (amounts[0], amounts[1]) =
            (
                amounts[0].zeroFloorSub(snapshot.ranges.length) << 96,
                amounts[1].zeroFloorSub(snapshot.ranges.length) << 96
            );

            // And: A and the step pay: a, with roundings and the step's wei, at 2^96.
            uint256 rounding = snapshotLib.getRounding(snapshot, state.sqrtPriceX96, !state.zeroForOne);
            amountOut = bound(amountOut, 1, ((amounts[1] + stepFull.amountOut) >> 96) - rounding - 1);
            amounts[2] = (amountOut + rounding + 1) << 96;

            // When: Previewing the withdraw.
            shares = withdrawMath.previewWithdraw(snapshot, pool, state.zeroForOne, amountOut);
        }

        // Then: The fewest of the burn, the step's end, the root at a + 1 and neighbour.
        uint256 sharesLeast = (amounts[2] >> 96) - 1 > amounts[1] >> 96
            ? type(uint256).max
            : ((amounts[2] >> 96) - 1).fullMulDivUp(state.supply, amounts[1] >> 96);
        {
            (uint256 sharesEnd,,,,) = withdrawMath.getSharesForAmounts(
                snapshot, state.zeroForOne, amounts[2], amounts[0], amounts[1], swapState, step, swapState.amountIn
            );
            sharesLeast = FixedPointMathLib.min(sharesLeast, sharesEnd);
        }
        {
            (int256 a, int256 b, int256 c) = withdrawMath.getQuadraticCoefficients(
                snapshot, state.zeroForOne, amounts[2] + 1, amounts[0], amounts[1], swapState, swapState.amountIn
            );
            step.sqrtPriceTargetX96 =
                withdrawMath.getNextSqrtPrice(state.zeroForOne, swapState, step, QuadraticMath.getRoot(a, b, c));
        }
        (uint256 sharesStep, bool costBinds,,,) = withdrawMath.getSharesForAmounts(
            snapshot, state.zeroForOne, amounts[2], amounts[0], amounts[1], swapState, step, swapState.amountIn
        );
        sharesLeast = FixedPointMathLib.min(sharesLeast, sharesStep);
        step.sqrtPriceTargetX96 =
            costBinds == state.zeroForOne ? step.sqrtPriceTargetX96 + 1 : step.sqrtPriceTargetX96 - 1;
        (sharesStep,,,,) = withdrawMath.getSharesForAmounts(
            snapshot, state.zeroForOne, amounts[2], amounts[0], amounts[1], swapState, step, swapState.amountIn
        );
        assertEq(shares, FixedPointMathLib.min(sharesLeast, sharesStep));
    }

    function testFuzz_Success_previewWithdraw_TheFewestSharesForAnAmountPastTheBitwiseOrOfAAndTheStep(
        RedeemState memory state,
        uint256 rangeCount,
        uint256 amountOut
    ) public {
        // Given: A price of 2^-32 to 2^32 mid tick, a supply, a fee.
        {
            state.sqrtPriceX96 =
                uint160(bound(state.sqrtPriceX96, Constants.MIN_SOLVER_SQRT_PRICE, Constants.MAX_SOLVER_SQRT_PRICE));
            int24 tick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);
            uint256 sqrtPriceLowerX96 = TickMath.getSqrtPriceAtTick(tick);
            uint256 quarter = (TickMath.getSqrtPriceAtTick(tick + 1) - sqrtPriceLowerX96) / 4;
            state.sqrtPriceX96 =
                uint160(bound(state.sqrtPriceX96, sqrtPriceLowerX96 + quarter, sqrtPriceLowerX96 + 3 * quarter));
        }
        state.supply = uint128(bound(state.supply, 1, type(uint128).max));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));

        // And: n empty ranges, a pool without ticks, its first step to the word's end.
        Snapshot memory snapshot = snapshotOf(
            new PricedRange[](bound(rangeCount, 1, ConfigLib.MAX_RANGE_CAP)),
            0,
            0,
            state.supply,
            state.sqrtPriceX96,
            state.fee
        );
        for (uint256 i; i < snapshot.ranges.length; ++i) {
            snapshot.ranges[i].sqrtPriceLowerX96 = TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK);
            snapshot.ranges[i].sqrtPriceUpperX96 = TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK);
        }
        state.liquidity =
            uint128(bound(state.liquidity, Constants.MIN_SOLVER_STEP_LIQUIDITY, Constants.MAX_SOLVER_LIQUIDITY));
        SwapState memory swapState;
        StepComputations memory step;
        uint256[3] memory amounts;
        uint256 shares;
        {
            address pool = poolOf(1, state.liquidity, snapshot.ranges);
            swapState = SwapStateLib.getSwapState(snapshot, pool, state.zeroForOne);
            SwapStateLib.setNextTick(
                step, swapState, pool, state.zeroForOne, PoolLogic.sqrtPriceLimit(state.zeroForOne)
            );

            // And: C of the roundings, and the step's cost and output, at 2^96.
            uint256 cost = (snapshotLib.getRounding(snapshot, state.sqrtPriceX96, state.zeroForOne) << 96)
                + ((2e6 - uint256(state.fee)) << 96).divUp(1e6 - uint256(state.fee));
            swapState.amountIn = cost;
            (,,,, StepComputations memory stepFull) = withdrawMath.getSharesForAmounts(
                snapshot, state.zeroForOne, 0, 0, 0, swapState, step, swapState.amountIn
            );

            // And: TokenIn above C within the step's cost, tokenOut to twice its output.
            state.idle1 = uint64(
                bound(
                    state.idle1,
                    1 + snapshot.ranges.length,
                    FixedPointMathLib.min((stepFull.amountOut >> 95) + 1 + snapshot.ranges.length, type(uint64).max)
                )
            );
            state.idle0 = uint64(
                bound(
                    state.idle0,
                    (cost >> 96) + 1 + snapshot.ranges.length,
                    ((cost + stepFull.amountIn) >> 96) + snapshot.ranges.length
                )
            );
            (snapshot.buffer0, snapshot.buffer1) =
                state.zeroForOne ? (state.idle0, state.idle1) : (state.idle1, state.idle0);
            swapState = SwapStateLib.getSwapState(snapshot, pool, state.zeroForOne);
            swapState.amountIn = cost;

            // And: The holdings B and A less n, at 2^96.
            (amounts[0], amounts[1]) =
                EquivalentPositionMath.amountsAt(swapState.position, state.sqrtPriceX96, state.zeroForOne);
            (amounts[0], amounts[1]) =
            (
                amounts[0].zeroFloorSub(snapshot.ranges.length) << 96,
                amounts[1].zeroFloorSub(snapshot.ranges.length) << 96
            );

            // And: A and the step pay, past their bitwise or if fit: a, at 2^96.
            uint256 rounding = snapshotLib.getRounding(snapshot, state.sqrtPriceX96, !state.zeroForOne);
            {
                uint256 amountOutMost = ((amounts[1] + stepFull.amountOut) >> 96) - rounding - 1;
                amountOut = bound(
                    amountOut,
                    FixedPointMathLib.min(((amounts[1] | stepFull.amountOut) >> 96) - rounding, amountOutMost),
                    amountOutMost
                );
            }
            amounts[2] = (amountOut + rounding + 1) << 96;

            // When: Previewing the withdraw.
            shares = withdrawMath.previewWithdraw(snapshot, pool, state.zeroForOne, amountOut);
        }

        // Then: The fewest of the burn, the step's end, the root at a + 1 and neighbour.
        uint256 sharesLeast = (amounts[2] >> 96) - 1 > amounts[1] >> 96
            ? type(uint256).max
            : ((amounts[2] >> 96) - 1).fullMulDivUp(state.supply, amounts[1] >> 96);
        {
            (uint256 sharesEnd,,,,) = withdrawMath.getSharesForAmounts(
                snapshot, state.zeroForOne, amounts[2], amounts[0], amounts[1], swapState, step, swapState.amountIn
            );
            sharesLeast = FixedPointMathLib.min(sharesLeast, sharesEnd);
        }
        {
            (int256 a, int256 b, int256 c) = withdrawMath.getQuadraticCoefficients(
                snapshot, state.zeroForOne, amounts[2] + 1, amounts[0], amounts[1], swapState, swapState.amountIn
            );
            step.sqrtPriceTargetX96 =
                withdrawMath.getNextSqrtPrice(state.zeroForOne, swapState, step, QuadraticMath.getRoot(a, b, c));
        }
        (uint256 sharesStep, bool costBinds,,,) = withdrawMath.getSharesForAmounts(
            snapshot, state.zeroForOne, amounts[2], amounts[0], amounts[1], swapState, step, swapState.amountIn
        );
        sharesLeast = FixedPointMathLib.min(sharesLeast, sharesStep);
        step.sqrtPriceTargetX96 =
            costBinds == state.zeroForOne ? step.sqrtPriceTargetX96 + 1 : step.sqrtPriceTargetX96 - 1;
        (sharesStep,,,,) = withdrawMath.getSharesForAmounts(
            snapshot, state.zeroForOne, amounts[2], amounts[0], amounts[1], swapState, step, swapState.amountIn
        );
        assertEq(shares, FixedPointMathLib.min(sharesLeast, sharesStep));
    }

    function testFuzz_Success_previewWithdraw_OneForZero_TheRootWhenTheStepPaysTheAmountExactly(
        RedeemState memory state,
        int24 tick,
        uint256 amountOut
    ) public {
        // Given: A tick at a word's end, priced 2^-32 to 2^32, a supply and a fee.
        tick = int24(
            bound(
                tick,
                TickMath.getTickAtSqrtPrice(Constants.MIN_SOLVER_SQRT_PRICE),
                TickMath.getTickAtSqrtPrice(Constants.MAX_SOLVER_SQRT_PRICE) - Constants.BITMAP_WORD_TICKS
            )
        ) | (Constants.BITMAP_WORD_TICKS - 1);
        state.supply = uint128(bound(state.supply, 1, type(uint128).max));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));

        {
            // And: An amount whose step stays in the word, costing half a uint64 at most.
            uint256 sqrtPriceTickX96 = TickMath.getSqrtPriceAtTick(tick);
            uint256 gap = (1 << 192) / TickMath.getSqrtPriceAtTick(tick - Constants.BITMAP_WORD_TICKS + 1)
                - uint256(1 << 192).divUp(sqrtPriceTickX96);
            amountOut = bound(
                amountOut,
                1,
                FixedPointMathLib.min(
                    FullMath.mulDiv(Constants.MAX_SOLVER_LIQUIDITY, gap, 1 << 96),
                    FullMath.mulDiv(type(uint64).max / 2, 1 << 192, sqrtPriceTickX96 * sqrtPriceTickX96)
                ) - 3
            );
            state.liquidity = uint128(
                bound(state.liquidity, (((amountOut + 2) << 96) + 1).divUp(gap), Constants.MAX_SOLVER_LIQUIDITY)
            );

            // And: Spot where the step pays it, rounding and wei exactly.
            state.sqrtPriceX96 = uint160(
                uint256(state.liquidity)
                    .fullMulDiv(
                        1 << 192,
                        uint256(state.liquidity).fullMulDivUp(1 << 192, sqrtPriceTickX96) + ((amountOut + 2) << 96)
                    )
            );
        }

        // And: Only tokenIn, at least the step's cost, and the tick initialized.
        Snapshot memory snapshot = snapshotOf(new PricedRange[](0), 0, 0, state.supply, state.sqrtPriceX96, state.fee);
        SwapState memory swapState;
        StepComputations memory step;
        uint256[3] memory amounts;
        uint256 shares;
        {
            PoolMock pool = new PoolMock(1, state.liquidity);
            pool.addLiquidityNet(tick, 1);
            swapState = SwapStateLib.getSwapState(snapshot, address(pool), false);
            SwapStateLib.setNextTick(step, swapState, address(pool), false, PoolLogic.sqrtPriceLimit(false));
            uint256 cost = (snapshotLib.getRounding(snapshot, state.sqrtPriceX96, false) << 96)
                + ((2e6 - uint256(state.fee)) << 96).divUp(1e6 - uint256(state.fee));
            swapState.amountIn = cost;
            (,,,, StepComputations memory stepFull) =
                withdrawMath.getSharesForAmounts(snapshot, false, 0, 0, 0, swapState, step, swapState.amountIn);
            state.idle0 = uint64(bound(state.idle0, ((cost + stepFull.amountIn) >> 96) + 1, type(uint64).max));
            snapshot.buffer1 = state.idle0;
            swapState = SwapStateLib.getSwapState(snapshot, address(pool), false);
            swapState.amountIn = cost;

            // And: The holdings B and A, and a with the rounding and step's wei, at 2^96.
            (amounts[0], amounts[1]) = EquivalentPositionMath.amountsAt(swapState.position, state.sqrtPriceX96, false);
            (amounts[0], amounts[1], amounts[2]) = (amounts[0] << 96, amounts[1] << 96, (amountOut + 2) << 96);

            // When: Previewing a withdraw of token0.
            shares = withdrawMath.previewWithdraw(snapshot, address(pool), false, amountOut);
        }

        // Then: The fewest of the step's end, the root at a + 1 and its neighbour.
        (uint256 sharesLeast,,,,) = withdrawMath.getSharesForAmounts(
            snapshot, false, amounts[2], amounts[0], amounts[1], swapState, step, swapState.amountIn
        );
        {
            (int256 a, int256 b, int256 c) = withdrawMath.getQuadraticCoefficients(
                snapshot, false, amounts[2] + 1, amounts[0], amounts[1], swapState, swapState.amountIn
            );
            step.sqrtPriceTargetX96 =
                withdrawMath.getNextSqrtPrice(false, swapState, step, QuadraticMath.getRoot(a, b, c));
        }
        (uint256 sharesStep, bool costBinds,,,) = withdrawMath.getSharesForAmounts(
            snapshot, false, amounts[2], amounts[0], amounts[1], swapState, step, swapState.amountIn
        );
        sharesLeast = FixedPointMathLib.min(sharesLeast, sharesStep);
        step.sqrtPriceTargetX96 = costBinds ? step.sqrtPriceTargetX96 - 1 : step.sqrtPriceTargetX96 + 1;
        (sharesStep,,,,) = withdrawMath.getSharesForAmounts(
            snapshot, false, amounts[2], amounts[0], amounts[1], swapState, step, swapState.amountIn
        );
        assertEq(shares, FixedPointMathLib.min(sharesLeast, sharesStep));
    }

    function testFuzz_Success_previewWithdraw_TheRootOfTheSecondStepAfterAStepPayingUnderAWei(
        RedeemState memory state,
        int24 tick,
        uint256 liquidityFirst,
        uint256 distance,
        uint256 amountOut
    ) public {
        // Given: Spot inside a tick of 2^-32 to 2^32, a supply, a fee.
        tick = int24(
            bound(
                tick,
                -TickMath.getTickAtSqrtPrice(Constants.MAX_SOLVER_SQRT_PRICE),
                TickMath.getTickAtSqrtPrice(Constants.MAX_SOLVER_SQRT_PRICE) - 1
            )
        );
        distance = bound(
            distance,
            1,
            FixedPointMathLib.min(
                TickMath.getSqrtPriceAtTick(tick + 1) - TickMath.getSqrtPriceAtTick(tick) - 1, (1 << 96) - 1
            )
        );
        state.sqrtPriceX96 = uint160(TickMath.getSqrtPriceAtTick(tick) + distance);
        state.supply = uint128(bound(state.supply, 1, type(uint128).max));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));

        // And: A liquidity past the tick, a step's output past its roundings.
        state.liquidity =
            uint128(bound(state.liquidity, Constants.MIN_SOLVER_STEP_LIQUIDITY, Constants.MAX_SOLVER_STEP_LIQUIDITY));

        // And: Less liquidity down to the tick, its step paying under a wei.
        liquidityFirst =
            bound(liquidityFirst, 1, FixedPointMathLib.min(((1 << 96) - 1) / distance, state.liquidity - 1));
        PoolMock pool = new PoolMock(1, uint128(liquidityFirst));
        pool.addLiquidityNet(tick, int128(int256(liquidityFirst)) - int128(state.liquidity));

        // And: Only tokenIn, at least both steps' cost, and the second step's output S2.
        Snapshot memory snapshot = snapshotOf(new PricedRange[](0), 0, 0, state.supply, state.sqrtPriceX96, state.fee);
        SwapState memory swapState;
        StepComputations memory step;
        {
            swapState = SwapStateLib.getSwapState(snapshot, address(pool), true);
            SwapStateLib.setNextTick(step, swapState, address(pool), true, PoolLogic.sqrtPriceLimit(true));
            swapState.amountIn = (snapshotLib.getRounding(snapshot, state.sqrtPriceX96, true) << 96)
                + ((2e6 - uint256(state.fee)) << 96).divUp(1e6 - uint256(state.fee));
            (,,,, step) = withdrawMath.getSharesForAmounts(snapshot, true, 0, 0, 0, swapState, step, swapState.amountIn);
            SwapStateLib.crossTick(swapState, step, snapshot, address(pool), true, PoolLogic.sqrtPriceLimit(true));
            swapState.amountIn += ((2e6 - uint256(state.fee)) << 96).divUp(1e6 - uint256(state.fee));
            SwapStateLib.setNextTick(step, swapState, address(pool), true, PoolLogic.sqrtPriceLimit(true));
            (,,,, step) = withdrawMath.getSharesForAmounts(snapshot, true, 0, 0, 0, swapState, step, swapState.amountIn);
            state.idle0 = uint64(bound(state.idle0, ((swapState.amountIn + step.amountIn) >> 96) + 1, type(uint64).max));
            snapshot.buffer0 = state.idle0;

            // And: An amount above half S2, so a plus the first step's output passes S2.
            amountOut = bound(amountOut, (step.amountOut >> 97) + 1, (step.amountOut >> 96) - 3);
        }

        // When: Previewing a withdraw of token1.
        uint256 shares = withdrawMath.previewWithdraw(snapshot, address(pool), true, amountOut);

        // Then: The holdings B and A, a with the rounding and first step's wei, at 2^96.
        swapState = SwapStateLib.getSwapState(snapshot, address(pool), true);
        uint256[3] memory amounts;
        (amounts[0], amounts[1]) = EquivalentPositionMath.amountsAt(swapState.position, state.sqrtPriceX96, true);
        (amounts[0], amounts[1], amounts[2]) = (amounts[0] << 96, amounts[1] << 96, (amountOut + 2) << 96);

        // And: The first step's end, then the holdings, cost and a after it.
        SwapStateLib.setNextTick(step, swapState, address(pool), true, PoolLogic.sqrtPriceLimit(true));
        swapState.amountIn = (snapshotLib.getRounding(snapshot, state.sqrtPriceX96, true) << 96)
            + ((2e6 - uint256(state.fee)) << 96).divUp(1e6 - uint256(state.fee));
        uint256 sharesLeast;
        {
            uint256 holdingsInDelta;
            uint256 holdingsOutDelta;
            (sharesLeast,, holdingsInDelta, holdingsOutDelta, step) = withdrawMath.getSharesForAmounts(
                snapshot, true, amounts[2], amounts[0], amounts[1], swapState, step, swapState.amountIn
            );
            (amounts[0], amounts[1]) = (amounts[0] + holdingsInDelta, amounts[1].zeroFloorSub(holdingsOutDelta));
        }
        SwapStateLib.crossTick(swapState, step, snapshot, address(pool), true, PoolLogic.sqrtPriceLimit(true));
        swapState.amountIn += ((2e6 - uint256(state.fee)) << 96).divUp(1e6 - uint256(state.fee));
        amounts[2] += 1 << 96;

        // And: The fewest of those, step two's end, its root at a + 1 and its neighbour.
        SwapStateLib.setNextTick(step, swapState, address(pool), true, PoolLogic.sqrtPriceLimit(true));
        {
            (uint256 sharesEnd,,,,) = withdrawMath.getSharesForAmounts(
                snapshot, true, amounts[2], amounts[0], amounts[1], swapState, step, swapState.amountIn
            );
            sharesLeast = FixedPointMathLib.min(sharesLeast, sharesEnd);
        }
        {
            (int256 a, int256 b, int256 c) = withdrawMath.getQuadraticCoefficients(
                snapshot,
                true,
                amounts[2] - swapState.amountOut + 1,
                amounts[0],
                amounts[1],
                swapState,
                swapState.amountIn
            );
            step.sqrtPriceTargetX96 =
                withdrawMath.getNextSqrtPrice(true, swapState, step, QuadraticMath.getRoot(a, b, c));
        }
        (uint256 sharesStep, bool costBinds,,,) = withdrawMath.getSharesForAmounts(
            snapshot, true, amounts[2], amounts[0], amounts[1], swapState, step, swapState.amountIn
        );
        sharesLeast = FixedPointMathLib.min(sharesLeast, sharesStep);
        step.sqrtPriceTargetX96 = costBinds ? step.sqrtPriceTargetX96 + 1 : step.sqrtPriceTargetX96 - 1;
        (sharesStep,,,,) = withdrawMath.getSharesForAmounts(
            snapshot, true, amounts[2], amounts[0], amounts[1], swapState, step, swapState.amountIn
        );
        assertEq(shares, FixedPointMathLib.min(sharesLeast, sharesStep));
    }
}
