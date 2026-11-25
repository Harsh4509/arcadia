/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { PlanCache } from "../../../../src/core/types/PlanCache.sol";
import { PlanCacheLib_Fuzz_Test } from "./_PlanCacheLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getValueAfter" of library "PlanCacheLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetValueAfter_PlanCacheLib_Fuzz_Test is PlanCacheLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getValueAfter_EndHoldingsAtTheTrustedPrice(
        uint256 sqrtPrice,
        uint256 held0,
        uint256 held1,
        bool sells,
        uint256 amountIn,
        uint256 amountOut
    ) public view {
        // Given: A core at a trusted price in the band.
        SettlementState memory state;
        state.sqrtPrice = uint160(
            bound(
                sqrtPrice,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );
        state.held0 = bound(held0, 1, Constants.MAX_FUZZED_AMOUNT);
        state.held1 = bound(held1, 1, Constants.MAX_FUZZED_AMOUNT);

        // And: A swap in either direction.
        amountOut = bound(amountOut, 0, Constants.MAX_FUZZED_AMOUNT);
        amountIn = bound(amountIn, 1, sells ? state.held0 : state.held1);
        (state.swap0, state.swap1) =
            sells ? (-int256(amountIn), int256(amountOut)) : (int256(amountOut), -int256(amountIn));
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the value after.
        uint256 valueAfter = planCacheLib.getValueAfter(cache);

        // Then: It is the end holdings at the trusted price.
        uint256 priceX192 = uint256(state.sqrtPrice) * state.sqrtPrice;
        assertEq(
            valueAfter,
            sells
                ? FullMath.mulDiv(state.held0 - amountIn, priceX192, 1 << 192) + state.held1 + amountOut
                : FullMath.mulDiv(state.held0 + amountOut, priceX192, 1 << 192) + state.held1 - amountIn
        );
    }

    function testFuzz_Success_getValueAfter_HoldingsBelowZeroValuedAtZero(
        uint256 sqrtPrice,
        uint256 held,
        uint256 owed,
        bool owesToken0
    ) public view {
        // Given: A core at a trusted price in the band holding one token.
        SettlementState memory state;
        state.sqrtPrice = uint160(
            bound(
                sqrtPrice,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );
        held = bound(held, 0, Constants.MAX_FUZZED_AMOUNT);
        owed = bound(owed, 1, Constants.MAX_FUZZED_AMOUNT);

        // And: Steps that left the other token's holdings below zero.
        if (owesToken0) (state.held1, state.other0) = (held, -int256(owed));
        else (state.held0, state.other1) = (held, -int256(owed));
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the value after.
        uint256 valueAfter = planCacheLib.getValueAfter(cache);

        // Then: It is the held token's value alone.
        assertEq(
            valueAfter, owesToken0 ? held : FullMath.mulDiv(held, uint256(state.sqrtPrice) * state.sqrtPrice, 1 << 192)
        );
    }
}
