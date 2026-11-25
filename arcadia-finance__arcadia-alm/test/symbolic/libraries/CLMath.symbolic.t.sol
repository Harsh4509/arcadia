/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { CLMathExtension } from "../../utils/extensions/CLMathExtension.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Symbolic tests for the library "CLMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract CLMath_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    CLMathExtension internal clMath;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public {
        clMath = new CLMathExtension();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    /// forge-config: default.symbolic.solver = "bitwuzla"
    function prove_convert_IsTheIdentityAtPriceOne(bool zeroForOne, uint256 amount) public pure {
        // Given: The price one and any amount.
        // When: Converting it in either direction.
        // Then: It comes back unchanged.
        assertEq(CLMath.convert(1 << 96, zeroForOne, amount, false), amount);
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_convert_ZeroForOne_IsTheFlooredValue(uint256 sqrtPriceX96, uint256 amount) public pure {
        // Given: A pool price below 2^128 and an amount whose value at it fits uint256.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= type(uint128).max);
        uint256 valueX192 = amount * (sqrtPriceX96 * sqrtPriceX96);

        // When: Converting token0 into token1.
        // Then: It is the value at the price, rounded down.
        assertEq(CLMath.convert(sqrtPriceX96, true, amount, false), valueX192 >> 192);
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_convert_OneForZero_IsTheFlooredValue(uint256 sqrtPriceX96, uint256 amount) public pure {
        // Given: A pool price below 2^128 and an amount below 2^64.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= type(uint128).max);
        vm.assume(amount < 1 << 64);
        uint256 converted = (amount << 192) / (sqrtPriceX96 * sqrtPriceX96);

        // When: Converting token1 into token0.
        // Then: It is the value at the price, rounded down.
        assertEq(CLMath.convert(sqrtPriceX96, false, amount, false), converted);
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_convert_OfNothingIsNothing(uint256 sqrtPriceX96, bool zeroForOne) public pure {
        // Given: A pool price below 2^128.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= type(uint128).max);

        // When: Converting a zero amount in either direction.
        // Then: It is zero.
        assertEq(CLMath.convert(sqrtPriceX96, zeroForOne, 0, false), 0);
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_convert_ZeroForOne_IsMonotoneInTheAmount(uint256 sqrtPriceX96, uint256 amountLow, uint256 amountHigh)
        public
        pure
    {
        // Given: A price below 2^128 and two ordered amounts whose values fit uint256.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= type(uint128).max);
        vm.assume(amountLow * (sqrtPriceX96 * sqrtPriceX96) <= amountHigh * (sqrtPriceX96 * sqrtPriceX96));

        // When: Converting both into token1.
        // Then: The larger amount converts to at least the smaller one's value.
        assertLe(
            CLMath.convert(sqrtPriceX96, true, amountLow, false), CLMath.convert(sqrtPriceX96, true, amountHigh, false)
        );
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_convert_OneForZero_IsMonotoneInTheAmount(uint256 sqrtPriceX96, uint256 amountLow, uint256 amountHigh)
        public
        pure
    {
        // Given: A pool price below 2^128 and two nonzero amounts below 2^64, in order.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= type(uint128).max);
        vm.assume(amountLow != 0 && amountLow <= amountHigh && amountHigh < 1 << 64);

        // When: Converting both into token0.
        // Then: The larger amount converts to at least the smaller one's value.
        assertLe(
            CLMath.convert(sqrtPriceX96, false, amountLow, false),
            CLMath.convert(sqrtPriceX96, false, amountHigh, false)
        );
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_getBand_LowerIsThePriceOverTheScaleRoundedUp(uint256 sqrtPriceX96, uint256 deviation) public pure {
        // Given: Any pool price and any uint64 deviation.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE);
        vm.assume(deviation <= type(uint64).max);
        uint256 scale = 1e18 + deviation;
        uint256 lowerFloored = sqrtPriceX96 * 1e18 / scale;

        // When: Taking the band around the price.
        (uint256 lower,) = CLMath.getBand(sqrtPriceX96, deviation);

        // Then: The lower bound is price / scale, rounded up.
        unchecked {
            assertEq(lower, lowerFloored + (mulmod(sqrtPriceX96, 1e18, scale) == 0 ? 0 : 1));
        }
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_getBand_UpperIsThePriceTimesTheScaleRoundedDown(uint256 sqrtPriceX96, uint256 deviation)
        public
        pure
    {
        // Given: Any pool price and any uint64 deviation.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE);
        vm.assume(deviation <= type(uint64).max);
        uint256 upperExpected = sqrtPriceX96 * (1e18 + deviation) / 1e18;

        // When: Taking the band around the price.
        (, uint256 upper) = CLMath.getBand(sqrtPriceX96, deviation);

        // Then: The upper bound is price * scale, rounded down.
        assertEq(upper, upperExpected);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getBand_LowerIsAtMostThePrice(uint256 sqrtPriceX96, uint256 deviation) public pure {
        // Given: Any pool price and any uint64 deviation.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE);
        vm.assume(deviation <= type(uint64).max);

        // When: Taking the band around the price.
        (uint256 lower,) = CLMath.getBand(sqrtPriceX96, deviation);

        // Then: The lower bound is at most the price.
        assertLe(lower, sqrtPriceX96);
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_getBand_UpperIsAtLeastThePrice(uint256 sqrtPriceX96, uint256 deviation) public pure {
        // Given: Any pool price and any uint64 deviation.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE);
        vm.assume(deviation <= type(uint64).max);

        // When: Taking the band around the price.
        (, uint256 upper) = CLMath.getBand(sqrtPriceX96, deviation);

        // Then: The upper bound is at least the price.
        assertGe(upper, sqrtPriceX96);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getBand_LowerIsThePriceWithoutADeviation(uint256 sqrtPriceX96) public pure {
        // Given: Any pool price.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE);

        // When: Taking the band without a deviation.
        (uint256 lower,) = CLMath.getBand(sqrtPriceX96, 0);

        // Then: The lower bound is the price.
        assertEq(lower, sqrtPriceX96);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getBand_UpperIsThePriceWithoutADeviation(uint256 sqrtPriceX96) public pure {
        // Given: Any pool price.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE);

        // When: Taking the band without a deviation.
        (, uint256 upper) = CLMath.getBand(sqrtPriceX96, 0);

        // Then: The upper bound is the price.
        assertEq(upper, sqrtPriceX96);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_convert_ZeroForOne_IsMonotoneInThePrice(
        uint256 sqrtPriceLowX96,
        uint256 sqrtPriceHighX96,
        uint256 amount
    ) public pure {
        // Given: Two ordered prices of at most one and an amount below 2^64.
        vm.assume(sqrtPriceLowX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceLowX96 <= sqrtPriceHighX96);
        vm.assume(sqrtPriceHighX96 <= 1 << 96 && amount < 1 << 64);

        // When: Converting the amount into token1 at both prices.
        // Then: The higher price converts to at least the lower price's value.
        assertLe(
            CLMath.convert(sqrtPriceLowX96, true, amount, false), CLMath.convert(sqrtPriceHighX96, true, amount, false)
        );
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_convert_OneForZero_IsAntitoneInThePrice(
        uint256 sqrtPriceLowX96,
        uint256 sqrtPriceHighX96,
        uint256 amount
    ) public pure {
        // Given: Two ordered prices of at most one and an amount below 2^64.
        vm.assume(sqrtPriceLowX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceLowX96 <= sqrtPriceHighX96);
        vm.assume(sqrtPriceHighX96 <= 1 << 96 && amount < 1 << 64);

        // When: Converting the amount into token0 at both prices.
        // Then: The higher price converts to at most the lower price's value.
        assertGe(
            CLMath.convert(sqrtPriceLowX96, false, amount, false),
            CLMath.convert(sqrtPriceHighX96, false, amount, false)
        );
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_convert_ThereAndBackNeverGains(uint256 sqrtPriceX96, bool zeroForOne, uint256 amount) public pure {
        // Given: A pool price of at most one and an amount below 2^64.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= 1 << 96);
        vm.assume(amount < 1 << 64);

        // When: Converting the amount into the other token and back.
        uint256 back =
            CLMath.convert(sqrtPriceX96, !zeroForOne, CLMath.convert(sqrtPriceX96, zeroForOne, amount, false), false);

        // Then: At most the amount comes back.
        assertLe(back, amount);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getNextSqrtPrice_StaysBetweenTheOldPriceAndTheBound(
        bool zeroForOne,
        uint256 sqrtPriceOld,
        uint256 sqrtPriceBound,
        uint256 sqrtPriceDelta
    ) public pure {
        // Given: Price < 2^64, a bound in the move's direction, a move of at most one.
        vm.assume(sqrtPriceOld >= TickMath.MIN_SQRT_PRICE && sqrtPriceOld < 1 << 64);
        vm.assume(sqrtPriceBound >= TickMath.MIN_SQRT_PRICE && sqrtPriceBound < 1 << 64);
        vm.assume(zeroForOne ? sqrtPriceBound <= sqrtPriceOld : sqrtPriceBound >= sqrtPriceOld);
        vm.assume(sqrtPriceDelta <= 1 << 192);

        // When: Moving the price.
        uint256 sqrtPriceNew = CLMath.getNextSqrtPrice(zeroForOne, sqrtPriceOld, sqrtPriceBound, sqrtPriceDelta);

        // Then: It lies between the old price and the bound.
        if (zeroForOne) {
            assertLe(sqrtPriceBound, sqrtPriceNew);
            assertLe(sqrtPriceNew, sqrtPriceOld);
        } else {
            assertLe(sqrtPriceOld, sqrtPriceNew);
            assertLe(sqrtPriceNew, sqrtPriceBound);
        }
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getNextSqrtPrice_WithoutAMoveIsTheOldPrice(
        bool zeroForOne,
        uint256 sqrtPriceOld,
        uint256 sqrtPriceBound
    ) public pure {
        // Given: A pool price below 2^64 and a bound in the move's direction.
        vm.assume(sqrtPriceOld >= TickMath.MIN_SQRT_PRICE && sqrtPriceOld < 1 << 64);
        vm.assume(sqrtPriceBound >= TickMath.MIN_SQRT_PRICE && sqrtPriceBound < 1 << 64);
        vm.assume(zeroForOne ? sqrtPriceBound <= sqrtPriceOld : sqrtPriceBound >= sqrtPriceOld);

        // When: Moving the price by nothing.
        // Then: It is the old price.
        assertEq(CLMath.getNextSqrtPrice(zeroForOne, sqrtPriceOld, sqrtPriceBound, 0), sqrtPriceOld);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getNextSqrtPrice_IsMonotoneInTheMove(
        bool zeroForOne,
        uint256 sqrtPriceOld,
        uint256 sqrtPriceBound,
        uint256 sqrtPriceDeltaLow,
        uint256 sqrtPriceDeltaHigh
    ) public pure {
        // Given: Price < 2^64, a bound in the move's direction, two ordered moves <= one.
        vm.assume(sqrtPriceOld >= TickMath.MIN_SQRT_PRICE && sqrtPriceOld < 1 << 64);
        vm.assume(sqrtPriceBound >= TickMath.MIN_SQRT_PRICE && sqrtPriceBound < 1 << 64);
        vm.assume(zeroForOne ? sqrtPriceBound <= sqrtPriceOld : sqrtPriceBound >= sqrtPriceOld);
        vm.assume(sqrtPriceDeltaLow <= sqrtPriceDeltaHigh && sqrtPriceDeltaHigh <= 1 << 192);

        // When: Moving the price by both.
        uint256 sqrtPriceLow = CLMath.getNextSqrtPrice(zeroForOne, sqrtPriceOld, sqrtPriceBound, sqrtPriceDeltaLow);
        uint256 sqrtPriceHigh = CLMath.getNextSqrtPrice(zeroForOne, sqrtPriceOld, sqrtPriceBound, sqrtPriceDeltaHigh);

        // Then: The larger move ends at least as far in its direction.
        if (zeroForOne) assertGe(sqrtPriceLow, sqrtPriceHigh);
        else assertLe(sqrtPriceLow, sqrtPriceHigh);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getNextSqrtPrice_ShortOfTheBoundNeverMovesPastTheRequestedMove(
        bool zeroForOne,
        uint256 sqrtPriceOld,
        uint256 sqrtPriceBound,
        uint256 sqrtPriceDelta
    ) public pure {
        // Given: Price < 2^64, bound in the move's direction, a move <= one short of it.
        vm.assume(sqrtPriceOld >= TickMath.MIN_SQRT_PRICE && sqrtPriceOld < 1 << 64);
        vm.assume(sqrtPriceBound >= TickMath.MIN_SQRT_PRICE && sqrtPriceBound < 1 << 64);
        vm.assume(zeroForOne ? sqrtPriceBound <= sqrtPriceOld : sqrtPriceBound >= sqrtPriceOld);
        vm.assume(sqrtPriceDelta <= 1 << 192);
        uint256 sqrtPriceNew = CLMath.getNextSqrtPrice(zeroForOne, sqrtPriceOld, sqrtPriceBound, sqrtPriceDelta);
        vm.assume(sqrtPriceNew != sqrtPriceBound);

        // When: Taking the relative move of the square root price of tokenIn, rounded up.
        uint256 realized = zeroForOne
            ? ((sqrtPriceOld - sqrtPriceNew) << 192) / sqrtPriceOld
                + (((sqrtPriceOld - sqrtPriceNew) << 192) % sqrtPriceOld == 0 ? 0 : 1)
            : ((sqrtPriceNew - sqrtPriceOld) << 192) / sqrtPriceNew
                + (((sqrtPriceNew - sqrtPriceOld) << 192) % sqrtPriceNew == 0 ? 0 : 1);

        // Then: It is at most the requested move.
        assertLe(realized, sqrtPriceDelta);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getAmount1ForLiquidityRoundingUp_IsTheCeiledAmount(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public pure {
        // Given: Two ordered bounds less than 2^128 apart.
        vm.assume(sqrtPriceAX96 <= sqrtPriceBX96 && uint256(sqrtPriceBX96) - sqrtPriceAX96 < 1 << 128);
        uint256 expected = (uint256(liquidity) * (sqrtPriceBX96 - sqrtPriceAX96) + (1 << 96) - 1) >> 96;

        // When: Taking the token1 for the liquidity between them.
        // Then: It is the liquidity times the width, rounded up.
        assertEq(CLMath.getAmount1ForLiquidityRoundingUp(sqrtPriceAX96, sqrtPriceBX96, liquidity), expected);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getAmount1ForLiquidityRoundingUp_ExceedsTheFlooredAmountByAtMostOne(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public pure {
        // Given: Two ordered bounds less than 2^128 apart.
        vm.assume(sqrtPriceAX96 <= sqrtPriceBX96 && uint256(sqrtPriceBX96) - sqrtPriceAX96 < 1 << 128);

        // When: Taking the token1 for the liquidity between them, and the floored amount.
        uint256 amount1 = CLMath.getAmount1ForLiquidityRoundingUp(sqrtPriceAX96, sqrtPriceBX96, liquidity);
        uint256 amount1Floored = uint256(liquidity) * (sqrtPriceBX96 - sqrtPriceAX96) >> 96;

        // Then: It is the floored amount or one more.
        assertLe(amount1Floored, amount1);
        assertLe(amount1, amount1Floored + 1);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getAmount0ForLiquidityRoundingUp_IsTheCeiledAmountOverTheManagersDivisor(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public pure {
        // Given: Two ordered bounds below 2^128 whose product reaches 2^96.
        vm.assume(sqrtPriceAX96 <= sqrtPriceBX96 && sqrtPriceBX96 <= type(uint128).max);
        uint256 divisor = uint256(sqrtPriceAX96) * sqrtPriceBX96 >> 96;
        vm.assume(divisor != 0);
        uint256 expected = (uint256(liquidity) * (sqrtPriceBX96 - sqrtPriceAX96) + divisor - 1) / divisor;

        // When: Taking the token0 for the liquidity between them.
        // Then: Liquidity times width over the manager's floored divisor, rounded up.
        assertEq(CLMath.getAmount0ForLiquidityRoundingUp(sqrtPriceAX96, sqrtPriceBX96, liquidity), expected);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getAmount0ForLiquidityRoundingUp_RevertsIffTheBoundsProductIsBelowQ96(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public view {
        // Given: Two ordered bounds below 2^128.
        vm.assume(sqrtPriceAX96 <= sqrtPriceBX96 && sqrtPriceBX96 <= type(uint128).max);
        bool divisorIsZero = uint256(sqrtPriceAX96) * sqrtPriceBX96 < 1 << 96;

        // When: Taking the token0 for the liquidity between them.
        (bool success, bytes memory result) = address(clMath)
            .staticcall(
                abi.encodeCall(
                    CLMathExtension.getAmount0ForLiquidityRoundingUp, (sqrtPriceAX96, sqrtPriceBX96, liquidity)
                )
            );

        // Then: It reverts exactly when the manager's divisor floors to zero.
        assertEq(success, !divisorIsZero);
        if (!success) assertEq(result, abi.encodeWithSelector(CLMath.NoLiquidityForToken0.selector));
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getAmount0ForLiquidityRoundingUp_IsAtLeastThePoolsRoundedDownDelta(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public pure {
        // Given: Ordered bounds < 2^128, product >= 2^96, liquidity times width < 2^160.
        vm.assume(sqrtPriceAX96 <= sqrtPriceBX96 && sqrtPriceBX96 <= type(uint128).max);
        vm.assume(uint256(sqrtPriceAX96) * sqrtPriceBX96 >= 1 << 96);
        vm.assume(uint256(liquidity) * (sqrtPriceBX96 - sqrtPriceAX96) < 1 << 160);
        uint256 amount0Floored =
            (uint256(liquidity) * (sqrtPriceBX96 - sqrtPriceAX96) << 96) / (uint256(sqrtPriceAX96) * sqrtPriceBX96);

        // When: Taking the token0 for the liquidity between them.
        // Then: It is at least the pool's token0 delta, the exact amount rounded down.
        assertGe(CLMath.getAmount0ForLiquidityRoundingUp(sqrtPriceAX96, sqrtPriceBX96, liquidity), amount0Floored);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getAmount0ForLiquidityRoundingUp_IsMonotoneInTheLiquidity(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidityLow,
        uint128 liquidityHigh
    ) public pure {
        // Given: Ordered bounds < 2^128, product >= 2^96, and two ordered liquidities.
        vm.assume(sqrtPriceAX96 <= sqrtPriceBX96 && sqrtPriceBX96 <= type(uint128).max);
        vm.assume(uint256(sqrtPriceAX96) * sqrtPriceBX96 >= 1 << 96 && liquidityLow <= liquidityHigh);

        // When: Taking the token0 for both liquidities.
        // Then: The larger liquidity takes at least as much.
        assertLe(
            CLMath.getAmount0ForLiquidityRoundingUp(sqrtPriceAX96, sqrtPriceBX96, liquidityLow),
            CLMath.getAmount0ForLiquidityRoundingUp(sqrtPriceAX96, sqrtPriceBX96, liquidityHigh)
        );
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getAmountsForLiquidityRoundingUp_DominateTheRoundedDownAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public pure {
        // Given: A price and a range <= one, bounds' product >= 2^96, liquidity < 2^63.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= 1 << 96);
        vm.assume(sqrtPriceAX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceAX96 < sqrtPriceBX96 && sqrtPriceBX96 <= 1 << 96);
        vm.assume(uint256(sqrtPriceAX96) * sqrtPriceBX96 >= 1 << 96 && liquidity < 1 << 63);

        // When: Taking the amounts for the liquidity both ways.
        (uint256 amount0Up, uint256 amount1Up) =
            CLMath.getAmountsForLiquidityRoundingUp(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidity);
        (uint256 amount0, uint256 amount1) =
            CLMath.getAmountsForLiquidity(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidity);

        // Then: The rounded up amounts are at least the rounded down ones in both tokens.
        assertGe(amount0Up, amount0);
        assertGe(amount1Up, amount1);
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_getAmountsForLiquidity_OfNoLiquidityAreNothing(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96
    ) public pure {
        // Given: A pool price and a range of at most one.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= 1 << 96);
        vm.assume(sqrtPriceAX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceAX96 < sqrtPriceBX96 && sqrtPriceBX96 <= 1 << 96);

        // When: Taking the amounts for no liquidity.
        (uint256 amount0, uint256 amount1) =
            CLMath.getAmountsForLiquidity(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, 0);

        // Then: Both are zero.
        assertEq(amount0, 0);
        assertEq(amount1, 0);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getAmountsForLiquidity_AreMonotoneInTheLiquidity(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidityLow,
        uint128 liquidityHigh
    ) public pure {
        // Given: A pool price, a range <= one, two ordered liquidities below 2^63.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= 1 << 96);
        vm.assume(sqrtPriceAX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceAX96 < sqrtPriceBX96 && sqrtPriceBX96 <= 1 << 96);
        vm.assume(liquidityLow <= liquidityHigh && liquidityHigh < 1 << 63);

        // When: Taking the amounts for both liquidities.
        (uint256 amount0Low, uint256 amount1Low) =
            CLMath.getAmountsForLiquidity(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidityLow);
        (uint256 amount0High, uint256 amount1High) =
            CLMath.getAmountsForLiquidity(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, liquidityHigh);

        // Then: The larger liquidity holds at least as much of both tokens.
        assertLe(amount0Low, amount0High);
        assertLe(amount1Low, amount1High);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getPrincipalAmounts_AreThePoolsRoundedDownAmountsAtTheTickPrices(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public pure {
        // Given: Any price and liquidity, and a range of valid ticks.
        vm.assume(TickMath.MIN_TICK <= tickLower && tickLower < tickUpper && tickUpper <= TickMath.MAX_TICK);
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtPriceAtTick(tickUpper);
        (uint160 sqrtPriceAX96, uint160 sqrtPriceBX96) = sqrtPriceX96 <= sqrtPriceLowerX96
            ? (sqrtPriceLowerX96, sqrtPriceUpperX96)
            : sqrtPriceX96 < sqrtPriceUpperX96
                ? (sqrtPriceX96, sqrtPriceUpperX96)
                : (sqrtPriceUpperX96, sqrtPriceUpperX96);
        uint256 expected0 = SqrtPriceMath.getAmount0Delta(sqrtPriceAX96, sqrtPriceBX96, liquidity, false);
        (sqrtPriceAX96, sqrtPriceBX96) = sqrtPriceX96 <= sqrtPriceLowerX96
            ? (sqrtPriceLowerX96, sqrtPriceLowerX96)
            : sqrtPriceX96 < sqrtPriceUpperX96
                ? (sqrtPriceLowerX96, sqrtPriceX96)
                : (sqrtPriceLowerX96, sqrtPriceUpperX96);
        uint256 expected1 = SqrtPriceMath.getAmount1Delta(sqrtPriceAX96, sqrtPriceBX96, liquidity, false);

        // When: Taking the principal of the liquidity at the price.
        (uint256 amount0, uint256 amount1) = CLMath.getPrincipalAmounts(sqrtPriceX96, tickLower, tickUpper, liquidity);

        // Then: Each is the pool's rounded down amount from the clamped price to an edge.
        assertEq(amount0, expected0);
        assertEq(amount1, expected1);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getMintAmounts_OfNoSharesTakeNothing(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceLowerX96,
        uint160 sqrtPriceUpperX96,
        uint256 rangeLiquidity,
        uint256 supply
    ) public pure {
        // Given: A price and range < 2^128, product >= 2^96, any liquidity and a supply.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= type(uint128).max);
        vm.assume(sqrtPriceLowerX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceLowerX96 < sqrtPriceUpperX96);
        vm.assume(sqrtPriceUpperX96 <= type(uint128).max && supply != 0);
        vm.assume(uint256(sqrtPriceLowerX96) * sqrtPriceUpperX96 >= 1 << 96);

        // When: Taking the amounts a mint of no shares owes.
        (uint256 amount0, uint256 amount1) =
            CLMath.getMintAmounts(sqrtPriceX96, sqrtPriceLowerX96, sqrtPriceUpperX96, rangeLiquidity, 0, supply);

        // Then: Both are zero.
        assertEq(amount0, 0);
        assertEq(amount1, 0);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getMintAmounts_OfTheWholeSupplyAreTheRangesRoundedUpAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceLowerX96,
        uint160 sqrtPriceUpperX96,
        uint128 rangeLiquidity,
        uint256 supply
    ) public pure {
        // Given: A price and range < 2^128, product >= 2^96, and a uint128 supply.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= type(uint128).max);
        vm.assume(sqrtPriceLowerX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceLowerX96 < sqrtPriceUpperX96);
        vm.assume(sqrtPriceUpperX96 <= type(uint128).max && supply != 0 && supply <= type(uint128).max);
        vm.assume(uint256(sqrtPriceLowerX96) * sqrtPriceUpperX96 >= 1 << 96);

        // When: Taking a whole-supply mint's amounts, and the range's amounts rounded up.
        (uint256 amount0, uint256 amount1) =
            CLMath.getMintAmounts(sqrtPriceX96, sqrtPriceLowerX96, sqrtPriceUpperX96, rangeLiquidity, supply, supply);
        (uint256 range0, uint256 range1) = CLMath.getAmountsForLiquidityRoundingUp(
            sqrtPriceX96, sqrtPriceLowerX96, sqrtPriceUpperX96, rangeLiquidity
        );

        // Then: They are the same.
        assertEq(amount0, range0);
        assertEq(amount1, range1);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getMintAmounts_AreMonotoneInTheShares(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceLowerX96,
        uint160 sqrtPriceUpperX96,
        uint128 rangeLiquidity,
        uint256 sharesLow,
        uint256 sharesHigh,
        uint256 supply
    ) public pure {
        // Given: Price, range < 2^128, product >= 2^96, ordered mints in uint128 supply.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= type(uint128).max);
        vm.assume(sqrtPriceLowerX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceLowerX96 < sqrtPriceUpperX96);
        vm.assume(sqrtPriceUpperX96 <= type(uint128).max && sharesLow <= sharesHigh && sharesHigh <= supply);
        vm.assume(supply <= type(uint128).max && uint256(sqrtPriceLowerX96) * sqrtPriceUpperX96 >= 1 << 96);

        // When: Taking the amounts both mints owe.
        (uint256 amount0Low, uint256 amount1Low) = CLMath.getMintAmounts(
            sqrtPriceX96, sqrtPriceLowerX96, sqrtPriceUpperX96, rangeLiquidity, sharesLow, supply
        );
        (uint256 amount0High, uint256 amount1High) = CLMath.getMintAmounts(
            sqrtPriceX96, sqrtPriceLowerX96, sqrtPriceUpperX96, rangeLiquidity, sharesHigh, supply
        );

        // Then: The larger mint owes at least as much of both tokens.
        assertLe(amount0Low, amount0High);
        assertLe(amount1Low, amount1High);
    }
}
