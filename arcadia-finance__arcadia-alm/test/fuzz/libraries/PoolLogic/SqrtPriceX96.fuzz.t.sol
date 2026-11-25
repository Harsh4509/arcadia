/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { PoolLogic_Fuzz_Test } from "./_PoolLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "sqrtPriceX96" of library "PoolLogic".
 */
contract SqrtPriceX96_PoolLogic_Fuzz_Test is PoolLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_sqrtPriceX96_ReadsThePoolsPrice(
        PoolState memory poolState,
        uint256 amountIn,
        bool zeroForOne
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A trade that moved the price either way.
        amountIn = bound(amountIn, 1, Constants.MAX_FUZZED_AMOUNT);
        (zeroForOne ? token0 : token1).mint(users.unprivilegedAddress, amountIn);
        pushPrice(pool, users.unprivilegedAddress, zeroForOne, amountIn);

        // When: Reading the spot price.
        uint160 spotPrice = poolLogic.sqrtPriceX96(address(pool));

        // Then: It is the pool's current price.
        assertEq(spotPrice, sqrtPriceX96(pool));
    }
}
