/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { EquivalentPosition } from "../../../src/vaults/types/EquivalentPosition.sol";
import { EquivalentPositionMath } from "../../../src/vaults/libraries/math/EquivalentPositionMath.sol";
import { PricedRange } from "../../../src/vaults/types/PricedRange.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Symbolic tests for the function "amountsAt" of library "EquivalentPositionMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract AmountsAt_EquivalentPositionMath_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function prove_amountsAt_FloorsTheNegatedConstantsWithoutLiquidity(
        int256 constant0,
        int256 constant1,
        uint160 sqrtPriceX96,
        bool zeroForOne
    ) public pure {
        // Given: No liquidity, any constants that negate, and any pool price.
        vm.assume(constant0 != type(int256).min && constant1 != type(int256).min);
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE);
        EquivalentPosition memory position;
        (position.constant0, position.constant1) = (constant0, constant1);

        // When: Taking the position's amounts at the price.
        (uint256 amountIn, uint256 amountOut) = EquivalentPositionMath.amountsAt(position, sqrtPriceX96, zeroForOne);

        // Then: Each is its negated constant floored at zero, in the swap's order.
        uint256 amount0 = constant0 < 0 ? uint256(-constant0) : 0;
        uint256 amount1 = constant1 < 0 ? uint256(-constant1) : 0;
        assertEq(amountIn, zeroForOne ? amount0 : amount1);
        assertEq(amountOut, zeroForOne ? amount1 : amount0);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_amountsAt_Token0NeverRisesWithThePrice(
        uint256 liquidity,
        int256 constant0,
        uint256 sqrtPriceLowX96,
        uint256 sqrtPriceHighX96
    ) public pure {
        // Given: Some uint128 liquidity, a constant below 2^254, ordered prices < 2^128.
        vm.assume(liquidity != 0 && liquidity <= type(uint128).max);
        vm.assume(constant0 > -(1 << 254) && constant0 < 1 << 254);
        vm.assume(sqrtPriceLowX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceLowX96 <= sqrtPriceHighX96);
        vm.assume(sqrtPriceHighX96 <= type(uint128).max);
        EquivalentPosition memory position;
        (position.liquidity, position.constant0) = (liquidity, constant0);

        // When: Taking the token0 amount at both prices.
        (uint256 amountLow,) = EquivalentPositionMath.amountsAt(position, uint160(sqrtPriceLowX96), true);
        (uint256 amountHigh,) = EquivalentPositionMath.amountsAt(position, uint160(sqrtPriceHighX96), true);

        // Then: The higher price holds at most the lower price's token0.
        assertGe(amountLow, amountHigh);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_amountsAt_FloorsTheOwnAmountsLessTheConstants(
        uint256 liquidity,
        int256 constant0,
        int256 constant1,
        uint256 sqrtPriceX96,
        bool zeroForOne
    ) public pure {
        // Given: Some uint128 liquidity, constants within 2^254, a price below 2^128.
        vm.assume(liquidity != 0 && liquidity <= type(uint128).max);
        vm.assume(constant0 > -(1 << 254) && constant0 < 1 << 254 && constant1 > -(1 << 254) && constant1 < 1 << 254);
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= type(uint128).max);
        EquivalentPosition memory position;
        (position.liquidity, position.constant0, position.constant1) = (liquidity, constant0, constant1);
        int256 own0 = int256((liquidity << 96) / sqrtPriceX96) - constant0;
        int256 own1 = int256(liquidity * sqrtPriceX96 >> 96) - constant1;
        uint256 amount0 = own0 > 0 ? uint256(own0) : 0;
        uint256 amount1 = own1 > 0 ? uint256(own1) : 0;

        // When: Taking the position's amounts at the price.
        (uint256 amountIn, uint256 amountOut) =
            EquivalentPositionMath.amountsAt(position, uint160(sqrtPriceX96), zeroForOne);

        // Then: Each is its floored own amount less its constant, at least 0.
        assertEq(amountIn, zeroForOne ? amount0 : amount1);
        assertEq(amountOut, zeroForOne ? amount1 : amount0);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_amountsAt_Token1NeverFallsWithThePrice(
        uint256 liquidity,
        int256 constant1,
        uint256 sqrtPriceLowX96,
        uint256 sqrtPriceHighX96
    ) public pure {
        // Given: Some uint128 liquidity, a constant below 2^254, ordered prices < 2^128.
        vm.assume(liquidity != 0 && liquidity <= type(uint128).max);
        vm.assume(constant1 > -(1 << 254) && constant1 < 1 << 254);
        vm.assume(sqrtPriceLowX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceLowX96 <= sqrtPriceHighX96);
        vm.assume(sqrtPriceHighX96 <= type(uint128).max);
        EquivalentPosition memory position;
        (position.liquidity, position.constant1) = (liquidity, constant1);

        // When: Taking the token1 amount at both prices.
        (, uint256 amountLow) = EquivalentPositionMath.amountsAt(position, uint160(sqrtPriceLowX96), true);
        (, uint256 amountHigh) = EquivalentPositionMath.amountsAt(position, uint160(sqrtPriceHighX96), true);

        // Then: The higher price holds at least the lower price's token1.
        assertLe(amountLow, amountHigh);
    }
}

