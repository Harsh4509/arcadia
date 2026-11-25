/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { DepositOptimizationMath_Fuzz_Test } from "./_DepositOptimizationMath.fuzz.t.sol";
import { FixedPoint96 } from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { PoolMock } from "../../../utils/mocks/PoolMock.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "computeSwap" of library "DepositOptimizationMath".
 */
contract ComputeSwap_DepositOptimizationMath_Fuzz_Test is DepositOptimizationMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_computeSwap_ZeroLiquidity(AmountOutParams memory params, bool zeroForOne) public {
        // Given: A deposit, one range around spot, and idle tokens holding some tokenOut.
        givenValidAmountOutParams(params, zeroForOne);
        givenValidRangeAroundSpot(params);
        givenValidIdleTokenOut(params);

        // And: The pool has no active liquidity.
        params.poolLiquidity = 0;

        // When: Calling computeSwap().
        (,, uint256 amountOut,,) =
            optimizationMath.computeSwap(snapshotOf(params), poolOf(params), params.zeroForOne, params.balanceIn);

        // Then: The deposit buys none of tokenOut.
        assertEq(amountOut, 0);
    }

    function testFuzz_Success_computeSwap_ZeroWhenThePositionHoldsNoTokenOut(
        AmountOutParams memory params,
        bool zeroForOne
    ) public {
        // Given: A deposit into a pool, and one range behind spot, holding tokenIn only.
        givenValidAmountOutParams(params, zeroForOne);
        givenValidRangeBehindSpot(params);

        // And: Idle tokens holding no tokenOut.
        if (zeroForOne) params.idle1 = 0;
        else params.idle0 = 0;

        // When: Calling computeSwap().
        (,, uint256 amountOut,,) =
            optimizationMath.computeSwap(snapshotOf(params), poolOf(params), params.zeroForOne, params.balanceIn);

        // Then: The deposit buys none of tokenOut.
        assertEq(amountOut, 0);
    }

    function testFuzz_Success_computeSwap_CountsARangeTheStepMovesInto(AmountOutParams memory params, bool zeroForOne)
        public
    {
        // Given: A deposit at spot on a tick, short of the far edge of the range entered.
        givenValidSpotOnATick(params, zeroForOne);
        params.liquidity = uint128(bound(params.liquidity, 1, Constants.MAX_RANGE_LIQUIDITY));
        givenValidAmountOutParams(params, zeroForOne);
        givenValidDepositShortOfTheEdge(params);

        // And: The range bound at spot on the side the swap moves toward.
        if (zeroForOne) params.sqrtPriceUpper = params.sqrtPrice;
        else params.sqrtPriceLower = params.sqrtPrice;

        // And: Idle tokens holding some tokenOut.
        givenValidIdleTokenOut(params);

        // When: Calling computeSwap().
        address pool = poolOf(params);
        (,, uint256 amountOut,,) =
            optimizationMath.computeSwap(snapshotOf(params), pool, params.zeroForOne, params.balanceIn);

        // Then: The balances cross the position with all the range's liquidity, and fee.
        (uint256 amountIn, bool withinBound, bool notShortIn, bool notShortOut) =
            crossThePosition(params, pool, true, amountOut);
        assertLe(amountIn, params.balanceIn);
        assertTrue(withinBound);
        assertTrue(notShortIn);
        assertTrue(notShortOut);
    }

    function testFuzz_Success_computeSwap_LeavesOutARangeTheStepMovesAwayFrom(
        AmountOutParams memory params,
        bool zeroForOne
    ) public {
        // Given: A deposit at spot on a tick, and a range behind spot, its edge at spot.
        givenValidSpotOnATick(params, zeroForOne);
        givenValidAmountOutParams(params, zeroForOne);
        givenValidRangeBehindSpot(params);
        if (zeroForOne) params.sqrtPriceLower = params.sqrtPrice;
        else params.sqrtPriceUpper = params.sqrtPrice;

        // And: Idle tokens holding some tokenOut.
        givenValidIdleTokenOut(params);

        // When: Calling computeSwap().
        address pool = poolOf(params);
        (,, uint256 amountOut,,) =
            optimizationMath.computeSwap(snapshotOf(params), pool, params.zeroForOne, params.balanceIn);

        // Then: The balances cross the position with none of the range's liquidity.
        (uint256 amountIn, bool withinBound, bool notShortIn, bool notShortOut) =
            crossThePosition(params, pool, false, amountOut);
        assertLe(amountIn, params.balanceIn);
        assertTrue(withinBound);
        assertTrue(notShortIn);
        assertTrue(notShortOut);
    }

    function testFuzz_Success_computeSwap_PricesTheBuyAsOnePoolStep(AmountOutParams memory params, bool zeroForOne)
        public
    {
        // Given: A deposit into a pool with depth, short of the edge of a range at spot.
        givenValidAmountOutParams(params, zeroForOne);
        givenValidRangeAroundSpot(params);
        givenValidDepositShortOfTheEdge(params);

        // When: Sizing the swap.
        address pool = poolOf(params);
        (uint160 sqrtPriceNew, uint256 amountIn, uint256 amountOut,,) =
            optimizationMath.computeSwap(snapshotOf(params), pool, params.zeroForOne, params.balanceIn);

        // Then: The exact-output swap at the end price delivers the buy within the input.
        (uint160 sqrtPriceEnd, uint256 amountSwapIn, uint256 amountSwapOut) =
            swap(snapshotOf(params), pool, params.zeroForOne, int256(amountOut), sqrtPriceNew);
        assertEq(amountSwapOut, amountOut);
        assertLe(amountSwapIn, amountIn);
        assertTrue(zeroForOne ? sqrtPriceEnd >= sqrtPriceNew : sqrtPriceEnd <= sqrtPriceNew);
    }

    function testFuzz_Success_computeSwap_EndsAtThePriceItsBuyMovesThePoolTo(
        AmountOutParams memory params,
        bool zeroForOne
    ) public {
        // Given: Spot on the side of tick zero with no word end in the swap's direction.
        params.sqrtPrice = zeroForOne
            ? uint160(bound(params.sqrtPrice, 2 * Constants.MIN_RANGE_SQRT_PRICE, TickMath.getSqrtPriceAtTick(0) - 1))
            : uint160(bound(params.sqrtPrice, TickMath.getSqrtPriceAtTick(0), Constants.MAX_RANGE_SQRT_PRICE / 2));

        // And: A deposit short of the edge of a range around spot, the only liquidity.
        params.liquidity = uint128(bound(params.liquidity, 1, Constants.MAX_RANGE_LIQUIDITY));
        params.poolLiquidity = 0;
        givenValidAmountOutParams(params, zeroForOne);
        givenValidRangeAroundSpot(params);
        givenValidDepositShortOfTheEdge(params);

        // When: Sizing the swap.
        (uint160 sqrtPriceNew,, uint256 amountOut,,) =
            optimizationMath.computeSwap(snapshotOf(params), poolOf(params), zeroForOne, params.balanceIn);

        // Then: It ends at the price its buy moves the pool to.
        assertEq(
            sqrtPriceNew,
            SqrtPriceMath.getNextSqrtPriceFromOutput(params.sqrtPrice, params.poolLiquidity, amountOut, zeroForOne)
        );
    }

    function testFuzz_Success_computeSwap_ZeroForOne_PricesTheBuyFromSpotOnThePoolsTick(AmountOutParams memory params)
        public
    {
        // Given: A deposit at spot on a tick, short of the far edge of the range entered.
        givenValidSpotOnATick(params, true);
        params.liquidity = uint128(bound(params.liquidity, 1, Constants.MAX_RANGE_LIQUIDITY));
        params.poolLiquidity =
            uint128(bound(params.poolLiquidity, 1, type(uint128).max - Constants.MAX_RANGE_LIQUIDITY));
        givenValidAmountOutParams(params, true);
        givenValidDepositShortOfTheEdge(params);

        // And: The range's upper edge at spot, and idle tokens holding some tokenOut.
        params.sqrtPriceUpper = params.sqrtPrice;
        givenValidIdleTokenOut(params);

        // And: The pool's tick at spot, the range not yet entered.
        Snapshot memory snapshot = snapshotOf(params);
        snapshot.tick = TickMath.getTickAtSqrtPrice(params.sqrtPrice);
        address pool = poolOf(MOCK_TICK_SPACING, params.poolLiquidity - params.liquidity, snapshot.ranges);

        // When: Sizing the swap.
        (,, uint256 amountOut,,) = optimizationMath.computeSwap(snapshot, pool, true, params.balanceIn);

        // Then: The balances cross the position with all the range's liquidity, and fee.
        (uint256 amountIn, bool withinBound, bool notShortIn, bool notShortOut) =
            crossThePosition(params, pool, true, amountOut);
        assertLe(amountIn, params.balanceIn);
        assertTrue(withinBound);
        assertTrue(notShortIn);
        assertTrue(notShortOut);
    }

    function testFuzz_Success_computeSwap_ZeroForOne_EndsInTheStepItsDepositIsShortOfPassing(
        MintState memory state,
        RangeState memory range,
        uint256 balanceIn
    ) public {
        // Given: A spot in the upper half of its bitmap word, in the band.
        state.sqrtPriceX96 = uint160(
            bound(state.sqrtPriceX96, Constants.MIN_RANGE_SQRT_PRICE << 1, Constants.MAX_RANGE_SQRT_PRICE >> 1)
        );
        int24 wordStart = (TickMath.getTickAtSqrtPrice(state.sqrtPriceX96) >> 8) << 8;
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(wordStart + Constants.BITMAP_WORD_TICKS / 2),
                TickMath.getSqrtPriceAtTick(wordStart + Constants.BITMAP_WORD_TICKS - 1)
            )
        );

        // And: An unstaked range around spot alone in the pool, lower edge a word under.
        range.tickLower = int24(
            bound(
                range.tickLower,
                wordStart - 2 * Constants.BITMAP_WORD_TICKS,
                wordStart - Constants.BITMAP_WORD_TICKS - 1
            )
        );
        range.tickUpper = int24(
            bound(
                range.tickUpper,
                wordStart + Constants.BITMAP_WORD_TICKS,
                TickMath.getTickAtSqrtPrice(Constants.MAX_RANGE_SQRT_PRICE)
            )
        );
        range.liquidity =
            uint128(bound(range.liquidity, Constants.MIN_DEPOSIT_RANGE_LIQUIDITY, Constants.MAX_RANGE_LIQUIDITY));
        range.liquidityStaked = 0;
        state.fee = uint24(bound(state.fee, 1, Constants.MAX_POOL_FEE));
        state.supply = uint128(bound(state.supply, 1, type(uint64).max));
        Snapshot memory snapshot;
        {
            RangeState[] memory ranges = new RangeState[](1);
            ranges[0] = range;
            snapshot =
                snapshotOf(pricedOf(ranges), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
        }
        address pool = poolOf(1, range.liquidity, snapshot.ranges);

        // And: A deposit short of the one whose swap to the word start ends at the ratio.
        {
            uint160 word = TickMath.getSqrtPriceAtTick(wordStart);
            uint256 stepIn = SqrtPriceMath.getAmount0Delta(word, state.sqrtPriceX96, range.liquidity, true);
            uint256 feeAmount = FixedPointMathLib.fullMulDivUp(stepIn, state.fee, 1e6 - state.fee);
            uint256 stepOut = SqrtPriceMath.getAmount1Delta(word, state.sqrtPriceX96, range.liquidity, false);
            uint256 positionIn = uint256(state.idle0) + FixedPointMathLib.fullMulDiv(range.liquidity, 1 << 96, word)
                - FixedPointMathLib.fullMulDiv(range.liquidity, 1 << 96, TickMath.getSqrtPriceAtTick(range.tickUpper))
                + feeAmount;
            uint256 positionOut = uint256(state.idle1) + FixedPointMathLib.fullMulDiv(range.liquidity, word, 1 << 96)
                - FixedPointMathLib.fullMulDiv(range.liquidity, TickMath.getSqrtPriceAtTick(range.tickLower), 1 << 96);
            uint256 window =
                FixedPointMathLib.min(feeAmount, FixedPointMathLib.fullMulDiv(stepOut, feeAmount, positionOut));
            balanceIn = stepIn + feeAmount + FixedPointMathLib.fullMulDiv(stepOut, positionIn, positionOut)
                - bound(balanceIn, window / 4, window / 2);
        }

        // When: Sizing the swap.
        (uint160 sqrtPriceNew,,,,) = optimizationMath.computeSwap(snapshot, pool, true, balanceIn);

        // Then: It ends inside the step, short of the word start.
        assertGt(sqrtPriceNew, TickMath.getSqrtPriceAtTick(wordStart));
    }

    function testFuzz_Success_computeSwap_ZeroForOne_PassesTheWordStartAWeiOverTheDepositEndingThere(
        MintState memory state,
        RangeState memory range
    ) public {
        // Given: A word start, a range around it alone in the pool, spot in its top half.
        int24 tickWord = givenValidWordStartBelowSpot(state, range);
        givenValidHalfTokenStepToTheWordStart(state, range, tickWord);
        Snapshot memory snapshot = snapshotOf(state, range);
        address pool = poolOf(1, range.liquidity, snapshot.ranges);

        // And: A wei past the deposit whose swap to the word start ends at the ratio.
        uint160 wordStart = TickMath.getSqrtPriceAtTick(tickWord);
        uint256 balanceIn = depositPassingAt(state, range, wordStart, range.liquidity, true) + 1;

        // When: Sizing the swap.
        (uint160 sqrtPriceNew,,,,) = optimizationMath.computeSwap(snapshot, pool, true, balanceIn);

        // Then: It passes the word start.
        assertLe(sqrtPriceNew, wordStart);
    }

    function testFuzz_Success_computeSwap_ZeroForOne_EndsInTheStepAtTheDepositEndingAtTheWordStart(
        MintState memory state,
        RangeState memory range
    ) public {
        // Given: A word start, a range around it alone in the pool, spot in its top half.
        int24 tickWord = givenValidWordStartBelowSpot(state, range);
        givenValidHalfTokenStepToTheWordStart(state, range, tickWord);
        Snapshot memory snapshot = snapshotOf(state, range);
        address pool = poolOf(1, range.liquidity, snapshot.ranges);

        // And: The deposit whose swap to the word start ends at the composition.
        uint160 wordStart = TickMath.getSqrtPriceAtTick(tickWord);
        uint256 balanceIn = depositPassingAt(state, range, wordStart, range.liquidity, true);

        // When: Sizing the swap.
        (uint160 sqrtPriceNew,,,,) = optimizationMath.computeSwap(snapshot, pool, true, balanceIn);

        // Then: It ends inside the step.
        assertGt(sqrtPriceNew, wordStart);
    }

    function testFuzz_Success_computeSwap_ZeroForOne_PassesTheWordStartAWeiOverTheDepositEndingThere_ThinTokenOut(
        MintState memory state,
        RangeState memory range
    ) public {
        // Given: A word start, a range around it alone in the pool, spot in its top half.
        int24 tickWord = givenValidWordStartBelowSpot(state, range);

        // And: No idle tokenOut and the range's lower edge near the word start.
        state.idle1 = 0;
        range.tickLower = int24(
            bound(range.tickLower, tickWord - Constants.MAX_THIN_EDGE_TICKS, tickWord - Constants.MIN_THIN_EDGE_TICKS)
        );
        givenValidHalfTokenStepToTheWordStart(state, range, tickWord);
        Snapshot memory snapshot = snapshotOf(state, range);
        address pool = poolOf(1, range.liquidity, snapshot.ranges);

        // And: A wei past the deposit whose swap to the word start ends at the ratio.
        uint160 wordStart = TickMath.getSqrtPriceAtTick(tickWord);
        uint256 balanceIn = depositPassingAt(state, range, wordStart, range.liquidity, true) + 1;

        // When: Sizing the swap.
        (uint160 sqrtPriceNew,,,,) = optimizationMath.computeSwap(snapshot, pool, true, balanceIn);

        // Then: It passes the word start.
        assertLe(sqrtPriceNew, wordStart);
    }

    function testFuzz_Success_computeSwap_ZeroForOne_EndsInTheStepAtTheDepositEndingAtTheWordStart_ThinTokenOut(
        MintState memory state,
        RangeState memory range
    ) public {
        // Given: A word start, a range around it alone in the pool, spot in its top half.
        int24 tickWord = givenValidWordStartBelowSpot(state, range);

        // And: No idle tokenOut and the range's lower edge near the word start.
        state.idle1 = 0;
        range.tickLower = int24(
            bound(range.tickLower, tickWord - Constants.MAX_THIN_EDGE_TICKS, tickWord - Constants.MIN_THIN_EDGE_TICKS)
        );
        givenValidHalfTokenStepToTheWordStart(state, range, tickWord);
        Snapshot memory snapshot = snapshotOf(state, range);
        address pool = poolOf(1, range.liquidity, snapshot.ranges);

        // And: The deposit whose swap to the word start ends at the composition.
        uint160 wordStart = TickMath.getSqrtPriceAtTick(tickWord);
        uint256 balanceIn = depositPassingAt(state, range, wordStart, range.liquidity, true);

        // When: Sizing the swap.
        (uint160 sqrtPriceNew,,,,) = optimizationMath.computeSwap(snapshot, pool, true, balanceIn);

        // Then: It ends inside the step.
        assertGt(sqrtPriceNew, wordStart);
    }

    function testFuzz_Success_computeSwap_ZeroForOne_PassesBothWordStartsItsDepositIsAWeiPast(
        MintState memory state,
        RangeState memory range
    ) public {
        // Given: A word start, a range around it alone in the pool, spot in its top half.
        int24 tickWord = givenValidWordStartBelowSpot(state, range);
        uint160 wordStart = TickMath.getSqrtPriceAtTick(tickWord);
        uint160 wordStartNext = TickMath.getSqrtPriceAtTick(tickWord - Constants.BITMAP_WORD_TICKS);
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(tickWord + Constants.BITMAP_WORD_TICKS / 2),
                TickMath.getSqrtPriceAtTick(tickWord + Constants.BITMAP_WORD_TICKS - 1)
            )
        );

        // And: A liquidity at which the step between word starts pays half a tokenOut.
        range.liquidity = uint128((uint256(1) << 95) / (wordStart - wordStartNext));
        Snapshot memory snapshot = snapshotOf(state, range);
        address pool = poolOf(1, range.liquidity, snapshot.ranges);

        // And: A deposit a wei past the cost of the swap to the second word start.
        uint256 balanceIn = SqrtPriceMath.getAmount0Delta(wordStart, state.sqrtPriceX96, range.liquidity, true);
        balanceIn += FixedPointMathLib.fullMulDivUp(balanceIn, state.fee, 1e6 - state.fee);
        uint256 stepIn = SqrtPriceMath.getAmount0Delta(wordStartNext, wordStart, range.liquidity, true);
        balanceIn += stepIn + FixedPointMathLib.fullMulDivUp(stepIn, state.fee, 1e6 - state.fee) + 1;

        // And: Past the balance margin at the second word start, r_in + 3 = u + 6.
        balanceIn += FixedPointMathLib.divUp(1 << 96, wordStartNext) + 6;

        // When: Sizing the swap.
        (uint160 sqrtPriceNew,,,,) = optimizationMath.computeSwap(snapshot, pool, true, balanceIn);

        // Then: It ends at the second word start, where the wei runs out.
        assertEq(sqrtPriceNew, wordStartNext);
    }

    function testFuzz_Success_computeSwap_PricesTheBuyAsPoolStepsAcrossAForeignTick(
        MintState memory state,
        RangeState memory range,
        int24 tickForeign,
        bool zeroForOne
    ) public {
        // Given: A range around spot, and as deep a foreign range ending a tick ahead.
        tickForeign = givenValidForeignTickAhead(state, range, tickForeign, zeroForOne);
        Snapshot memory snapshot = snapshotOf(state, range);
        address pool = poolOf(1, 2 * range.liquidity, snapshot.ranges);
        int128 liquidityNet = zeroForOne ? int128(range.liquidity) : -int128(range.liquidity);
        PoolMock(pool).addLiquidityNet(tickForeign, liquidityNet);
        PoolMock(pool).addLiquidityNet(zeroForOne ? range.tickUpper : range.tickLower, -liquidityNet);

        // And: The deposit whose swap to the foreign tick ends at the composition.
        uint160 sqrtPriceForeign = TickMath.getSqrtPriceAtTick(tickForeign);
        uint256 balanceIn = depositPassingAt(state, range, sqrtPriceForeign, 2 * range.liquidity, zeroForOne);

        // When: Sizing the swap.
        (uint160 sqrtPriceNew, uint256 amountIn, uint256 amountOut,,) =
            optimizationMath.computeSwap(snapshot, pool, zeroForOne, balanceIn);

        // Then: The exact-output swap at the end price delivers the buy within the input.
        (uint160 sqrtPriceEnd, uint256 amountSwapIn, uint256 amountSwapOut) =
            swap(snapshot, pool, zeroForOne, int256(amountOut), sqrtPriceNew);
        assertEq(amountSwapOut, amountOut);
        assertLe(amountSwapIn, amountIn);
        assertTrue(zeroForOne ? sqrtPriceEnd >= sqrtPriceNew : sqrtPriceEnd <= sqrtPriceNew);
    }

    function testFuzz_Success_computeSwap_CreditsTheCoreItsShareOfTheFee(AmountOutParams memory params, bool zeroForOne)
        public
    {
        // Given: A deposit at spot on a tick, short of the edge of a range around spot.
        givenValidSpotOnATick(params, zeroForOne);
        givenValidAmountOutParams(params, zeroForOne);
        givenValidRangeAroundSpot(params);
        givenValidDepositShortOfTheEdge(params);

        // When: Sizing the swap.
        (uint160 sqrtPriceNew, uint256 amountIn,, uint256 fees0, uint256 fees1) =
            optimizationMath.computeSwap(snapshotOf(params), poolOf(params), zeroForOne, params.balanceIn);

        // Then: The tokenIn fees rise by the range's share of the step's fee, rounded up.
        uint256 fee = amountIn
            - (zeroForOne
                    ? SqrtPriceMath.getAmount0Delta(sqrtPriceNew, params.sqrtPrice, params.poolLiquidity, true)
                    : SqrtPriceMath.getAmount1Delta(params.sqrtPrice, sqrtPriceNew, params.poolLiquidity, true));
        assertEq(
            zeroForOne ? fees0 : fees1, FixedPointMathLib.fullMulDivUp(fee, params.liquidity, params.poolLiquidity)
        );
        assertEq(zeroForOne ? fees1 : fees0, 0);
    }

    function testFuzz_Success_computeSwap_PricesTheBuyAsPoolStepsAcrossTheEdge(
        AmountOutParams memory params,
        bool zeroForOne
    ) public {
        // Given: A deposit into a pool, and a range ahead of spot it crosses into.
        givenValidAmountOutParams(params, zeroForOne);
        givenValidCrossing(params);

        // When: Sizing the swap.
        address pool = poolOf(params);
        (uint160 sqrtPriceNew, uint256 amountIn, uint256 amountOut,,) =
            optimizationMath.computeSwap(snapshotOf(params), pool, params.zeroForOne, params.balanceIn);

        // Then: The swap crosses the edge, and exact output at its end buys in full.
        assertTrue(zeroForOne ? sqrtPriceNew <= params.sqrtPriceUpper : sqrtPriceNew >= params.sqrtPriceLower);
        (uint160 sqrtPriceEnd, uint256 amountSwapIn, uint256 amountSwapOut) =
            swap(snapshotOf(params), pool, params.zeroForOne, int256(amountOut), sqrtPriceNew);
        assertEq(amountSwapOut, amountOut);
        assertLe(amountSwapIn, amountIn);
        assertTrue(zeroForOne ? sqrtPriceEnd >= sqrtPriceNew : sqrtPriceEnd <= sqrtPriceNew);
    }

    function testFuzz_Success_computeSwap_CrossesThePositionPastTheEdge(AmountOutParams memory params, bool zeroForOne)
        public
    {
        // Given: A deposit into a pool, and a range ahead of spot it crosses into.
        givenValidAmountOutParams(params, zeroForOne);
        givenValidCrossing(params);

        // When: Sizing the swap.
        address pool = poolOf(params);
        (,, uint256 amountOut,,) =
            optimizationMath.computeSwap(snapshotOf(params), pool, params.zeroForOne, params.balanceIn);

        // And: Past the edge the buy is held and the range is in.
        {
            uint160 edge = zeroForOne ? params.sqrtPriceUpper : params.sqrtPriceLower;
            (, uint256 stepIn, uint256 stepOut) =
                swap(snapshotOf(params), pool, params.zeroForOne, int256(amountOut), edge);
            (params.balanceIn, params.balanceOut) = (params.balanceIn - stepIn, stepOut);
            (params.sqrtPrice, params.poolLiquidity) = (edge, params.poolLiquidity + params.liquidity);
            amountOut -= stepOut;
        }

        // Then: The balances cross the position past the edge, within the deposit.
        (uint256 amountIn, bool withinBound, bool notShortIn, bool notShortOut) =
            crossThePosition(params, pool, true, amountOut);
        assertLe(amountIn, params.balanceIn);
        assertTrue(withinBound);
        assertTrue(notShortIn);
        assertTrue(notShortOut);
    }

    function testFuzz_Success_computeSwap_OneForZero_KeepsTheMintsCostOfAThinAssetLeg(
        AmountOutParams memory params,
        uint128 liquidityBelow,
        bool twoRanges
    ) public {
        // Given: An unstaked dust range up from price one.
        params.liquidity = uint128(bound(params.liquidity, 1, type(uint16).max));
        PricedRange[] memory ranges = new PricedRange[](twoRanges ? 2 : 1);
        ranges[0] = PricedRange({
            liquidity: params.liquidity,
            unstakedLiquidity: params.liquidity,
            sqrtPriceLowerX96: uint160(FixedPoint96.Q96),
            sqrtPriceUpperX96: TickMath.getSqrtPriceAtTick(4 * MOCK_TICK_SPACING)
        });

        // And: With two ranges, one below spot holding a few wei of token1 alone.
        if (twoRanges) {
            liquidityBelow = uint128(
                bound(
                    liquidityBelow,
                    1,
                    FixedPointMathLib.fullMulDiv(
                        Constants.MAX_THIN_IDLE1,
                        FixedPoint96.Q96,
                        TickMath.getSqrtPriceAtTick(-MOCK_TICK_SPACING)
                            - TickMath.getSqrtPriceAtTick(-2 * MOCK_TICK_SPACING)
                    )
                )
            );
            ranges[1] = PricedRange({
                liquidity: liquidityBelow,
                unstakedLiquidity: liquidityBelow,
                sqrtPriceLowerX96: TickMath.getSqrtPriceAtTick(-2 * MOCK_TICK_SPACING),
                sqrtPriceUpperX96: TickMath.getSqrtPriceAtTick(-MOCK_TICK_SPACING)
            });
        }

        // And: Spot in the range's lower eighth, a few wei of token1 idle, any token0.
        params.sqrtPrice = uint160(FixedPoint96.Q96 + bound(params.sqrtPrice, 1, FixedPoint96.Q96 / 8));
        params.idle0 = bound(params.idle0, 0, Constants.MAX_FUZZED_AMOUNT);
        params.idle1 = bound(params.idle1, 0, Constants.MAX_THIN_IDLE1);
        params.supply = bound(params.supply, 1, type(uint64).max);
        params.fee = uint24(bound(params.fee, 0, Constants.MAX_POOL_FEE));
        params.balanceIn = bound(params.balanceIn, 1, Constants.MAX_FUZZED_AMOUNT);

        // And: A pool deep enough that the deposit's swap stays in the range.
        params.poolLiquidity = uint128(
            bound(
                params.poolLiquidity,
                FixedPointMathLib.max(
                    params.liquidity,
                    FixedPointMathLib.fullMulDivUp(
                        params.balanceIn, FixedPoint96.Q96, ranges[0].sqrtPriceUpperX96 - params.sqrtPrice
                    )
                ),
                type(uint128).max
            )
        );
        Snapshot memory snapshot =
            snapshotOf(ranges, params.idle0, params.idle1, params.supply, params.sqrtPrice, params.fee);

        // When: Sizing the swap of token1, the core's token1 fees accrued.
        uint160 sqrtPriceNew;
        uint256 amountOut;
        uint256 kept;
        {
            uint256 fees0;
            uint256 fees1;
            (sqrtPriceNew, kept, amountOut, fees0, fees1) = optimizationMath.computeSwap(
                snapshot, poolOf(MOCK_TICK_SPACING, params.poolLiquidity, ranges), false, params.balanceIn
            );
            assertEq(fees0, 0);
            params.idle1 += fees1;
        }
        if (amountOut == 0) return;

        // Then: The token1 kept, less the swap's input, covers the mint's rounding.
        kept = params.balanceIn - kept - snapshotLib.getRounding(snapshot, sqrtPriceNew, false);

        // And: Net of it, per token0 bought, at least the cost ratio, a wei up.
        (, uint256 costIn) = snapshotLib.getMintAmounts(ranges, sqrtPriceNew, params.idle0, params.idle1, 1, 1, false);
        uint256 positionOut = params.idle0 + FixedPointMathLib.fullMulDiv(params.liquidity, 1 << 96, sqrtPriceNew)
            - FixedPointMathLib.fullMulDiv(params.liquidity, 1 << 96, ranges[0].sqrtPriceUpperX96);
        assertGe(kept * (positionOut + 1), amountOut * costIn);
    }
}
