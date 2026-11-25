/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { RedeemOptimizationMath_Fuzz_Test } from "./_RedeemOptimizationMath.fuzz.t.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "maxRedeem" of library "RedeemOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract MaxRedeem_RedeemOptimizationMath_Fuzz_Test is RedeemOptimizationMath_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_maxRedeem_TheSharesWithoutTokenIn(
        RedeemState memory state,
        uint64 bufferOut,
        uint256 shares
    ) public {
        // Given: A core holding only tokenOut, the supply in shares at most, a pool.
        (Snapshot memory snapshot, address pool) = givenBuffersOnly(state, bufferOut, 0, 1);
        shares = bound(shares, 1, state.supply);

        // When: Calculating the most of the shares a redeem burns.
        uint256 redeemable = redeemMath.maxRedeem(snapshot, pool, state.zeroForOne, shares);

        // Then: It is the shares, their redeem selling nothing.
        assertEq(redeemable, shares);
    }

    function testFuzz_Success_maxRedeem_ZeroWithoutActiveLiquidity(
        RedeemState memory state,
        uint64 bufferOut,
        uint64 bufferIn,
        uint256 shares
    ) public {
        // Given: A core with tokenIn idle, shares up to the supply, an inactive pool.
        bufferIn = uint64(bound(bufferIn, 1, type(uint64).max));
        (Snapshot memory snapshot, address pool) = givenBuffersOnly(state, bufferOut, bufferIn, 0);
        shares = bound(shares, 1, state.supply);

        // When: Calculating the most of the shares a redeem burns.
        uint256 redeemable = redeemMath.maxRedeem(snapshot, pool, state.zeroForOne, shares);

        // Then: It is zero, the pool buying none of the tokenIn the burn releases.
        assertEq(redeemable, 0);
    }

    function testFuzz_Success_maxRedeem_TheSaleToTheRangesEdgeAsThePoolsOnlyLiquidity(
        RedeemState memory state,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: Idle tokenIn, a range around spot, and fewer shares than the supply.
        if (state.zeroForOne) state.idle0 = uint64(bound(state.idle0, 1, type(uint64).max));
        else state.idle1 = uint64(bound(state.idle1, 1, type(uint64).max));
        state.supply = uint128(bound(state.supply, 2, type(uint64).max));
        (Snapshot memory snapshot,) = givenValidState(state, range);
        shares = bound(shares, 1, state.supply - 1);

        // And: The range's edge in the sale's direction inside the swap cost limit.
        uint160 sqrtPriceLimitX96 = snapshotLib.getSwapCostLimit(snapshot, state.zeroForOne);
        if (state.zeroForOne) {
            range.tickLower =
                int24(bound(range.tickLower, TickMath.getTickAtSqrtPrice(sqrtPriceLimitX96) + 1, snapshot.tick - 1));
        } else {
            range.tickUpper =
                int24(bound(range.tickUpper, snapshot.tick + 1, TickMath.getTickAtSqrtPrice(sqrtPriceLimitX96) - 1));
        }

        // And: The range as the pool's only liquidity.
        address pool;
        {
            RangeState[] memory ranges = new RangeState[](1);
            ranges[0] = range;
            snapshot.ranges = pricedOf(ranges);
            state.liquidity = range.liquidity + range.liquidityStaked;
            pool = poolOf(1, state.liquidity, snapshot.ranges);
        }

        // When: Calculating the most of the shares a redeem burns.
        uint256 redeemable = redeemMath.maxRedeem(snapshot, pool, state.zeroForOne, shares);

        // Then: It is the shares whose tokenIn the pool buys to the edge, less the burn.
        uint256 amountIn;
        {
            PricedRange[] memory left = new PricedRange[](1);
            left[0] = PricedRange({
                liquidity: uint128(state.liquidity - uint256(state.liquidity).fullMulDivUp(shares, state.supply)),
                unstakedLiquidity: 0,
                sqrtPriceLowerX96: snapshot.ranges[0].sqrtPriceLowerX96,
                sqrtPriceUpperX96: snapshot.ranges[0].sqrtPriceUpperX96
            });
            (, amountIn,) = swap(
                snapshot, poolOf(1, left[0].liquidity, left), state.zeroForOne, -type(int256).max, sqrtPriceLimitX96
            );
        }
        uint256 released;
        {
            (uint256 amount0, uint256 amount1,) =
                snapshotLib.getBurnAmounts(snapshot, state.sqrtPriceX96, state.supply, state.zeroForOne);
            released = (state.zeroForOne ? amount0 : amount1) + 2 * snapshot.ranges.length;
        }
        assertEq(redeemable, FixedPointMathLib.min(shares, amountIn.fullMulDiv(state.supply, released)));
    }

    function testFuzz_Success_maxRedeem_TheSaleToTheSwapCostLimitOverTheIdleTokenIn(
        RedeemState memory state,
        uint64 bufferOut,
        uint256 bufferIn,
        uint256 maxSwapCostBps,
        uint256 shares
    ) public {
        // Given: A core holding only buffers, an active pool.
        state.liquidity = uint128(bound(state.liquidity, 1, type(uint64).max));
        (Snapshot memory snapshot, address pool) = givenBuffersOnly(state, bufferOut, 0, 1);

        // And: A max swap cost above the fee, the tokenIn the pool takes to its price.
        maxSwapCostBps = bound(
            maxSwapCostBps,
            FixedPointMathLib.divUp(state.fee, Constants.PIPS_PER_BPS) + 1,
            ConfigLib.BPS_DENOMINATOR - 1
        );
        mockMaxSwapCostBps(MOCK_CORE, maxSwapCostBps);
        (, uint256 taken,) = swap(
            snapshot,
            pool,
            state.zeroForOne,
            -type(int256).max,
            snapshotLib.getSwapCostLimit(snapshot, state.zeroForOne)
        );

        // And: Idle tokenIn above that, a supply of its square over it, shares near it.
        bufferIn = bound(bufferIn, taken + 1, 2 * taken);
        if (state.zeroForOne) snapshot.buffer0 = bufferIn;
        else snapshot.buffer1 = bufferIn;
        snapshot.supply = bound(state.supply, (bufferIn * (bufferIn + 1)).divUp(taken), type(uint128).max);
        shares = bound(shares, taken.fullMulDiv(snapshot.supply, bufferIn), snapshot.supply);

        // When: Calculating the most of the shares a redeem burns.
        uint256 redeemable = redeemMath.maxRedeem(snapshot, pool, state.zeroForOne, shares);

        // Then: The shares whose idle tokenIn the pool takes to that price, no floors.
        assertEq(redeemable, FixedPointMathLib.min(shares, taken.fullMulDiv(snapshot.supply, bufferIn)));
    }

    function testFuzz_Success_maxRedeem_ItsSaleEndsAtOrBeforeTheSwapCostLimit(
        RedeemState memory state,
        RangeState memory range,
        uint256 maxSwapCostBps,
        uint256 shares
    ) public {
        // Given: A range around spot, a supply of the dead shares at least, fewer shares.
        state.supply = uint128(bound(state.supply, Constants.DEAD_SHARES, type(uint64).max));
        (Snapshot memory snapshot, address pool) = givenValidState(state, range);
        shares = bound(shares, 1, state.supply - 1);

        // And: A max swap cost above the pool fee, and the price where a sale reaches it.
        maxSwapCostBps = bound(
            maxSwapCostBps,
            FixedPointMathLib.divUp(state.fee, Constants.PIPS_PER_BPS) + 1,
            ConfigLib.BPS_DENOMINATOR - 1
        );
        mockMaxSwapCostBps(MOCK_CORE, maxSwapCostBps);
        uint256 sqrtPriceLimitX96 = snapshotLib.getSwapCostLimit(snapshot, state.zeroForOne);

        // When: Calculating the most of the shares a redeem burns.
        uint256 redeemable = redeemMath.maxRedeem(snapshot, pool, state.zeroForOne, shares);

        // Then: It is the shares at most, their tokenIn's sale ending within the limit.
        assertLe(redeemable, shares);
        (, uint160 sqrtPriceEnd) = saleOf(snapshot, state, redeemable);
        if (state.zeroForOne) assertGe(sqrtPriceEnd, sqrtPriceLimitX96);
        else assertLe(sqrtPriceEnd, sqrtPriceLimitX96);
    }

    function testFuzz_Success_maxRedeem_TheSharesWhenTheirSaleEndsInsideTheSwapCostLimit(
        RedeemState memory state,
        RangeState memory range,
        uint256 maxSwapCostBps,
        uint256 shares
    ) public {
        // Given: A range around spot, a supply of the dead shares at least, fewer shares.
        state.supply = uint128(bound(state.supply, Constants.DEAD_SHARES, type(uint64).max));
        (Snapshot memory snapshot, address pool) = givenValidState(state, range);
        shares = bound(shares, 1, state.supply - 1);

        // And: A max swap cost above the pool fee, and the price where a sale reaches it.
        maxSwapCostBps = bound(
            maxSwapCostBps,
            FixedPointMathLib.divUp(state.fee, Constants.PIPS_PER_BPS) + 1,
            ConfigLib.BPS_DENOMINATOR - 1
        );
        mockMaxSwapCostBps(MOCK_CORE, maxSwapCostBps);
        uint256 sqrtPriceLimitX96 = snapshotLib.getSwapCostLimit(snapshot, state.zeroForOne);

        // And: Shares releasing tokenIn, its sale ending halfway to that price at most.
        {
            (uint256 amountIn, uint160 sqrtPriceEnd) = saleOf(snapshot, state, shares);
            uint256 halfway = (state.sqrtPriceX96 + sqrtPriceLimitX96) / 2;
            // Hole: the shares' sale, a pool output, is empty or past halfway.
            vm.assume(amountIn > 0 && (state.zeroForOne ? sqrtPriceEnd >= halfway : sqrtPriceEnd <= halfway));
        }

        // When: Calculating the most of the shares a redeem burns.
        uint256 redeemable = redeemMath.maxRedeem(snapshot, pool, state.zeroForOne, shares);

        // Then: It is the shares.
        assertEq(redeemable, shares);
    }

    function testFuzz_Success_maxRedeem_ZeroWhenAShareSellsPastTheSwapCostLimit(
        RedeemState memory state,
        uint64 bufferOut,
        uint256 bufferIn,
        uint256 maxSwapCostBps,
        uint256 shares
    ) public {
        // Given: A core of the dead shares holding buffers, them in shares at most.
        state.supply = uint128(Constants.DEAD_SHARES);
        state.liquidity = uint128(bound(state.liquidity, 1, type(uint64).max));
        (Snapshot memory snapshot, address pool) = givenBuffersOnly(state, bufferOut, 0, 1);
        shares = bound(shares, 1, state.supply);

        // And: A max swap cost above the fee, and the price at which a sale reaches it.
        maxSwapCostBps = bound(
            maxSwapCostBps,
            FixedPointMathLib.divUp(state.fee, Constants.PIPS_PER_BPS) + 1,
            ConfigLib.BPS_DENOMINATOR - 1
        );
        mockMaxSwapCostBps(MOCK_CORE, maxSwapCostBps);
        uint160 sqrtPriceLimitX96 = snapshotLib.getSwapCostLimit(snapshot, state.zeroForOne);

        // And: A share's tokenIn above what the pool takes to that price, 2 wei a step.
        {
            uint256 taken = state.zeroForOne
                ? SqrtPriceMath.getAmount0Delta(sqrtPriceLimitX96, state.sqrtPriceX96, state.liquidity, true)
                : SqrtPriceMath.getAmount1Delta(state.sqrtPriceX96, sqrtPriceLimitX96, state.liquidity, true);
            int256 ticks = int256(TickMath.getTickAtSqrtPrice(sqrtPriceLimitX96)) - snapshot.tick;
            uint256 steps = uint256(ticks < 0 ? -ticks : ticks) / 256 + 2;
            bufferIn = bound(
                bufferIn,
                state.supply * (taken.fullMulDivUp(1e6, 1e6 - state.fee) + 2 * steps + 1),
                Constants.MAX_FUZZED_AMOUNT
            );
        }
        if (state.zeroForOne) snapshot.buffer0 = bufferIn;
        else snapshot.buffer1 = bufferIn;

        // When: Calculating the most of the shares a redeem burns.
        uint256 redeemable = redeemMath.maxRedeem(snapshot, pool, state.zeroForOne, shares);

        // Then: It is zero, a redeem of a single share selling past that price.
        assertEq(redeemable, 0);
    }
}