/**
 * @notice Symbolic tests for the function "getPosition" of library "EquivalentPositionMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetPosition_EquivalentPositionMath_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                              HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function oneRange(uint128 liquidity, uint128 unstakedLiquidity, uint160 lower, uint160 upper)
        internal
        pure
        returns (PricedRange[] memory ranges)
    {
        ranges = new PricedRange[](1);
        ranges[0] = PricedRange(liquidity, unstakedLiquidity, lower, upper);
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function prove_getPosition_WithoutRangesHoldsTheIdleTokens(
        uint160 sqrtPriceX96,
        bool zeroForOne,
        uint256 idle0,
        uint256 idle1
    ) public pure {
        // Given: No ranges, idle tokens below 2^255 and any pool price.
        vm.assume(idle0 < 1 << 255 && idle1 < 1 << 255);

        // When: Taking the equivalent position.
        EquivalentPosition memory position =
            EquivalentPositionMath.getPosition(new PricedRange[](0), sqrtPriceX96, zeroForOne, idle0, idle1);

        // Then: No liquidity, holds the idle tokens, bounded by the pool's extreme price.
        assertEq(position.liquidity, 0);
        assertEq(position.unstakedLiquidity, 0);
        assertEq(position.constant0, -int256(idle0));
        assertEq(position.constant1, -int256(idle1));
        assertEq(position.sqrtPriceBound, zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getPosition_OneRangeInRange_FoldsItsLiquidityAndEdges(
        uint128 liquidity,
        uint128 unstakedLiquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        bool zeroForOne
    ) public pure {
        // Given: A range < 2^128 with liquidity, price inside it in swap direction.
        vm.assume(liquidity != 0 && unstakedLiquidity <= liquidity);
        vm.assume(lower > TickMath.MIN_SQRT_PRICE + 1 && lower < upper && upper <= type(uint128).max);
        vm.assume(
            zeroForOne ? lower < sqrtPriceX96 && sqrtPriceX96 <= upper : lower <= sqrtPriceX96 && sqrtPriceX96 < upper
        );

        // When: Taking the equivalent position without idle tokens.
        EquivalentPosition memory position = EquivalentPositionMath.getPosition(
            oneRange(liquidity, unstakedLiquidity, lower, upper), sqrtPriceX96, zeroForOne, 0, 0
        );

        // Then: Range's liquidity, far edge amounts as constants, near edge as bound.
        assertEq(position.liquidity, liquidity);
        assertEq(position.unstakedLiquidity, unstakedLiquidity);
        assertEq(position.constant0, int256((uint256(liquidity) << 96) / upper));
        assertEq(position.constant1, int256(uint256(liquidity) * lower >> 96));
        assertEq(position.sqrtPriceBound, zeroForOne ? lower : upper);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getPosition_OneRangeAboveThePrice_HoldsItsToken0(
        uint128 liquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        bool zeroForOne
    ) public pure {
        // Given: One range below 2^128 with liquidity, and a pool price below it.
        vm.assume(liquidity != 0);
        vm.assume(lower > TickMath.MIN_SQRT_PRICE + 1 && lower < upper && upper <= type(uint128).max);
        vm.assume(
            sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && (zeroForOne ? sqrtPriceX96 <= lower : sqrtPriceX96 < lower)
        );

        // When: Taking the equivalent position without idle tokens.
        EquivalentPosition memory position =
            EquivalentPositionMath.getPosition(oneRange(liquidity, 0, lower, upper), sqrtPriceX96, zeroForOne, 0, 0);

        // Then: No liquidity, range's token0 as constant, bounded from lower edge up.
        assertEq(position.liquidity, 0);
        assertEq(position.constant0, -int256((uint256(liquidity) << 96) / lower - (uint256(liquidity) << 96) / upper));
        assertEq(position.constant1, 0);
        assertEq(position.sqrtPriceBound, zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : lower);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getPosition_OneRangeBelowThePrice_HoldsItsToken1(
        uint128 liquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        bool zeroForOne
    ) public pure {
        // Given: One range below 2^128 with liquidity, and a pool price above it.
        vm.assume(liquidity != 0);
        vm.assume(lower > TickMath.MIN_SQRT_PRICE + 1 && lower < upper && upper <= type(uint128).max);
        vm.assume(
            sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE && (zeroForOne ? sqrtPriceX96 > upper : sqrtPriceX96 >= upper)
        );

        // When: Taking the equivalent position without idle tokens.
        EquivalentPosition memory position =
            EquivalentPositionMath.getPosition(oneRange(liquidity, 0, lower, upper), sqrtPriceX96, zeroForOne, 0, 0);

        // Then: No liquidity, range's token1 as constant, bounded from upper edge down.
        assertEq(position.liquidity, 0);
        assertEq(position.constant0, 0);
        assertEq(position.constant1, -int256(uint256(liquidity) * (upper - lower) >> 96));
        assertEq(position.sqrtPriceBound, zeroForOne ? upper : TickMath.MAX_SQRT_PRICE - 1);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getPosition_OneRangeInRange_HoldsTheRangesAmountsOrOneMore(
        uint128 liquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        uint128 idle0,
        uint128 idle1
    ) public pure {
        // Given: Range <= one, liquidity < 2^63, idle tokens, price inside for token0 in.
        vm.assume(liquidity != 0 && liquidity < 1 << 63);
        vm.assume(lower > TickMath.MIN_SQRT_PRICE + 1 && lower < upper && upper <= 1 << 96);
        vm.assume(lower < sqrtPriceX96 && sqrtPriceX96 <= upper);

        // When: Taking the equivalent position's amounts at the price, and the range's.
        (uint256 amount0, uint256 amount1) = EquivalentPositionMath.amountsAt(
            EquivalentPositionMath.getPosition(oneRange(liquidity, 0, lower, upper), sqrtPriceX96, true, idle0, idle1),
            sqrtPriceX96,
            true
        );
        (uint256 range0, uint256 range1) = CLMath.getAmountsForLiquidity(sqrtPriceX96, lower, upper, liquidity);

        // Then: Each is the range's amount plus the idle, or one more.
        assertLe(range0 + idle0, amount0);
        assertLe(amount0, range0 + idle0 + 1);
        assertLe(range1 + idle1, amount1);
        assertLe(amount1, range1 + idle1 + 1);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getPosition_OneRangeAboveThePrice_HoldsTheRangesToken0OrOneMore(
        uint128 liquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        uint128 idle0,
        uint128 idle1
    ) public pure {
        // Given: One range <= one, liquidity < 2^63, idle tokens, and a price below it.
        vm.assume(liquidity != 0 && liquidity < 1 << 63);
        vm.assume(lower > TickMath.MIN_SQRT_PRICE + 1 && lower < upper && upper <= 1 << 96);
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= lower);

        // When: Taking the equivalent position's amounts at the price, and the range's.
        (uint256 amount0, uint256 amount1) = EquivalentPositionMath.amountsAt(
            EquivalentPositionMath.getPosition(oneRange(liquidity, 0, lower, upper), sqrtPriceX96, true, idle0, idle1),
            sqrtPriceX96,
            true
        );
        (uint256 range0,) = CLMath.getAmountsForLiquidity(sqrtPriceX96, lower, upper, liquidity);

        // Then: Token0 is the range's plus the idle, or one more, and token1 is the idle.
        assertLe(range0 + idle0, amount0);
        assertLe(amount0, range0 + idle0 + 1);
        assertEq(amount1, idle1);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getPosition_OneRangeBelowThePrice_HoldsTheRangesToken1(
        uint128 liquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        uint128 idle0,
        uint128 idle1
    ) public pure {
        // Given: One range < 2^128 with liquidity, idle tokens, a price above it.
        vm.assume(liquidity != 0);
        vm.assume(lower > TickMath.MIN_SQRT_PRICE + 1 && lower < upper && upper <= type(uint128).max);
        vm.assume(sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE && sqrtPriceX96 > upper);

        // When: Taking the equivalent position's amounts at the price, and the range's.
        (uint256 amount0, uint256 amount1) = EquivalentPositionMath.amountsAt(
            EquivalentPositionMath.getPosition(oneRange(liquidity, 0, lower, upper), sqrtPriceX96, true, idle0, idle1),
            sqrtPriceX96,
            true
        );
        (, uint256 range1) = CLMath.getAmountsForLiquidity(sqrtPriceX96, lower, upper, liquidity);

        // Then: Token1 is exactly the range's plus the idle, and token0 is the idle.
        assertEq(amount0, idle0);
        assertEq(amount1, range1 + idle1);
    }
}
