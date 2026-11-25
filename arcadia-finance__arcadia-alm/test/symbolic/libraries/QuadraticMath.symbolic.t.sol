/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { QuadraticMath } from "../../../src/vaults/libraries/math/QuadraticMath.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";

/**
 * @notice Symbolic tests for the function "getRoot" of library "QuadraticMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetRoot_QuadraticMath_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function prove_getRoot_ReturnsTheEdgesOutsideTheInterior(int256 a, int256 b, int256 c) public pure {
        // Given: A non-negative a, and a c that is not positive or at least b.
        vm.assume(a >= 0 && (c <= 0 || c >= b));

        // When: Taking the root.
        uint256 x = QuadraticMath.getRoot(a, b, c);

        // Then: It is zero without a positive c and one otherwise.
        assertEq(x, c <= 0 ? 0 : 1 << 192);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getRoot_WithoutAQuadraticTermIsTheFlooredRatio(int256 b, int256 c) public pure {
        // Given: No quadratic term, linear coefficient >= 4 units, 0 < c < min(b, 2^64).
        vm.assume(b >= 4 && c > 0 && c < b && c < 1 << 64);

        // When: Taking the root.
        // Then: It is c / b, rounded down.
        assertEq(QuadraticMath.getRoot(0, b, c), (uint256(c) << 192) / uint256(b));
    }

    function prove_getRoot_WithoutAQuadraticTermAndALinearCoefficientBelowFourIsOne(int256 b, int256 c) public pure {
        // Given: No quadratic term, linear coefficient of two or three units, 0 < c < b.
        vm.assume(b >= 2 && b <= 3 && c > 0 && c < b);

        // When: Taking the root.
        // Then: It is one.
        assertEq(QuadraticMath.getRoot(0, b, c), 1 << 192);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getRoot_IsZeroWhenTheRatioFloorsToZero(int256 a, int256 b, int256 c) public pure {
        // Given: 0 <= a < 2^192, 0 < c < 2^64, c / b floors to zero, inside the guard.
        vm.assume(a >= 0 && a < 1 << 192 && c > 0 && c < 1 << 64 && b > 0 && uint256(c) << 192 < uint256(b));
        vm.assume(uint256(a) * uint256(c) / uint256(b) < uint256(b) / 4);

        // When: Taking the root.
        // Then: It is zero.
        assertEq(QuadraticMath.getRoot(a, b, c), 0);
    }

    /// forge-config: default.symbolic.solver = "bitwuzla"
    function prove_getRoot_IsAtMostTwiceTheRatio(int256 a, int256 b, int256 c) public pure {
        // Given: Interior: 0 <= a < 2^192, 0 < c < min(b, 2^64), with a real root.
        vm.assume(a >= 0 && a < 1 << 192 && c > 0 && c < b && c < 1 << 64);
        vm.assume(uint256(a) * uint256(c) / uint256(b) < uint256(b) / 4);

        // When: Taking the root.
        // Then: It is at most twice c / b.
        assertLe(QuadraticMath.getRoot(a, b, c), 2 * ((uint256(c) << 192) / uint256(b)));
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getRoot_IsAtLeastTheRatio(int256 a, int256 b, int256 c) public pure {
        // Given: Interior: 0 <= a < 2^192, 0 < c < min(b, 2^64), with a real root.
        vm.assume(a >= 0 && a < 1 << 192 && c > 0 && c < b && c < 1 << 64);
        vm.assume(uint256(a) * uint256(c) / uint256(b) < uint256(b) / 4);

        // When: Taking the root.
        // Then: It is at least c / b.
        assertGe(QuadraticMath.getRoot(a, b, c), (uint256(c) << 192) / uint256(b));
    }
}
