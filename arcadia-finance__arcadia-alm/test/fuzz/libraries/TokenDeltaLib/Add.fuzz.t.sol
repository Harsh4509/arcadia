/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";
import { TokenDeltaLib_Fuzz_Test } from "./_TokenDeltaLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "add" of library "TokenDeltaLib".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract Add_TokenDeltaLib_Fuzz_Test is TokenDeltaLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_add_Amount0Overflow(int128 a0, int128 b0, int128 a1) public {
        // Given: Deltas whose token0 sum is past an int128, the second with no token1.
        a0 = int128(bound(a0, type(int128).min, type(int128).max - 1));
        if (a0 >= 0) ++a0;
        b0 = a0 > 0
            ? int128(bound(b0, int256(type(int128).max) - a0 + 1, type(int128).max))
            : int128(bound(b0, type(int128).min, int256(type(int128).min) - a0 - 1));
        TokenDelta a = tokenDeltaLib.toTokenDelta(a0, a1);
        TokenDelta b = tokenDeltaLib.toTokenDelta(b0, 0);

        // When: Adding them.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        tokenDeltaLib.add(a, b);
    }

    function testFuzz_Revert_add_Amount1Overflow(int128 a0, int128 a1, int128 b1) public {
        // Given: Deltas whose token1 sum is past an int128, the second with no token0.
        a1 = int128(bound(a1, type(int128).min, type(int128).max - 1));
        if (a1 >= 0) ++a1;
        b1 = a1 > 0
            ? int128(bound(b1, int256(type(int128).max) - a1 + 1, type(int128).max))
            : int128(bound(b1, type(int128).min, int256(type(int128).min) - a1 - 1));
        TokenDelta a = tokenDeltaLib.toTokenDelta(a0, a1);
        TokenDelta b = tokenDeltaLib.toTokenDelta(0, b1);

        // When: Adding them.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        tokenDeltaLib.add(a, b);
    }

    function testFuzz_Revert_add_BothAmountsOverflowAlike(int128 a, int128 b) public {
        // Given: Deltas equal in both components, whose sum is past an int128.
        a = int128(bound(a, type(int128).min, type(int128).max - 1));
        if (a >= 0) ++a;
        b = a > 0
            ? int128(bound(b, int256(type(int128).max) - a + 1, type(int128).max))
            : int128(bound(b, type(int128).min, int256(type(int128).min) - a - 1));
        TokenDelta deltaA = tokenDeltaLib.toTokenDelta(a, a);
        TokenDelta deltaB = tokenDeltaLib.toTokenDelta(b, b);

        // When: Adding them.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        tokenDeltaLib.add(deltaA, deltaB);
    }

    function testFuzz_Success_add_ComponentWise(int128 a0, int128 b0, int128 a1, int128 b1) public view {
        // Given: Two deltas whose amounts sum within an int128, component by component.
        b0 = int128(
            bound(
                b0,
                FixedPointMathLib.max(type(int128).min, int256(type(int128).min) - a0),
                FixedPointMathLib.min(type(int128).max, int256(type(int128).max) - a0)
            )
        );
        b1 = int128(
            bound(
                b1,
                FixedPointMathLib.max(type(int128).min, int256(type(int128).min) - a1),
                FixedPointMathLib.min(type(int128).max, int256(type(int128).max) - a1)
            )
        );

        // When: Adding them.
        TokenDelta sum = tokenDeltaLib.add(tokenDeltaLib.toTokenDelta(a0, a1), tokenDeltaLib.toTokenDelta(b0, b1));

        // Then: Each component is the sum of its inputs.
        assertEq(int256(tokenDeltaLib.amount0(sum)), int256(a0) + b0);
        assertEq(int256(tokenDeltaLib.amount1(sum)), int256(a1) + b1);
    }
}
