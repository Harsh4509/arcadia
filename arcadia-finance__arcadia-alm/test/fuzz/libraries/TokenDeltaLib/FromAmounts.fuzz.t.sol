/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";
import { TokenDeltaLib_Fuzz_Test } from "./_TokenDeltaLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "fromAmounts" of library "TokenDeltaLib".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract FromAmounts_TokenDeltaLib_Fuzz_Test is TokenDeltaLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_fromAmounts_Token0ExceedsInt128(uint256 token0Amount, uint256 token1Amount) public {
        // Given: A token0 magnitude past the int128 maximum.
        token0Amount = bound(token0Amount, Constants.MAX_FUZZED_AMOUNT + 1, type(uint256).max);
        token1Amount = bound(token1Amount, 0, Constants.MAX_FUZZED_AMOUNT);

        // When: Building a delta from the magnitudes.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        tokenDeltaLib.fromAmounts(token0Amount, token1Amount);
    }

    function testFuzz_Revert_fromAmounts_Token1ExceedsInt128(uint256 token0Amount, uint256 token1Amount) public {
        // Given: A token1 magnitude past the int128 maximum.
        token0Amount = bound(token0Amount, 0, Constants.MAX_FUZZED_AMOUNT);
        token1Amount = bound(token1Amount, Constants.MAX_FUZZED_AMOUNT + 1, type(uint256).max);

        // When: Building a delta from the magnitudes.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        tokenDeltaLib.fromAmounts(token0Amount, token1Amount);
    }

    function testFuzz_Revert_fromAmounts_BothExceedInt128Alike(uint256 amount) public {
        // Given: Equal token0 and token1 magnitudes past the int128 maximum.
        amount = bound(amount, Constants.MAX_FUZZED_AMOUNT + 1, type(uint256).max);

        // When: Building a delta from the magnitudes.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        tokenDeltaLib.fromAmounts(amount, amount);
    }

    function testFuzz_Success_fromAmounts_RoundTrip(uint256 token0Amount, uint256 token1Amount) public view {
        // Given: Two magnitudes within the int128 range.
        token0Amount = bound(token0Amount, 0, Constants.MAX_FUZZED_AMOUNT);
        token1Amount = bound(token1Amount, 0, Constants.MAX_FUZZED_AMOUNT);

        // When: Building a delta from the magnitudes.
        TokenDelta delta = tokenDeltaLib.fromAmounts(token0Amount, token1Amount);

        // Then: Both components read back as the same non-negative amounts.
        assertEq(uint256(uint128(tokenDeltaLib.amount0(delta))), token0Amount);
        assertEq(uint256(uint128(tokenDeltaLib.amount1(delta))), token1Amount);
    }
}
