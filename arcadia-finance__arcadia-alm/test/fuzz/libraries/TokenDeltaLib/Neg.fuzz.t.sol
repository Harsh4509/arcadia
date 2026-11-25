/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";
import { TokenDeltaLib_Fuzz_Test } from "./_TokenDeltaLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "neg" of library "TokenDeltaLib".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract Neg_TokenDeltaLib_Fuzz_Test is TokenDeltaLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_neg_Amount0Overflow(int128 token1Amount) public {
        // Given: A delta whose token0 amount is the int128 minimum.
        TokenDelta delta = tokenDeltaLib.toTokenDelta(type(int128).min, token1Amount);

        // When: Negating it.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        tokenDeltaLib.neg(delta);
    }

    function testFuzz_Revert_neg_Amount1Overflow(int128 token0Amount) public {
        // Given: A delta whose token1 amount is the int128 minimum.
        TokenDelta delta = tokenDeltaLib.toTokenDelta(token0Amount, type(int128).min);

        // When: Negating it.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        tokenDeltaLib.neg(delta);
    }

    function testFuzz_Success_neg_ComponentWise(int128 token0Amount, int128 token1Amount) public view {
        // Given: A delta whose components are both above the int128 minimum.
        token0Amount = int128(bound(int256(token0Amount), type(int128).min + 1, type(int128).max));
        token1Amount = int128(bound(int256(token1Amount), type(int128).min + 1, type(int128).max));
        TokenDelta delta = tokenDeltaLib.toTokenDelta(token0Amount, token1Amount);

        // When: Negating it.
        TokenDelta negated = tokenDeltaLib.neg(delta);

        // Then: Each component is the negation of its input.
        assertEq(int256(tokenDeltaLib.amount0(negated)), -int256(token0Amount));
        assertEq(int256(tokenDeltaLib.amount1(negated)), -int256(token1Amount));
    }
}
