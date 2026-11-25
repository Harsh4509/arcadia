/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { QuadraticMath_Fuzz_Test } from "./_QuadraticMath.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "getRoot" of library "QuadraticMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetRoot_QuadraticMath_Fuzz_Test is QuadraticMath_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getRoot_ZeroWithoutAPositiveConstant(int256 a, int256 b, int256 c) public view {
        // Given: A constant term at most zero.
        c = bound(c, type(int256).min, 0);

        // When: Taking the root.
        uint256 x = quadraticMath.getRoot(a, b, c);

        // Then: It is zero.
        assertEq(x, 0);
    }

    function testFuzz_Success_getRoot_ZeroWhenAZeroConstantReachesTheLinear(int256 a, int256 b) public view {
        // Given: A zero constant term at least the linear one.
        b = bound(b, type(int256).min, 0);

        // When: Taking the root.
        uint256 x = quadraticMath.getRoot(a, b, 0);

        // Then: It is zero.
        assertEq(x, 0);
    }

    function testFuzz_Success_getRoot_OneWhenTheConstantReachesTheLinear(int256 a, int256 b, int256 c) public view {
        // Given: A positive constant term at least the linear one.
        c = bound(c, 1, type(int256).max);
        b = bound(b, type(int256).min, c);

        // When: Taking the root.
        uint256 x = quadraticMath.getRoot(a, b, c);

        // Then: It is one, with 192 binary precision.
        assertEq(x, 1 << 192);
    }

    function testFuzz_Success_getRoot_OneWhenTheConstantEqualsTheLinear(int256 a, int256 b) public view {
        // Given: A positive constant equal to the linear term, 4ac / b^2 below one.
        b = bound(b, 8, type(int256).max);
        a = bound(a, 1, b / 4 - 1);

        // When: Taking the root.
        uint256 x = quadraticMath.getRoot(a, b, b);

        // Then: It is one, with 192 binary precision.
        assertEq(x, 1 << 192);
    }

    function testFuzz_Success_getRoot_OneWithoutARealRoot(int256 a, int256 b, int256 c) public view {
        // Given: Positive terms with c below b, and an a at which 4ac / b^2 reaches one.
        b = bound(b, 2, type(int256).max);
        uint256 cLeast = (uint256(b) / 4).fullMulDivUp(uint256(b), uint256(type(int256).max));
        c = int256(bound(uint256(c), FixedPointMathLib.max(cLeast, 1), uint256(b) - 1));
        uint256 aLeast = (uint256(b) / 4).fullMulDivUp(uint256(b), uint256(c));
        a = int256(bound(uint256(a), aLeast, uint256(type(int256).max)));

        // When: Taking the root.
        uint256 x = quadraticMath.getRoot(a, b, c);

        // Then: It is one, with 192 binary precision.
        assertEq(x, 1 << 192);
    }

    function testFuzz_Success_getRoot_LinearWhenTheQuadraticTermIsZero(int256 b, int256 c) public view {
        // Given: No quadratic term, b at least 4, and c / b from 2^-192 to below 1.
        b = bound(b, 4, type(int256).max);
        c = int256(bound(uint256(c), (uint256(b) >> 192) + 1, uint256(b) - 1));

        // When: Taking the smallest positive root.
        uint256 x = quadraticMath.getRoot(0, b, c);

        // Then: It is c / b at 192 binary precision, rounded down.
        assertEq(x, FullMath.mulDiv(uint256(c), 1 << 192, uint256(b)));
    }

    function testFuzz_Success_getRoot_BetweenTheLinearRootAndTwiceIt(int256 a, int256 b, int256 c) public view {
        // Given: b at least 4, and c / b at least 2^-192 and below 1.
        b = bound(b, 4, type(int256).max);
        c = int256(bound(uint256(c), (uint256(b) >> 192) + 1, uint256(b) - 1));

        // And: A quadratic term below the root's guard, so 4ac / b^2 stays below one.
        uint256 ratio = uint256(c).fullMulDiv(1 << 192, uint256(b));
        uint256 guard = uint256(b) / 4 - 1;
        uint256 aMost = uint256(c) > guard.fullMulDiv(uint256(b), type(uint256).max)
            ? guard.fullMulDiv(uint256(b), uint256(c))
            : type(uint256).max;
        a = int256(bound(uint256(a), 0, FixedPointMathLib.min(aMost, uint256(type(int256).max))));

        // When: Taking the smallest positive root.
        uint256 x = quadraticMath.getRoot(a, b, c);

        // Then: It lies between c / b and twice it.
        assertGe(x, ratio);
        assertLe(x, 2 * ratio);
    }

    function testFuzz_Success_getRoot_GrowsWithTheQuadraticTerm(int256 a, int256 aLarger, int256 b, int256 c)
        public
        view
    {
        // Given: b at least 4, and c / b at least 2^-192 and below 1.
        b = bound(b, 4, type(int256).max);
        c = int256(bound(uint256(c), (uint256(b) >> 192) + 1, uint256(b) - 1));

        // And: Two quadratic terms below the root's guard, so 4ac / b^2 stays below one.
        uint256 guard = uint256(b) / 4 - 1;
        uint256 aMost = uint256(c) > guard.fullMulDiv(uint256(b), type(uint256).max)
            ? guard.fullMulDiv(uint256(b), uint256(c))
            : type(uint256).max;
        aLarger = int256(bound(uint256(aLarger), 0, FixedPointMathLib.min(aMost, uint256(type(int256).max))));
        a = int256(bound(uint256(a), 0, uint256(aLarger)));

        // When: Taking the smallest positive root of both.
        uint256 x = quadraticMath.getRoot(a, b, c);
        uint256 xLarger = quadraticMath.getRoot(aLarger, b, c);

        // Then: The larger quadratic term has the larger root.
        assertLe(x, xLarger);
    }

    function testFuzz_Success_getRoot_FourThirdsOfTheLinearRootAtAThreeQuarterDiscriminant(
        uint256 exponentB,
        int256 gap
    ) public view {
        // Given: b = 2^p and c = 2^(p - gap), c / b = 2^-gap from 2^-128 to 2^-1.
        gap = bound(gap, 1, 128);
        uint256 lowest = gap > 0 ? uint256(gap) : 0;
        if (4 - gap > int256(lowest)) lowest = uint256(4 - gap);
        uint256 highest = gap < 0 ? uint256(254 + gap) : 254;
        if (257 - gap < int256(highest)) highest = uint256(257 - gap);
        exponentB = bound(exponentB, lowest, highest);
        uint256 b = 1 << exponentB;
        uint256 c = 1 << uint256(int256(exponentB) - gap);

        // And: a = 3b^2 / (16c), so 4ac / b^2 = 3/4 and sqrt(1 - 4ac / b^2) = 1/2.
        uint256 a = 3 << uint256(int256(exponentB) + gap - 4);

        // When: Taking the smallest positive root.
        uint256 x = quadraticMath.getRoot(int256(a), int256(b), int256(c));

        // Then: It is 2(c / b) / (1 + 1/2), 4/3 of c / b at 192 bits, rounded down.
        assertEq(x, FixedPointMathLib.fullMulDiv(1 << uint256(193 - gap), 2, 3));
    }

    function testFuzz_Success_getRoot_TheDiscriminantRootRoundedUpAtAHalfDiscriminant(uint256 exponentB, uint256 gap)
        public
        view
    {
        // Given: b = 2^p and c = 2^(p - gap), c / b = 2^-gap from 2^-128 to 2^-1.
        gap = bound(gap, 1, 128);
        exponentB = bound(exponentB, FixedPointMathLib.max(gap, 3), FixedPointMathLib.min(254, 257 - gap));
        uint256 b = 1 << exponentB;
        uint256 c = 1 << (exponentB - gap);

        // And: a = b^2 / (8c), so sqrt(1 - 4ac / b^2) = sqrt(2) / 2, irrational.
        uint256 a = 1 << (exponentB + gap - 3);

        // When: Taking the smallest positive root.
        uint256 x = quadraticMath.getRoot(int256(a), int256(b), int256(c));

        // Then: It is 2(c / b) / (1 + sqrt(2) / 2), the root rounded up at 127 bits.
        assertEq(
            x,
            FixedPointMathLib.fullMulDiv(1 << (193 - gap), 1 << 127, (1 << 127) + FixedPointMathLib.sqrt(1 << 253) + 1)
        );
    }
}
