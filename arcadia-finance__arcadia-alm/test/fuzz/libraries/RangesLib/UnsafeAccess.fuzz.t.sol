/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Range } from "../../../../src/core/types/Range.sol";
import { RangesLib_Fuzz_Test } from "./_RangesLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "unsafeAccess" of library "RangesLib".
 */
// forge-lint: disable-next-item(calls-loop, uninitialized-local)
contract UnsafeAccess_RangesLib_Fuzz_Test is RangesLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_unsafeAccess_ReadsEveryRange(
        PoolState memory poolState,
        Range[4] memory ranges,
        uint256 count
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: Some ranges with fuzzed fields.
        count = bound(count, 1, ranges.length);
        for (uint256 i; i < count; ++i) {
            rangesLib.pushRange(ranges[i]);
        }

        for (uint256 i; i < count; ++i) {
            // When: Reading the range at that index without a length check.
            Range memory read = rangesLib.unsafeAccess(i);

            // Then: Every field equals the checked read.
            Range memory checked = rangesLib.getRange(i);
            assertEq(read.stakedLiquidity, checked.stakedLiquidity);
            assertEq(read.tickLower, checked.tickLower);
            assertEq(read.tickUpper, checked.tickUpper);
            assertEq(read.unstakedTokenId, checked.unstakedTokenId);
            assertEq(read.stakedTokenId, checked.stakedTokenId);
            assertEq(read.stakedBlock, checked.stakedBlock);
        }
    }
}
