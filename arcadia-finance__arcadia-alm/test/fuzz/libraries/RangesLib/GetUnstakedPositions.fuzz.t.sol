/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../../utils/Constants.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { RangesLib_Fuzz_Test } from "./_RangesLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "getUnstakedPositions" of library "RangesLib".
 */
contract GetUnstakedPositions_RangesLib_Fuzz_Test is RangesLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getUnstakedPositions_NoRangesIsZero(
        PoolState memory poolState,
        uint128 buffer0,
        uint128 buffer1
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A buffer, and no ranges.
        rangesLib.setBuffers(buffer0, buffer1);

        // When: Reading the uncollected fees.
        (uint256 fees0, uint256 fees1,) = rangesLib.getUnstakedPositions(0);

        // Then: There are none, whatever the buffer holds.
        assertEq(fees0, 0);
        assertEq(fees1, 0);
    }

    function testFuzz_Success_getUnstakedPositions_SkipsARangeWithNoUnstakedLiquidity(
        PoolState memory poolState,
        RangeState memory held,
        uint128 buffer0,
        uint128 buffer1
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A buffer, and a range with nothing on its unstaked side.
        rangesLib.setBuffers(buffer0, buffer1);
        givenValidRangeState(held, poolState, false);
        held.liquidity = 0;
        pushRangeOf(held);

        // When: Reading the uncollected fees.
        (uint256 fees0, uint256 fees1,) = rangesLib.getUnstakedPositions(0);

        // Then: The range adds none.
        assertEq(fees0, 0);
        assertEq(fees1, 0);
    }

    function testFuzz_Success_getUnstakedPositions_NetOfTheProtocolShare(
        PoolState memory poolState,
        RangeState memory range,
        uint128 buffer0,
        uint128 buffer1,
        uint256 amountIn,
        uint16 bps,
        bool zeroForOne
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A buffer, and a protocol share of every collection.
        rangesLib.setBuffers(buffer0, buffer1);
        bps = uint16(bound(bps, 0, ConfigLib.MAX_FEE_BPS));

        // And: A range around the price, a share of the room, with fees a spacing ahead.
        givenValidRangeState(range, poolState, true);
        givenRangeRoom(range, poolState, zeroForOne);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));
        pushRangeOf(range);
        (address tokenIn, address tokenOut) =
            zeroForOne ? (address(token0), address(token1)) : (address(token1), address(token0));
        swapInPool(
            pool,
            users.liquidityProvider,
            tokenIn,
            tokenOut,
            feeEarningTrade(pool, range.liquidity, amountIn, zeroForOne)
        );

        // And: What the position earned, from the pool's fee growth inside its ticks.
        (uint256 gross0, uint256 gross1) = positionFees(pool, range.unstakedTokenId);

        // When: Reading the uncollected fees.
        (uint256 fees0, uint256 fees1,) = rangesLib.getUnstakedPositions(bps);

        // Then: They are those fees less the protocol share rounded down, no buffer.
        assertGt(zeroForOne ? gross0 : gross1, 0);
        assertEq(fees0, gross0 - gross0 * bps / 10_000);
        assertEq(fees1, gross1 - gross1 * bps / 10_000);
    }

    function testFuzz_Success_getUnstakedPositions_SumsEveryRange(
        PoolState memory poolState,
        RangeState memory first,
        RangeState memory second,
        uint256 amountIn,
        uint16 bps,
        bool zeroForOne
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A protocol share of every collection.
        bps = uint16(bound(bps, 0, ConfigLib.MAX_FEE_BPS));

        // And: Two ranges around the price, real shares of the room, that earned fees.
        givenValidRangeState(first, poolState, true);
        uint128 free = liquidityCeiling(first.tickLower, first.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        first.liquidity = uint128(bound(first.liquidity, free / 8, free / 4));
        pushRangeOf(first);
        givenValidRangeState(second, poolState, true);
        free = liquidityCeiling(second.tickLower, second.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        second.liquidity = uint128(bound(second.liquidity, free / 8, free / 4));
        pushRangeOf(second);
        (address tokenIn, address tokenOut) =
            zeroForOne ? (address(token0), address(token1)) : (address(token1), address(token0));
        swapInPool(
            pool,
            users.liquidityProvider,
            tokenIn,
            tokenOut,
            feeEarningTrade(pool, first.liquidity, amountIn, zeroForOne)
        );

        // And: What each position earned, from the pool's fee growth inside its ticks.
        (uint256 first0, uint256 first1) = positionFees(pool, first.unstakedTokenId);
        (uint256 second0, uint256 second1) = positionFees(pool, second.unstakedTokenId);

        // When: Reading the uncollected fees.
        (uint256 fees0, uint256 fees1,) = rangesLib.getUnstakedPositions(bps);

        // Then: They are both ranges' fees summed, less the protocol share rounded down.
        assertEq(fees0, first0 + second0 - (first0 + second0) * bps / 10_000);
        assertEq(fees1, first1 + second1 - (first1 + second1) * bps / 10_000);
    }
}
