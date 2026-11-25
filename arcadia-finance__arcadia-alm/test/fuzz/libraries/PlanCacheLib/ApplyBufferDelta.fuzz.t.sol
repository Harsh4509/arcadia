/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { PlanCache } from "../../../../src/core/types/PlanCache.sol";
import { PlanCacheLib_Fuzz_Test } from "./_PlanCacheLib.fuzz.t.sol";
import { TokenDeltaLib, toTokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "applyBufferDelta" of library "PlanCacheLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract ApplyBufferDelta_PlanCacheLib_Fuzz_Test is PlanCacheLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_applyBufferDelta_Credit(
        uint160 trustedSqrtPriceX96,
        uint256 supply,
        bool isToken0,
        uint128 credited
    ) public view {
        // Given: A running execution, and a credit of one token.
        PlanCache memory cache = planCacheLib.start(trustedSqrtPriceX96, trustedSqrtPriceX96, supply, 0, 0);
        credited = uint128(bound(credited, 1, Constants.MAX_FUZZED_AMOUNT));

        // When: Applying the credit.
        cache = planCacheLib.applyBufferDelta(cache, TokenDeltaLib.single(isToken0, int128(credited)));

        // Then: The execution holds the credit of that token alone.
        assertEq(cache.amount0, isToken0 ? int128(credited) : int128(0));
        assertEq(cache.amount1, isToken0 ? int128(0) : int128(credited));
    }

    function testFuzz_Success_applyBufferDelta_Take(
        uint160 trustedSqrtPriceX96,
        uint256 supply,
        bool isToken0,
        uint128 taken
    ) public view {
        // Given: A running execution, and a take of one token.
        PlanCache memory cache = planCacheLib.start(trustedSqrtPriceX96, trustedSqrtPriceX96, supply, 0, 0);
        taken = uint128(bound(taken, 1, Constants.MAX_FUZZED_AMOUNT));

        // When: Applying the take.
        cache = planCacheLib.applyBufferDelta(cache, TokenDeltaLib.single(isToken0, -int128(taken)));

        // Then: The execution holds the take of that token alone.
        assertEq(cache.amount0, isToken0 ? -int128(taken) : int128(0));
        assertEq(cache.amount1, isToken0 ? int128(0) : -int128(taken));
    }

    function testFuzz_Success_applyBufferDelta_BothTokens(
        uint160 trustedSqrtPriceX96,
        uint256 supply,
        int128 amount0,
        int128 amount1
    ) public view {
        // Given: A running execution, and a delta moving both tokens.
        PlanCache memory cache = planCacheLib.start(trustedSqrtPriceX96, trustedSqrtPriceX96, supply, 0, 0);
        amount0 = int128(bound(amount0, -type(int128).max, type(int128).max));
        amount1 = int128(bound(amount1, -type(int128).max, type(int128).max));

        // When: Applying the delta.
        cache = planCacheLib.applyBufferDelta(cache, toTokenDelta(amount0, amount1));

        // Then: The execution holds both amounts.
        assertEq(cache.amount0, amount0);
        assertEq(cache.amount1, amount1);
    }

    function testFuzz_Success_applyBufferDelta_ZeroDeltaChangesNothing(
        uint160 trustedSqrtPriceX96,
        uint256 supply,
        int128 earlier0,
        int128 earlier1
    ) public view {
        // Given: A running execution that already holds both tokens.
        PlanCache memory cache = planCacheLib.start(trustedSqrtPriceX96, trustedSqrtPriceX96, supply, 0, 0);
        earlier0 = int128(bound(earlier0, -type(int128).max, type(int128).max));
        earlier1 = int128(bound(earlier1, -type(int128).max, type(int128).max));
        cache = planCacheLib.applyBufferDelta(cache, toTokenDelta(earlier0, earlier1));

        // When: Applying a delta of nothing.
        cache = planCacheLib.applyBufferDelta(cache, toTokenDelta(0, 0));

        // Then: The holdings are unchanged.
        assertEq(cache.amount0, earlier0);
        assertEq(cache.amount1, earlier1);
    }

    function testFuzz_Success_applyBufferDelta_AddsToWhatTheExecutionAlreadyHolds(
        uint160 trustedSqrtPriceX96,
        uint256 supply,
        int128 earlier0,
        int128 earlier1,
        int128 amount0,
        int128 amount1
    ) public view {
        // Given: A running execution that already holds both tokens.
        PlanCache memory cache = planCacheLib.start(trustedSqrtPriceX96, trustedSqrtPriceX96, supply, 0, 0);
        earlier0 = int128(bound(earlier0, -type(int128).max / 2, type(int128).max / 2));
        earlier1 = int128(bound(earlier1, -type(int128).max / 2, type(int128).max / 2));
        cache = planCacheLib.applyBufferDelta(cache, toTokenDelta(earlier0, earlier1));

        // And: A second delta moving both tokens.
        amount0 = int128(bound(amount0, -type(int128).max / 2, type(int128).max / 2));
        amount1 = int128(bound(amount1, -type(int128).max / 2, type(int128).max / 2));

        // When: Applying the second delta.
        cache = planCacheLib.applyBufferDelta(cache, toTokenDelta(amount0, amount1));

        // Then: The holdings are the sum of both.
        assertEq(cache.amount0, earlier0 + amount0);
        assertEq(cache.amount1, earlier1 + amount1);
    }
}
