/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PlanCache } from "../../../../src/core/types/PlanCache.sol";
import { PlanCacheLib_Fuzz_Test } from "./_PlanCacheLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "getCleared" of library "PlanCacheLib".
 */
contract GetCleared_PlanCacheLib_Fuzz_Test is PlanCacheLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getCleared_TheQueuesField(PlanCache memory cache, bool isDeposit, bool isToken0)
        public
        view
    {
        // Given: A plan that cleared any amount of each queue.
        // When: Reading the amount cleared of one queue.
        uint256 cleared = planCacheLib.getCleared(cache, isDeposit, isToken0);

        // Then: It is that queue's field.
        if (isDeposit) assertEq(cleared, isToken0 ? cache.depositAssets0 : cache.depositAssets1);
        else assertEq(cleared, isToken0 ? cache.redeemShares0 : cache.redeemShares1);
    }
}
