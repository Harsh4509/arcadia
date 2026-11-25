/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { Range } from "../../../../src/core/types/Range.sol";

/**
 * @notice Fuzz tests for the function "decodeRanges" of library "ALMCoreViewLogic".
 */
contract DecodeRanges_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_decodeRanges_ReadsEveryFieldOfEveryRange(
        PoolState memory poolState,
        Range[3] memory fuzzed,
        uint256 count
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Up to three ranges, every field fuzzed, pushed through the accessor.
        count = bound(count, 0, fuzzed.length);
        for (uint256 i; i < count; ++i) {
            almCore.pushRange(fuzzed[i]);
        }

        // When: Decoding the ranges' words.
        Range[] memory ranges = coreViewLogic.decodeRanges(coreViewLogic.readRangeWords(address(almCore)));

        // Then: Every field of every range reads back.
        assertEq(ranges.length, count);
        for (uint256 i; i < count; ++i) {
            assertEq(ranges[i].stakedLiquidity, fuzzed[i].stakedLiquidity);
            assertEq(ranges[i].tickLower, fuzzed[i].tickLower);
            assertEq(ranges[i].tickUpper, fuzzed[i].tickUpper);
            assertEq(ranges[i].unstakedTokenId, fuzzed[i].unstakedTokenId);
            assertEq(ranges[i].stakedTokenId, fuzzed[i].stakedTokenId);
            assertEq(ranges[i].stakedBlock, fuzzed[i].stakedBlock);
        }
    }
}
