/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { PoolLogic_Fuzz_Test } from "./_PoolLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "liquidity" of library "PoolLogic".
 */
contract Liquidity_PoolLogic_Fuzz_Test is PoolLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_liquidity_ReadsThePoolsActiveLiquidity(
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

        // When: Reading the active liquidity.
        uint128 liquidity = poolLogic.liquidity(address(pool));

        // Then: It is the pool's in-range liquidity.
        assertEq(liquidity, pool.liquidity());
    }
}
