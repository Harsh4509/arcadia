/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { IALMCore } from "../../../../src/interfaces/IALMCore.sol";
import { LiquidityAmounts } from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SnapshotLib_Fuzz_Test } from "./_SnapshotLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getAmountsAt" of library "SnapshotLib".
 */
contract GetAmountsAt_SnapshotLib_Fuzz_Test is SnapshotLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getAmountsAt_NoRanges(
        uint256 buffer0,
        uint256 buffer1,
        uint256 fees0,
        uint256 fees1,
        uint160 sqrtPriceX96
    ) public view {
        // Given: A snapshot without ranges, with fuzzed buffers and uncollected fees.
        buffer0 = bound(buffer0, 0, type(uint128).max);
        buffer1 = bound(buffer1, 0, type(uint128).max);
        fees0 = bound(fees0, 0, type(uint128).max);
        fees1 = bound(fees1, 0, type(uint128).max);
        Snapshot memory snapshot = Snapshot({
            buffer0: buffer0,
            buffer1: buffer1,
            fees0: fees0,
            fees1: fees1,
            supply: 1,
            sqrtPriceX96: 0,
            tick: 0,
            fee: 0,
            core: IALMCore(address(0)),
            ranges: new PricedRange[](0)
        });

        // When: Reading the amounts at any price.
        (uint256 amount0, uint256 amount1) = snapshotLib.getAmountsAt(
            snapshot, uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1))
        );

        // Then: They are the buffers plus the uncollected fees.
        assertEq(amount0, buffer0 + fees0);
        assertEq(amount1, buffer1 + fees1);
    }

    function testFuzz_Success_getAmountsAt_SkipsARangeHoldingNoLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint160 sqrtPriceX96
    ) public view {
        // Given: A snapshot with one range holding no liquidity, and no buffers or fees.
        tickLower = int24(bound(tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        tickUpper = int24(bound(tickUpper, tickLower + 1, TickMath.MAX_TICK));
        PricedRange[] memory ranges = new PricedRange[](1);
        ranges[0] = PricedRange({
            liquidity: 0,
            unstakedLiquidity: 0,
            sqrtPriceLowerX96: TickMath.getSqrtPriceAtTick(tickLower),
            sqrtPriceUpperX96: TickMath.getSqrtPriceAtTick(tickUpper)
        });
        Snapshot memory snapshot = Snapshot({
            buffer0: 0,
            buffer1: 0,
            fees0: 0,
            fees1: 0,
            supply: 1,
            sqrtPriceX96: 0,
            tick: 0,
            fee: 0,
            core: IALMCore(address(0)),
            ranges: ranges
        });

        // When: Reading the amounts at any price.
        (uint256 amount0, uint256 amount1) = snapshotLib.getAmountsAt(
            snapshot, uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1))
        );

        // Then: The range adds nothing.
        assertEq(amount0, 0);
        assertEq(amount1, 0);
    }

    function testFuzz_Success_getAmountsAt_AddsEveryRangeAndTheIdleTokens(
        int24[2] memory ticksLower,
        int24[2] memory ticksUpper,
        uint128[2] memory liquidities,
        uint256[4] memory idle,
        uint160 sqrtPriceX96
    ) public view {
        // Given: Two ranges holding liquidity, and a price anywhere the pool can reach.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        PricedRange[] memory ranges = new PricedRange[](2);
        uint256 expected0;
        uint256 expected1;
        for (uint256 i; i < 2; ++i) {
            ticksLower[i] = int24(bound(ticksLower[i], TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
            ticksUpper[i] = int24(bound(ticksUpper[i], ticksLower[i] + 1, TickMath.MAX_TICK));
            liquidities[i] = uint128(bound(liquidities[i], 1, type(uint96).max));
            ranges[i] = PricedRange({
                liquidity: liquidities[i],
                unstakedLiquidity: liquidities[i],
                sqrtPriceLowerX96: TickMath.getSqrtPriceAtTick(ticksLower[i]),
                sqrtPriceUpperX96: TickMath.getSqrtPriceAtTick(ticksUpper[i])
            });
            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96, ranges[i].sqrtPriceLowerX96, ranges[i].sqrtPriceUpperX96, liquidities[i]
            );
            expected0 += amount0;
            expected1 += amount1;
        }

        // And: Fuzzed buffers and uncollected fees.
        for (uint256 i; i < 4; ++i) {
            idle[i] = bound(idle[i], 0, type(uint128).max);
        }
        Snapshot memory snapshot = Snapshot({
            buffer0: idle[0],
            buffer1: idle[1],
            fees0: idle[2],
            fees1: idle[3],
            supply: 1,
            sqrtPriceX96: 0,
            tick: 0,
            fee: 0,
            core: IALMCore(address(0)),
            ranges: ranges
        });

        // When: Reading the amounts at the price.
        (uint256 total0, uint256 total1) = snapshotLib.getAmountsAt(snapshot, sqrtPriceX96);

        // Then: They are each range's amounts there, rounded down, plus buffers and fees.
        assertEq(total0, expected0 + idle[0] + idle[2]);
        assertEq(total1, expected1 + idle[1] + idle[3]);
    }
}
