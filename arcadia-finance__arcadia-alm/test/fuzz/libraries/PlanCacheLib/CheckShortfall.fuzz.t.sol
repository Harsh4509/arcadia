/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { PlanCache, PlanCacheLib } from "../../../../src/core/types/PlanCache.sol";
import { PlanCacheLib_Fuzz_Test } from "./_PlanCacheLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "checkShortfall" of library "PlanCacheLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract CheckShortfall_PlanCacheLib_Fuzz_Test is PlanCacheLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_checkShortfall_MaxShortfallExceeded(
        uint16 maxShortfallBps,
        uint128 valueBefore,
        uint256 valueAfter,
        uint96 supplyBefore,
        uint96 supplyAfter
    ) public {
        // Given: A loss ceiling short of the whole value.
        maxShortfallBps = uint16(bound(maxShortfallBps, 0, ConfigLib.BPS_DENOMINATOR - 1));
        planCacheLib.setMaxShortfallBps(maxShortfallBps);

        // And: Supplies before and after the plan, and the least value per share allowed.
        supplyBefore = uint96(bound(supplyBefore, 1, type(uint96).max));
        supplyAfter = uint96(bound(supplyAfter, 1, type(uint96).max));
        valueBefore = uint128(
            bound(
                valueBefore,
                FixedPointMathLib.divUp(ConfigLib.BPS_DENOMINATOR, ConfigLib.BPS_DENOMINATOR - maxShortfallBps),
                type(uint128).max
            )
        );
        uint256 least = uint256(valueBefore) * (ConfigLib.BPS_DENOMINATOR - maxShortfallBps) / ConfigLib.BPS_DENOMINATOR;

        // And: A value after the plan that leaves each share worth less than that.
        valueAfter = bound(valueAfter, 0, FixedPointMathLib.fullMulDivUp(least, supplyAfter, supplyBefore) - 1);

        // And: An execution that started on that supply and value.
        PlanCache memory cache;
        (cache.supplyBefore, cache.valueBefore) = (supplyBefore, valueBefore);

        // When: Checking the loss.
        // Then: It reverts.
        vm.expectRevert(PlanCacheLib.MaxShortfallExceeded.selector);
        planCacheLib.checkShortfall(cache, valueAfter, supplyAfter);
    }

    function testFuzz_Success_checkShortfall_WithinMaxShortfall(
        uint16 maxShortfallBps,
        uint128 valueBefore,
        uint256 valueAfter,
        uint96 supplyBefore,
        uint96 supplyAfter
    ) public {
        // Given: A loss ceiling.
        maxShortfallBps = uint16(bound(maxShortfallBps, 0, ConfigLib.BPS_DENOMINATOR));
        planCacheLib.setMaxShortfallBps(maxShortfallBps);

        // And: Supplies before and after the plan, and the least value per share allowed.
        supplyBefore = uint96(bound(supplyBefore, 1, type(uint96).max));
        supplyAfter = uint96(bound(supplyAfter, 1, type(uint96).max));
        uint256 least = uint256(valueBefore) * (ConfigLib.BPS_DENOMINATOR - maxShortfallBps) / ConfigLib.BPS_DENOMINATOR;

        // And: A value after the plan that leaves each share worth at least that.
        uint256 floor = FixedPointMathLib.fullMulDivUp(least, supplyAfter, supplyBefore);
        valueAfter = bound(valueAfter, floor, floor + type(uint128).max);

        // And: An execution that started on that supply and value.
        PlanCache memory cache;
        (cache.supplyBefore, cache.valueBefore) = (supplyBefore, valueBefore);

        // When: Checking the loss.
        (bool success,) = address(planCacheLib)
            .staticcall(abi.encodeCall(planCacheLib.checkShortfall, (cache, valueAfter, supplyAfter)));

        // Then: It does not revert.
        assertTrue(success);
    }

    function testFuzz_Success_checkShortfall_ExactlyAtTheFloor(
        uint16 maxShortfallBps,
        uint128 valueBefore,
        uint96 supplyBefore,
        uint96 supplyAfter
    ) public {
        // Given: A loss ceiling short of the whole value.
        maxShortfallBps = uint16(bound(maxShortfallBps, 0, ConfigLib.BPS_DENOMINATOR - 1));
        planCacheLib.setMaxShortfallBps(maxShortfallBps);

        // And: Supplies before and after the plan, and the least value per share allowed.
        supplyBefore = uint96(bound(supplyBefore, 1, type(uint96).max));
        supplyAfter = uint96(bound(supplyAfter, 1, type(uint96).max));
        valueBefore = uint128(
            bound(
                valueBefore,
                FixedPointMathLib.divUp(ConfigLib.BPS_DENOMINATOR, ConfigLib.BPS_DENOMINATOR - maxShortfallBps),
                type(uint128).max
            )
        );
        uint256 least = uint256(valueBefore) * (ConfigLib.BPS_DENOMINATOR - maxShortfallBps) / ConfigLib.BPS_DENOMINATOR;

        // And: A value after the plan exactly at the floor.
        uint256 floor = FixedPointMathLib.fullMulDivUp(least, supplyAfter, supplyBefore);

        // And: An execution that started on that supply and value.
        PlanCache memory cache;
        (cache.supplyBefore, cache.valueBefore) = (supplyBefore, valueBefore);

        // When: Checking the loss at the floor.
        // Then: It does not revert.
        planCacheLib.checkShortfall(cache, floor, supplyAfter);

        // And: One wei below the floor reverts.
        vm.expectRevert(PlanCacheLib.MaxShortfallExceeded.selector);
        planCacheLib.checkShortfall(cache, floor - 1, supplyAfter);
    }
}
