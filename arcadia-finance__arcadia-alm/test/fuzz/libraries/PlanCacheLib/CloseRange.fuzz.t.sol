/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PlanCache } from "../../../../src/core/types/PlanCache.sol";
import { PlanCacheLib_Fuzz_Test } from "./_PlanCacheLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "closeRange" of library "PlanCacheLib".
 */
contract CloseRange_PlanCacheLib_Fuzz_Test is PlanCacheLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_closeRange_MovesTheLastMarkOntoTheIndex(
        uint256 index,
        uint256 last,
        bool indexMarked,
        uint256 untouched
    ) public view {
        // Given: A closed range's index below the last index, marked or not.
        PlanCache memory cache;
        last = bound(last, 1, type(uint8).max);
        index = bound(index, 0, last - 1);
        if (indexMarked) cache = planCacheLib.openRange(cache, index);

        // And: The last range marked opened, and an untouched index that is also marked.
        cache = planCacheLib.openRange(cache, last);
        untouched = bound(untouched, 0, type(uint8).max - 2);
        if (untouched >= index) ++untouched;
        if (untouched >= last) ++untouched;
        cache = planCacheLib.openRange(cache, untouched);

        // When: Removing the closed range's mark.
        cache = planCacheLib.closeRange(cache, index, last);

        // Then: The index carries the last range's mark and the last index is cleared.
        assertTrue(planCacheLib.isOpenedRange(cache, index));
        assertFalse(planCacheLib.isOpenedRange(cache, last));

        // And: The untouched index keeps its mark.
        assertTrue(planCacheLib.isOpenedRange(cache, untouched));
    }

    function testFuzz_Success_closeRange_ClearsTheIndexWhenTheLastIsUnmarked(uint256 index, uint256 last) public view {
        // Given: A marked closed range's index below the last, the last range not marked.
        PlanCache memory cache;
        last = bound(last, 1, type(uint8).max);
        index = bound(index, 0, last - 1);
        cache = planCacheLib.openRange(cache, index);

        // When: Removing the closed range's mark.
        cache = planCacheLib.closeRange(cache, index, last);

        // Then: Neither index is marked.
        assertFalse(planCacheLib.isOpenedRange(cache, index));
        assertFalse(planCacheLib.isOpenedRange(cache, last));
    }

    function testFuzz_Success_closeRange_ClosingTheLastClearsIt(uint256 last, uint256 untouched) public view {
        // Given: The last range marked opened, and another marked index.
        PlanCache memory cache;
        last = bound(last, 0, type(uint8).max);
        cache = planCacheLib.openRange(cache, last);
        untouched = bound(untouched, 0, type(uint8).max - 1);
        if (untouched >= last) ++untouched;
        cache = planCacheLib.openRange(cache, untouched);

        // When: Removing the last range's own mark.
        cache = planCacheLib.closeRange(cache, last, last);

        // Then: Its mark is cleared and the other is kept.
        assertFalse(planCacheLib.isOpenedRange(cache, last));
        assertTrue(planCacheLib.isOpenedRange(cache, untouched));
    }
}
