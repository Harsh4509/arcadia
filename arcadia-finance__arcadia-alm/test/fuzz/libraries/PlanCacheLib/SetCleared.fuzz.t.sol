/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PlanCache } from "../../../../src/core/types/PlanCache.sol";
import { PlanCacheLib_Fuzz_Test } from "./_PlanCacheLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setCleared" of library "PlanCacheLib".
 */
contract SetCleared_PlanCacheLib_Fuzz_Test is PlanCacheLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_setCleared_WritesOnlyTheQueuesField(
        PlanCache memory cache,
        bool isDeposit,
        bool isToken0,
        uint256 cleared
    ) public view {
        // Given: A plan that cleared any amount of each queue.
        // When: Setting the amount cleared of one queue.
        PlanCache memory cacheAfter = planCacheLib.setCleared(cache, isDeposit, isToken0, cleared);

        // Then: That queue's field holds the amount, the other queues' fields are kept.
        assertEq(cacheAfter.depositAssets0, isDeposit && isToken0 ? cleared : cache.depositAssets0);
        assertEq(cacheAfter.depositAssets1, isDeposit && !isToken0 ? cleared : cache.depositAssets1);
        assertEq(cacheAfter.redeemShares0, !isDeposit && isToken0 ? cleared : cache.redeemShares0);
        assertEq(cacheAfter.redeemShares1, !isDeposit && !isToken0 ? cleared : cache.redeemShares1);

        // And: The rest of the plan is kept.
        assertEq(cacheAfter.openedRanges, cache.openedRanges);
        assertEq(cacheAfter.supplyBefore, cache.supplyBefore);
        assertEq(cacheAfter.valueBefore, cache.valueBefore);
        assertEq(cacheAfter.amount0, cache.amount0);
        assertEq(cacheAfter.amount1, cache.amount1);
    }
}
