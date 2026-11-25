/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { LiquidityAmounts } from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import { CLMath_Fuzz_Test } from "./_CLMath.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getPrincipalAmounts" of library "CLMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetPrincipalAmounts_CLMath_Fuzz_Test is CLMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getPrincipalAmounts_MatchesTheTicksTranslatedToPrices(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public view {
        // Given: An ascending tick range inside the pool's usable range.
        tickLower = int24(bound(tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        tickUpper = int24(bound(tickUpper, tickLower + 1, TickMath.MAX_TICK));

        // And: A price anywhere the pool can reach.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // When: Computing the principal from ticks.
        (uint256 amount0, uint256 amount1) = clMath.getPrincipalAmounts(sqrtPriceX96, tickLower, tickUpper, liquidity);

        // Then: It is Uniswap's LiquidityAmounts at the ticks' prices, rounded down.
        (uint256 expected0, uint256 expected1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96, TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), liquidity
        );
        assertEq(amount0, expected0);
        assertEq(amount1, expected1);
    }
}
