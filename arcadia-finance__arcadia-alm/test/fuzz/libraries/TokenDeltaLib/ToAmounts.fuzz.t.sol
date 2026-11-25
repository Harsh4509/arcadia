/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";
import { TokenDeltaLib_Fuzz_Test } from "./_TokenDeltaLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "toAmounts" of library "TokenDeltaLib".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract ToAmounts_TokenDeltaLib_Fuzz_Test is TokenDeltaLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_toAmounts_RoundTrip(uint256 token0Amount, uint256 token1Amount) public view {
        // Given: A delta built from two magnitudes within the int128 range.
        token0Amount = bound(token0Amount, 0, Constants.MAX_FUZZED_AMOUNT);
        token1Amount = bound(token1Amount, 0, Constants.MAX_FUZZED_AMOUNT);
        TokenDelta delta = tokenDeltaLib.fromAmounts(token0Amount, token1Amount);

        // When: Reading both magnitudes back.
        (uint256 token0Out, uint256 token1Out) = tokenDeltaLib.toAmounts(delta);

        // Then: They equal the original magnitudes.
        assertEq(token0Out, token0Amount);
        assertEq(token1Out, token1Amount);
    }
}
