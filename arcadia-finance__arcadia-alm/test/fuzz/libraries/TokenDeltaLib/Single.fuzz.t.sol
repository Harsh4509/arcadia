/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";
import { TokenDeltaLib_Fuzz_Test } from "./_TokenDeltaLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "single" of library "TokenDeltaLib".
 */
contract Single_TokenDeltaLib_Fuzz_Test is TokenDeltaLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_single_Token0(int128 amount) public view {
        // Given: A signed amount of token0.

        // When: Packing it as token0.
        TokenDelta delta = tokenDeltaLib.single(true, amount);

        // Then: Token0 carries it and token1 is zero.
        assertEq(tokenDeltaLib.amount0(delta), amount);
        assertEq(tokenDeltaLib.amount1(delta), 0);
    }

    function testFuzz_Success_single_Token1(int128 amount) public view {
        // Given: A signed amount of token1.

        // When: Packing it as token1.
        TokenDelta delta = tokenDeltaLib.single(false, amount);

        // Then: Token1 carries it and token0 is zero.
        assertEq(tokenDeltaLib.amount0(delta), 0);
        assertEq(tokenDeltaLib.amount1(delta), amount);
    }
}
