/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PlanCache } from "../../../../src/core/types/PlanCache.sol";
import { PlanCacheLib_Fuzz_Test } from "./_PlanCacheLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "isOpenedRange" of library "PlanCacheLib".
 */
contract IsOpenedRange_PlanCacheLib_Fuzz_Test is PlanCacheLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_isOpenedRange_FalseWhenNotMarked(uint256 index, uint256 marked) public view {
        // Given: A running execution that marked another index.
        PlanCache memory cache;
        index = bound(index, 0, type(uint8).max);
        marked = bound(marked, 0, type(uint8).max - 1);
        if (marked >= index) ++marked;
        cache = planCacheLib.openRange(cache, marked);

        // When: Reading whether the index was opened.
        // Then: It was not.
        assertFalse(planCacheLib.isOpenedRange(cache, index));
    }

    function testFuzz_Success_isOpenedRange_TrueWhenMarked(uint256 index) public view {
        // Given: A running execution that marked the index.
        PlanCache memory cache;
        index = bound(index, 0, type(uint8).max);
        cache = planCacheLib.openRange(cache, index);

        // When: Reading whether the index was opened.
        // Then: It was.
        assertTrue(planCacheLib.isOpenedRange(cache, index));
    }
}
