/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { DepositOptimizationMath } from "../../../../src/vaults/libraries/math/DepositOptimizationMath.sol";
import { DepositOptimizationMath_Fuzz_Test } from "./_DepositOptimizationMath.fuzz.t.sol";
import { FixedPoint96 } from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { SwapMath } from "@uniswap/v4-core/src/libraries/SwapMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getAmountOut" of library "DepositOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetAmountOut_DepositOptimizationMath_Fuzz_Test is DepositOptimizationMath_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override {
        DepositOptimizationMath_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getAmountOut_ZeroForOne_ZeroLiquidity(DepositParams memory params) public {
        // Given: A deposit of token0 and a position on its segment.
        givenValidDepositParams(params, true);

        // And: The position takes token0 past sqrtPriceOld.
        params.positionAmount0 = bound(params.positionAmount0, 1, type(uint128).max);

        // And: liquidity is zero.
        params.liquidity = 0;

        // When: Calling getAmountOut() for a zeroForOne swap.
        // Then: It should revert.
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        getAmountOut(params);
    }

    function testFuzz_Revert_getAmountOut_ZeroForOne_AmountInTooLarge(DepositParams memory params) public {
        // Given: A deposit of token0 and a position on its segment.
        givenValidDepositParams(params, true);

        // And: The position takes token0 past sqrtPriceOld.
        params.positionAmount0 = bound(params.positionAmount0, 1, type(uint128).max);

        // And: The normalized amount0 exceeds MAX_NORMALIZED.
        uint256 denominator = uint256(params.sqrtPriceOld) << 96;
        params.balanceIn = bound(
            params.balanceIn,
            FullMath.mulDivRoundingUp(DepositOptimizationMath.MAX_NORMALIZED + 1, params.liquidity, denominator),
            FullMath.mulDiv(type(uint256).max, params.liquidity, denominator)
        );

        // When: Calling getAmountOut() for a zeroForOne swap.
        // Then: It should revert.
        vm.expectRevert(DepositOptimizationMath.AmountInTooLarge.selector);
        getAmountOut(params);
    }

    function testFuzz_Revert_getAmountOut_OneForZero_ZeroLiquidity(DepositParams memory params) public {
        // Given: A deposit of token1 and a position on its segment.
        givenValidDepositParams(params, false);

        // And: The position takes token1 past sqrtPriceOld.
        params.positionAmount1 = bound(params.positionAmount1, 1, type(uint128).max);

        // And: liquidity is zero.
        params.liquidity = 0;

        // When: Calling getAmountOut() for a oneForZero swap.
        // Then: It should revert.
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        getAmountOut(params);
    }

    function testFuzz_Revert_getAmountOut_OneForZero_AmountInTooLarge(DepositParams memory params) public {
        // Given: A deposit of token1 and a position on its segment.
        givenValidDepositParams(params, false);

        // And: The position takes token1 past sqrtPriceOld.
        params.positionAmount1 = bound(params.positionAmount1, 1, type(uint128).max);

        // And: The normalized amount1 exceeds MAX_NORMALIZED.
        params.balanceIn = bound(
            params.balanceIn,
            FullMath.mulDivRoundingUp(
                FullMath.mulDivRoundingUp(DepositOptimizationMath.MAX_NORMALIZED + 1, params.sqrtPriceOld, 1 << 160),
                params.liquidity,
                1 << 128
            ),
            FullMath.mulDiv(
                FullMath.mulDiv(type(uint256).max, params.sqrtPriceOld, 1 << 160), params.liquidity, 1 << 128
            )
        );

        // When: Calling getAmountOut() for a oneForZero swap.
        // Then: It should revert.
        vm.expectRevert(DepositOptimizationMath.AmountInTooLarge.selector);
        getAmountOut(params);
    }

    function testFuzz_Success_getAmountOut_ZeroForOne_NoToken1(DepositParams memory params) public view {
        // Given: A deposit of token0 and a position on its segment.
        givenValidDepositParams(params, true);

        // And: The position holds no token1, and some token0.
        params.positionAmount1 = 0;
        params.positionAmount0 = bound(params.positionAmount0, 1, type(uint128).max);

        // When: Calling getAmountOut() for a zeroForOne swap.
        uint256 amountOut = getAmountOut(params);

        // Then: amountOut is zero.
        assertEq(amountOut, 0);
    }

    function testFuzz_Success_getAmountOut_ZeroForOne_NoToken0_SellsAll(DepositParams memory params) public view {
        // Given: A token0 deposit and a position holding only token1, on the full range.
        givenValidDepositParams(params, true);
        params.positionLiquidity = 0;
        params.positionAmount0 = 0;
        params.roundingMargin = 0;
        params.sqrtPriceBound = TickMath.MIN_SQRT_PRICE;

        // And: A deposit short of the move to the bound, moving spot by 2^16 at most.
        {
            (uint256 minBalanceIn, uint256 maxBalanceIn) = getBalanceInBounds(params);
            maxBalanceIn = FixedPointMathLib.max(
                minBalanceIn,
                FixedPointMathLib.min(maxBalanceIn, FullMath.mulDiv(params.liquidity, 1 << 112, params.sqrtPriceOld))
            );
            uint256 toBound =
                SqrtPriceMath.getAmount0Delta(params.sqrtPriceBound, params.sqrtPriceOld, params.liquidity, true);
            params.balanceIn = bound(
                params.balanceIn,
                minBalanceIn,
                FixedPointMathLib.min(maxBalanceIn, FullMath.mulDivRoundingUp(toBound, 1e6, 1e6 - params.fee) - 1)
            );
        }
        (uint160 sqrtPriceFull,, uint256 amountOutFull,) = SwapMath.computeSwapStep(
            params.sqrtPriceOld, params.sqrtPriceBound, params.liquidity, -int256(params.balanceIn), params.fee
        );

        // When: Calling getAmountOut() for a zeroForOne swap.
        uint256 amountOut = getAmountOut(params);

        // Then: It sells the deposit, to the full sale's price or one short of it.
        assertLe(amountOut, amountOutFull);
        assertGe(
            amountOut,
            SqrtPriceMath.getAmount1Delta(
                uint160(FixedPointMathLib.min(sqrtPriceFull + 1, params.sqrtPriceOld)),
                params.sqrtPriceOld,
                params.liquidity,
                false
            )
        );
    }

    function testFuzz_Success_getAmountOut_ZeroForOne_NoToken0_LimitReached(DepositParams memory params) public view {
        // Given: A token0 deposit and a position holding only token1, on the full range.
        givenValidDepositParams(params, true);
        params.positionLiquidity = 0;
        params.positionAmount0 = 0;
        params.roundingMargin = 0;

        // And: A bound the largest deposit can reach, and a deposit that pays for it.
        (uint256 minBalanceIn, uint256 maxBalanceIn) = getBalanceInBounds(params);
        params.sqrtPriceBound = uint160(
            bound(
                params.sqrtPriceBound,
                FixedPointMathLib.max(
                    getSegmentEnd(params),
                    SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
                        params.sqrtPriceOld,
                        params.liquidity,
                        FullMath.mulDiv(maxBalanceIn, 1e6 - params.fee, 1e6),
                        true
                    )
                ),
                params.sqrtPriceOld
            )
        );
        minBalanceIn = FixedPointMathLib.max(
            minBalanceIn,
            FullMath.mulDivRoundingUp(
                SqrtPriceMath.getAmount0Delta(params.sqrtPriceBound, params.sqrtPriceOld, params.liquidity, true),
                1e6,
                1e6 - params.fee
            )
        );
        params.balanceIn = bound(params.balanceIn, minBalanceIn, maxBalanceIn);

        // When: Calling getAmountOut() for a zeroForOne swap.
        uint256 amountOut = getAmountOut(params);

        // Then: It sells up to sqrtPriceBound.
        assertEq(
            amountOut,
            SqrtPriceMath.getAmount1Delta(params.sqrtPriceBound, params.sqrtPriceOld, params.liquidity, false)
        );

        // And: The swap costs at most the deposit.
        (, uint256 amountIn) = buy(params, amountOut);
        assertLe(amountIn, params.balanceIn);
    }

    function testFuzz_Success_getAmountOut_ZeroForOne_WithinSegmentAndDeposit(DepositParams memory params) public view {
        // Given: A deposit of token0 and a position on its segment.
        givenValidDepositParams(params, true);

        // When: Calling getAmountOut() for a zeroForOne swap.
        uint256 amountOut = getAmountOut(params);

        // Then: The pool price after the swap is between sqrtPriceBound and sqrtPriceOld.
        (uint160 sqrtPriceNew, uint256 amountIn) = buy(params, amountOut);
        assertLe(sqrtPriceNew, params.sqrtPriceOld);
        assertGe(sqrtPriceNew, params.sqrtPriceBound);

        // And: The swap costs at most the deposit.
        assertLe(amountIn, params.balanceIn);
    }

    function testFuzz_Success_getAmountOut_ZeroForOne_DustDemandOfToken0(DepositParams memory params) public view {
        // Given: A deposit of token0 and a position on its segment.
        givenValidDepositParams(params, true);

        // And: The position holds no token0 and needs less token1 than the swap leaves.
        (uint256 minBalanceIn, uint256 maxBalanceIn) = getBalanceInBounds(params);
        maxBalanceIn =
            FixedPointMathLib.min(maxBalanceIn, FullMath.mulDiv(type(uint128).max, 1 << 96, params.sqrtPriceOld) - 1);
        params.balanceIn = bound(params.balanceIn, minBalanceIn, maxBalanceIn);
        params.positionAmount0 = 0;
        params.positionAmount1 = bound(
            params.positionAmount1,
            FullMath.mulDivRoundingUp(params.balanceIn + 1, params.sqrtPriceOld, 1 << 96),
            type(uint128).max
        );
        params.positionLiquidity = bound(
            params.positionLiquidity,
            1,
            FixedPointMathLib.min(
                params.liquidity,
                FullMath.mulDiv(params.positionAmount1, 1 << 96, params.sqrtPriceOld) / (params.balanceIn + 1)
            )
        );
        params.sqrtPriceBound = uint160(bound(params.sqrtPriceBound, getSegmentEnd(params), params.sqrtPriceOld));

        // When: Calling getAmountOut() for a zeroForOne swap.
        uint256 amountOut = getAmountOut(params);

        // Then: The swap costs at most the deposit.
        (, uint256 amountIn) = buy(params, amountOut);
        assertLe(amountIn, params.balanceIn);
    }

    function testFuzz_Success_getAmountOut_ZeroForOne_DustDemandOfToken0_NoLiquidity(DepositParams memory params)
        public
        view
    {
        // Given: A deposit of token0 and a position on its segment.
        givenValidDepositParams(params, true);

        // And: The position has no liquidity in range, keeping less than the swap leaves.
        (uint256 minBalanceIn, uint256 maxBalanceIn) = getBalanceInBounds(params);
        maxBalanceIn = FixedPointMathLib.min(
            maxBalanceIn,
            FullMath.mulDiv(
                FullMath.mulDiv(type(uint128).max, 1 << 96, params.sqrtPriceOld), 1 << 96, params.sqrtPriceOld
            )
        );
        params.balanceIn = bound(params.balanceIn, minBalanceIn, maxBalanceIn);
        uint256 maxAmountOut = FullMath.mulDivRoundingUp(
            FullMath.mulDivRoundingUp(params.balanceIn, params.sqrtPriceOld, 1 << 96), params.sqrtPriceOld, 1 << 96
        );
        params.positionLiquidity = 0;
        params.positionAmount1 = bound(params.positionAmount1, maxAmountOut, type(uint128).max);
        params.positionAmount0 = bound(params.positionAmount0, 1, params.positionAmount1 / maxAmountOut);
        params.sqrtPriceBound = uint160(bound(params.sqrtPriceBound, getSegmentEnd(params), params.sqrtPriceOld));

        // When: Calling getAmountOut() for a zeroForOne swap.
        uint256 amountOut = getAmountOut(params);

        // Then: The swap costs at most the deposit.
        (, uint256 amountIn) = buy(params, amountOut);
        assertLe(amountIn, params.balanceIn);
    }

    function testFuzz_Success_getAmountOut_ZeroForOne_LargestUpToItsPrice(DepositParams memory params) public view {
        // Given: A deposit of token0 and a position on its segment.
        givenValidDepositParams(params, true);

        // And: The deposit times sqrtPriceOld plus L * 2^96 fits 256 bits.
        (uint256 minBalanceIn, uint256 maxBalanceIn) = getBalanceInBounds(params);
        maxBalanceIn = FixedPointMathLib.min(
            maxBalanceIn, (type(uint256).max - (uint256(params.liquidity) << 96)) / params.sqrtPriceOld
        );
        params.balanceIn = bound(params.balanceIn, minBalanceIn, maxBalanceIn);

        // When: Calling getAmountOut() for a zeroForOne swap.
        uint256 amountOut = getAmountOut(params);

        // Then: One wei more passes the bound or the solver's price, or costs too much.
        uint160 sqrtPriceSolve = getSqrtPrice(params);
        uint256 toLimit =
            SqrtPriceMath.getAmount1Delta(params.sqrtPriceBound, params.sqrtPriceOld, params.liquidity, false);
        bool pastTheBound = amountOut + 1 >= toLimit;
        uint160 sqrtPriceNext;
        uint256 amountInNext;
        if (!pastTheBound) {
            (sqrtPriceNext, amountInNext) = buy(params, amountOut + 1);
        }
        assertTrue(pastTheBound || sqrtPriceNext < sqrtPriceSolve || amountInNext > params.balanceIn);
    }

    function testFuzz_Success_getAmountOut_ZeroForOne_LargestUpToItsPrice_InexactFrontier(DepositParams memory params)
        public
        view
    {
        // Given: A token0 deposit at spot from 2^129, L * 2^156 net of fee past 2^256.
        params.sqrtPriceOld =
            uint160(bound(params.sqrtPriceOld, 2 * Constants.MAX_RANGE_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 2));
        params.liquidity = uint128(
            bound(
                params.liquidity,
                FullMath.mulDivRoundingUp(1 << 100, 1e6, 1e6 - Constants.MAX_POOL_FEE),
                type(uint128).max
            )
        );
        givenValidDepositParams(params, true);

        // And: The net deposit times sqrtPriceOld plus L * 2^96 exceeds 256 bits.
        {
            uint256 numerator = uint256(params.liquidity) << 96;
            (uint256 minBalanceIn, uint256 maxBalanceIn) = getBalanceInBounds(params);
            minBalanceIn = FixedPointMathLib.max(
                minBalanceIn,
                FullMath.mulDivRoundingUp(
                    (type(uint256).max - numerator) / params.sqrtPriceOld + 2, 1e6, 1e6 - params.fee
                )
            );
            params.balanceIn = bound(params.balanceIn, minBalanceIn, maxBalanceIn);
        }

        // When: Calling getAmountOut() for a zeroForOne swap.
        uint256 amountOut = getAmountOut(params);

        // Then: amountOut is short of the largest up to its price by under a wei of each.
        uint160 sqrtPriceSolve = getSqrtPrice(params);
        uint256 sqrtPriceInput = SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
            params.sqrtPriceOld, params.liquidity, FullMath.mulDiv(params.balanceIn, 1e6 - params.fee, 1e6), true
        );
        uint256 shortfall = FullMath.mulDivRoundingUp(sqrtPriceInput, sqrtPriceInput, 1 << 192)
            + FullMath.mulDivRoundingUp(sqrtPriceInput, sqrtPriceInput, 1 << 227)
            + FixedPointMathLib.divUp(params.liquidity, 1 << 96) + 1;
        uint256 toLimit =
            SqrtPriceMath.getAmount1Delta(params.sqrtPriceBound, params.sqrtPriceOld, params.liquidity, false);
        bool pastTheBound = amountOut + shortfall + 1 >= toLimit;
        uint160 sqrtPriceNext;
        uint256 amountInNext;
        if (!pastTheBound) {
            (sqrtPriceNext, amountInNext) = buy(params, amountOut + shortfall + 1);
        }
        assertTrue(pastTheBound || sqrtPriceNext < sqrtPriceSolve || amountInNext > params.balanceIn);
    }

    function testFuzz_Success_getAmountOut_ZeroForOne_NoToken0_TheFeeKeepsThePriceShortOfTheBound(DepositParams memory params)
        public
        view
    {
        // Given: A token0 deposit into a pool with fee, liquidity to 2^96, spot 2^64 up.
        params.sqrtPriceOld =
            uint160(bound(params.sqrtPriceOld, Constants.MIN_RANGE_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 2));
        params.liquidity = uint128(
            bound(params.liquidity, 3 * FixedPointMathLib.divUp(params.sqrtPriceOld, 1 << 156), type(uint96).max)
        );
        givenValidDepositParams(params, true);

        // And: A position holding only token1, and a bound the largest deposit can reach.
        params.positionLiquidity = 0;
        params.positionAmount0 = 0;
        params.roundingMargin = 0;
        params.fee = uint24(bound(params.fee, 1, Constants.MAX_POOL_FEE));
        (uint256 minBalanceIn, uint256 maxBalanceIn) = getBalanceInBounds(params);
        params.sqrtPriceBound = uint160(
            bound(
                params.sqrtPriceBound,
                FixedPointMathLib.max(
                    getSegmentEnd(params),
                    SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
                        params.sqrtPriceOld,
                        params.liquidity,
                        FullMath.mulDiv(maxBalanceIn, 1e6 - params.fee, 1e6),
                        true
                    )
                ),
                params.sqrtPriceOld - 1
            )
        );

        // And: A deposit paying the move to the bound before the fee, not with it.
        uint256 toBound =
            SqrtPriceMath.getAmount0Delta(params.sqrtPriceBound, params.sqrtPriceOld, params.liquidity, true);
        minBalanceIn = FixedPointMathLib.max(minBalanceIn, toBound);
        maxBalanceIn =
            FixedPointMathLib.min(maxBalanceIn, FullMath.mulDivRoundingUp(toBound, 1e6, 1e6 - params.fee) - 1);
        params.balanceIn = bound(params.balanceIn, minBalanceIn, maxBalanceIn);

        // When: Calling getAmountOut() for a zeroForOne swap.
        uint256 amountOut = getAmountOut(params);

        // Then: It sells the deposit, which stops short of sqrtPriceBound.
        (,, uint256 expected,) = SwapMath.computeSwapStep(
            params.sqrtPriceOld, params.sqrtPriceBound, params.liquidity, -int256(params.balanceIn), params.fee
        );
        assertEq(amountOut, expected);
    }

    function testFuzz_Success_getAmountOut_ZeroForOne_NoToken0_ExactlyTheCostToTheBound(DepositParams memory params)
        public
        view
    {
        // Given: A token0 deposit into a pool with fee, liquidity to 2^96, spot 2^64 up.
        params.sqrtPriceOld =
            uint160(bound(params.sqrtPriceOld, Constants.MIN_RANGE_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 2));
        params.liquidity = uint128(
            bound(params.liquidity, 3 * FixedPointMathLib.divUp(params.sqrtPriceOld, 1 << 156), type(uint96).max)
        );
        givenValidDepositParams(params, true);

        // And: A position holding only token1, and a bound the largest deposit can reach.
        params.positionLiquidity = 0;
        params.positionAmount0 = 0;
        params.roundingMargin = 0;
        params.fee = uint24(bound(params.fee, 1, Constants.MAX_POOL_FEE));
        (, uint256 maxBalanceIn) = getBalanceInBounds(params);
        params.sqrtPriceBound = uint160(
            bound(
                params.sqrtPriceBound,
                FixedPointMathLib.max(
                    getSegmentEnd(params),
                    SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
                        params.sqrtPriceOld,
                        params.liquidity,
                        FullMath.mulDiv(maxBalanceIn, 1e6 - params.fee, 1e6),
                        true
                    )
                ),
                params.sqrtPriceOld - 1
            )
        );

        // And: A deposit of exactly the move to sqrtPriceBound with the fee.
        params.balanceIn = FullMath.mulDivRoundingUp(
            SqrtPriceMath.getAmount0Delta(params.sqrtPriceBound, params.sqrtPriceOld, params.liquidity, true),
            1e6,
            1e6 - params.fee
        );

        // When: Calling getAmountOut() for a zeroForOne swap.
        uint256 amountOut = getAmountOut(params);

        // Then: It sells up to sqrtPriceBound.
        assertEq(
            amountOut,
            SqrtPriceMath.getAmount1Delta(params.sqrtPriceBound, params.sqrtPriceOld, params.liquidity, false)
        );
    }

    function testFuzz_Success_getAmountOut_OneForZero_NoToken0(DepositParams memory params) public view {
        // Given: A deposit of token1 and a position on its segment.
        givenValidDepositParams(params, false);

        // And: The position holds no token0, and some token1.
        params.positionAmount0 = 0;
        params.positionAmount1 = bound(params.positionAmount1, 1, type(uint128).max);

        // When: Calling getAmountOut() for a oneForZero swap.
        uint256 amountOut = getAmountOut(params);

        // Then: amountOut is zero.
        assertEq(amountOut, 0);
    }

    function testFuzz_Success_getAmountOut_OneForZero_NoToken1_SellsAll(DepositParams memory params) public view {
        // Given: A token1 deposit 2^97 below the top, and a token0 position on the range.
        params.sqrtPriceOld = uint160(
            bound(params.sqrtPriceOld, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE - 2 * FixedPoint96.Q96)
        );
        givenValidDepositParams(params, false);
        params.positionLiquidity = 0;
        params.positionAmount1 = 0;
        params.roundingMargin = 0;
        params.sqrtPriceBound = TickMath.MAX_SQRT_PRICE - 1;

        // And: A deposit short of the move to the bound, moving spot by 2^16 at most.
        {
            (uint256 minBalanceIn, uint256 maxBalanceIn) = getBalanceInBounds(params);
            maxBalanceIn = FixedPointMathLib.max(
                minBalanceIn,
                FixedPointMathLib.min(maxBalanceIn, FullMath.mulDiv(params.liquidity, params.sqrtPriceOld, 1 << 80))
            );
            uint256 toBound =
                SqrtPriceMath.getAmount1Delta(params.sqrtPriceOld, params.sqrtPriceBound, params.liquidity, true);
            params.balanceIn = bound(
                params.balanceIn,
                minBalanceIn,
                FixedPointMathLib.min(maxBalanceIn, FullMath.mulDivRoundingUp(toBound, 1e6, 1e6 - params.fee) - 1)
            );
        }
        (uint160 sqrtPriceFull,, uint256 amountOutFull,) = SwapMath.computeSwapStep(
            params.sqrtPriceOld, params.sqrtPriceBound, params.liquidity, -int256(params.balanceIn), params.fee
        );

        // When: Calling getAmountOut() for a oneForZero swap.
        uint256 amountOut = getAmountOut(params);

        // Then: It sells the deposit, to the full sale's price or one short of it.
        assertLe(amountOut, amountOutFull);
        assertGe(
            amountOut,
            SqrtPriceMath.getAmount0Delta(
                params.sqrtPriceOld,
                uint160(FixedPointMathLib.max(sqrtPriceFull - 1, params.sqrtPriceOld)),
                params.liquidity,
                false
            )
        );
    }

    function testFuzz_Success_getAmountOut_OneForZero_NoToken1_LimitReached(DepositParams memory params) public view {
        // Given: A token1 deposit and a position holding only token0, on the full range.
        givenValidDepositParams(params, false);
        params.positionLiquidity = 0;
        params.positionAmount1 = 0;
        params.roundingMargin = 0;

        // And: A bound the largest deposit can reach, and a deposit that pays for it.
        (uint256 minBalanceIn, uint256 maxBalanceIn) = getBalanceInBounds(params);
        params.sqrtPriceBound = uint160(
            bound(
                params.sqrtPriceBound,
                params.sqrtPriceOld,
                FixedPointMathLib.min(
                    getSegmentEnd(params),
                    params.sqrtPriceOld
                        + FullMath.mulDiv(maxBalanceIn, 1e6 - params.fee, 1e6).fullMulDiv(1 << 96, params.liquidity)
                )
            )
        );
        minBalanceIn = FixedPointMathLib.max(
            minBalanceIn,
            FullMath.mulDivRoundingUp(
                SqrtPriceMath.getAmount1Delta(params.sqrtPriceOld, params.sqrtPriceBound, params.liquidity, true),
                1e6,
                1e6 - params.fee
            )
        );
        params.balanceIn = bound(params.balanceIn, minBalanceIn, maxBalanceIn);

        // When: Calling getAmountOut() for a oneForZero swap.
        uint256 amountOut = getAmountOut(params);

        // Then: It sells up to sqrtPriceBound.
        assertEq(
            amountOut,
            SqrtPriceMath.getAmount0Delta(params.sqrtPriceOld, params.sqrtPriceBound, params.liquidity, false)
        );

        // And: The swap costs at most the deposit.
        (, uint256 amountIn) = buy(params, amountOut);
        assertLe(amountIn, params.balanceIn);
    }

    function testFuzz_Success_getAmountOut_OneForZero_WithinSegmentAndDeposit(DepositParams memory params) public view {
        // Given: A deposit of token1 and a position on its segment.
        givenValidDepositParams(params, false);

        // When: Calling getAmountOut() for a oneForZero swap.
        uint256 amountOut = getAmountOut(params);

        // Then: The pool price after the swap is between sqrtPriceOld and sqrtPriceBound.
        (uint160 sqrtPriceNew, uint256 amountIn) = buy(params, amountOut);
        assertGe(sqrtPriceNew, params.sqrtPriceOld);
        assertLe(sqrtPriceNew, params.sqrtPriceBound);

        // And: The swap costs at most the deposit.
        assertLe(amountIn, params.balanceIn);
    }

    function testFuzz_Success_getAmountOut_OneForZero_DustDemandOfToken1(DepositParams memory params) public view {
        // Given: A deposit of token1 and a position on its segment.
        givenValidDepositParams(params, false);

        // And: The position holds no token1 and needs less token0 than the swap leaves.
        (uint256 minBalanceIn, uint256 maxBalanceIn) = getBalanceInBounds(params);
        maxBalanceIn =
            FixedPointMathLib.min(maxBalanceIn, FullMath.mulDiv(type(uint128).max, params.sqrtPriceOld, 1 << 96) - 1);
        params.balanceIn = bound(params.balanceIn, minBalanceIn, maxBalanceIn);
        params.positionAmount1 = 0;
        params.positionAmount0 = bound(
            params.positionAmount0,
            FullMath.mulDivRoundingUp(params.balanceIn + 1, 1 << 96, params.sqrtPriceOld),
            type(uint128).max
        );
        params.positionLiquidity = bound(
            params.positionLiquidity,
            1,
            FixedPointMathLib.min(
                params.liquidity,
                FullMath.mulDiv(params.positionAmount0, params.sqrtPriceOld, 1 << 96) / (params.balanceIn + 1)
            )
        );
        params.sqrtPriceBound = uint160(bound(params.sqrtPriceBound, params.sqrtPriceOld, getSegmentEnd(params)));

        // When: Calling getAmountOut() for a oneForZero swap.
        uint256 amountOut = getAmountOut(params);

        // Then: The swap costs at most the deposit.
        (, uint256 amountIn) = buy(params, amountOut);
        assertLe(amountIn, params.balanceIn);
    }

    function testFuzz_Success_getAmountOut_OneForZero_DustDemandOfToken1_NoLiquidity(DepositParams memory params)
        public
        view
    {
        // Given: A deposit of token1 and a position on its segment.
        givenValidDepositParams(params, false);

        // And: The position has no liquidity in range, keeping less than the swap leaves.
        (uint256 minBalanceIn, uint256 maxBalanceIn) = getBalanceInBounds(params);
        maxBalanceIn = FixedPointMathLib.min(
            maxBalanceIn,
            FullMath.mulDiv(
                FullMath.mulDiv(type(uint128).max, params.sqrtPriceOld, 1 << 96), params.sqrtPriceOld, 1 << 96
            )
        );
        params.balanceIn = bound(params.balanceIn, minBalanceIn, maxBalanceIn);
        uint256 maxAmountOut = FullMath.mulDivRoundingUp(
            FullMath.mulDivRoundingUp(params.balanceIn, 1 << 96, params.sqrtPriceOld), 1 << 96, params.sqrtPriceOld
        );
        params.positionLiquidity = 0;
        params.positionAmount0 = bound(params.positionAmount0, maxAmountOut, type(uint128).max);
        params.positionAmount1 = bound(params.positionAmount1, 1, params.positionAmount0 / maxAmountOut);
        params.sqrtPriceBound = uint160(bound(params.sqrtPriceBound, params.sqrtPriceOld, getSegmentEnd(params)));

        // When: Calling getAmountOut() for a oneForZero swap.
        uint256 amountOut = getAmountOut(params);

        // Then: The swap costs at most the deposit.
        (, uint256 amountIn) = buy(params, amountOut);
        assertLe(amountIn, params.balanceIn);
    }

    function testFuzz_Success_getAmountOut_OneForZero_LargestUpToItsPrice(DepositParams memory params) public view {
        // Given: A deposit of token1 and a position on its segment.
        givenValidDepositParams(params, false);

        // When: Calling getAmountOut() for a oneForZero swap.
        uint256 amountOut = getAmountOut(params);

        // Then: One wei more passes the bound or the solver's price, or costs too much.
        uint160 sqrtPriceSolve = getSqrtPrice(params);
        uint256 toLimit =
            SqrtPriceMath.getAmount0Delta(params.sqrtPriceOld, params.sqrtPriceBound, params.liquidity, false);
        bool pastTheBound = amountOut + 1 >= toLimit;
        uint160 sqrtPriceNext;
        uint256 amountInNext;
        if (!pastTheBound) {
            (sqrtPriceNext, amountInNext) = buy(params, amountOut + 1);
        }
        assertTrue(pastTheBound || sqrtPriceNext > sqrtPriceSolve || amountInNext > params.balanceIn);
    }

    function testFuzz_Success_getAmountOut_OneForZero_NoToken1_TheFeeKeepsThePriceShortOfTheBound(DepositParams memory params)
        public
        view
    {
        // Given: A token1 deposit into a pool with a fee, at liquidity to 2^96.
        params.sqrtPriceOld =
            uint160(bound(params.sqrtPriceOld, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE - 2));
        params.liquidity = uint128(
            bound(params.liquidity, 3 * FixedPointMathLib.divUp(1 << 36, params.sqrtPriceOld), type(uint96).max)
        );
        givenValidDepositParams(params, false);

        // And: A position holding only token0, and a bound the largest deposit can reach.
        params.positionLiquidity = 0;
        params.positionAmount1 = 0;
        params.roundingMargin = 0;
        params.fee = uint24(bound(params.fee, 1, Constants.MAX_POOL_FEE));
        (uint256 minBalanceIn, uint256 maxBalanceIn) = getBalanceInBounds(params);
        params.sqrtPriceBound = uint160(
            bound(
                params.sqrtPriceBound,
                params.sqrtPriceOld + 1,
                FixedPointMathLib.min(
                    getSegmentEnd(params),
                    params.sqrtPriceOld
                        + FullMath.mulDiv(maxBalanceIn, 1e6 - params.fee, 1e6).fullMulDiv(1 << 96, params.liquidity)
                )
            )
        );

        // And: A deposit paying the move to the bound before the fee, not with it.
        uint256 toBound =
            SqrtPriceMath.getAmount1Delta(params.sqrtPriceOld, params.sqrtPriceBound, params.liquidity, true);
        minBalanceIn = FixedPointMathLib.max(minBalanceIn, toBound);
        maxBalanceIn =
            FixedPointMathLib.min(maxBalanceIn, FullMath.mulDivRoundingUp(toBound, 1e6, 1e6 - params.fee) - 1);
        params.balanceIn = bound(params.balanceIn, minBalanceIn, maxBalanceIn);

        // When: Calling getAmountOut() for a oneForZero swap.
        uint256 amountOut = getAmountOut(params);

        // Then: It sells the deposit, which stops short of sqrtPriceBound.
        (,, uint256 expected,) = SwapMath.computeSwapStep(
            params.sqrtPriceOld, params.sqrtPriceBound, params.liquidity, -int256(params.balanceIn), params.fee
        );
        assertEq(amountOut, expected);
    }

    function testFuzz_Success_getAmountOut_OneForZero_NoToken1_ExactlyTheCostToTheBound(DepositParams memory params)
        public
        view
    {
        // Given: A token1 deposit into a pool with a fee, at liquidity to 2^96.
        params.sqrtPriceOld =
            uint160(bound(params.sqrtPriceOld, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE - 2));
        params.liquidity = uint128(
            bound(params.liquidity, 3 * FixedPointMathLib.divUp(1 << 36, params.sqrtPriceOld), type(uint96).max)
        );
        givenValidDepositParams(params, false);

        // And: A position holding only token0, and a bound the largest deposit can reach.
        params.positionLiquidity = 0;
        params.positionAmount1 = 0;
        params.roundingMargin = 0;
        params.fee = uint24(bound(params.fee, 1, Constants.MAX_POOL_FEE));
        (, uint256 maxBalanceIn) = getBalanceInBounds(params);
        params.sqrtPriceBound = uint160(
            bound(
                params.sqrtPriceBound,
                params.sqrtPriceOld + 1,
                FixedPointMathLib.min(
                    getSegmentEnd(params),
                    params.sqrtPriceOld
                        + FullMath.mulDiv(maxBalanceIn, 1e6 - params.fee, 1e6).fullMulDiv(1 << 96, params.liquidity)
                )
            )
        );

        // And: A deposit of exactly the move to sqrtPriceBound with the fee.
        params.balanceIn = FullMath.mulDivRoundingUp(
            SqrtPriceMath.getAmount1Delta(params.sqrtPriceOld, params.sqrtPriceBound, params.liquidity, true),
            1e6,
            1e6 - params.fee
        );

        // When: Calling getAmountOut() for a oneForZero swap.
        uint256 amountOut = getAmountOut(params);

        // Then: It sells up to sqrtPriceBound.
        assertEq(
            amountOut,
            SqrtPriceMath.getAmount0Delta(params.sqrtPriceOld, params.sqrtPriceBound, params.liquidity, false)
        );
    }
}
