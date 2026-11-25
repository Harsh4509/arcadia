/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { EquivalentPosition } from "../../../../src/vaults/types/EquivalentPosition.sol";
import { EquivalentPositionMath_Fuzz_Test } from "./_EquivalentPositionMath.fuzz.t.sol";
import { FixedPoint96 } from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getPosition" of library "EquivalentPositionMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetPosition_EquivalentPositionMath_Fuzz_Test is EquivalentPositionMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(EquivalentPositionMath_Fuzz_Test) {
        EquivalentPositionMath_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getPosition_BufferOverflow_Token0(
        uint160 sqrtPriceX96,
        bool zeroForOne,
        uint256 buffer0,
        uint256 buffer1
    ) public {
        // Given: Any price, and a token0 buffer past what a signed constant holds.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        buffer0 = bound(buffer0, uint256(type(int256).max) + 1, type(uint256).max);

        // When: Building the position.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        equivalentPositionMath.getPosition(sqrtPriceX96, zeroForOne, buffer0, buffer1);
    }

    function testFuzz_Revert_getPosition_BufferOverflow_Token1(
        uint160 sqrtPriceX96,
        bool zeroForOne,
        uint256 buffer0,
        uint256 buffer1
    ) public {
        // Given: Any price, a token0 buffer an int256 holds, and a token1 buffer past it.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        buffer0 = bound(buffer0, 0, uint256(type(int256).max));
        buffer1 = bound(buffer1, uint256(type(int256).max) + 1, type(uint256).max);

        // When: Building the position.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        equivalentPositionMath.getPosition(sqrtPriceX96, zeroForOne, buffer0, buffer1);
    }

    function testFuzz_Success_getPosition_BufferOnly(
        uint160 sqrtPriceX96,
        bool zeroForOne,
        uint256 buffer0,
        uint256 buffer1
    ) public view {
        // Given: Any price, no ranges and a buffer.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        buffer0 = bound(buffer0, 0, uint256(type(int256).max));
        buffer1 = bound(buffer1, 0, uint256(type(int256).max));

        // When: Building the position.
        EquivalentPosition memory position =
            equivalentPositionMath.getPosition(sqrtPriceX96, zeroForOne, buffer0, buffer1);

        // Then: It holds no liquidity, and its constants are the negated buffer.
        assertEq(position.liquidity, 0);
        assertEq(position.constant0, -int256(buffer0));
        assertEq(position.constant1, -int256(buffer1));
    }

    function testFuzz_Success_getPosition_SkipsARangeWithNoLiquidity(
        uint160 sqrtPriceX96,
        bool zeroForOne,
        int24 tickLower,
        int24 tickUpper,
        uint128 buffer0,
        uint128 buffer1
    ) public {
        // Given: Any price, a buffer, and a range that holds no liquidity.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        tickLower = int24(bound(tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        tickUpper = int24(bound(tickUpper, tickLower + 1, TickMath.MAX_TICK));
        pushRange(tickLower, tickUpper, 0);

        // When: Building the position.
        EquivalentPosition memory position =
            equivalentPositionMath.getPosition(sqrtPriceX96, zeroForOne, buffer0, buffer1);

        // Then: It is the buffer alone.
        assertEq(position.liquidity, 0);
        assertEq(position.constant0, -int256(uint256(buffer0)));
        assertEq(position.constant1, -int256(uint256(buffer1)));
    }

    function testFuzz_Success_getPosition_RangeAroundThePrice(
        uint160 sqrtPriceX96,
        bool zeroForOne,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public {
        // Given: A price strictly inside a range holding liquidity.
        sqrtPriceX96 = uint160(
            bound(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK + 1),
                TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK - 1)
            )
        );
        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        tickLower = int24(bound(tickLower, TickMath.MIN_TICK, tick - 1));
        tickUpper = int24(bound(tickUpper, tick + 1, TickMath.MAX_TICK));
        liquidity = uint128(bound(liquidity, 1, type(uint128).max));
        pushRange(tickLower, tickUpper, liquidity);

        // When: Building the position in either direction.
        EquivalentPosition memory position = equivalentPositionMath.getPosition(sqrtPriceX96, zeroForOne, 0, 0);

        // Then: The range is in range.
        assertEq(position.liquidity, liquidity);
    }

    function testFuzz_Success_getPosition_RangeStartingAtThePrice_OutOfRangeDown(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public {
        // Given: A range holding liquidity whose lower bound is the price.
        tickLower = int24(bound(tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        tickUpper = int24(bound(tickUpper, tickLower + 1, TickMath.MAX_TICK));
        liquidity = uint128(bound(liquidity, 1, type(uint128).max));
        pushRange(tickLower, tickUpper, liquidity);

        // When: Building the position for a step that moves the price down.
        EquivalentPosition memory position =
            equivalentPositionMath.getPosition(TickMath.getSqrtPriceAtTick(tickLower), true, 0, 0);

        // Then: The range is not in range, and the step does not stop at its edge.
        assertEq(position.liquidity, 0);
        assertEq(position.sqrtPriceBound, TickMath.MIN_SQRT_PRICE + 1);

        // And: Its token0 alone folds into the constants.
        uint256 held0 = FullMath.mulDiv(liquidity, FixedPoint96.Q96, TickMath.getSqrtPriceAtTick(tickLower))
            - FullMath.mulDiv(liquidity, FixedPoint96.Q96, TickMath.getSqrtPriceAtTick(tickUpper));
        assertEq(-position.constant0, int256(held0));
        assertEq(position.constant1, 0);
    }

    function testFuzz_Success_getPosition_RangeStartingAtThePrice_InRangeUp(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public {
        // Given: A range holding liquidity whose lower bound is the price.
        tickLower = int24(bound(tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        tickUpper = int24(bound(tickUpper, tickLower + 1, TickMath.MAX_TICK));
        liquidity = uint128(bound(liquidity, 1, type(uint128).max));
        pushRange(tickLower, tickUpper, liquidity);

        // When: Building the position for a step that moves the price up.
        EquivalentPosition memory position =
            equivalentPositionMath.getPosition(TickMath.getSqrtPriceAtTick(tickLower), false, 0, 0);

        // Then: It is in range, and the step stops at its upper edge or the pool's limit.
        assertEq(position.liquidity, liquidity);
        assertEq(
            position.sqrtPriceBound,
            FixedPointMathLib.min(TickMath.getSqrtPriceAtTick(tickUpper), TickMath.MAX_SQRT_PRICE - 1)
        );
    }

    function testFuzz_Success_getPosition_RangeEndingAtThePrice_InRangeDown(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public {
        // Given: A range holding liquidity whose upper bound is the price.
        tickLower = int24(bound(tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        tickUpper = int24(bound(tickUpper, tickLower + 1, TickMath.MAX_TICK));
        liquidity = uint128(bound(liquidity, 1, type(uint128).max));
        pushRange(tickLower, tickUpper, liquidity);

        // When: Building the position for a step that moves the price down.
        EquivalentPosition memory position =
            equivalentPositionMath.getPosition(TickMath.getSqrtPriceAtTick(tickUpper), true, 0, 0);

        // Then: It is in range, and the step stops at its lower edge or the pool's limit.
        assertEq(position.liquidity, liquidity);
        assertEq(
            position.sqrtPriceBound,
            FixedPointMathLib.max(TickMath.getSqrtPriceAtTick(tickLower), TickMath.MIN_SQRT_PRICE + 1)
        );
    }

    function testFuzz_Success_getPosition_RangeEndingAtThePrice_OutOfRangeUp(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public {
        // Given: A range holding liquidity whose upper bound is the price.
        tickLower = int24(bound(tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        tickUpper = int24(bound(tickUpper, tickLower + 1, TickMath.MAX_TICK));
        liquidity = uint128(bound(liquidity, 1, type(uint128).max));
        pushRange(tickLower, tickUpper, liquidity);

        // When: Building the position for a step that moves the price up.
        EquivalentPosition memory position =
            equivalentPositionMath.getPosition(TickMath.getSqrtPriceAtTick(tickUpper), false, 0, 0);

        // Then: The range is not in range, and the step does not stop at its edge.
        assertEq(position.liquidity, 0);
        assertEq(position.sqrtPriceBound, TickMath.MAX_SQRT_PRICE - 1);

        // And: Its token1 alone folds into the constants.
        uint256 held1 = SqrtPriceMath.getAmount1Delta(
            TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), liquidity, false
        );
        assertEq(position.constant0, 0);
        assertEq(-position.constant1, int256(held1));
    }

    function testFuzz_Success_getPosition_BoundDownIsTheHighestEdgeBelow(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        int24 belowLower,
        int24 belowUpper,
        uint128 liquidity
    ) public {
        // Given: A price strictly inside a range, and a second range wholly below it.
        sqrtPriceX96 = uint160(
            bound(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK + 2),
                TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK - 1)
            )
        );
        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        tickLower = int24(bound(tickLower, TickMath.MIN_TICK + 1, tick - 1));
        tickUpper = int24(bound(tickUpper, tick + 1, TickMath.MAX_TICK));
        int24 belowMost = TickMath.getSqrtPriceAtTick(tick) == sqrtPriceX96 ? tick - 1 : tick;
        belowLower = int24(bound(belowLower, TickMath.MIN_TICK, belowMost - 1));
        belowUpper = int24(bound(belowUpper, belowLower + 1, belowMost));
        liquidity = uint128(bound(liquidity, 1, type(uint64).max));
        pushRange(tickLower, tickUpper, liquidity);
        pushRange(belowLower, belowUpper, liquidity);

        // When: Building the position for a swap that moves the price down.
        uint160 bound_ = equivalentPositionMath.getPosition(sqrtPriceX96, true, 0, 0).sqrtPriceBound;

        // Then: The bound is the highest range edge below the price.
        uint160 lowerEdge = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 belowEdge = TickMath.getSqrtPriceAtTick(belowUpper);
        assertEq(bound_, lowerEdge > belowEdge ? lowerEdge : belowEdge);
    }

    function testFuzz_Success_getPosition_BoundUpIsTheLowestEdgeAbove(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        int24 aboveLower,
        int24 aboveUpper,
        uint128 liquidity
    ) public {
        // Given: A price strictly inside a range, and a second range wholly above it.
        sqrtPriceX96 = uint160(
            bound(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK + 1),
                TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK - 2)
            )
        );
        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        tickLower = int24(bound(tickLower, TickMath.MIN_TICK, tick - 1));
        tickUpper = int24(bound(tickUpper, tick + 1, TickMath.MAX_TICK - 1));
        aboveLower = int24(bound(aboveLower, tick + 1, TickMath.MAX_TICK - 1));
        aboveUpper = int24(bound(aboveUpper, aboveLower + 1, TickMath.MAX_TICK));
        liquidity = uint128(bound(liquidity, 1, type(uint64).max));
        pushRange(tickLower, tickUpper, liquidity);
        pushRange(aboveLower, aboveUpper, liquidity);

        // When: Building the position for a swap that moves the price up.
        uint160 bound_ = equivalentPositionMath.getPosition(sqrtPriceX96, false, 0, 0).sqrtPriceBound;

        // Then: The bound is the lowest range edge above the price.
        uint160 upperEdge = TickMath.getSqrtPriceAtTick(tickUpper);
        uint160 aboveEdge = TickMath.getSqrtPriceAtTick(aboveLower);
        assertEq(bound_, upperEdge < aboveEdge ? upperEdge : aboveEdge);
    }

    function testFuzz_Success_getPosition_BoundWithoutLiquidityIsTheExtremePrice(
        uint160 sqrtPriceX96,
        bool zeroForOne,
        int24 tickLower,
        int24 tickUpper
    ) public {
        // Given: A range holding no liquidity around any price.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        tickLower = int24(bound(tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        tickUpper = int24(bound(tickUpper, tickLower + 1, TickMath.MAX_TICK));
        pushRange(tickLower, tickUpper, 0);

        // When: Building the position.
        uint160 bound_ = equivalentPositionMath.getPosition(sqrtPriceX96, zeroForOne, 0, 0).sqrtPriceBound;

        // Then: Nothing changes before the price's own extreme.
        assertEq(bound_, zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1);
    }

    function testFuzz_Success_getPosition_BoundDownSkipsARangeAboveThePrice(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public {
        // Given: A price, and a range holding liquidity wholly above it.
        sqrtPriceX96 =
            uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK - 2)));
        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        tickLower = int24(bound(tickLower, tick + 1, TickMath.MAX_TICK - 1));
        tickUpper = int24(bound(tickUpper, tickLower + 1, TickMath.MAX_TICK));
        liquidity = uint128(bound(liquidity, 1, type(uint128).max));
        pushRange(tickLower, tickUpper, liquidity);

        // When: Building the position for a swap that moves the price down.
        uint160 bound_ = equivalentPositionMath.getPosition(sqrtPriceX96, true, 0, 0).sqrtPriceBound;

        // Then: Nothing changes before the price's own extreme.
        assertEq(bound_, TickMath.MIN_SQRT_PRICE + 1);
    }

    function testFuzz_Success_getPosition_BoundUpSkipsARangeBelowThePrice(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public {
        // Given: A price, and a range holding liquidity wholly below it.
        sqrtPriceX96 = uint160(
            bound(sqrtPriceX96, TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK + 2), TickMath.MAX_SQRT_PRICE - 1)
        );
        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        tickLower = int24(bound(tickLower, TickMath.MIN_TICK, tick - 2));
        tickUpper = int24(bound(tickUpper, tickLower + 1, tick - 1));
        liquidity = uint128(bound(liquidity, 1, type(uint128).max));
        pushRange(tickLower, tickUpper, liquidity);

        // When: Building the position for a swap that moves the price up.
        uint160 bound_ = equivalentPositionMath.getPosition(sqrtPriceX96, false, 0, 0).sqrtPriceBound;

        // Then: Nothing changes before the price's own extreme.
        assertEq(bound_, TickMath.MAX_SQRT_PRICE - 1);
    }

    function testFuzz_Success_getPosition_BoundDownFromTheLowestPriceIsTheExtremePrice(
        int24 tickUpper,
        uint128 liquidity
    ) public {
        // Given: A range with liquidity from the lowest tick, the price at that edge.
        tickUpper = int24(bound(tickUpper, TickMath.MIN_TICK + 1, TickMath.MAX_TICK));
        liquidity = uint128(bound(liquidity, 1, type(uint128).max));
        pushRange(TickMath.MIN_TICK, tickUpper, liquidity);

        // When: Building the position for a swap that moves the price down.
        uint160 bound_ = equivalentPositionMath.getPosition(TickMath.MIN_SQRT_PRICE, true, 0, 0).sqrtPriceBound;

        // Then: The bound stays the extreme price.
        assertEq(bound_, TickMath.MIN_SQRT_PRICE + 1);
    }

    function testFuzz_Success_getPosition_SumsTheUnstakedLiquidityInRange(
        uint160 sqrtPriceX96,
        bool zeroForOne,
        RangeState memory first,
        RangeState memory second
    ) public {
        // Given: A price strictly inside two ranges, each with unstaked and staked parts.
        sqrtPriceX96 = uint160(
            bound(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK + 1),
                TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK - 1)
            )
        );
        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        first.tickLower = int24(bound(first.tickLower, TickMath.MIN_TICK, tick - 1));
        first.tickUpper = int24(bound(first.tickUpper, tick + 1, TickMath.MAX_TICK));
        second.tickLower = int24(bound(second.tickLower, TickMath.MIN_TICK, tick - 1));
        second.tickUpper = int24(bound(second.tickUpper, tick + 1, TickMath.MAX_TICK));
        first.liquidity = uint128(bound(first.liquidity, 1, type(uint64).max));
        first.liquidityStaked = uint128(bound(first.liquidityStaked, 0, type(uint64).max));
        second.liquidity = uint128(bound(second.liquidity, 1, type(uint64).max));
        second.liquidityStaked = uint128(bound(second.liquidityStaked, 0, type(uint64).max));
        RangeState[] memory ranges = new RangeState[](2);
        (ranges[0], ranges[1]) = (first, second);
        PricedRange[] memory priced = pricedOf(ranges);
        equivalentPositionMath.pushRange(priced[0]);
        equivalentPositionMath.pushRange(priced[1]);

        // When: Building the position in either direction.
        uint256 unstakedLiquidity = equivalentPositionMath.getPosition(sqrtPriceX96, zeroForOne, 0, 0).unstakedLiquidity;

        // Then: Its unstaked liquidity is the sum of both ranges'.
        assertEq(unstakedLiquidity, uint256(first.liquidity) + second.liquidity);
    }
}
