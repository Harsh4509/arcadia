/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FixedPoint96 } from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { CLMath } from "../../../../src/shared/libraries/math/CLMath.sol";
import { CLMath_Fuzz_Test } from "./_CLMath.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getAmount0ForLiquidityRoundingUp" of library "CLMath".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract GetAmount0ForLiquidityRoundingUp_CLMath_Fuzz_Test is CLMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getAmount0ForLiquidityRoundingUp_NoLiquidityForToken0(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public {
        // Given: An ascending range whose bounds multiply to under the manager's unit.
        sqrtPriceAX96 = uint160(bound(sqrtPriceAX96, TickMath.MIN_SQRT_PRICE, Constants.SQRT_Q96 - 1));
        sqrtPriceBX96 = uint160(bound(sqrtPriceBX96, sqrtPriceAX96 + 1, (FixedPoint96.Q96 - 1) / sqrtPriceAX96));

        // When: Computing the token0 amount.
        // Then: It reverts.
        vm.expectRevert(CLMath.NoLiquidityForToken0.selector);
        clMath.getAmount0ForLiquidityRoundingUp(sqrtPriceAX96, sqrtPriceBX96, liquidity);
    }

    function testFuzz_Success_getAmount0ForLiquidityRoundingUp_BuysTheLiquidityBack(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public view {
        // Given: An ascending range token0 buys liquidity in.
        sqrtPriceAX96 = uint160(bound(sqrtPriceAX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 3));
        uint256 earning = FullMath.mulDivRoundingUp(FixedPoint96.Q96, 1, sqrtPriceAX96);
        sqrtPriceBX96 = uint160(
            bound(sqrtPriceBX96, earning > sqrtPriceAX96 + 2 ? earning : sqrtPriceAX96 + 2, TickMath.MAX_SQRT_PRICE - 1)
        );
        uint256 intermediate = FullMath.mulDiv(sqrtPriceAX96, sqrtPriceBX96, FixedPoint96.Q96);
        uint256 span = sqrtPriceBX96 - sqrtPriceAX96;
        liquidity = uint128(
            bound(
                liquidity,
                0,
                intermediate >= span ? type(uint128).max : FullMath.mulDiv(type(uint128).max, intermediate, span)
            )
        );

        // When: Computing the token0 amount.
        uint256 amount0 = clMath.getAmount0ForLiquidityRoundingUp(sqrtPriceAX96, sqrtPriceBX96, liquidity);

        // Then: It is the least amount the manager derives at least the liquidity from.
        assertLeastAmounts(sqrtPriceAX96, sqrtPriceAX96, sqrtPriceBX96, liquidity, amount0, 0);
    }
}
