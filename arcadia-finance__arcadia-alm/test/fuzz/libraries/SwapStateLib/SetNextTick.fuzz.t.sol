/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { PoolMock } from "../../../utils/mocks/PoolMock.sol";
import { StepComputations, SwapState } from "../../../../src/vaults/types/SwapState.sol";
import { SwapStateLib_Fuzz_Test } from "./_SwapStateLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "setNextTick" of library "SwapStateLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract SetNextTick_SwapStateLib_Fuzz_Test is SwapStateLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_setNextTick_TargetAtMostTheLimit(int24 tick, uint160 sqrtPriceLimitX96, bool zeroForOne)
        public
    {
        // Given: A pool without initialized ticks, a tick in it and a price limit.
        tick = int24(bound(tick, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        sqrtPriceLimitX96 = uint160(bound(sqrtPriceLimitX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE));
        address pool = address(new PoolMock(1, 1));
        SwapState memory state;
        (state.tick, state.tickSpacing) = (tick, 1);

        // When: Calling setNextTick().
        StepComputations memory step = swapStateLib.setNextTick(state, pool, zeroForOne, sqrtPriceLimitX96);

        // Then: The step's next tick is a bitmap word end, its price at that tick.
        assertFalse(step.initialized);
        assertEq(step.sqrtPriceNextX96, TickMath.getSqrtPriceAtTick(step.tickNext));

        // And: The step swaps to its next price, at most the limit.
        bool pastTheLimit =
            zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96;
        assertEq(step.sqrtPriceTargetX96, pastTheLimit ? sqrtPriceLimitX96 : step.sqrtPriceNextX96);
    }

    function testFuzz_Success_setNextTick_NextInitializedTick(
        int16 wordPosition,
        uint8 bitTick,
        uint8 bitInitialized,
        bool zeroForOne
    ) public {
        // Given: A tick and an initialized tick in its word, at or below it for token0.
        wordPosition = int16(
            bound(
                wordPosition,
                TickMath.MIN_TICK / Constants.BITMAP_WORD_TICKS,
                (TickMath.MAX_TICK - Constants.BITMAP_WORD_TICKS + 1) / Constants.BITMAP_WORD_TICKS
            )
        );
        if (zeroForOne) {
            bitInitialized = uint8(bound(bitInitialized, 0, bitTick));
        } else {
            bitTick = uint8(bound(bitTick, 0, type(uint8).max - 1));
            bitInitialized = uint8(bound(bitInitialized, uint256(bitTick) + 1, type(uint8).max));
        }
        SwapState memory state;
        (state.tick, state.tickSpacing) =
        (int24(wordPosition) * Constants.BITMAP_WORD_TICKS + int24(uint24(bitTick)), 1);
        int24 tickInitialized = int24(wordPosition) * Constants.BITMAP_WORD_TICKS + int24(uint24(bitInitialized));
        address pool = address(new PoolMock(1, 1));
        PoolMock(pool).addLiquidityNet(tickInitialized, 1);

        // When: Calling setNextTick() without a price limit.
        StepComputations memory step = swapStateLib.setNextTick(
            state, pool, zeroForOne, zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        );

        // Then: The step's next tick is the initialized tick, and it swaps to its price.
        assertTrue(step.initialized);
        assertEq(step.tickNext, tickInitialized);
        assertEq(step.sqrtPriceTargetX96, step.sqrtPriceNextX96);
    }

    function testFuzz_Success_setNextTick_ZeroForOne_IgnoresAnInitializedTickAboveInItsWord(
        int16 wordPosition,
        uint8 bitTick,
        uint8 bitInitialized
    ) public {
        // Given: A tick, and the only initialized tick of its word above it.
        wordPosition = int16(
            bound(
                wordPosition,
                TickMath.MIN_TICK / Constants.BITMAP_WORD_TICKS,
                (TickMath.MAX_TICK - Constants.BITMAP_WORD_TICKS + 1) / Constants.BITMAP_WORD_TICKS
            )
        );
        bitTick = uint8(bound(bitTick, 0, type(uint8).max - 1));
        bitInitialized = uint8(bound(bitInitialized, uint256(bitTick) + 1, type(uint8).max));
        SwapState memory state;
        (state.tick, state.tickSpacing) =
        (int24(wordPosition) * Constants.BITMAP_WORD_TICKS + int24(uint24(bitTick)), 1);
        address pool = address(new PoolMock(1, 1));
        PoolMock(pool)
            .addLiquidityNet(int24(wordPosition) * Constants.BITMAP_WORD_TICKS + int24(uint24(bitInitialized)), 1);

        // When: Calling setNextTick() for a swap moving the price down, without a limit.
        StepComputations memory step = swapStateLib.setNextTick(state, pool, true, TickMath.MIN_SQRT_PRICE + 1);

        // Then: The step's next tick is the word's start, not initialized.
        assertFalse(step.initialized);
        assertEq(step.tickNext, int24(wordPosition) * Constants.BITMAP_WORD_TICKS);
    }

    function testFuzz_Success_setNextTick_ClampsTheWordEndBelowTheLowestTick(int24 tick) public {
        // Given: A pool without initialized ticks, and a tick in the lowest bitmap word.
        tick = int24(
            bound(
                tick,
                TickMath.MIN_TICK,
                TickMath.MIN_TICK / Constants.BITMAP_WORD_TICKS * Constants.BITMAP_WORD_TICKS - 1
            )
        );
        address pool = address(new PoolMock(1, 1));
        SwapState memory state;
        (state.tick, state.tickSpacing) = (tick, 1);

        // When: Calling setNextTick() for a swap moving the price down, without a limit.
        StepComputations memory step = swapStateLib.setNextTick(state, pool, true, TickMath.MIN_SQRT_PRICE + 1);

        // Then: The word's end below the lowest tick is clamped to it.
        assertEq(step.tickNext, TickMath.MIN_TICK);
        assertEq(step.sqrtPriceNextX96, TickMath.MIN_SQRT_PRICE);
    }

    function testFuzz_Success_setNextTick_ClampsTheWordEndAboveTheHighestTick(int24 tick) public {
        // Given: A pool without initialized ticks, a tick whose next is in the top word.
        tick = int24(
            bound(
                tick,
                TickMath.MAX_TICK / Constants.BITMAP_WORD_TICKS * Constants.BITMAP_WORD_TICKS - 1,
                TickMath.MAX_TICK - 1
            )
        );
        address pool = address(new PoolMock(1, 1));
        SwapState memory state;
        (state.tick, state.tickSpacing) = (tick, 1);

        // When: Calling setNextTick() for a swap moving the price up, without a limit.
        StepComputations memory step = swapStateLib.setNextTick(state, pool, false, TickMath.MAX_SQRT_PRICE - 1);

        // Then: The word's end above the highest tick is clamped to it.
        assertEq(step.tickNext, TickMath.MAX_TICK);
        assertEq(step.sqrtPriceNextX96, TickMath.MAX_SQRT_PRICE);
    }
}
