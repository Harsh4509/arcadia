/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { LiquidityAmounts } from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import { PlanCache } from "../../../../src/core/types/PlanCache.sol";
import { PlanCacheLib_Fuzz_Test } from "./_PlanCacheLib.fuzz.t.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "applyLiquidityDelta" of library "PlanCacheLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract ApplyLiquidityDelta_PlanCacheLib_Fuzz_Test is PlanCacheLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_applyLiquidityDelta_PrincipalPastInt128(
        uint160 trustedSqrtPriceX96,
        uint256 supply,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public {
        // Given: A wide range below a price of one.
        tickLower = int24(bound(tickLower, TickMath.MIN_TICK, -Constants.WIDE_RANGE_TICKS));
        tickUpper = int24(bound(tickUpper, tickLower + Constants.WIDE_RANGE_TICKS, TickMath.MAX_TICK));

        // And: A running execution at a trusted price at or below the range.
        trustedSqrtPriceX96 =
            uint160(bound(trustedSqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.getSqrtPriceAtTick(tickLower)));
        PlanCache memory cache = planCacheLib.start(trustedSqrtPriceX96, trustedSqrtPriceX96, supply, 0, 0);

        // And: Liquidity whose token0 principal passes an int128.
        liquidity = uint128(bound(liquidity, Constants.MAX_FUZZED_AMOUNT + 1, type(uint128).max));

        // When: Applying the liquidity added.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        cache = planCacheLib.applyLiquidityDelta(cache, tickLower, tickUpper, int256(uint256(liquidity)));
    }

    function testFuzz_Success_applyLiquidityDelta_Added(
        uint160 trustedSqrtPriceX96,
        uint256 supply,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public view {
        // Given: A running execution at a trusted price in the band, and a range in it.
        trustedSqrtPriceX96 = uint160(
            bound(
                trustedSqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );
        tickLower = int24(bound(tickLower, -Constants.BOUND_TICK, Constants.BOUND_TICK - 1));
        tickUpper = int24(bound(tickUpper, tickLower + 1, Constants.BOUND_TICK));
        PlanCache memory cache = planCacheLib.start(trustedSqrtPriceX96, trustedSqrtPriceX96, supply, 0, 0);

        // And: Liquidity whose principal fits an int128 anywhere in the band.
        liquidity = uint128(
            bound(
                liquidity,
                0,
                Constants.MAX_FUZZED_AMOUNT / (TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK) / 2 ** 96 + 1)
            )
        );

        // When: Applying the liquidity added.
        cache = planCacheLib.applyLiquidityDelta(cache, tickLower, tickUpper, int256(uint256(liquidity)));

        // Then: The execution holds the principal of the liquidity at the trusted price.
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            trustedSqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );
        assertEq(cache.amount0, int256(amount0));
        assertEq(cache.amount1, int256(amount1));
    }

    function testFuzz_Success_applyLiquidityDelta_Removed(
        uint160 trustedSqrtPriceX96,
        uint256 supply,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public view {
        // Given: A running execution at a trusted price in the band, and a range in it.
        trustedSqrtPriceX96 = uint160(
            bound(
                trustedSqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );
        tickLower = int24(bound(tickLower, -Constants.BOUND_TICK, Constants.BOUND_TICK - 1));
        tickUpper = int24(bound(tickUpper, tickLower + 1, Constants.BOUND_TICK));
        PlanCache memory cache = planCacheLib.start(trustedSqrtPriceX96, trustedSqrtPriceX96, supply, 0, 0);

        // And: Liquidity whose principal fits an int128 anywhere in the band.
        liquidity = uint128(
            bound(
                liquidity,
                0,
                Constants.MAX_FUZZED_AMOUNT / (TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK) / 2 ** 96 + 1)
            )
        );

        // When: Applying the liquidity removed.
        cache = planCacheLib.applyLiquidityDelta(cache, tickLower, tickUpper, -int256(uint256(liquidity)));

        // Then: The execution holds the principal at the trusted price, taken out.
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            trustedSqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );
        assertEq(cache.amount0, -int256(amount0));
        assertEq(cache.amount1, -int256(amount1));
    }

    function testFuzz_Success_applyLiquidityDelta_AddsToWhatTheExecutionAlreadyMoved(
        uint160 trustedSqrtPriceX96,
        uint256 supply,
        int128 earlier0,
        int128 earlier1,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        bool removed
    ) public view {
        // Given: A running execution at a trusted price in the band, and a range in it.
        trustedSqrtPriceX96 = uint160(
            bound(
                trustedSqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );
        tickLower = int24(bound(tickLower, -Constants.BOUND_TICK, Constants.BOUND_TICK - 1));
        tickUpper = int24(bound(tickUpper, tickLower + 1, Constants.BOUND_TICK));
        PlanCache memory cache = planCacheLib.start(trustedSqrtPriceX96, trustedSqrtPriceX96, supply, 0, 0);

        // And: The execution already holds both tokens, or owes them.
        earlier0 = int128(bound(earlier0, -type(int128).max / 2, type(int128).max / 2));
        earlier1 = int128(bound(earlier1, -type(int128).max / 2, type(int128).max / 2));
        (cache.amount0, cache.amount1) = (earlier0, earlier1);

        // And: Liquidity whose principal fits half an int128 anywhere in the band.
        liquidity = uint128(
            bound(
                liquidity,
                0,
                Constants.MAX_FUZZED_AMOUNT / (TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK) / 2 ** 96 + 1) / 2
            )
        );

        // When: Applying the liquidity added or removed.
        cache = planCacheLib.applyLiquidityDelta(
            cache, tickLower, tickUpper, removed ? -int256(uint256(liquidity)) : int256(uint256(liquidity))
        );

        // Then: The execution holds the earlier amounts plus the principal, or minus it.
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            trustedSqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );
        assertEq(cache.amount0, earlier0 + (removed ? -int256(amount0) : int256(amount0)));
        assertEq(cache.amount1, earlier1 + (removed ? -int256(amount1) : int256(amount1)));
    }
}
