/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";

/**
 * @notice Symbolic lemmas on the library "FixedPointMathLib", used by the derivations in docs/proofs.
 */
contract FixedPointMathLib_Symbolic_Test is Symbolic_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_fullMulDiv_IsMonotoneInTheAmount(
        uint256 amountLow,
        uint256 amountHigh,
        uint256 factor,
        uint256 divisor
    ) public pure {
        // Given: Two ordered amounts whose products fit, and a nonzero divisor.
        vm.assume(amountLow <= amountHigh && (factor == 0 || amountHigh <= type(uint256).max / factor));
        vm.assume(divisor != 0);

        // When: Taking both amounts times the factor over the divisor, floored.
        // Then: The larger amount gives at least the smaller one's quotient.
        assertLe(amountLow.fullMulDiv(factor, divisor), amountHigh.fullMulDiv(factor, divisor));
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_fullMulDiv_IsSymmetricInBothFactors(uint256 amount, uint256 factor, uint256 divisor) public pure {
        // Given: An amount and a factor whose product fits, and a nonzero divisor.
        vm.assume((factor == 0 || amount <= type(uint256).max / factor) && divisor != 0);

        // When: Taking the product over the divisor in both orders, floored.
        // Then: Both are equal.
        assertEq(amount.fullMulDiv(factor, divisor), factor.fullMulDiv(amount, divisor));
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_fullMulDiv_NeverRisesWithTheDivisor(
        uint256 amount,
        uint256 factor,
        uint256 divisorLow,
        uint256 divisorHigh
    ) public pure {
        // Given: An amount and a factor whose product fits, ordered nonzero divisors.
        vm.assume((factor == 0 || amount <= type(uint256).max / factor) && divisorLow <= divisorHigh);
        vm.assume(divisorLow != 0);

        // When: Taking the product over both divisors, floored.
        // Then: The higher divisor gives at most the lower one's quotient.
        assertLe(amount.fullMulDiv(factor, divisorHigh), amount.fullMulDiv(factor, divisorLow));
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_fullMulDivUp_APartOfAnAmountIsAtMostTheAmount(uint256 amount, uint256 part, uint256 whole)
        public
        pure
    {
        // Given: An amount and a part whose product fits, a whole of at least it.
        vm.assume(part == 0 || amount <= type(uint256).max / part);
        vm.assume(part <= whole && whole != 0);

        // When: Taking the part of the amount, rounded up.
        // Then: It is at most the amount.
        assertLe(amount.fullMulDivUp(part, whole), amount);
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_fullMulDivUp_ExceedsFullMulDivByAtMostOne(uint256 amount, uint256 factor, uint256 divisor)
        public
        pure
    {
        // Given: An amount and a factor whose product fits, and a nonzero divisor.
        vm.assume((factor == 0 || amount <= type(uint256).max / factor) && divisor != 0);

        // When: Taking the product over the divisor, rounded up and floored.
        // Then: Rounding up adds at most one.
        assertLe(amount.fullMulDivUp(factor, divisor), amount.fullMulDiv(factor, divisor) + 1);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_fullMulDivUp_APartRoundedUpAndTheRestFlooredMakeTheAmount(
        uint256 amount,
        uint256 part0,
        uint256 part1
    ) public pure {
        // Given: Two uint128 parts, not both zero, an amount times their sum that fits.
        vm.assume(part0 <= type(uint128).max && part1 <= type(uint128).max && part0 + part1 != 0);
        vm.assume(amount <= type(uint256).max / (part0 + part1));

        // When: Taking the first part of the amount rounded up, and the second floored.
        // Then: Both together are the amount.
        assertEq(amount.fullMulDivUp(part0, part0 + part1) + amount.fullMulDiv(part1, part0 + part1), amount);
    }
}
