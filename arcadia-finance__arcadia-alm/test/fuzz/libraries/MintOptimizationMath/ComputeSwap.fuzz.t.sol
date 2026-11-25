/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { MetadexTickBitmap } from "../../../../src/shared/libraries/vendored/MetadexTickBitmap.sol";
import { MintOptimizationMath_Fuzz_Test } from "./_MintOptimizationMath.fuzz.t.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "computeSwap" of library "MintOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract ComputeSwap_MintOptimizationMath_Fuzz_Test is MintOptimizationMath_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_computeSwap_BuysNothingWithoutLiquidity(
        MintState memory state,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A range around spot, a mint of at most the supply, and an inactive pool.
        PricedRange[] memory priced = givenValidRange(state, range);
        shares = bound(shares, 1, state.supply);

        // When: Calculating the mint's buy.
        (uint160 sqrtPriceNew,, uint256 amountOut,,) = optimizationMath.computeSwap(
            snapshotOf(priced, state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee),
            poolOf(1, 0, priced),
            state.zeroForOne,
            shares
        );

        // Then: Nothing is bought, the pool having nothing to sell.
        assertEq(amountOut, 0);
        assertEq(sqrtPriceNew, state.sqrtPriceX96);
    }

    function testFuzz_Success_computeSwap_ZeroWithoutATokenOutCost(MintState memory state, uint256 shares) public {
        // Given: No ranges, only tokenIn idle beside them, and a valid spot price.
        if (state.zeroForOne) state.idle1 = 0;
        else state.idle0 = 0;
        state.supply = uint128(bound(state.supply, 1, type(uint128).max));
        state.sqrtPriceX96 = uint160(bound(state.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        shares = bound(shares, 0, state.supply);

        // When: Calculating the mint's buy.
        (,, uint256 amountOut,,) = optimizationMath.computeSwap(
            snapshotOf(new PricedRange[](0), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee),
            poolOf(1, state.liquidity, new PricedRange[](0)),
            state.zeroForOne,
            shares
        );

        // Then: Nothing is bought.
        assertEq(amountOut, 0);
    }

    function testFuzz_Success_computeSwap_CoversThePullAtTheEndPrice(
        MintState memory state,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A range around spot, a mint of the supply at most, sold before the edge.
        PricedRange[] memory priced = givenValidRange(state, range);
        shares = bound(shares, 1, state.supply);
        givenValidBuy(
            state, priced, shares, state.zeroForOne ? priced[0].sqrtPriceLowerX96 : priced[0].sqrtPriceUpperX96
        );

        // When: Calculating the mint's buy.
        (uint160 sqrtPriceNew,, uint256 amountOut,,) = optimizationMath.computeSwap(
            snapshotOf(priced, state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee),
            poolOf(1, state.liquidity, priced),
            state.zeroForOne,
            shares
        );

        // Then: The tokenOut bought covers the pull at the buy's end price.
        assertLe(pullOut(state, priced, sqrtPriceNew, shares), amountOut);
    }

    function testFuzz_Success_computeSwap_KeepsTheRounding(
        MintState memory state,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A range around spot, a mint of the supply at most, sold before the edge.
        PricedRange[] memory priced = givenValidRange(state, range);
        shares = bound(shares, 1, state.supply);
        givenValidBuy(
            state, priced, shares, state.zeroForOne ? priced[0].sqrtPriceLowerX96 : priced[0].sqrtPriceUpperX96
        );

        // When: Calculating the mint's buy.
        uint256 amountOut;
        uint160 sqrtPriceNew;
        {
            Snapshot memory snapshot =
                snapshotOf(priced, state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
            (sqrtPriceNew,, amountOut,,) =
                optimizationMath.computeSwap(snapshot, poolOf(1, state.liquidity, priced), state.zeroForOne, shares);
        }

        // Then: It exceeds the pull at its end by a range's rounding at most.
        uint256 rounding = FixedPointMathLib.dist(
                TickMath.getTickAtSqrtPrice(sqrtPriceNew), TickMath.getTickAtSqrtPrice(state.sqrtPriceX96)
            ) / uint24(Constants.BITMAP_WORD_TICKS) + 5;
        {
            uint256 unit =
                state.zeroForOne ? 1 << 96 : uint256(state.sqrtPriceX96).fullMulDiv(state.sqrtPriceX96, 1 << 96);
            {
                uint256 added = shares.fullMulDiv(priced[0].liquidity, state.supply);
                rounding += (added + 2 * amountOut).divUp(state.liquidity) + (added + 2).divUp(unit);
            }
            if (!state.zeroForOne) rounding += 2 * pullOut(state, priced, state.sqrtPriceX96, shares).divUp(unit);
        }
        assertLe(amountOut - FixedPointMathLib.min(pullOut(state, priced, sqrtPriceNew, shares), amountOut), rounding);
    }

    function testFuzz_Success_computeSwap_PricesTheBuyAsThePoolsSteps(
        MintState memory state,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A range around spot, a mint of the supply at most, a pool selling it.
        PricedRange[] memory priced = givenValidRange(state, range);
        shares = bound(shares, 1, state.supply);
        givenValidBuy(
            state, priced, shares, state.zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        );
        Snapshot memory snapshot =
            snapshotOf(priced, state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
        address pool = poolOf(1, state.liquidity, priced);

        // When: Calculating the mint's buy.
        (uint160 sqrtPriceNew,, uint256 amountOut,,) =
            optimizationMath.computeSwap(snapshot, pool, state.zeroForOne, shares);

        // Then: The pool's swap limited at the end price delivers the buy, ending there.
        (uint160 sqrtPriceEnd,, uint256 amountSwapOut) =
            swap(snapshot, pool, state.zeroForOne, int256(amountOut), sqrtPriceNew);
        assertEq(amountSwapOut, amountOut);
        assertEq(sqrtPriceEnd, amountOut == 0 ? state.sqrtPriceX96 : sqrtPriceNew);
    }

    function testFuzz_Success_computeSwap_BuysThePullInItsFirstStepLessTheMintsOwnLiquidity(
        MintState memory state,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A range around spot, and a mint of the supply at most.
        PricedRange[] memory priced = givenValidRange(state, range);
        shares = bound(shares, 1, state.supply);

        // And: Spot strictly inside its tick, so the first step moves the price.
        int24 tick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);
        state.sqrtPriceX96 = uint160(
            bound(state.sqrtPriceX96, TickMath.getSqrtPriceAtTick(tick) + 1, TickMath.getSqrtPriceAtTick(tick + 1) - 1)
        );

        // And: A pool selling the pull and its rounding before its first step ends.
        {
            (int24 tickNext,) =
                MetadexTickBitmap.nextInitializedTickWithinOneWord(poolOf(1, 1, priced), tick, 1, state.zeroForOne);
            givenValidBuy(state, priced, shares, TickMath.getSqrtPriceAtTick(tickNext));
        }

        // When: Calculating the mint's buy.
        (,, uint256 amountOut,,) = optimizationMath.computeSwap(
            snapshotOf(priced, state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee),
            poolOf(1, state.liquidity, priced),
            state.zeroForOne,
            shares
        );

        // Then: It buys the pull, n and its ceiling, less the mint's liquidity's sale.
        (uint256 pull0, uint256 pull1) = snapshotLib.getMintAmounts(
            priced, state.sqrtPriceX96, state.idle0, state.idle1, shares, state.supply, state.zeroForOne
        );
        uint256 need = state.zeroForOne
            ? pull1 + 1
            : pull0 + 1 + pull0.divUp(uint256(state.sqrtPriceX96).fullMulDiv(state.sqrtPriceX96, 1 << 96));
        uint256 liquidityDelta =
            snapshotLib.getMintLiquidityDelta(priced, state.sqrtPriceX96, shares, state.supply, state.zeroForOne);
        assertEq(amountOut, need.fullMulDivUp(state.liquidity, uint256(state.liquidity) + liquidityDelta));
    }
}
