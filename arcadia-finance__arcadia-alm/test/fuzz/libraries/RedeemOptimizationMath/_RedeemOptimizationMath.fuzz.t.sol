/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { OptimizationMath_Fuzz_Test } from "../_OptimizationMath.fuzz.t.sol";
import { PoolLogic } from "../../../../src/shared/libraries/logic/PoolLogic.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { RedeemOptimizationMathExtension } from "../../../utils/extensions/RedeemOptimizationMathExtension.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { StepComputations, SwapState } from "../../../../src/vaults/types/SwapState.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { WithdrawOptimizationMathExtension } from "../../../utils/extensions/WithdrawOptimizationMathExtension.sol";

/**
 * @notice Common logic needed by all "RedeemOptimizationMath" and "WithdrawOptimizationMath" fuzz tests.
 */
// forge-lint: disable-next-item(unsafe-typecast)
abstract contract RedeemOptimizationMath_Fuzz_Test is OptimizationMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    struct RedeemState {
        uint160 sqrtPriceX96;
        uint128 liquidity;
        uint128 supply;
        uint64 idle0;
        uint64 idle1;
        uint64 fees0;
        uint64 fees1;
        uint24 fee;
        bool onEdge;
        bool zeroForOne;
    }

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    RedeemOptimizationMathExtension internal redeemMath;
    WithdrawOptimizationMathExtension internal withdrawMath;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(OptimizationMath_Fuzz_Test) {
        OptimizationMath_Fuzz_Test.setUp();
        redeemMath = new RedeemOptimizationMathExtension();
        withdrawMath = new WithdrawOptimizationMathExtension();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function givenValidState(RedeemState memory state, RangeState memory range)
        internal
        returns (Snapshot memory snapshot, address pool)
    {
        // And: A spot in the band, a supply, a fee, buffers, and a range around spot.
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 1),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 1)
            )
        );
        state.supply = uint128(bound(state.supply, 1, type(uint64).max));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));
        state.idle0 = uint64(bound(state.idle0, 1e6, type(uint64).max));
        state.idle1 = uint64(bound(state.idle1, 1e6, type(uint64).max));
        int24 tick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);
        range.tickLower = int24(bound(range.tickLower, -Constants.BOUND_TICK, tick));
        range.tickUpper = int24(bound(range.tickUpper, tick + 1, Constants.BOUND_TICK));

        // And: Spot on the range's lower edge, when asked.
        if (state.onEdge) state.sqrtPriceX96 = TickMath.getSqrtPriceAtTick(range.tickLower);

        // And: A pool holding the range, its reserves at spot within a uint128.
        uint256 liquidityMost = type(uint128).max
            / (FixedPointMathLib.max(state.sqrtPriceX96 >> 96, (1 << 96) / uint256(state.sqrtPriceX96)) + 1);
        range.liquidity = uint128(bound(range.liquidity, 1, FixedPointMathLib.min(type(uint64).max, liquidityMost / 2)));
        range.liquidityStaked =
            uint128(bound(range.liquidityStaked, 0, FixedPointMathLib.min(type(uint64).max, liquidityMost / 2)));
        state.liquidity =
            uint128(bound(state.liquidity, uint256(range.liquidity) + range.liquidityStaked, liquidityMost));

        RangeState[] memory ranges = new RangeState[](1);
        ranges[0] = range;
        snapshot = snapshotOf(pricedOf(ranges), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
        (snapshot.fees0, snapshot.fees1) = (state.fees0, state.fees1);
        pool = poolOf(1, state.liquidity, snapshot.ranges);
    }

    function givenBuffersOnly(RedeemState memory state, uint256 bufferOut, uint256 bufferIn, uint128 liquidityMin)
        internal
        returns (Snapshot memory snapshot, address pool)
    {
        // And: A core holding only buffers, a spot in the band, a supply and a pool.
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );
        state.supply = uint128(bound(state.supply, 1, type(uint64).max));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));
        state.liquidity = liquidityMin == 0 ? 0 : uint128(bound(state.liquidity, liquidityMin, type(uint128).max));
        snapshot = state.zeroForOne
            ? snapshotOf(new PricedRange[](0), bufferIn, bufferOut, state.supply, state.sqrtPriceX96, state.fee)
            : snapshotOf(new PricedRange[](0), bufferOut, bufferIn, state.supply, state.sqrtPriceX96, state.fee);
        pool = poolOf(1, state.liquidity, snapshot.ranges);
    }

    function burnedPoolOf(Snapshot memory snapshot, int24 tickSpacing, uint128 liquidity, uint256 shares)
        internal
        returns (address pool)
    {
        // The pool after a burn: each range less floor(L_i * shares / supply).
        PricedRange[] memory ranges = new PricedRange[](snapshot.ranges.length);
        for (uint256 i; i < ranges.length; ++i) {
            PricedRange memory range = snapshot.ranges[i];
            ranges[i] = PricedRange({
                liquidity: range.liquidity,
                unstakedLiquidity: range.unstakedLiquidity,
                sqrtPriceLowerX96: range.sqrtPriceLowerX96,
                sqrtPriceUpperX96: range.sqrtPriceUpperX96
            });
            uint128 burned = uint128(FixedPointMathLib.fullMulDiv(ranges[i].liquidity, shares, snapshot.supply));
            ranges[i].liquidity -= burned;
            if (
                TickMath.getTickAtSqrtPrice(ranges[i].sqrtPriceLowerX96) <= snapshot.tick
                    && snapshot.tick < TickMath.getTickAtSqrtPrice(ranges[i].sqrtPriceUpperX96)
            ) liquidity -= burned;
        }
        pool = poolOf(tickSpacing, liquidity, ranges);
    }

    function saleOf(Snapshot memory snapshot, RedeemState memory state, uint256 shares)
        internal
        returns (uint256 amountIn, uint160 sqrtPriceEnd)
    {
        // The pool's sale of the tokenIn a burn of the shares releases, after it.
        sqrtPriceEnd = state.sqrtPriceX96;
        if (shares == 0) return (0, sqrtPriceEnd);
        (uint256 amount0, uint256 amount1,) =
            snapshotLib.getBurnAmounts(snapshot, state.sqrtPriceX96, shares, state.zeroForOne);
        amountIn = state.zeroForOne ? amount0 : amount1;
        if (amountIn == 0) return (0, sqrtPriceEnd);
        (sqrtPriceEnd,,) = swap(
            snapshot,
            burnedPoolOf(snapshot, 1, state.liquidity, shares),
            state.zeroForOne,
            -int256(amountIn),
            PoolLogic.sqrtPriceLimit(state.zeroForOne)
        );
    }

    function redeemOf(
        Snapshot memory snapshot,
        RedeemState memory state,
        int24 tickSpacing,
        uint256 shares,
        uint256 roundingMarginIn
    ) internal returns (uint256 amountOut) {
        // The burn's tokenOut, plus the pool's sale of its tokenIn less the margin.
        (uint256 amount0, uint256 amount1,) =
            snapshotLib.getBurnAmounts(snapshot, state.sqrtPriceX96, shares, state.zeroForOne);
        (uint256 amountIn, uint256 released) = state.zeroForOne ? (amount0, amount1) : (amount1, amount0);
        (,, amountOut) = swap(
            snapshot,
            burnedPoolOf(snapshot, tickSpacing, state.liquidity, shares),
            state.zeroForOne,
            -int256(FixedPointMathLib.zeroFloorSub(amountIn, roundingMarginIn)),
            PoolLogic.sqrtPriceLimit(state.zeroForOne)
        );
        amountOut += released;
    }

    function givenValidStep(SwapState memory state, StepComputations memory step, bool zeroForOne) internal pure {
        // And: A price in the band, a target on the sale's side, a pool, W within it.
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 1),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 1)
            )
        );
        step.sqrtPriceTargetX96 = zeroForOne
            ? uint160(
                bound(
                    step.sqrtPriceTargetX96, TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK), state.sqrtPriceX96 - 1
                )
            )
            : uint160(
                bound(
                    step.sqrtPriceTargetX96, state.sqrtPriceX96 + 1, TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
                )
            );
        state.liquidity = uint128(bound(state.liquidity, 1, type(uint64).max));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));
        state.position.liquidity = bound(state.position.liquidity, 0, state.liquidity);
    }
}
