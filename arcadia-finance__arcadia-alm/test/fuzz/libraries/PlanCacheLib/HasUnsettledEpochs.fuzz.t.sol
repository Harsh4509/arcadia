/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PlanCache } from "../../../../src/core/types/PlanCache.sol";
import { PlanCacheLib_Fuzz_Test } from "./_PlanCacheLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "hasUnsettledEpochs" of library "PlanCacheLib".
 */
contract HasUnsettledEpochs_PlanCacheLib_Fuzz_Test is PlanCacheLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_hasUnsettledEpochs_FalseWhenNothingCleared(PlanCache memory cache) public view {
        // Given: A plan that cleared nothing of any queue.
        (cache.depositAssets0, cache.depositAssets1, cache.redeemShares0, cache.redeemShares1) = (0, 0, 0, 0);

        // When: Reading whether it has unsettled epochs.
        // Then: It has none.
        assertFalse(planCacheLib.hasUnsettledEpochs(cache));
    }

    function testFuzz_Success_hasUnsettledEpochs_TrueWhenAnyQueueCleared(
        PlanCache memory cache,
        bool isDeposit,
        bool isToken0,
        uint256 cleared
    ) public view {
        // Given: A plan that cleared some of one queue, the others any amount.
        cleared = bound(cleared, 1, type(uint256).max);
        cache = planCacheLib.setCleared(cache, isDeposit, isToken0, cleared);

        // When: Reading whether it has unsettled epochs.
        // Then: It has.
        assertTrue(planCacheLib.hasUnsettledEpochs(cache));
    }
}
