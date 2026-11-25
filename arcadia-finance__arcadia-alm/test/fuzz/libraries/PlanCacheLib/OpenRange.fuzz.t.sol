/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PlanCache } from "../../../../src/core/types/PlanCache.sol";
import { PlanCacheLib_Fuzz_Test } from "./_PlanCacheLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "openRange" of library "PlanCacheLib".
 */
contract OpenRange_PlanCacheLib_Fuzz_Test is PlanCacheLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_openRange_MarksOnlyThatIndex(uint256 index, uint256 untouched, uint256 marked)
        public
        view
    {
        // Given: An index that neither call marks.
        untouched = bound(untouched, 0, type(uint8).max);

        // And: A running execution that already marked another index.
        PlanCache memory cache;
        marked = bound(marked, 0, type(uint8).max - 1);
        if (marked >= untouched) ++marked;
        cache = planCacheLib.openRange(cache, marked);

        // And: A third index, possibly the marked one.
        index = bound(index, 0, type(uint8).max - 1);
        if (index >= untouched) ++index;

        // When: Marking the index.
        cache = planCacheLib.openRange(cache, index);

        // Then: The index and the earlier mark are opened, and nothing else.
        assertTrue(planCacheLib.isOpenedRange(cache, index));
        assertTrue(planCacheLib.isOpenedRange(cache, marked));
        assertFalse(planCacheLib.isOpenedRange(cache, untouched));
    }

    function testFuzz_Success_openRange_MarkingTwiceKeepsItOpened(uint256 index) public view {
        // Given: A running execution that already marked an index.
        PlanCache memory cache;
        index = bound(index, 0, type(uint8).max);
        cache = planCacheLib.openRange(cache, index);

        // When: Marking the same index again.
        cache = planCacheLib.openRange(cache, index);

        // Then: It is still opened.
        assertTrue(planCacheLib.isOpenedRange(cache, index));
    }
}
