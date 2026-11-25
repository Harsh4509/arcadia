/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CoreImmutables } from "../../../../src/core/types/CoreImmutables.sol";
import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { PlanCache } from "../../../../src/core/types/PlanCache.sol";
import { PlanCacheLib_Fuzz_Test } from "./_PlanCacheLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "start" of library "PlanCacheLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract Start_PlanCacheLib_Fuzz_Test is PlanCacheLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_start_ReturnsTheVaultValue(
        uint160 trustedSqrtPriceX96,
        uint128 amount0,
        uint128 amount1,
        uint128 buffer0,
        uint128 buffer1,
        uint256 supply
    ) public {
        // Given: Buffers, and a trusted price in the band.
        planCacheLib.setBuffers(buffer0, buffer1);
        trustedSqrtPriceX96 = uint160(
            bound(
                trustedSqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );

        // When: Starting an execution on the principal of every range.
        PlanCache memory cache = planCacheLib.start(trustedSqrtPriceX96, trustedSqrtPriceX96, supply, amount0, amount1);

        // Then: It starts on the principal plus the buffer, in token1 at the price.
        assertEq(
            cache.valueBefore,
            uint256(amount1) + buffer1
                + FixedPointMathLib.fullMulDiv(
                    uint256(amount0) + buffer0, uint256(trustedSqrtPriceX96) * trustedSqrtPriceX96, 1 << 192
                )
        );

        // And: It holds each token's principal plus its buffer.
        assertEq(cache.amount0, int256(uint256(amount0) + buffer0));
        assertEq(cache.amount1, int256(uint256(amount1) + buffer1));
    }

    function testFuzz_Success_start_ReturnsTheStartingValues(
        uint160 trustedSqrtPriceX96,
        uint160 spotSqrtPriceX96,
        uint256 supply,
        CoreImmutables memory immutables
    ) public {
        // Given: The immutables of the core.
        planCacheLib.setImmutables(immutables);

        // When: Starting an execution at a trusted price and a spot price.
        PlanCache memory cache = planCacheLib.start(trustedSqrtPriceX96, spotSqrtPriceX96, supply, 0, 0);

        // Then: It holds both prices, the starting supply and the core's immutables.
        assertEq(cache.trustedSqrtPriceX96, trustedSqrtPriceX96);
        assertEq(cache.spotSqrtPriceX96, spotSqrtPriceX96);
        assertEq(cache.supplyBefore, supply);
        assertEq(keccak256(abi.encode(cache.immutables)), keccak256(abi.encode(immutables)));

        // And: No range is opened, no queue is closed and no swap has run.
        assertEq(cache.openedRanges, 0);
        assertEq(cache.depositAssets0, 0);
        assertEq(cache.depositAssets1, 0);
        assertEq(cache.redeemShares0, 0);
        assertEq(cache.redeemShares1, 0);
        assertEq(cache.swapDelta.amount0(), 0);
        assertEq(cache.swapDelta.amount1(), 0);
    }
}
