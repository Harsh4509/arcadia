/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { EquivalentPosition } from "../../../../src/vaults/types/EquivalentPosition.sol";
import { PoolLogic } from "../../../../src/shared/libraries/logic/PoolLogic.sol";
import { PoolMock } from "../../../utils/mocks/PoolMock.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { Snapshot, SnapshotLib } from "../../../../src/vaults/types/Snapshot.sol";
import { StepComputations, SwapState } from "../../../../src/vaults/types/SwapState.sol";
import { SwapStateLib_Fuzz_Test } from "./_SwapStateLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "crossTick" of library "SwapStateLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract CrossTick_SwapStateLib_Fuzz_Test is SwapStateLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_crossTick_ShortOfTheNextPrice(
        SwapState memory state,
        StepComputations memory step,
        bool zeroForOne
    ) public {
        // Given: A step whose target is short of its next price.
        givenValidStep(state, step, zeroForOne, true);
        Snapshot memory snapshot;

        // When: Calling crossTick().
        (bool crossed, SwapState memory stateAfter) = swapStateLib.crossTick(
            state, step, snapshot, address(new PoolMock(1, 1)), zeroForOne, PoolLogic.sqrtPriceLimit(zeroForOne)
        );

        // Then: The swap ends at the step's target, with the step's amounts taken.
        assertFalse(crossed);
        assertEq(stateAfter.sqrtPriceX96, step.sqrtPriceTargetX96);
        assertEq(stateAfter.amountIn, state.amountIn + step.amountIn + step.feeAmount);
        assertEq(stateAfter.amountOut, state.amountOut + step.amountOut);

        // And: The tick is not crossed.
        assertEq(stateAfter.tick, state.tick);
        assertEq(stateAfter.liquidity, state.liquidity);
    }

    function testFuzz_Success_crossTick_AtThePriceLimit(
        SwapState memory state,
        StepComputations memory step,
        bool zeroForOne
    ) public {
        // Given: A step that reaches its next price, which is the price limit.
        givenValidStep(state, step, zeroForOne, false);
        step.sqrtPriceTargetX96 = step.sqrtPriceNextX96;
        Snapshot memory snapshot;

        // When: Calling crossTick() with the next price as the limit.
        (bool crossed, SwapState memory stateAfter) = swapStateLib.crossTick(
            state, step, snapshot, address(new PoolMock(1, 1)), zeroForOne, step.sqrtPriceNextX96
        );

        // Then: The swap ends at the limit, with the step's amounts taken.
        assertFalse(crossed);
        assertEq(stateAfter.sqrtPriceX96, step.sqrtPriceTargetX96);
        assertEq(stateAfter.amountIn, state.amountIn + step.amountIn + step.feeAmount);
        assertEq(stateAfter.amountOut, state.amountOut + step.amountOut);

        // And: The tick is not crossed.
        assertEq(stateAfter.tick, state.tick);
        assertEq(stateAfter.liquidity, state.liquidity);
    }

    function testFuzz_Success_crossTick_InitializedTick(
        SwapState memory state,
        StepComputations memory step,
        bool zeroForOne,
        int64 liquidityNet,
        bool negative
    ) public {
        // Given: A step to an initialized tick, its nonzero net keeping liquidity >= 0.
        givenValidStep(state, step, zeroForOne, false);
        step.sqrtPriceTargetX96 = step.sqrtPriceNextX96;
        state.liquidity = uint128(bound(state.liquidity, 1, uint64(type(int64).max)));
        liquidityNet = int64(bound(liquidityNet, 1, int256(uint256(state.liquidity))));
        if (negative) liquidityNet = -liquidityNet;
        address pool = address(new PoolMock(1, 1));
        PoolMock(pool).addLiquidityNet(step.tickNext, liquidityNet);
        step.initialized = true;
        Snapshot memory snapshot;

        // When: Calling crossTick().
        (bool crossed, SwapState memory stateAfter) =
            swapStateLib.crossTick(state, step, snapshot, pool, zeroForOne, PoolLogic.sqrtPriceLimit(zeroForOne));

        // Then: The swap goes on from the next price, with the step's amounts taken.
        assertTrue(crossed);
        assertEq(stateAfter.sqrtPriceX96, step.sqrtPriceTargetX96);
        assertEq(stateAfter.amountIn, state.amountIn + step.amountIn + step.feeAmount);
        assertEq(stateAfter.amountOut, state.amountOut + step.amountOut);

        // And: The tick shifts past the next tick, the liquidity moving by its net.
        assertEq(stateAfter.tick, zeroForOne ? step.tickNext - 1 : step.tickNext);
        int256 liquidityDelta = zeroForOne ? -int256(liquidityNet) : int256(liquidityNet);
        assertEq(int256(uint256(stateAfter.liquidity)), int256(uint256(state.liquidity)) + liquidityDelta);
    }

    function testFuzz_Success_crossTick_UninitializedTick(
        SwapState memory state,
        StepComputations memory step,
        bool zeroForOne
    ) public {
        // Given: A step that reaches a bitmap word end.
        givenValidStep(state, step, zeroForOne, false);
        step.sqrtPriceTargetX96 = step.sqrtPriceNextX96;
        step.initialized = false;
        Snapshot memory snapshot;

        // When: Calling crossTick().
        (bool crossed, SwapState memory stateAfter) = swapStateLib.crossTick(
            state, step, snapshot, address(new PoolMock(1, 1)), zeroForOne, PoolLogic.sqrtPriceLimit(zeroForOne)
        );

        // Then: The swap goes on from the next price, with the step's amounts taken.
        assertTrue(crossed);
        assertEq(stateAfter.sqrtPriceX96, step.sqrtPriceTargetX96);
        assertEq(stateAfter.amountIn, state.amountIn + step.amountIn + step.feeAmount);
        assertEq(stateAfter.amountOut, state.amountOut + step.amountOut);

        // And: The tick shifts past the next tick, the liquidity unchanged.
        assertEq(stateAfter.tick, zeroForOne ? step.tickNext - 1 : step.tickNext);
        assertEq(stateAfter.liquidity, state.liquidity);
    }

    function testFuzz_Success_crossTick_RenewsThePositionAtTheCoresEdge(
        SwapState memory state,
        StepComputations memory step,
        bool zeroForOne,
        uint64 rangeLiquidity,
        uint8 width
    ) public {
        // Given: A step that reaches a bitmap word end at the core's edge.
        givenValidStep(state, step, zeroForOne, false);
        step.sqrtPriceTargetX96 = step.sqrtPriceNextX96;
        step.initialized = false;
        state.position.sqrtPriceBound = step.sqrtPriceNextX96;

        // And: A core with a range on the far side of that edge.
        int24 tickFar = zeroForOne
            ? int24(bound(step.tickNext - int24(uint24(width)) - 1, TickMath.MIN_TICK, step.tickNext - 1))
            : int24(bound(step.tickNext + int24(uint24(width)) + 1, step.tickNext + 1, TickMath.MAX_TICK));
        PricedRange[] memory ranges = new PricedRange[](1);
        ranges[0] = PricedRange({
            liquidity: uint128(bound(rangeLiquidity, 1, type(uint64).max)),
            unstakedLiquidity: 0,
            sqrtPriceLowerX96: TickMath.getSqrtPriceAtTick(zeroForOne ? tickFar : step.tickNext),
            sqrtPriceUpperX96: TickMath.getSqrtPriceAtTick(zeroForOne ? step.tickNext : tickFar)
        });
        Snapshot memory snapshot;
        snapshot.ranges = ranges;
        snapshot.supply = 1;

        // When: Calling crossTick().
        (bool crossed, SwapState memory stateAfter) = swapStateLib.crossTick(
            state, step, snapshot, address(new PoolMock(1, 1)), zeroForOne, PoolLogic.sqrtPriceLimit(zeroForOne)
        );

        // Then: The swap goes on with the core's equivalent position at the edge.
        assertTrue(crossed);
        EquivalentPosition memory position = SnapshotLib.getPosition(snapshot, step.sqrtPriceNextX96, zeroForOne);
        assertEq(abi.encode(stateAfter.position), abi.encode(position));
    }
}
