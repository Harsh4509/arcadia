/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PoolLogic_Fuzz_Test } from "./_PoolLogic.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "sqrtPriceLimit" of library "PoolLogic".
 */
contract SqrtPriceLimit_PoolLogic_Fuzz_Test is PoolLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_sqrtPriceLimit_ZeroForOne(PoolState memory poolState) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // When: Reading the bound of a swap that sells token0.
        uint160 sqrtPriceLimitX96 = poolLogic.sqrtPriceLimit(true);

        // Then: It is the lowest bound the pool accepts, below spot.
        assertEq(sqrtPriceLimitX96, TickMath.MIN_SQRT_PRICE + 1);
        assertLt(sqrtPriceLimitX96, sqrtPriceX96(pool));
    }

    function testFuzz_Success_sqrtPriceLimit_OneForZero(PoolState memory poolState) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // When: Reading the bound of a swap that sells token1.
        uint160 sqrtPriceLimitX96 = poolLogic.sqrtPriceLimit(false);

        // Then: It is the highest bound the pool accepts, above spot.
        assertEq(sqrtPriceLimitX96, TickMath.MAX_SQRT_PRICE - 1);
        assertGt(sqrtPriceLimitX96, sqrtPriceX96(pool));
    }
}
