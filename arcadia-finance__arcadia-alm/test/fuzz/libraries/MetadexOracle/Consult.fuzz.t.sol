/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { MetadexOracle_Fuzz_Test } from "./_MetadexOracle.fuzz.t.sol";
import { stdError } from "@forge-std/StdError.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "consult" of library "MetadexOracle".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract Consult_MetadexOracle_Fuzz_Test is MetadexOracle_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_consult_ZeroWindow(int56 start, int56 delta) public {
        // Given: Two readings an int56 difference apart, over no time.
        start = int56(bound(start, type(int56).min / 2, type(int56).max / 2));
        delta = int56(bound(delta, type(int56).min / 2, type(int56).max / 2));
        mockObserve(start, start + delta);

        // When: Calling consult().
        // Then: It reverts on the division.
        vm.expectRevert(stdError.divisionError);
        oracleLibrary.consult(address(pool), 0);
    }

    function testFuzz_Success_consult_TickOutsideTheCurve(int24 tick, uint32 secondsAgo) public {
        // Given: A window, and readings whose mean tick is an int24 past the curve.
        secondsAgo = uint32(bound(secondsAgo, 1, type(uint32).max));
        tick = tick >= 0
            ? int24(bound(tick, TickMath.MAX_TICK + 1, type(int24).max))
            : int24(bound(tick, type(int24).min, TickMath.MIN_TICK - 1));
        mockObserve(0, int56(tick) * int56(uint56(secondsAgo)));

        // When: Calling consult().
        int24 arithmeticMeanTick = oracleLibrary.consult(address(pool), secondsAgo);

        // Then: It is that tick, which has no price on the curve.
        assertEq(arithmeticMeanTick, tick);
    }

    function testFuzz_Success_consult_NonNegativeMean(int56 start, int56 delta, uint32 secondsAgo) public {
        // Given: A window, and readings that grew by under the highest tick per second.
        secondsAgo = uint32(bound(secondsAgo, 1, type(uint32).max));
        int56 span = int56(uint56(secondsAgo));
        delta = int56(bound(delta, 0, int256(TickMath.MAX_TICK) * span - 1));
        start = int56(bound(start, type(int56).min, type(int56).max - delta));
        mockObserve(start, start + delta);

        // When: Calling consult().
        int24 arithmeticMeanTick = oracleLibrary.consult(address(pool), secondsAgo);

        // Then: It is the mean tick, truncated down.
        assertEq(arithmeticMeanTick, delta / span);
    }

    function testFuzz_Success_consult_NegativeMeanOnAWholeTick(int56 start, int24 tick, uint32 secondsAgo) public {
        // Given: A window, and readings that fell by whole ticks per second.
        secondsAgo = uint32(bound(secondsAgo, 1, type(uint32).max));
        int56 span = int56(uint56(secondsAgo));
        tick = int24(bound(tick, TickMath.MIN_TICK, -1));
        int56 delta = int56(tick) * span;
        start = int56(bound(start, type(int56).min - delta, type(int56).max));
        mockObserve(start, start + delta);

        // When: Calling consult().
        int24 arithmeticMeanTick = oracleLibrary.consult(address(pool), secondsAgo);

        // Then: It is that tick.
        assertEq(arithmeticMeanTick, tick);
    }

    function testFuzz_Success_consult_NegativeMeanRoundsDown(
        int56 start,
        int24 tick,
        uint32 remainder,
        uint32 secondsAgo
    ) public {
        // Given: A window, and readings that fell by a fraction past a whole tick.
        secondsAgo = uint32(bound(secondsAgo, 2, type(uint32).max));
        int56 span = int56(uint56(secondsAgo));
        tick = int24(bound(tick, TickMath.MIN_TICK + 2, 0));
        int56 delta = int56(tick) * span - int56(uint56(bound(remainder, 1, secondsAgo - 1)));
        start = int56(bound(start, type(int56).min - delta, type(int56).max));
        mockObserve(start, start + delta);

        // When: Calling consult().
        int24 arithmeticMeanTick = oracleLibrary.consult(address(pool), secondsAgo);

        // Then: It is the floor of the mean tick, one below the truncated one.
        assertEq(arithmeticMeanTick, delta / span - 1);
    }

    function testFuzz_Success_consult_NoTrade(PoolState memory poolState, uint32 elapsed) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Time passed on a pool that has seen no trade, the clock within a uint32.
        vm.warp(
            vm.getBlockTimestamp() + bound(elapsed, Constants.TWAP_WINDOW, type(uint32).max - vm.getBlockTimestamp())
        );

        // When: Calling consult().
        int24 arithmeticMeanTick = oracleLibrary.consult(address(pool), Constants.TWAP_WINDOW);

        // Then: It is the tick the pool was initialized in.
        assertEq(arithmeticMeanTick, poolState.tickCurrent);
    }

    function testFuzz_Success_consult_LagsSpot(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range around spot.
        int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
        int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
        if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
        range.tickLower = int24(bound(range.tickLower, -band + 1, compressed)) * poolState.tickSpacing;
        range.tickUpper = int24(bound(range.tickUpper, compressed + 1, band - 1)) * poolState.tickSpacing;
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A trade a window later that moved the price a tick spacing down.
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);
        parkAtTick(pool, users.unprivilegedAddress, poolState.tickCurrent - poolState.tickSpacing);

        // When: Calling consult().
        int24 arithmeticMeanTick = oracleLibrary.consult(address(pool), Constants.TWAP_WINDOW);

        // Then: It is the tick the pool sat at over the window.
        assertEq(arithmeticMeanTick, poolState.tickCurrent);

        // And: It sits above the depressed spot.
        assertGt(TickMath.getSqrtPriceAtTick(arithmeticMeanTick), sqrtPriceX96(pool));
    }
}
