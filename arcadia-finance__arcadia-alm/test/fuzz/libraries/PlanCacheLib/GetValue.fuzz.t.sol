/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { PlanCacheLib_Fuzz_Test } from "./_PlanCacheLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getValue" of library "PlanCacheLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetValue_PlanCacheLib_Fuzz_Test is PlanCacheLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getValue_BothAmountsAtTheTrustedPrice(
        uint256 sqrtPrice,
        uint256 amount0,
        uint256 amount1,
        bool roundUp
    ) public view {
        // Given: A trusted price in the band, and amounts of both tokens.
        uint160 sqrtPriceX96 = uint160(
            bound(
                sqrtPrice,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );
        amount0 = bound(amount0, 0, Constants.MAX_FUZZED_AMOUNT);
        amount1 = bound(amount1, 0, Constants.MAX_FUZZED_AMOUNT);

        // When: Reading their value.
        uint256 value = planCacheLib.getValue(sqrtPriceX96, int256(amount0), int256(amount1), roundUp);

        // Then: It is the token1 plus the token0 at the price, rounded as asked.
        uint256 priceX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
        assertEq(
            value,
            amount1
                + (roundUp
                        ? FullMath.mulDivRoundingUp(amount0, priceX192, 1 << 192)
                        : FullMath.mulDiv(amount0, priceX192, 1 << 192))
        );
    }

    function testFuzz_Success_getValue_ANegativeAmountValuedAtZero(
        uint256 sqrtPrice,
        uint256 held,
        uint256 owed,
        bool owesToken0,
        bool roundUp
    ) public view {
        // Given: A trusted price in the band, one token held and the other owed.
        uint160 sqrtPriceX96 = uint160(
            bound(
                sqrtPrice,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );
        held = bound(held, 0, Constants.MAX_FUZZED_AMOUNT);
        owed = bound(owed, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: Reading their value.
        uint256 value = owesToken0
            ? planCacheLib.getValue(sqrtPriceX96, -int256(owed), int256(held), roundUp)
            : planCacheLib.getValue(sqrtPriceX96, int256(held), -int256(owed), roundUp);

        // Then: It is the held token's value alone.
        uint256 priceX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
        uint256 heldValue =
            roundUp ? FullMath.mulDivRoundingUp(held, priceX192, 1 << 192) : FullMath.mulDiv(held, priceX192, 1 << 192);
        assertEq(value, owesToken0 ? held : heldValue);
    }
}
