/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { DepositOptimizationMath_Fuzz_Test } from "./_DepositOptimizationMath.fuzz.t.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { MintOptimizationMath } from "../../../../src/vaults/libraries/math/MintOptimizationMath.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "maxDeposit" of library "DepositOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract MaxDeposit_DepositOptimizationMath_Fuzz_Test is DepositOptimizationMath_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_maxDeposit_ZeroWithoutShares(
        MintState memory state,
        RangeState memory range,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: A range around a spot price in the band.
        givenValidState(state, range, true);
        PricedRange[] memory priced;
        {
            RangeState[] memory ranges = new RangeState[](1);
            ranges[0] = range;
            priced = pricedOf(ranges);
        }
        sqrtPriceLimitX96 = givenValidLimit(state, sqrtPriceLimitX96);

        // When: Calculating the most a deposit minting no shares takes.
        uint256 assets = optimizationMath.maxDeposit(
            snapshotOf(priced, state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee),
            poolOf(1, state.liquidity, priced),
            sqrtPriceLimitX96,
            state.zeroForOne,
            0
        );

        // Then: It takes nothing.
        assertEq(assets, 0);
    }

    function testFuzz_Success_maxDeposit_TheSharesValueWhenThePoolRunsOutBeforeTheLimit(
        MintState memory state,
        RangeState memory range,
        uint256 shares,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: A range around a spot price in the band.
        givenValidState(state, range, true);

        // And: Each token idle at twice the mint's rounding of it at least.
        state.idle0 = uint64(bound(state.idle0, 2 * (uint256(1 << 96).divUp(state.sqrtPriceX96) + 3), type(uint64).max));
        state.idle1 = uint64(bound(state.idle1, 2 * (uint256(state.sqrtPriceX96).divUp(1 << 96) + 3), type(uint64).max));

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

        // And: The range as the pool's only liquidity, and twice the supply in shares+.
        state.liquidity = range.liquidity + range.liquidityStaked;
        {
            RangeState[] memory ranges = new RangeState[](1);
            ranges[0] = range;
            snapshot.ranges = pricedOf(ranges);
        }
        address pool = poolOf(1, state.liquidity, snapshot.ranges);
        shares = bound(shares, 2 * uint256(state.supply), type(uint128).max);

        // When: Calculating the most a deposit takes.
        uint256 assets = optimizationMath.maxDeposit(snapshot, pool, sqrtPriceLimitX96, state.zeroForOne, shares);

        // Then: It is the shares' value of the core in tokenIn, each token less 1 wei.
        uint256 amount0 = FullMath.mulDiv(state.liquidity, 1 << 96, state.sqrtPriceX96)
            - FullMath.mulDiv(state.liquidity, 1 << 96, snapshot.ranges[0].sqrtPriceUpperX96) + state.idle0 - 1;
        uint256 amount1 = FullMath.mulDiv(state.liquidity, state.sqrtPriceX96, 1 << 96)
            - FullMath.mulDiv(state.liquidity, snapshot.ranges[0].sqrtPriceLowerX96, 1 << 96) + state.idle1 - 1;
        uint256 priceX192 = uint256(state.sqrtPriceX96) * state.sqrtPriceX96;
        assertEq(
            assets,
            shares.saturatingMul(
                state.zeroForOne
                    ? amount0 + FullMath.mulDiv(amount1, 1 << 192, priceX192)
                    : amount1 + FullMath.mulDiv(amount0, priceX192, 1 << 192)
            ) / state.supply
        );
    }

    function testFuzz_Success_maxDeposit_ItsDepositMintsAtMostTheSharesWithinTheLimit(
        MintState memory state,
        RangeState memory range,
        uint256 shares,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: A range around a spot price in the band.
        givenValidState(state, range, true);
        Snapshot memory snapshot = snapshotOf(state, range);
        sqrtPriceLimitX96 = givenValidLimit(state, sqrtPriceLimitX96);

        // And: Shares worth 2^60 tokenIn reserves at most, where the solve is normalized.
        uint256 sharesMost;
        {
            (uint256 cost0, uint256 cost1) = snapshotLib.getMintAmounts(
                snapshot.ranges,
                state.sqrtPriceX96,
                state.idle0,
                state.idle1,
                state.supply,
                state.supply,
                state.zeroForOne
            );
            uint256 priceX192 = uint256(state.sqrtPriceX96) * state.sqrtPriceX96;
            sharesMost = state.zeroForOne
                ? uint256(state.liquidity)
                    .fullMulDiv(1 << 156, state.sqrtPriceX96)
                    .fullMulDiv(state.supply, cost0 + cost1.fullMulDivUp(1 << 192, priceX192))
                : uint256(state.liquidity)
                    .fullMulDiv(state.sqrtPriceX96, 1 << 36)
                    .fullMulDiv(state.supply, cost1 + cost0.fullMulDivUp(priceX192, 1 << 192));
        }

        // And: At most the shares whose mint's buy ends within the limit.
        address pool = poolOf(1, state.liquidity, snapshot.ranges);
        sharesMost = FixedPointMathLib.min(
            sharesMost, MintOptimizationMath.maxMint(snapshot, pool, sqrtPriceLimitX96, state.zeroForOne)
        );
        shares = bound(shares, 0, sharesMost);

        // When: Calculating the most a deposit takes.
        uint256 assets = optimizationMath.maxDeposit(snapshot, pool, sqrtPriceLimitX96, state.zeroForOne, shares);

        // Then: A deposit of it mints at most the shares, and its swap ends in the limit.
        (uint160 sqrtPriceNew,,,,) = optimizationMath.computeSwap(snapshot, pool, state.zeroForOne, assets);
        assertLe(optimizationMath.previewDeposit_(snapshot, pool, state.zeroForOne, assets), shares);
        if (state.zeroForOne) assertGe(sqrtPriceNew, sqrtPriceLimitX96);
        else assertLe(sqrtPriceNew, sqrtPriceLimitX96);
    }

    function testFuzz_Success_maxDeposit_ItsDepositEndsWithinTheLimitAtTheLargestTotalCap(
        MintState memory state,
        RangeState memory range,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: A range around a spot price in the band.
        givenValidState(state, range, true);
        PricedRange[] memory priced;
        {
            RangeState[] memory ranges = new RangeState[](1);
            ranges[0] = range;
            priced = pricedOf(ranges);
        }
        sqrtPriceLimitX96 = givenValidLimit(state, sqrtPriceLimitX96);

        // When: Calculating the max deposit, for the most shares the uint128 cap allows.
        Snapshot memory snapshot =
            snapshotOf(priced, state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
        address pool = poolOf(1, state.liquidity, priced);
        uint256 assets =
            optimizationMath.maxDeposit(snapshot, pool, sqrtPriceLimitX96, state.zeroForOne, type(uint128).max);
        // And: Hole: a deposit past 2^60 tokenIn reserves, the solve not normalized.
        vm.assume(
            state.zeroForOne
                ? assets <= FixedPointMathLib.fullMulDiv(state.liquidity, 1 << 156, state.sqrtPriceX96)
                : assets <= FixedPointMathLib.fullMulDiv(state.liquidity, state.sqrtPriceX96, 1 << 36)
        );

        // Then: A deposit of it ends its swap at or before the limit.
        (uint160 sqrtPriceNew,,,,) = optimizationMath.computeSwap(snapshot, pool, state.zeroForOne, assets);
        if (state.zeroForOne) assertGe(sqrtPriceNew, sqrtPriceLimitX96);
        else assertLe(sqrtPriceNew, sqrtPriceLimitX96);
    }

    function testFuzz_Success_maxDeposit_ItsDepositMintsAtMostTheSharesWithoutTokenOut(
        MintState memory state,
        uint256 shares,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: Only tokenIn idle, a spot, and a limit whose square over 2^96 is 1+.
        state.supply = uint128(bound(state.supply, 1, type(uint64).max));
        sqrtPriceLimitX96 = uint160(bound(sqrtPriceLimitX96, Constants.SQRT_Q96, TickMath.MAX_SQRT_PRICE));
        state.sqrtPriceX96 = uint160(bound(state.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        if (state.zeroForOne) (state.idle0, state.idle1) = (uint64(bound(state.idle0, 1, type(uint64).max)), 0);
        else (state.idle0, state.idle1) = (0, uint64(bound(state.idle1, 1, type(uint64).max)));
        PricedRange[] memory priced = new PricedRange[](0);

        // When: Calculating the most a deposit takes.
        uint256 assets = optimizationMath.maxDeposit(
            snapshotOf(priced, state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee),
            poolOf(1, state.liquidity, priced),
            sqrtPriceLimitX96,
            state.zeroForOne,
            shares
        );

        // Then: The tokenIn it takes mints at most the shares.
        assertLe(
            snapshotLib.getMintShares(
                priced,
                state.idle0,
                state.idle1,
                state.supply,
                state.sqrtPriceX96,
                state.zeroForOne ? assets : 0,
                state.zeroForOne ? 0 : assets,
                state.zeroForOne
            ),
            shares
        );
    }

    function testFuzz_Success_maxDeposit_TheSharesPartOfTheTokenInWithoutTokenOut(
        MintState memory state,
        uint256 shares,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: Only tokenIn idle, a spot, and a limit whose square over 2^96 is 1+.
        state.supply = uint128(bound(state.supply, 1, type(uint64).max));
        sqrtPriceLimitX96 = uint160(bound(sqrtPriceLimitX96, Constants.SQRT_Q96, TickMath.MAX_SQRT_PRICE));
        state.sqrtPriceX96 = uint160(bound(state.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        if (state.zeroForOne) (state.idle0, state.idle1) = (uint64(bound(state.idle0, 1, type(uint64).max)), 0);
        else (state.idle0, state.idle1) = (0, uint64(bound(state.idle1, 1, type(uint64).max)));
        PricedRange[] memory priced = new PricedRange[](0);

        // When: Calculating the most a deposit takes.
        uint256 assets = optimizationMath.maxDeposit(
            snapshotOf(priced, state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee),
            poolOf(1, state.liquidity, priced),
            sqrtPriceLimitX96,
            state.zeroForOne,
            shares
        );

        // Then: It is the shares' part of the core's tokenIn.
        assertEq(assets, shares.saturatingMul(state.zeroForOne ? state.idle0 : state.idle1) / state.supply);
    }

    function testFuzz_Success_maxDeposit_ZeroWithoutHoldings(
        MintState memory state,
        uint256 shares,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: A core holding nothing, a valid spot and limit, and bounded shares.
        state.supply = uint128(bound(state.supply, 1, type(uint128).max));
        sqrtPriceLimitX96 = bound(sqrtPriceLimitX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE);
        state.sqrtPriceX96 = uint160(bound(state.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        shares = bound(shares, 1, type(uint256).max - 1);

        // When: Calculating the most a deposit takes.
        uint256 assets = optimizationMath.maxDeposit(
            snapshotOf(new PricedRange[](0), 0, 0, state.supply, state.sqrtPriceX96, state.fee),
            poolOf(1, state.liquidity, new PricedRange[](0)),
            sqrtPriceLimitX96,
            state.zeroForOne,
            shares
        );

        // Then: It takes nothing, a mint taking nothing.
        assertEq(assets, 0);
    }

    function testFuzz_Success_maxDeposit_ZeroWithoutLiquidity(
        MintState memory state,
        uint256 shares,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: Only tokenOut idle, a spot and limit whose squares over 2^96 are 1+.
        state.supply = uint128(bound(state.supply, 1, type(uint64).max));
        sqrtPriceLimitX96 = uint160(bound(sqrtPriceLimitX96, Constants.SQRT_Q96, TickMath.MAX_SQRT_PRICE));
        state.sqrtPriceX96 = uint160(bound(state.sqrtPriceX96, Constants.SQRT_Q96, TickMath.MAX_SQRT_PRICE - 1));
        if (state.zeroForOne) state.idle1 = uint64(bound(state.idle1, 1, type(uint64).max));
        else state.idle0 = uint64(bound(state.idle0, 1, type(uint64).max));
        shares = bound(shares, 1, type(uint256).max - 1);

        // When: Calculating the most a deposit takes in a pool without active liquidity.
        uint256 assets = optimizationMath.maxDeposit(
            snapshotOf(new PricedRange[](0), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee),
            poolOf(1, 0, new PricedRange[](0)),
            sqrtPriceLimitX96,
            state.zeroForOne,
            shares
        );

        // Then: It takes nothing, there being nothing to buy from.
        assertEq(assets, 0);
    }

    function testFuzz_Success_maxDeposit_SellingAllBuysAtMostTheSharesPartOfTheTokenOut(
        MintState memory state,
        uint256 shares,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: Only tokenOut idle, a price in the band, an active pool and a limit.
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 1),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 1)
            )
        );
        state.supply = uint128(bound(state.supply, 1, type(uint64).max));
        state.liquidity = uint128(bound(state.liquidity, 1, type(uint128).max));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));
        if (state.zeroForOne) (state.idle0, state.idle1) = (0, uint64(bound(state.idle1, 1, type(uint64).max)));
        else (state.idle0, state.idle1) = (uint64(bound(state.idle0, 1, type(uint64).max)), 0);
        sqrtPriceLimitX96 = givenValidLimit(state, sqrtPriceLimitX96);
        shares = bound(shares, 0, type(uint128).max);

        // When: Calculating the most a deposit takes.
        uint256 assets = optimizationMath.maxDeposit(
            snapshotOf(new PricedRange[](0), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee),
            poolOf(1, state.liquidity, new PricedRange[](0)),
            sqrtPriceLimitX96,
            state.zeroForOne,
            shares
        );

        // Then: Its tokenIn at spot is at most the shares' part of the core's tokenOut.
        assertLe(
            FixedPointMathLib.fullMulDiv(
                assets,
                state.zeroForOne
                    ? FixedPointMathLib.fullMulDiv(state.sqrtPriceX96, state.sqrtPriceX96, 1 << 96)
                    : FixedPointMathLib.fullMulDiv(1 << 96, 1 << 96, state.sqrtPriceX96),
                state.zeroForOne ? 1 << 96 : state.sqrtPriceX96
            ),
            FixedPointMathLib.fullMulDiv(state.zeroForOne ? state.idle1 : state.idle0, shares, state.supply)
        );
    }

    function testFuzz_Success_maxDeposit_TheOneStepSwapToTheLimitAtItsComposition_ZeroForOne(
        MintState memory state,
        RangeState memory range,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: A range around spot, inside its tick, in a pool without fee.
        givenValidState(state, range, true);
        state.fee = 0;

        // And: At least 2 shares, and 2^40 of each token idle, over the mint rounding.
        state.supply = uint128(bound(state.supply, 2, type(uint64).max));
        state.idle0 = uint64(bound(state.idle0, type(uint40).max, type(uint64).max));
        state.idle1 = uint64(bound(state.idle1, type(uint40).max, type(uint64).max));
        uint256 assets;
        {
            // And: Spot three past its tick's start.
            int24 tick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);
            state.sqrtPriceX96 = uint160(
                bound(
                    state.sqrtPriceX96, TickMath.getSqrtPriceAtTick(tick) + 3, TickMath.getSqrtPriceAtTick(tick + 1) - 1
                )
            );
            Snapshot memory snapshot;
            {
                RangeState[] memory ranges = new RangeState[](1);
                ranges[0] = range;
                snapshot =
                    snapshotOf(pricedOf(ranges), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
            }
            address pool = poolOf(1, state.liquidity, snapshot.ranges);

            // And: A limit inside spot's tick, the swap to it a wei short in one step.
            sqrtPriceLimitX96 = bound(sqrtPriceLimitX96, TickMath.getSqrtPriceAtTick(tick) + 1, state.sqrtPriceX96 - 2);

            // When: Calculating the most a deposit of the whole supply's worth takes.
            assets = optimizationMath.maxDeposit(snapshot, pool, sqrtPriceLimitX96, true, state.supply);
        }

        // Then: The core's worth in token0, or the swap to the limit and its token1.
        uint256 liquidity = uint256(range.liquidity) + range.liquidityStaked;
        (uint256 lower, uint256 upper) =
            (TickMath.getSqrtPriceAtTick(range.tickLower), TickMath.getSqrtPriceAtTick(range.tickUpper));
        uint256 worth = uint256(state.idle0) + FullMath.mulDiv(liquidity, 1 << 96, state.sqrtPriceX96)
            - FullMath.mulDiv(liquidity, 1 << 96, upper) - 1;
        worth += FullMath.mulDiv(
            uint256(state.idle1) + FullMath.mulDiv(liquidity, state.sqrtPriceX96, 1 << 96)
                - FullMath.mulDiv(liquidity, lower, 1 << 96) - 1,
            1 << 192,
            uint256(state.sqrtPriceX96) * state.sqrtPriceX96
        );
        uint256 composition;
        {
            uint256 limit = sqrtPriceLimitX96 + 1;
            uint256 positionIn = uint256(state.idle0) + FullMath.mulDiv(liquidity, 1 << 96, limit)
                - FullMath.mulDiv(liquidity, 1 << 96, upper);
            uint256 positionOut = uint256(state.idle1) + FullMath.mulDiv(liquidity, limit, 1 << 96)
                - FullMath.mulDiv(liquidity, lower, 1 << 96);
            composition = SqrtPriceMath.getAmount0Delta(uint160(limit), state.sqrtPriceX96, state.liquidity, false)
                + FullMath.mulDiv(
                    SqrtPriceMath.getAmount1Delta(uint160(limit), state.sqrtPriceX96, state.liquidity, false),
                    positionIn - 1,
                    positionOut + 1
                );
        }
        assertEq(assets, FixedPointMathLib.min(worth, composition));
    }

    function testFuzz_Success_maxDeposit_TheTwoStepSwapToTheLimitAtItsComposition_ZeroForOne(
        MintState memory state,
        RangeState memory range,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: A spot a word above the band's floor, a range around it, no pool fee.
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 2 * Constants.BITMAP_WORD_TICKS),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 2)
            )
        );
        givenValidState(state, range, true);
        state.fee = 0;

        // And: A limit in the word under the spot's, the range's lower edge below it.
        {
            int24 wordStart = (TickMath.getTickAtSqrtPrice(state.sqrtPriceX96) >> 8) << 8;
            range.tickLower =
                int24(bound(range.tickLower, -Constants.BOUND_TICK, wordStart - Constants.BITMAP_WORD_TICKS - 1));
            sqrtPriceLimitX96 = bound(
                sqrtPriceLimitX96,
                TickMath.getSqrtPriceAtTick(wordStart - Constants.BITMAP_WORD_TICKS),
                TickMath.getSqrtPriceAtTick(wordStart) - 2
            );
        }

        // And: At least 2 shares, and 2^40 of each token idle, above the mint rounding.
        state.supply = uint128(bound(state.supply, 2, type(uint64).max));
        state.idle0 = uint64(bound(state.idle0, type(uint40).max, type(uint64).max));
        state.idle1 = uint64(bound(state.idle1, type(uint40).max, type(uint64).max));
        uint256 assets;
        {
            Snapshot memory snapshot;
            {
                RangeState[] memory ranges = new RangeState[](1);
                ranges[0] = range;
                snapshot =
                    snapshotOf(pricedOf(ranges), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
            }
            address pool = poolOf(1, state.liquidity, snapshot.ranges);

            // When: Calculating the most a deposit of the whole supply's worth takes.
            assets = optimizationMath.maxDeposit(snapshot, pool, sqrtPriceLimitX96, true, state.supply);
        }

        // Then: The core's worth in token0, or the swap to the limit plus its token1.
        uint256 liquidity = uint256(range.liquidity) + range.liquidityStaked;
        (uint256 lower, uint256 upper) =
            (TickMath.getSqrtPriceAtTick(range.tickLower), TickMath.getSqrtPriceAtTick(range.tickUpper));
        uint256 composition;
        {
            uint160 limit = uint160(sqrtPriceLimitX96 + 1);
            uint160 word = TickMath.getSqrtPriceAtTick((TickMath.getTickAtSqrtPrice(state.sqrtPriceX96) >> 8) << 8);
            uint256 positionIn = uint256(state.idle0) + FullMath.mulDiv(liquidity, 1 << 96, limit)
                - FullMath.mulDiv(liquidity, 1 << 96, upper);
            uint256 positionOut = uint256(state.idle1) + FullMath.mulDiv(liquidity, limit, 1 << 96)
                - FullMath.mulDiv(liquidity, lower, 1 << 96);
            composition = SqrtPriceMath.getAmount1Delta(word, state.sqrtPriceX96, state.liquidity, false)
                + SqrtPriceMath.getAmount1Delta(limit, word, state.liquidity, false);
            composition = FullMath.mulDiv(composition, positionIn - 1, positionOut + 1);
            composition += SqrtPriceMath.getAmount0Delta(word, state.sqrtPriceX96, state.liquidity, true)
            + SqrtPriceMath.getAmount0Delta(limit, word, state.liquidity, false);
        }
        {
            uint256 worth = uint256(state.idle0) + FullMath.mulDiv(liquidity, 1 << 96, state.sqrtPriceX96)
                - FullMath.mulDiv(liquidity, 1 << 96, upper) - 1;
            worth += FullMath.mulDiv(
                uint256(state.idle1) + FullMath.mulDiv(liquidity, state.sqrtPriceX96, 1 << 96)
                    - FullMath.mulDiv(liquidity, lower, 1 << 96) - 1,
                1 << 192,
                uint256(state.sqrtPriceX96) * state.sqrtPriceX96
            );
            assertEq(assets, FixedPointMathLib.min(worth, composition));
        }
    }

    function testFuzz_Success_maxDeposit_TheTwoStepSwapToTheLimitAtItsComposition_OneForZero(
        MintState memory state,
        RangeState memory range,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: A spot a word below the band's top, a range around it, no pool fee.
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 1),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 2 * Constants.BITMAP_WORD_TICKS)
            )
        );
        givenValidState(state, range, true);
        state.fee = 0;

        // And: A limit in the word over the spot's, the range's upper edge above it.
        {
            int24 wordEnd =
                (((TickMath.getTickAtSqrtPrice(state.sqrtPriceX96) + 1) >> 8) << 8) + Constants.BITMAP_WORD_TICKS - 1;
            range.tickUpper =
                int24(bound(range.tickUpper, wordEnd + Constants.BITMAP_WORD_TICKS + 1, Constants.BOUND_TICK));
            sqrtPriceLimitX96 = bound(
                sqrtPriceLimitX96,
                TickMath.getSqrtPriceAtTick(wordEnd) + 2,
                TickMath.getSqrtPriceAtTick(wordEnd + Constants.BITMAP_WORD_TICKS)
            );
        }

        // And: At least 2 shares, and 2^40 of each token idle, above the mint rounding.
        state.supply = uint128(bound(state.supply, 2, type(uint64).max));
        state.idle0 = uint64(bound(state.idle0, type(uint40).max, type(uint64).max));
        state.idle1 = uint64(bound(state.idle1, type(uint40).max, type(uint64).max));
        uint256 assets;
        {
            Snapshot memory snapshot;
            {
                RangeState[] memory ranges = new RangeState[](1);
                ranges[0] = range;
                snapshot =
                    snapshotOf(pricedOf(ranges), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
            }
            address pool = poolOf(1, state.liquidity, snapshot.ranges);

            // When: Calculating the most a deposit of the whole supply's worth takes.
            assets = optimizationMath.maxDeposit(snapshot, pool, sqrtPriceLimitX96, false, state.supply);
        }

        // Then: The core's worth in token1, or the swap to the limit plus its token0.
        uint256 liquidity = uint256(range.liquidity) + range.liquidityStaked;
        (uint256 lower, uint256 upper) =
            (TickMath.getSqrtPriceAtTick(range.tickLower), TickMath.getSqrtPriceAtTick(range.tickUpper));
        uint256 composition;
        {
            uint160 limit = uint160(sqrtPriceLimitX96 - 1);
            uint160 word = TickMath.getSqrtPriceAtTick(
                (((TickMath.getTickAtSqrtPrice(state.sqrtPriceX96) + 1) >> 8) << 8) + Constants.BITMAP_WORD_TICKS - 1
            );
            uint256 positionIn = uint256(state.idle1) + FullMath.mulDiv(liquidity, limit, 1 << 96)
                - FullMath.mulDiv(liquidity, lower, 1 << 96);
            uint256 positionOut = uint256(state.idle0) + FullMath.mulDiv(liquidity, 1 << 96, limit)
                - FullMath.mulDiv(liquidity, 1 << 96, upper);
            composition = SqrtPriceMath.getAmount0Delta(state.sqrtPriceX96, word, state.liquidity, false)
                + SqrtPriceMath.getAmount0Delta(word, limit, state.liquidity, false);
            composition = FullMath.mulDiv(composition, positionIn - 1, positionOut + 1);
            composition += SqrtPriceMath.getAmount1Delta(state.sqrtPriceX96, word, state.liquidity, true)
            + SqrtPriceMath.getAmount1Delta(word, limit, state.liquidity, false);
        }
        {
            uint256 worth = uint256(state.idle1) + FullMath.mulDiv(liquidity, state.sqrtPriceX96, 1 << 96)
                - FullMath.mulDiv(liquidity, lower, 1 << 96) - 1;
            worth += FullMath.mulDiv(
                uint256(state.idle0) + FullMath.mulDiv(liquidity, 1 << 96, state.sqrtPriceX96)
                    - FullMath.mulDiv(liquidity, 1 << 96, upper) - 1,
                uint256(state.sqrtPriceX96) * state.sqrtPriceX96,
                1 << 192
            );
            assertEq(assets, FixedPointMathLib.min(worth, composition));
        }
    }

    function testFuzz_Success_maxDeposit_TheOneStepSwapToTheLimitAtItsComposition_OneForZero(
        MintState memory state,
        RangeState memory range,
        uint256 sqrtPriceLimitX96
    ) public {
        // Given: A range around spot, inside its tick, in a pool without fee.
        givenValidState(state, range, true);
        state.fee = 0;

        // And: At least 2 shares, and 2^40 of each token idle, over the mint rounding.
        state.supply = uint128(bound(state.supply, 2, type(uint64).max));
        state.idle0 = uint64(bound(state.idle0, type(uint40).max, type(uint64).max));
        state.idle1 = uint64(bound(state.idle1, type(uint40).max, type(uint64).max));
        uint256 assets;
        {
            // And: Spot three short of its tick's end.
            int24 tick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);
            state.sqrtPriceX96 = uint160(
                bound(state.sqrtPriceX96, TickMath.getSqrtPriceAtTick(tick), TickMath.getSqrtPriceAtTick(tick + 1) - 3)
            );
            Snapshot memory snapshot;
            {
                RangeState[] memory ranges = new RangeState[](1);
                ranges[0] = range;
                snapshot =
                    snapshotOf(pricedOf(ranges), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
            }
            address pool = poolOf(1, state.liquidity, snapshot.ranges);

            // And: A limit inside spot's tick, the swap to it a wei short in one step.
            sqrtPriceLimitX96 =
                bound(sqrtPriceLimitX96, state.sqrtPriceX96 + 2, TickMath.getSqrtPriceAtTick(tick + 1) - 1);

            // When: Calculating the most a deposit of the whole supply's worth takes.
            assets = optimizationMath.maxDeposit(snapshot, pool, sqrtPriceLimitX96, false, state.supply);
        }

        // Then: The core's worth in token1, or the swap to the limit and its token0.
        uint256 liquidity = uint256(range.liquidity) + range.liquidityStaked;
        (uint256 lower, uint256 upper) =
            (TickMath.getSqrtPriceAtTick(range.tickLower), TickMath.getSqrtPriceAtTick(range.tickUpper));
        uint256 worth = uint256(state.idle1) + FullMath.mulDiv(liquidity, state.sqrtPriceX96, 1 << 96)
            - FullMath.mulDiv(liquidity, lower, 1 << 96) - 1;
        worth += FullMath.mulDiv(
            uint256(state.idle0) + FullMath.mulDiv(liquidity, 1 << 96, state.sqrtPriceX96)
                - FullMath.mulDiv(liquidity, 1 << 96, upper) - 1,
            uint256(state.sqrtPriceX96) * state.sqrtPriceX96,
            1 << 192
        );
        uint256 composition;
        {
            uint256 limit = sqrtPriceLimitX96 - 1;
            uint256 positionIn = uint256(state.idle1) + FullMath.mulDiv(liquidity, limit, 1 << 96)
                - FullMath.mulDiv(liquidity, lower, 1 << 96);
            uint256 positionOut = uint256(state.idle0) + FullMath.mulDiv(liquidity, 1 << 96, limit)
                - FullMath.mulDiv(liquidity, 1 << 96, upper);
            composition = SqrtPriceMath.getAmount1Delta(state.sqrtPriceX96, uint160(limit), state.liquidity, false)
                + FullMath.mulDiv(
                    SqrtPriceMath.getAmount0Delta(state.sqrtPriceX96, uint160(limit), state.liquidity, false),
                    positionIn - 1,
                    positionOut + 1
                );
        }
        assertEq(assets, FixedPointMathLib.min(worth, composition));
    }
}
