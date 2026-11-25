/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { MintOptimizationMath_Fuzz_Test } from "./_MintOptimizationMath.fuzz.t.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "maxMint" of library "MintOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract MaxMint_MintOptimizationMath_Fuzz_Test is MintOptimizationMath_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_maxMint_UnboundedWithoutATokenOutCost(MintState memory state, uint256 sqrtPriceLimitX96)
        public
    {
        // Given: No ranges, only tokenIn idle beside them, and a valid spot price.
        if (state.zeroForOne) state.idle1 = 0;
        else state.idle0 = 0;
        state.supply = uint128(bound(state.supply, 1, type(uint128).max));
        state.sqrtPriceX96 = uint160(bound(state.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // When: Sizing the most shares.
        uint256 shares = optimizationMath.maxMint(
            snapshotOf(new PricedRange[](0), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee),
            poolOf(1, state.liquidity, new PricedRange[](0)),
            sqrtPriceLimitX96,
            state.zeroForOne
        );

        // Then: No buy limits them.
        assertEq(shares, type(uint256).max);
    }

    function testFuzz_Success_maxMint_ZeroWithoutLiquidity(MintState memory state, uint256 sqrtPriceLimitX96) public {
        // Given: No ranges, tokenOut idle beside them, and a valid spot price.
        if (state.zeroForOne) state.idle1 = uint64(bound(state.idle1, 1, type(uint64).max));
        else state.idle0 = uint64(bound(state.idle0, 1, type(uint64).max));
        state.supply = uint128(bound(state.supply, 1, type(uint128).max));
        state.sqrtPriceX96 = uint160(bound(state.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // When: Sizing the most shares in a pool without active liquidity.
        uint256 shares = optimizationMath.maxMint(
            snapshotOf(new PricedRange[](0), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee),
            poolOf(1, 0, new PricedRange[](0)),
            sqrtPriceLimitX96,
            state.zeroForOne
        );

        // Then: None, there being nothing to buy from.
        assertEq(shares, 0);
    }

    function testFuzz_Success_maxMint_ZeroBelowTheToken0Floor(MintState memory state, uint256 sqrtPriceLimitX96)
        public
    {
        // Given: A price and limit with squares over 2^96 at 0, idle token0, no ranges.
        state.sqrtPriceX96 = uint160(bound(state.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, Constants.SQRT_Q96 - 1));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));
        state.idle0 = uint64(bound(state.idle0, 1, type(uint64).max));
        state.supply = uint128(bound(state.supply, 1, type(uint128).max));
        state.liquidity = uint128(bound(state.liquidity, 1, type(uint128).max));
        sqrtPriceLimitX96 = bound(sqrtPriceLimitX96, state.sqrtPriceX96, Constants.SQRT_Q96 - 1);
        Snapshot memory snapshot =
            snapshotOf(new PricedRange[](0), state.idle0, 0, state.supply, state.sqrtPriceX96, state.fee);

        // When: Sizing the most shares of a buy of token0.
        uint256 shares = optimizationMath.maxMint(
            snapshot, poolOf(1, state.liquidity, new PricedRange[](0)), sqrtPriceLimitX96, false
        );

        // Then: None, the core's token0 amounts dividing by that floor.
        assertEq(shares, 0);
    }

    function testFuzz_Success_maxMint_TheBuyEndsAtOrBeforeTheLimit(
        MintState memory state,
        RangeState memory range,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: A range around a spot price in the band.
        givenValidState(state, range, false);
        PricedRange[] memory priced;
        {
            RangeState[] memory ranges = new RangeState[](1);
            ranges[0] = range;
            priced = pricedOf(ranges);
        }

        // And: Idle tokenOut, so the whole supply costs some tokenOut.
        if (state.zeroForOne) state.idle1 = uint64(bound(state.idle1, 1, type(uint64).max));
        else state.idle0 = uint64(bound(state.idle0, 1, type(uint64).max));

        // And: A limit in the buy's direction, up to 10^6 times that cost at spot.
        {
            (uint256 cost0, uint256 cost1) = snapshotLib.getMintAmounts(
                priced, state.sqrtPriceX96, state.idle0, state.idle1, state.supply, state.supply, state.zeroForOne
            );
            uint256 most = (state.zeroForOne ? cost1 : cost0) * Constants.MAX_COST_MULTIPLE;
            uint256 depth = uint256(state.liquidity) << 96;
            sqrtPriceLimitX96 = state.zeroForOne
                ? bound(
                    sqrtPriceLimitX96,
                    state.sqrtPriceX96
                        - FixedPointMathLib.min(
                            state.sqrtPriceX96 - TickMath.MIN_SQRT_PRICE - 1, most.fullMulDiv(1 << 96, state.liquidity)
                        ),
                    state.sqrtPriceX96
                )
                : bound(
                    sqrtPriceLimitX96,
                    state.sqrtPriceX96,
                    most.fullMulDiv(state.sqrtPriceX96, 1) < depth
                        ? FixedPointMathLib.min(
                            TickMath.MAX_SQRT_PRICE - 1,
                            depth.fullMulDiv(state.sqrtPriceX96, depth - most * state.sqrtPriceX96)
                        )
                        : TickMath.MAX_SQRT_PRICE - 1
                );
        }
        Snapshot memory snapshot =
            snapshotOf(priced, state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
        address pool = poolOf(1, state.liquidity, priced);

        // When: Sizing the most shares, capped where their liquidity fits a uint128.
        uint256 shares = FixedPointMathLib.min(
            optimizationMath.maxMint(snapshot, pool, sqrtPriceLimitX96, state.zeroForOne),
            uint256(type(uint128).max - 1).fullMulDiv(state.supply, priced[0].liquidity)
        );

        // Then: The buy for those shares ends at or before the limit.
        (uint160 sqrtPriceNew,,,,) = optimizationMath.computeSwap(snapshot, pool, state.zeroForOne, shares);
        if (state.zeroForOne) assertGe(sqrtPriceNew, sqrtPriceLimitX96);
        else assertLe(sqrtPriceNew, sqrtPriceLimitX96);
    }

    function testFuzz_Success_maxMint_TheBuyEndsAtOrBeforeTheLimitPastTheRangeAsThePoolsOnlyLiquidity(
        MintState memory state,
        RangeState memory range,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: A range around a spot price in the band.
        givenValidState(state, range, false);

        // And: Idle tokenOut, so the whole supply costs some tokenOut.
        if (state.zeroForOne) state.idle1 = uint64(bound(state.idle1, 1, type(uint64).max));
        else state.idle0 = uint64(bound(state.idle0, 1, type(uint64).max));

        // And: The range's edge ahead inside the swap cost limit, and a limit past it.
        Snapshot memory snapshot =
            snapshotOf(new PricedRange[](0), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
        {
            uint160 sqrtPriceCostLimitX96 = snapshotLib.getSwapCostLimit(snapshot, state.zeroForOne);
            if (state.zeroForOne) {
                range.tickLower = int24(
                    bound(range.tickLower, TickMath.getTickAtSqrtPrice(sqrtPriceCostLimitX96) + 1, snapshot.tick - 1)
                );
                sqrtPriceLimitX96 = bound(
                    sqrtPriceLimitX96, TickMath.MIN_SQRT_PRICE, TickMath.getSqrtPriceAtTick(range.tickLower - 1)
                );
            } else {
                range.tickUpper = int24(
                    bound(range.tickUpper, snapshot.tick + 2, TickMath.getTickAtSqrtPrice(sqrtPriceCostLimitX96) - 1)
                );
                sqrtPriceLimitX96 = bound(
                    sqrtPriceLimitX96, TickMath.getSqrtPriceAtTick(range.tickUpper + 1), TickMath.MAX_SQRT_PRICE
                );
            }
        }

        // And: The range as the pool's only liquidity, and a supply.
        state.liquidity = range.liquidity + range.liquidityStaked;
        state.supply = uint128(bound(state.supply, 1, type(uint128).max));
        {
            RangeState[] memory ranges = new RangeState[](1);
            ranges[0] = range;
            snapshot.ranges = pricedOf(ranges);
            snapshot.supply = state.supply;
        }
        address pool = poolOf(1, state.liquidity, snapshot.ranges);

        // When: Sizing the most shares, capped where their liquidity fits a uint128.
        uint256 shares = FixedPointMathLib.min(
            optimizationMath.maxMint(snapshot, pool, sqrtPriceLimitX96, state.zeroForOne),
            uint256(type(uint128).max - 1).fullMulDiv(state.supply, snapshot.ranges[0].liquidity)
        );

        // Then: The buy for those shares ends at or before the limit.
        (uint160 sqrtPriceNew,,,,) = optimizationMath.computeSwap(snapshot, pool, state.zeroForOne, shares);
        if (state.zeroForOne) assertGe(sqrtPriceNew, sqrtPriceLimitX96);
        else assertLe(sqrtPriceNew, sqrtPriceLimitX96);
    }

    function testFuzz_Success_maxMint_TheOneStepBuyLessTheRoundingOverTheEndCost_Token1(
        MintState memory state,
        RangeState memory range,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: A range around a spot in the band, inside its tick, and idle token1.
        state.zeroForOne = true;
        givenValidState(state, range, false);
        PricedRange[] memory priced;
        uint256 shares;
        {
            // And: Spot two past its tick's start.
            int24 tick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);
            state.sqrtPriceX96 = uint160(
                bound(
                    state.sqrtPriceX96, TickMath.getSqrtPriceAtTick(tick) + 2, TickMath.getSqrtPriceAtTick(tick + 1) - 1
                )
            );
            state.idle1 = uint64(bound(state.idle1, 1, type(uint64).max));
            {
                RangeState[] memory ranges = new RangeState[](1);
                ranges[0] = range;
                priced = pricedOf(ranges);
            }

            // And: A limit inside the spot's tick, so the buy is one pool step.
            sqrtPriceLimitX96 = bound(sqrtPriceLimitX96, TickMath.getSqrtPriceAtTick(tick) + 1, state.sqrtPriceX96 - 1);
            Snapshot memory snapshot =
                snapshotOf(priced, state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
            address pool = poolOf(1, state.liquidity, priced);

            // When: Sizing the most shares.
            shares = optimizationMath.maxMint(snapshot, pool, sqrtPriceLimitX96, true);
        }

        // Then: The step's token1 less the rounding, pro rata to the cost at its end.
        uint256 bought =
            SqrtPriceMath.getAmount1Delta(uint160(sqrtPriceLimitX96), state.sqrtPriceX96, state.liquidity, false);
        uint256 rounding = (uint256(state.sqrtPriceX96).divUp(1 << 96) + 2) + 1 + 1 + 2;
        (, uint256 costEnd) = snapshotLib.getMintAmounts(
            priced, uint160(sqrtPriceLimitX96), state.idle0, state.idle1, state.supply, state.supply, state.zeroForOne
        );
        assertEq(shares, bought <= rounding ? 0 : (bought - rounding).fullMulDiv(state.supply, costEnd + 1));
    }

    function testFuzz_Success_maxMint_TheOneStepBuyLessTheRoundingOverTheEndCost_Token0(
        MintState memory state,
        RangeState memory range,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: A range around a spot price in the band, and idle token0.
        state.zeroForOne = false;
        givenValidState(state, range, false);
        PricedRange[] memory priced;
        uint256 shares;
        {
            int24 tick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);

            // And: Spot at least two below its tick's end.
            state.sqrtPriceX96 = uint160(
                bound(state.sqrtPriceX96, TickMath.getSqrtPriceAtTick(tick), TickMath.getSqrtPriceAtTick(tick + 1) - 2)
            );
            state.idle0 = uint64(bound(state.idle0, 1, type(uint64).max));
            {
                RangeState[] memory ranges = new RangeState[](1);
                ranges[0] = range;
                priced = pricedOf(ranges);
            }

            // And: A limit inside the spot's tick, so the buy is one pool step.
            sqrtPriceLimitX96 =
                bound(sqrtPriceLimitX96, state.sqrtPriceX96 + 1, TickMath.getSqrtPriceAtTick(tick + 1) - 1);
            Snapshot memory snapshot =
                snapshotOf(priced, state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
            address pool = poolOf(1, state.liquidity, priced);

            // When: Sizing the most shares.
            shares = optimizationMath.maxMint(snapshot, pool, sqrtPriceLimitX96, false);
        }

        // Then: The step's token0 less the rounding at J0, pro rata to the end cost.
        uint256 priceX96 = uint256(state.sqrtPriceX96).fullMulDiv(state.sqrtPriceX96, 1 << 96);
        uint256 costEnd;
        {
            (uint256 costSpot,) = snapshotLib.getMintAmounts(
                priced, state.sqrtPriceX96, state.idle0, state.idle1, state.supply, state.supply, state.zeroForOne
            );
            (costEnd,) = snapshotLib.getMintAmounts(
                priced,
                uint160(sqrtPriceLimitX96),
                state.idle0,
                state.idle1,
                state.supply,
                state.supply,
                state.zeroForOne
            );
            uint256 roundingSpot = costSpot.divUp(priceX96);
            costEnd += 2 * roundingSpot + roundingSpot.divUp(priceX96);
        }
        {
            uint256 bought =
                SqrtPriceMath.getAmount0Delta(state.sqrtPriceX96, uint160(sqrtPriceLimitX96), state.liquidity, false);
            uint256 unit = uint256(1 << 96).divUp(state.sqrtPriceX96);
            uint256 roundingUnit = unit.divUp(priceX96);
            uint256 rounding = (unit + 2) + 1 + 1 + (2 * roundingUnit + roundingUnit.divUp(priceX96) + 1) + 2 + 2;
            assertEq(shares, bought <= rounding ? 0 : (bought - rounding).fullMulDiv(state.supply, costEnd + 1));
        }
    }

    function testFuzz_Success_maxMint_OneStepBuyLessRoundingOverEndCost_Token0BelowTwoToTheMinus66(
        MintState memory state,
        RangeState memory range,
        uint256 sqrtPriceLimitX96
    ) public {
        uint256 shares;
        PricedRange[] memory priced;
        {
            // Given: A sqrt price of 2^48 to 2^63, so J0 = s0^2 / 2^96 is 1 to 2^30.
            state.zeroForOne = false;
            state.sqrtPriceX96 =
                uint160(bound(state.sqrtPriceX96, Constants.SQRT_Q96, Constants.MIN_RANGE_SQRT_PRICE / 2));
            int24 tick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);

            // And: Spot at least two below its tick's end.
            state.sqrtPriceX96 = uint160(
                bound(
                    state.sqrtPriceX96,
                    FixedPointMathLib.max(TickMath.getSqrtPriceAtTick(tick), Constants.SQRT_Q96),
                    TickMath.getSqrtPriceAtTick(tick + 1) - 2
                )
            );
            state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));

            // And: A supply of 2^64+, a wei moving the shares, under 2^8 idle token0.
            state.supply = uint128(bound(state.supply, uint256(type(uint64).max) + 1, type(uint128).max));
            state.idle0 = uint64(bound(state.idle0, 1, type(uint8).max));

            // And: A range of up to 2^8 liquidity around spot, and a pool holding it.
            range.tickLower = int24(bound(range.tickLower, TickMath.MIN_TICK, tick - 1));
            range.tickUpper =
                int24(bound(range.tickUpper, tick + 2, TickMath.getTickAtSqrtPrice(Constants.MIN_RANGE_SQRT_PRICE)));
            range.liquidity = uint128(bound(range.liquidity, 1, type(uint8).max));
            range.liquidityStaked = 0;
            state.liquidity =
                uint128(bound(state.liquidity, uint256(range.liquidity) + range.liquidityStaked, type(uint128).max));
            RangeState[] memory ranges = new RangeState[](1);
            ranges[0] = range;
            priced = pricedOf(ranges);

            // And: A limit inside the spot's tick, so the buy is one pool step.
            sqrtPriceLimitX96 =
                bound(sqrtPriceLimitX96, state.sqrtPriceX96 + 1, TickMath.getSqrtPriceAtTick(tick + 1) - 1);
            Snapshot memory snapshot =
                snapshotOf(priced, state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
            address pool = poolOf(1, state.liquidity, priced);

            // When: Sizing the most shares.
            shares = optimizationMath.maxMint(snapshot, pool, sqrtPriceLimitX96, false);
        }

        // Then: The step's token0 less the rounding at J0, pro rata to the end cost.
        uint256 priceX96 = uint256(state.sqrtPriceX96).fullMulDiv(state.sqrtPriceX96, 1 << 96);
        uint256 costEnd;
        {
            (uint256 costSpot,) = snapshotLib.getMintAmounts(
                priced, state.sqrtPriceX96, state.idle0, state.idle1, state.supply, state.supply, state.zeroForOne
            );
            (costEnd,) = snapshotLib.getMintAmounts(
                priced,
                uint160(sqrtPriceLimitX96),
                state.idle0,
                state.idle1,
                state.supply,
                state.supply,
                state.zeroForOne
            );
            uint256 roundingSpot = costSpot.divUp(priceX96);
            costEnd += 2 * roundingSpot + roundingSpot.divUp(priceX96);
        }
        uint256 roundingUnit = uint256(1 << 96).divUp(state.sqrtPriceX96).divUp(priceX96);
        {
            uint256 rounding = (uint256(1 << 96).divUp(state.sqrtPriceX96) + 2) + 1 + 1
                + (2 * roundingUnit + roundingUnit.divUp(priceX96) + 1) + 2 + 2;
            uint256 bought =
                SqrtPriceMath.getAmount0Delta(state.sqrtPriceX96, uint160(sqrtPriceLimitX96), state.liquidity, false);
            assertEq(shares, bought <= rounding ? 0 : (bought - rounding).fullMulDiv(state.supply, costEnd + 1));
        }

        // And: A token0 unit spans more than one J0.
        assertGt(roundingUnit, 1);
    }
}
