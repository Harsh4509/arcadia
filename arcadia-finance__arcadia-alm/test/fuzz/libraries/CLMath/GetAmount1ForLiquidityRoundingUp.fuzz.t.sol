/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CLMath_Fuzz_Test } from "./_CLMath.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getAmount1ForLiquidityRoundingUp" of library "CLMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetAmount1ForLiquidityRoundingUp_CLMath_Fuzz_Test is CLMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getAmount1ForLiquidityRoundingUp_BuysTheLiquidityBack(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public view {
        // Given: An ascending range.
        sqrtPriceAX96 = uint160(bound(sqrtPriceAX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 2));
        sqrtPriceBX96 = uint160(bound(sqrtPriceBX96, sqrtPriceAX96 + 1, TickMath.MAX_SQRT_PRICE - 1));

        // When: Computing the token1 amount.
        uint256 amount1 = clMath.getAmount1ForLiquidityRoundingUp(sqrtPriceAX96, sqrtPriceBX96, liquidity);

        // Then: It is the least amount the manager derives at least the liquidity from.
        assertLeastAmounts(sqrtPriceBX96, sqrtPriceAX96, sqrtPriceBX96, liquidity, 0, amount1);
    }
}
