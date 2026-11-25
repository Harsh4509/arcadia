/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { PlanCache } from "../../../../src/core/types/PlanCache.sol";
import { PlanCacheLib_Fuzz_Test } from "./_PlanCacheLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getOwed" of library "PlanCacheLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetOwed_PlanCacheLib_Fuzz_Test is PlanCacheLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getOwed_ZeroWithoutARedeem(SettlementState memory state, bool isToken0) public view {
        // Given: A core at a trusted price in the band, with deposits and no redeem.
        state.sqrtPrice = uint160(
            bound(
                state.sqrtPrice,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );
        state.supply = bound(state.supply, 0, Constants.MAX_FUZZED_AMOUNT);
        state.held0 = bound(state.held0, 0, Constants.MAX_FUZZED_AMOUNT);
        state.held1 = bound(state.held1, 0, Constants.MAX_FUZZED_AMOUNT);
        state.deposit0 = bound(state.deposit0, 0, Constants.MAX_FUZZED_AMOUNT);
        state.deposit1 = bound(state.deposit1, 0, Constants.MAX_FUZZED_AMOUNT);
        (state.redeem0, state.redeem1, state.swap0, state.swap1, state.other0, state.other1) = (0, 0, 0, 0, 0, 0);
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the payout owed in either token.
        (uint256 owed0, uint256 owed1) = planCacheLib.getOwed(cache);
        uint256 owed = isToken0 ? owed0 : owed1;

        // Then: Nothing is owed.
        assertEq(owed, 0);
    }

    function testFuzz_Success_getOwed_ZeroWithoutARedeemOnAnEmptySupply(SettlementState memory state, bool isToken0)
        public
        view
    {
        // Given: A core at a trusted price in the band, no supply, deposits, no redeem.
        state.sqrtPrice = uint160(
            bound(
                state.sqrtPrice,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );
        state.supply = 0;
        state.held0 = bound(state.held0, 0, Constants.MAX_FUZZED_AMOUNT);
        state.held1 = bound(state.held1, 0, Constants.MAX_FUZZED_AMOUNT);
        state.deposit0 = bound(state.deposit0, 0, Constants.MAX_FUZZED_AMOUNT);
        state.deposit1 = bound(state.deposit1, 0, Constants.MAX_FUZZED_AMOUNT);
        (state.redeem0, state.redeem1, state.swap0, state.swap1, state.other0, state.other1) = (0, 0, 0, 0, 0, 0);
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the payout owed in either token.
        (uint256 owed0, uint256 owed1) = planCacheLib.getOwed(cache);
        uint256 owed = isToken0 ? owed0 : owed1;

        // Then: Nothing is owed.
        assertEq(owed, 0);
    }

    function testFuzz_Success_getOwed_RedeemSharesAtPriceOne(SettlementState memory state, bool isToken0) public view {
        // Given: A core at a price of one, a share worth one, and pending deposits.
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.held0 = bound(state.held0, 0, Constants.MAX_FUZZED_AMOUNT);
        state.held1 = bound(state.held1, 1, Constants.MAX_FUZZED_AMOUNT);
        state.supply = state.held0 + state.held1;
        state.deposit0 = bound(state.deposit0, 0, Constants.MAX_FUZZED_AMOUNT);
        state.deposit1 = bound(state.deposit1, 0, Constants.MAX_FUZZED_AMOUNT);
        (state.swap0, state.swap1, state.other0, state.other1) = (0, 0, 0, 0);

        // And: A cleared redeem in each vault.
        state.redeem0 = bound(state.redeem0, 1, state.supply);
        state.redeem1 = bound(state.redeem1, 1, state.supply);
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the payout owed in one token.
        (uint256 owed0, uint256 owed1) = planCacheLib.getOwed(cache);
        uint256 owed = isToken0 ? owed0 : owed1;

        // Then: The vault is owed its redeem shares' value, the deposits left out.
        uint256 redeem = isToken0 ? state.redeem0 : state.redeem1;
        assertEq(owed, redeem);
    }

    function testFuzz_Success_getOwed_Token0AtATrustedPrice(SettlementState memory state) public view {
        // Given: A trusted price in the band, small amounts, token1 held, deposits.
        state.sqrtPrice = uint160(
            bound(
                state.sqrtPrice,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );
        state.supply = bound(state.supply, 1, Constants.MAX_FUZZED_AMOUNT);
        uint256 priceX192 = uint256(state.sqrtPrice) * state.sqrtPrice;
        uint256 most0 = FixedPointMathLib.min(
            Constants.MAX_FUZZED_AMOUNT, FullMath.mulDiv(Constants.MAX_FUZZED_AMOUNT, 1 << 192, priceX192)
        );
        uint256 most1 = FixedPointMathLib.min(
            Constants.MAX_FUZZED_AMOUNT, FullMath.mulDiv(Constants.MAX_FUZZED_AMOUNT, priceX192, 1 << 192)
        );
        state.held0 = bound(state.held0, 0, most0);
        state.held1 = bound(state.held1, 1, FixedPointMathLib.max(most1, 1));
        state.deposit0 = bound(state.deposit0, 0, most0);
        state.deposit1 = bound(state.deposit1, 0, most1);
        (state.swap0, state.swap1, state.other0, state.other1) = (0, 0, 0, 0);

        // And: A cleared token0 redeem.
        state.redeem0 = bound(state.redeem0, 1, state.supply);
        state.redeem1 = 0;
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the token0 payout owed.
        (uint256 owed,) = planCacheLib.getOwed(cache);

        // Then: The redeem's share of the existing aLP's value, in token0 at the price.
        uint256 value = state.held1 + FullMath.mulDiv(state.held0, priceX192, 1 << 192);
        assertEq(owed, FullMath.mulDiv(FullMath.mulDiv(state.redeem0, value, state.supply), 1 << 192, priceX192));
    }

    function testFuzz_Success_getOwed_Token1AtATrustedPrice(SettlementState memory state) public view {
        // Given: A trusted price in the band, small amounts, token1 held, deposits.
        state.sqrtPrice = uint160(
            bound(
                state.sqrtPrice,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );
        state.supply = bound(state.supply, 1, Constants.MAX_FUZZED_AMOUNT);
        uint256 priceX192 = uint256(state.sqrtPrice) * state.sqrtPrice;
        uint256 most0 = FixedPointMathLib.min(
            Constants.MAX_FUZZED_AMOUNT, FullMath.mulDiv(Constants.MAX_FUZZED_AMOUNT, 1 << 192, priceX192)
        );
        uint256 most1 = FixedPointMathLib.min(
            Constants.MAX_FUZZED_AMOUNT, FullMath.mulDiv(Constants.MAX_FUZZED_AMOUNT, priceX192, 1 << 192)
        );
        state.held0 = bound(state.held0, 0, most0);
        state.held1 = bound(state.held1, 1, FixedPointMathLib.max(most1, 1));
        state.deposit0 = bound(state.deposit0, 0, most0);
        state.deposit1 = bound(state.deposit1, 0, most1);
        (state.swap0, state.swap1, state.other0, state.other1) = (0, 0, 0, 0);

        // And: A cleared token1 redeem.
        state.redeem0 = 0;
        state.redeem1 = bound(state.redeem1, 1, state.supply);
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the token1 payout owed.
        (, uint256 owed) = planCacheLib.getOwed(cache);

        // Then: The redeem's share of the existing aLP's value at the trusted price.
        uint256 value = state.held1 + FullMath.mulDiv(state.held0, priceX192, 1 << 192);
        assertEq(owed, FullMath.mulDiv(state.redeem1, value, state.supply));
    }
}
