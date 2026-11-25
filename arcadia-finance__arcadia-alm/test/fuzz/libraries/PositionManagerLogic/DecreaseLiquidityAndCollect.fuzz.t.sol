/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { LiquidityAmounts } from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import { PositionManagerLogic_Fuzz_Test } from "./_PositionManagerLogic.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "decreaseLiquidityAndCollect" of library "PositionManagerLogic".
 */
// forge-lint: disable-next-item(unused-return)
contract DecreaseLiquidityAndCollect_PositionManagerLogic_Fuzz_Test is PositionManagerLogic_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_decreaseLiquidityAndCollect_ReleasesThePrincipal(
        PoolState memory poolState,
        RangeState memory range,
        uint128 liquidity
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A caller of the library on the pool's tokens and tick spacing.
        deployPositionManagerLogic();

        // And: A position the caller owns without fees, and a part of its liquidity.
        givenValidRangeState(range, poolState, false);
        (uint256 tokenId,) = mintPositionFor(
            pool,
            users.liquidityProvider,
            address(positionManagerLogic),
            range.tickLower,
            range.tickUpper,
            range.liquidity
        );
        uint128 liquidityBefore = positionLiquidity(tokenId);
        liquidity = uint128(bound(liquidity, 1, liquidityBefore));

        // When: Removing that liquidity and collecting it.
        (TokenDelta principal, TokenDelta fees) = positionManagerLogic.decreaseLiquidityAndCollect(tokenId, liquidity);

        // Then: The position shrank by it.
        assertEq(positionLiquidity(tokenId), liquidityBefore - liquidity);

        // And: Its principal at the current price, rounded down, is paid with no fees.
        (uint256 expected0, uint256 expected1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96(pool),
            TickMath.getSqrtPriceAtTick(range.tickLower),
            TickMath.getSqrtPriceAtTick(range.tickUpper),
            liquidity
        );
        assertEq(int256(principal.amount0()), int256(expected0));
        assertEq(int256(principal.amount1()), int256(expected1));
        assertEq(int256(fees.amount0()), 0);
        assertEq(int256(fees.amount1()), 0);
        assertEq(token0.balanceOf(address(positionManagerLogic)), expected0);
        assertEq(token1.balanceOf(address(positionManagerLogic)), expected1);
    }

    function testFuzz_Success_decreaseLiquidityAndCollect_ReturnsTheGrossFees(
        PoolState memory poolState,
        RangeState memory range,
        uint128 liquidity,
        uint256 amountIn
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A caller of the library on the pool's tokens and tick spacing.
        deployPositionManagerLogic();

        // And: A range around the price.
        givenValidRangeState(range, poolState, false);
        int24 tickSpacing = poolState.tickSpacing;
        int24 band = bandTick(tickSpacing) / tickSpacing;
        int24 spot = poolState.tickCurrent / tickSpacing;
        if (poolState.tickCurrent < 0 && poolState.tickCurrent % tickSpacing != 0) --spot;
        range.tickLower = int24(bound(range.tickLower / tickSpacing, -band + 1, spot - 1)) * tickSpacing;
        range.tickUpper = int24(bound(range.tickUpper / tickSpacing, spot + 1, band - 1)) * tickSpacing;

        // And: A swap down to the lower tick of an input whose fee the position earns.
        uint160 sqrtPriceLower = TickMath.getSqrtPriceAtTick(range.tickLower);
        uint256 least = (4 * MAX_PIPS * MAX_PIPS).divUp((MAX_PIPS - pool.unstakedFee()) * pool.fee());
        amountIn = bound(amountIn, least, Constants.MAX_FUZZED_AMOUNT);

        // And: A position of at least the other providers' depth holding that input.
        least = FixedPointMathLib.max(
            FixedPointMathLib.max(
                poolState.liquidityPool,
                LiquidityAmounts.getLiquidityForAmount0(sqrtPriceLower, sqrtPriceX96(pool), least) + 1
            ),
            Constants.MIN_FUZZED_LIQUIDITY
        );
        range.liquidity = uint128(
            bound(
                range.liquidity,
                least,
                FixedPointMathLib.max(
                    liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4, least
                )
            )
        );
        (uint256 tokenId,) = mintPositionFor(
            pool,
            users.liquidityProvider,
            address(positionManagerLogic),
            range.tickLower,
            range.tickUpper,
            range.liquidity
        );

        // And: The swap.
        token0.mint(users.liquidityProvider, amountIn);
        swapAsActor(pool, users.liquidityProvider, address(token0), address(token1), amountIn, sqrtPriceLower);

        // And: A part of the position's liquidity.
        liquidity = uint128(bound(liquidity, 1, positionLiquidity(tokenId)));

        // And: The position's fees from the pool's fee growth.
        (uint256 fees0, uint256 fees1) = positionFees(pool, tokenId);

        // When: Removing that liquidity and collecting it.
        (TokenDelta principal, TokenDelta fees) = positionManagerLogic.decreaseLiquidityAndCollect(tokenId, liquidity);

        // Then: The fees are returned apart from the principal.
        assertGt(fees0, 0);
        assertEq(int256(fees.amount0()), int256(fees0));
        assertEq(int256(fees.amount1()), int256(fees1));

        // And: The caller received both.
        assertEq(int256(principal.amount0() + fees.amount0()), int256(token0.balanceOf(address(positionManagerLogic))));
        assertEq(int256(principal.amount1() + fees.amount1()), int256(token1.balanceOf(address(positionManagerLogic))));
    }
}
