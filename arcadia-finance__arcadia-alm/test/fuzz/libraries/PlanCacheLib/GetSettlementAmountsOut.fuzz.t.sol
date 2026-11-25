/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { PlanCache, PlanCacheLib } from "../../../../src/core/types/PlanCache.sol";
import { PlanCacheLib_Fuzz_Test } from "./_PlanCacheLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getSettlementAmountsOut" of library "PlanCacheLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetSettlementAmountsOut_PlanCacheLib_Fuzz_Test is PlanCacheLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getSettlementAmountsOut_ZeroValue(uint256 sqrtPrice, uint256 supply, uint256 deposit)
        public
    {
        // Given: An empty core at a trusted price in the band, and a token1 deposit.
        SettlementState memory state;
        state.sqrtPrice = uint160(
            bound(
                sqrtPrice,
                TickMath.getSqrtPriceAtTick(-TickMath.getTickAtSqrtPrice(Constants.BOUND_SQRT_PRICE_UPPER)),
                Constants.BOUND_SQRT_PRICE_UPPER
            )
        );
        state.supply = bound(supply, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        state.deposit1 = bound(deposit, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        // Then: It reverts.
        vm.expectRevert(PlanCacheLib.ZeroValue.selector);
        planCacheLib.getSettlementAmountsOut(cache);
    }

    function testFuzz_Revert_getSettlementAmountsOut_ZeroValue_SwappedDepositAboveTheEndValue(
        uint256 supply,
        uint256 deposit,
        uint256 sold,
        uint256 bought
    ) public {
        // Given: An empty core at a trusted price of one, and a pending token0 deposit.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.supply = bound(supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.deposit0 = bound(deposit, 2, Constants.MAX_SETTLEMENT_AMOUNT);

        // And: Part of the deposit sold below the trusted price.
        sold = bound(sold, 1, state.deposit0);
        bought = bound(bought, 0, sold - 1);
        (state.swap0, state.swap1) = (-int256(sold), int256(bought));
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        // Then: It reverts.
        vm.expectRevert(PlanCacheLib.ZeroValue.selector);
        planCacheLib.getSettlementAmountsOut(cache);
    }

    function testFuzz_Revert_getSettlementAmountsOut_ZeroValue_EqualDepositsInBothTokens(
        uint256 supply,
        uint256 deposit
    ) public {
        // Given: An empty core at a trusted price of one, equal deposits of both tokens.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.supply = bound(supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.deposit0 = bound(deposit, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.deposit1 = state.deposit0;
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        // Then: It reverts.
        vm.expectRevert(PlanCacheLib.ZeroValue.selector);
        planCacheLib.getSettlementAmountsOut(cache);
    }

    function testFuzz_Revert_getSettlementAmountsOut_ZeroSupply(
        uint256 sqrtPrice,
        uint256 held0,
        uint256 held1,
        uint256 deposit
    ) public {
        // Given: A core with value and no supply in the band, and a token1 deposit.
        SettlementState memory state;
        state.sqrtPrice = uint160(
            bound(
                sqrtPrice,
                TickMath.getSqrtPriceAtTick(-TickMath.getTickAtSqrtPrice(Constants.BOUND_SQRT_PRICE_UPPER)),
                Constants.BOUND_SQRT_PRICE_UPPER
            )
        );
        state.held0 = bound(held0, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held1 = bound(held1, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.deposit1 = bound(deposit, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        // Then: It reverts.
        vm.expectRevert(PlanCacheLib.ZeroSupply.selector);
        planCacheLib.getSettlementAmountsOut(cache);
    }

    function testFuzz_Success_getSettlementAmountsOut_LoneToken0DepositCarriesTheCost(
        uint256 held0,
        uint256 held1,
        uint256 deposit,
        uint256 sold,
        uint256 fee
    ) public view {
        // Given: A core at a trusted price of one, and a pending token0 deposit.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.held1 = bound(held1, 3, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = bound(held0, 0, state.held1);
        state.deposit0 = bound(deposit, 3, Constants.MAX_SETTLEMENT_AMOUNT);

        // And: A sale of token0 no larger than the net swap, paying a fee.
        sold = bound(sold, 1, state.deposit0 * state.held1 / (state.held0 + state.deposit0 + state.held1));
        fee = bound(fee, 0, sold);
        (state.swap0, state.swap1) = (-int256(sold), int256(sold - fee));

        // And: A supply at which a share is worth one with the levies back.
        state.supply = state.held0 + state.held1;
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        uint256[4] memory out;
        (out[0], out[1], out[2], out[3]) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The deposit pays the swap's whole cost, its fee.
        assertEq(out[0], state.deposit0 - fee);
        assertEq(out[1], 0);
        assertEq(out[2], 0);
        assertEq(out[3], 0);

        // And: Nothing is paid out of the value after.
        assertEq(planCacheLib.getValueAfter(cache), state.held0 + state.held1 + state.deposit0 - fee);
    }

    function testFuzz_Success_getSettlementAmountsOut_LoneToken1DepositCarriesTheCost(
        uint256 held0,
        uint256 held1,
        uint256 deposit,
        uint256 spent,
        uint256 fee
    ) public view {
        // Given: A core at a trusted price of one, and a pending token1 deposit.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.held0 = bound(held0, 3, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held1 = bound(held1, 0, state.held0);
        state.deposit1 = bound(deposit, 3, Constants.MAX_SETTLEMENT_AMOUNT);

        // And: A purchase of token0 no larger than the net swap, paying a fee.
        spent = bound(spent, 1, state.deposit1 * state.held0 / (state.held0 + state.held1 + state.deposit1));
        fee = bound(fee, 0, spent - 1);
        (state.swap0, state.swap1) = (int256(spent - fee), -int256(spent));

        // And: A supply at which a share is worth one with the levies back.
        state.supply = state.held0 + state.held1;
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        uint256[4] memory out;
        (out[0], out[1], out[2], out[3]) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The deposit pays the swap's whole cost.
        assertEq(out[0], 0);
        assertEq(out[1], state.deposit1 - fee);
        assertEq(out[2], 0);
        assertEq(out[3], 0);
    }

    function testFuzz_Success_getSettlementAmountsOut_LoneToken1RedeemCarriesTheCost(
        uint256 held0,
        uint256 held1,
        uint256 shares,
        uint256 sold,
        uint256 fee
    ) public view {
        // Given: A core at a price of one, a share worth one with the levies back.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.held0 = bound(held0, 16, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held1 = bound(held1, 16, state.held0);
        state.supply = state.held0 + state.held1;

        // And: A pending redeem paid in token1, within the token1 held.
        state.redeem1 = bound(shares, 16, state.held1);

        // And: A sale of token0 no larger than the net swap, paying a fee.
        sold = bound(sold, 1, FixedPointMathLib.min(state.held0 / 2, state.redeem1 / 16));
        fee = bound(fee, 0, sold);
        (state.swap0, state.swap1) = (-int256(sold), int256(sold - fee));
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        uint256[4] memory out;
        (out[0], out[1], out[2], out[3]) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The redeem pays the swap's whole cost.
        assertEq(out[0], 0);
        assertEq(out[1], 0);
        assertEq(out[2], 0);
        assertEq(out[3], state.redeem1 - fee);

        // And: The value after is net of the payout.
        cache.amount1 -= int256(out[3]);
        assertEq(planCacheLib.getValueAfter(cache), state.held0 + state.held1 - fee - out[3]);
    }

    function testFuzz_Success_getSettlementAmountsOut_LoneToken0RedeemCarriesTheCost(
        uint256 held0,
        uint256 held1,
        uint256 shares,
        uint256 spent,
        uint256 fee
    ) public view {
        // Given: A core at a price of one, a share worth one with the levies back.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.held1 = bound(held1, 32, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = bound(held0, 32, state.held1);
        state.supply = state.held0 + state.held1;

        // And: A pending redeem paid in token0, within the token0 held.
        state.redeem0 = bound(shares, 32, state.held0);

        // And: A purchase of token0 no larger than the net swap, paying a fee.
        spent = bound(spent, 2, FixedPointMathLib.min(state.held1 / 2, state.redeem0 / 16));
        fee = bound(fee, 0, spent - 1);
        (state.swap0, state.swap1) = (int256(spent - fee), -int256(spent));
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        uint256[4] memory out;
        (out[0], out[1], out[2], out[3]) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The redeem pays the swap's whole cost.
        assertEq(out[0], 0);
        assertEq(out[1], 0);
        assertEq(out[2], state.redeem0 - fee);
        assertEq(out[3], 0);

        // And: The value after is net of the payout.
        cache.amount0 -= int256(out[2]);
        assertEq(planCacheLib.getValueAfter(cache), state.held0 + state.held1 - fee - out[2]);
    }

    function testFuzz_Success_getSettlementAmountsOut_MatchedSameTokenFlowsAreFree(
        uint256 sqrtPrice,
        uint256 supply,
        uint256 held0,
        uint256 held1,
        uint256 shares,
        bool sells,
        uint256 amountIn,
        uint256 amountOut
    ) public view {
        // Given: A core at a trusted price in the band, and a swap in either direction.
        SettlementState memory state;
        state.sqrtPrice = uint160(
            bound(
                sqrtPrice,
                TickMath.getSqrtPriceAtTick(-TickMath.getTickAtSqrtPrice(Constants.BOUND_SQRT_PRICE_UPPER)),
                Constants.BOUND_SQRT_PRICE_UPPER
            )
        );
        state.supply = bound(supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = bound(held0, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held1 = bound(held1, 2, Constants.MAX_SETTLEMENT_AMOUNT);
        amountOut = bound(amountOut, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        amountIn = bound(amountIn, 1, sells ? state.held0 : state.held1 - 1);
        (state.swap0, state.swap1) =
            sells ? (-int256(amountIn), int256(amountOut)) : (int256(amountOut), -int256(amountIn));
        uint256 priceX192 = uint256(state.sqrtPrice) * state.sqrtPrice;
        uint256 valueBefore = FullMath.mulDiv(state.held0, priceX192, 1 << 192) + state.held1;
        uint256 value = sells
            ? valueBefore + amountOut - FullMath.mulDivRoundingUp(amountIn, priceX192, 1 << 192)
            : valueBefore + FullMath.mulDiv(amountOut, priceX192, 1 << 192) - amountIn;

        // And: A token1 redeem and a token1 deposit of its redeem value.
        state.redeem1 = bound(shares, 1, state.supply);
        state.deposit1 = FullMath.mulDiv(state.redeem1, value, state.supply);
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        uint256[4] memory out;
        (out[0], out[1], out[2], out[3]) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: Both settle free of the swap cost, the deposit at the value rounded up.
        uint256 valueUp = FullMath.mulDivRoundingUp(state.held0, priceX192, 1 << 192) + state.held1;
        valueUp = sells
            ? valueUp + amountOut - FullMath.mulDiv(amountIn, priceX192, 1 << 192)
            : valueUp + FullMath.mulDivRoundingUp(amountOut, priceX192, 1 << 192) - amountIn;
        assertEq(out[0], 0);
        assertEq(out[1], state.deposit1 == 0 ? 0 : FullMath.mulDiv(state.deposit1, state.supply, valueUp));
        assertEq(out[2], 0);

        // And: The redeem at that value, at most the value before the swap.
        assertEq(out[3], FullMath.mulDiv(state.redeem1, FixedPointMathLib.min(value, valueBefore), state.supply));
    }

    function testFuzz_Success_getSettlementAmountsOut_OffsettersPayNothing_Sale(
        uint256 held1,
        uint256 deposit0,
        uint256 deposit1,
        uint256 sold,
        uint256 fee
    ) public view {
        // Given: A core holding token1 at a price of one, a share worth one.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.held1 = bound(held1, 8, Constants.MAX_SETTLEMENT_AMOUNT);
        state.supply = state.held1;

        // And: A token0 deposit, and a token1 deposit of at most a quarter of it.
        state.deposit0 = bound(deposit0, 8, state.held1);
        state.deposit1 = bound(deposit1, 0, state.deposit0 / 4);

        // And: A sale of token0 no larger than the net swap, paying a fee.
        sold = bound(sold, 1, state.deposit0 / 8);
        fee = bound(fee, 0, sold);
        (state.swap0, state.swap1) = (-int256(sold), int256(sold - fee));
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (uint256 shares0, uint256 shares1,,) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The token0 deposit pays the whole cost, the token1 deposit nothing.
        assertEq(shares0, state.deposit0 - fee);
        assertEq(shares1, state.deposit1);
    }

    function testFuzz_Success_getSettlementAmountsOut_OffsettersPayNothing_Purchase(
        uint256 held0,
        uint256 deposit0,
        uint256 deposit1,
        uint256 spent,
        uint256 fee
    ) public view {
        // Given: A core holding token0 at a price of one, a share worth one.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.held0 = bound(held0, 16, Constants.MAX_SETTLEMENT_AMOUNT);
        state.supply = state.held0;

        // And: A token1 deposit, and a token0 deposit of at most a quarter of it.
        state.deposit1 = bound(deposit1, 16, state.held0);
        state.deposit0 = bound(deposit0, 0, state.deposit1 / 4);

        // And: A purchase of token0 no larger than the net swap, paying a fee.
        spent = bound(spent, 2, state.deposit1 / 8);
        fee = bound(fee, 0, spent - 1);
        (state.swap0, state.swap1) = (int256(spent - fee), -int256(spent));
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (uint256 shares0, uint256 shares1,,) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The token1 deposit pays the whole cost, the token0 deposit nothing.
        assertEq(shares0, state.deposit0);
        assertEq(shares1, state.deposit1 - fee);
    }

    function testFuzz_Success_getSettlementAmountsOut_ProRataToContribution(
        SettlementState memory state,
        uint256 sold,
        uint256 fee
    ) public view {
        // Given: A core at a price of one, a share worth one with the levies back.
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.held0 = bound(state.held0, 8, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held1 = bound(state.held1, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        state.supply = state.held0 + state.held1;

        // And: A token0 deposit and a token1 redeem, both selling token0, no other flow.
        state.deposit0 = bound(state.deposit0, 2, Constants.MAX_SETTLEMENT_AMOUNT);
        state.redeem1 = bound(state.redeem1, 8, state.supply);
        (state.deposit1, state.redeem0, state.other0, state.other1) = (0, 0, 0, 0);

        // And: A sale of token0 no larger than the net swap, paying a fee.
        sold = bound(sold, 1, FixedPointMathLib.min(state.deposit0, state.redeem1 / 4) / 2);
        fee = bound(fee, 0, sold);
        (state.swap0, state.swap1) = (-int256(sold), int256(sold - fee));

        // When: Reading the settlement.
        (uint256 shares0,,, uint256 assets1) = planCacheLib.getSettlementAmountsOut(setSettlementState(state));

        // Then: Each leg is levied the swap's cost, its fee, pro rata to its part.
        uint256 levy0;
        uint256 levy1;
        {
            uint256 redeemValue1 = FullMath.mulDiv(state.redeem1, state.held0 + state.held1 - fee, state.supply);
            uint256 depositSwap;
            uint256 redeemSwap;
            {
                uint256 heldIn = state.held0 + state.deposit0 - sold;
                uint256 heldOut = FixedPointMathLib.zeroFloorSub(state.held1 + sold - fee, redeemValue1);
                depositSwap = FullMath.mulDiv(state.deposit0, heldOut, heldIn + heldOut);
                redeemSwap = FullMath.mulDiv(redeemValue1, heldIn, heldIn + heldOut);
            }
            uint256 levy = FullMath.mulDivRoundingUp(fee, FixedPointMathLib.min(depositSwap + redeemSwap, sold), sold);
            levy0 = FixedPointMathLib.min(
                FullMath.mulDivRoundingUp(levy, depositSwap, depositSwap + redeemSwap), state.deposit0
            );
            levy1 = FixedPointMathLib.min(
                FullMath.mulDivRoundingUp(levy, redeemSwap, depositSwap + redeemSwap), redeemValue1
            );
        }
        uint256 value = state.held0 + state.held1 - fee + levy0 + levy1;
        assertEq(shares0, FullMath.mulDiv(state.deposit0 - levy0, state.supply, value));

        // And: The redeem is paid at the value plus levies, capped, less its levy.
        assertEq(
            assets1,
            FullMath.mulDiv(state.redeem1, FixedPointMathLib.min(state.held0 + state.held1, value), state.supply)
                - levy1
        );
    }

    function testFuzz_Success_getSettlementAmountsOut_StayersEndAtTheCounterfactualPerShare(
        uint256 held0,
        uint256 held1,
        uint256 deposit0,
        uint256 deposit1,
        uint256 shares0,
        uint256 shares1,
        uint256 sold,
        uint256 fee
    ) public view {
        // Given: A core at a price of one, a share worth one with the levies back.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.held0 = bound(held0, 64, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held1 = bound(held1, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        state.supply = state.held0 + state.held1;

        // And: A token0 deposit and a token1 redeem selling token0, and smaller offsets.
        state.deposit0 = bound(deposit0, 8, Constants.MAX_SETTLEMENT_AMOUNT);
        state.redeem1 = bound(shares1, 32, state.supply / 2);
        state.deposit1 = bound(deposit1, 0, state.redeem1 / 8);
        state.redeem0 = bound(shares0, 0, FixedPointMathLib.min(state.deposit0 / 2, state.supply / 2));

        // And: A sale of token0 no larger than the net swap, paying a fee.
        sold = bound(sold, 1, FixedPointMathLib.min(state.deposit0, state.redeem1 / 4) / 8);
        fee = bound(fee, 0, sold);
        (state.swap0, state.swap1) = (-int256(sold), int256(sold - fee));
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        uint256[4] memory out;
        (out[0], out[1], out[2], out[3]) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The redeems are paid at the value before the swap, token1 less its levy.
        uint256 owed = FullMath.mulDiv(state.redeem1, state.held0 + state.held1, state.supply);
        assertEq(out[2], FullMath.mulDiv(state.redeem0, state.held0 + state.held1, state.supply));
        assertLe(out[3], owed);

        // And: One (W + levies) / S, levies the cost plus two wei, prices the deposits.
        uint256 valueStar;
        {
            uint256 value = state.held0 + state.held1 - fee;
            for (uint256 levied = fee; levied <= fee + 2; ++levied) {
                if (owed - out[3] > levied) continue;
                if (
                    FullMath.mulDiv(state.deposit0 - (levied - (owed - out[3])), state.supply, value + levied) == out[0]
                        && FullMath.mulDiv(state.deposit1, state.supply, value + levied) == out[1]
                ) valueStar = value + levied;
            }
        }
        assertGt(valueStar, 0);

        // And: The value after is the end holdings less the payouts held.
        (cache.amount0, cache.amount1) = (cache.amount0 - int256(out[2]), cache.amount1 - int256(out[3]));
        // Hole: the payouts, an output, exceed a token held.
        vm.assume(cache.amount0 >= 0 && cache.amount1 >= 0);
        uint256 valueAfter = planCacheLib.getValueAfter(cache);
        assertEq(valueAfter, state.held0 + state.held1 + state.deposit0 + state.deposit1 - fee - out[2] - out[3]);

        // And: The stayers end at that value per share, within a share per mint/payout.
        uint256 supplyAfter = state.supply - state.redeem0 - state.redeem1 + out[0] + out[1];
        assertGe(valueAfter * state.supply, valueStar * supplyAfter);
        assertLt(valueAfter * state.supply, valueStar * supplyAfter + 2 * valueStar + 2 * state.supply);
    }

    function testFuzz_Success_getSettlementAmountsOut_DepositSoldForNothingIsLeviedWhole(uint256 held1, uint256 deposit)
        public
        view
    {
        // Given: A core holding token1 at a price of one, a share worth one.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.held1 = bound(held1, 2, Constants.MAX_SETTLEMENT_AMOUNT);
        state.supply = state.held1 + 1;

        // And: A token0 deposit below the token1 held, sold whole for nothing.
        state.deposit0 = bound(deposit, 1, state.held1 - 1);
        (state.swap0, state.swap1) = (-int256(state.deposit0), 0);
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (uint256 shares0,,,) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The deposit is levied its whole value.
        assertEq(shares0, 0);

        // And: The stayers keep the token1 held, the deposit's value gone to the swap.
        assertEq(planCacheLib.getValueAfter(cache), state.held1);
    }

    function testFuzz_Success_getSettlementAmountsOut_AStrategyLossIsNotInTheEntrantsPrice(
        uint256 supply,
        uint256 held0,
        uint256 held1,
        uint256 deposit,
        uint256 shares,
        uint256 loss
    ) public view {
        // Given: A core at a trusted price of one.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.supply = bound(supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = bound(held0, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held1 = bound(held1, 2, Constants.MAX_SETTLEMENT_AMOUNT);

        // And: A token1 deposit and a token0 redeem.
        state.deposit1 = bound(deposit, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.redeem0 = bound(shares, 1, state.supply);

        // And: A strategy loss of up to half the token1 held.
        loss = bound(loss, 1, state.held1 / 2);
        state.other1 = -int256(loss);
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        uint256[4] memory out;
        (out[0], out[1], out[2], out[3]) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The entrant gets shares at the value after the loss, the redeemer too.
        uint256 value = state.held0 + state.held1 - loss;
        assertEq(out[0], 0);
        assertEq(out[1], FullMath.mulDiv(state.deposit1, state.supply, value));
        assertEq(out[2], FullMath.mulDiv(state.redeem0, value, state.supply));
        assertEq(out[3], 0);
    }

    function testFuzz_Success_getSettlementAmountsOut_ZeroWithoutASwap(
        uint256 sqrtPrice,
        uint256 supply,
        uint256 held0,
        uint256 held1,
        uint256 deposit0,
        uint256 deposit1,
        uint256 shares0,
        uint256 shares1
    ) public view {
        // Given: A core at a trusted price in the band, and no swap.
        SettlementState memory state;
        state.sqrtPrice = uint160(
            bound(
                sqrtPrice,
                TickMath.getSqrtPriceAtTick(-TickMath.getTickAtSqrtPrice(Constants.BOUND_SQRT_PRICE_UPPER)),
                Constants.BOUND_SQRT_PRICE_UPPER
            )
        );
        state.supply = bound(supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = bound(held0, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held1 = bound(held1, 1, Constants.MAX_SETTLEMENT_AMOUNT);

        // And: A deposit in each vault.
        state.deposit0 = bound(deposit0, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.deposit1 = bound(deposit1, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        uint256 priceX192 = uint256(state.sqrtPrice) * state.sqrtPrice;
        uint256 value0 = FullMath.mulDiv(state.deposit0, priceX192, 1 << 192);
        uint256 value = FullMath.mulDiv(state.held0, priceX192, 1 << 192) + state.held1;

        // And: A redeem in each vault, each paid out of the token it is paid in.
        state.redeem0 = bound(
            shares0,
            0,
            FixedPointMathLib.min(
                state.supply,
                FullMath.mulDiv(FullMath.mulDiv(state.held0 + state.deposit0, priceX192, 1 << 192), state.supply, value)
            )
        );
        state.redeem1 = bound(
            shares1,
            0,
            FixedPointMathLib.min(
                state.supply - state.redeem0, FullMath.mulDiv(state.held1 + state.deposit1, state.supply, value)
            )
        );
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        uint256[4] memory out;
        (out[0], out[1], out[2], out[3]) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The deposits settle at the existing value rounded up, levied nothing.
        uint256 valueUp = FullMath.mulDivRoundingUp(state.held0, priceX192, 1 << 192) + state.held1;
        assertEq(out[0], value0 == 0 ? 0 : FullMath.mulDiv(value0, state.supply, valueUp));
        assertEq(out[1], state.deposit1 == 0 ? 0 : FullMath.mulDiv(state.deposit1, state.supply, valueUp));

        // And: The redeems at that value rounded down.
        assertEq(out[2], FullMath.mulDiv(FullMath.mulDiv(state.redeem0, value, state.supply), 1 << 192, priceX192));
        assertEq(out[3], FullMath.mulDiv(state.redeem1, value, state.supply));

        // And: The value after is the end holdings less the payouts.
        (cache.amount0, cache.amount1) = (cache.amount0 - int256(out[2]), cache.amount1 - int256(out[3]));
        assertEq(
            planCacheLib.getValueAfter(cache),
            FullMath.mulDiv(state.held0 + state.deposit0 - out[2], priceX192, 1 << 192) + state.held1 + state.deposit1
                - out[3]
        );
    }

    function testFuzz_Success_getSettlementAmountsOut_ZeroWhenTheSwapRunsAgainstTheFlows(
        uint256 sqrtPrice,
        uint256 supply,
        uint256 held0,
        uint256 held1,
        uint256 deposit,
        uint256 spent,
        uint256 bought
    ) public view {
        // Given: A core at a trusted price in the band, and a token0 deposit selling it.
        SettlementState memory state;
        state.sqrtPrice = uint160(
            bound(
                sqrtPrice,
                TickMath.getSqrtPriceAtTick(-TickMath.getTickAtSqrtPrice(Constants.BOUND_SQRT_PRICE_UPPER)),
                Constants.BOUND_SQRT_PRICE_UPPER
            )
        );
        state.supply = bound(supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = bound(held0, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held1 = bound(held1, 2, Constants.MAX_SETTLEMENT_AMOUNT);
        state.deposit0 = bound(deposit, 1, Constants.MAX_SETTLEMENT_AMOUNT);

        // And: A purchase of token0 at any rate.
        bought = bound(bought, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        spent = bound(spent, 1, state.held1 / 2);
        (state.swap0, state.swap1) = (int256(bought), -int256(spent));
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (uint256 shares0,,,) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The deposit settles at the existing value rounded up, levied nothing.
        uint256 priceX192 = uint256(state.sqrtPrice) * state.sqrtPrice;
        uint256 value0 = FullMath.mulDiv(state.deposit0, priceX192, 1 << 192);
        uint256 value = FullMath.mulDivRoundingUp(state.held0, priceX192, 1 << 192) + state.held1
            + FullMath.mulDivRoundingUp(bought, priceX192, 1 << 192) - spent;
        assertEq(shares0, value0 == 0 ? 0 : FullMath.mulDiv(value0, state.supply, value));
    }

    function testFuzz_Success_getSettlementAmountsOut_ZeroWhenFilledAtOrBetterThanThePrice(
        uint256 sqrtPrice,
        uint256 supply,
        uint256 held0,
        uint256 held1,
        uint256 deposit,
        uint256 sold,
        uint256 bought
    ) public view {
        // Given: A core at a trusted price in the band, and a token0 deposit selling it.
        SettlementState memory state;
        state.sqrtPrice = uint160(
            bound(
                sqrtPrice,
                TickMath.getSqrtPriceAtTick(-TickMath.getTickAtSqrtPrice(Constants.BOUND_SQRT_PRICE_UPPER)),
                Constants.BOUND_SQRT_PRICE_UPPER
            )
        );
        uint256 priceX192 = uint256(state.sqrtPrice) * state.sqrtPrice;
        state.supply = bound(supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = bound(held0, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held1 = bound(held1, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.deposit0 = bound(deposit, 1, Constants.MAX_SETTLEMENT_AMOUNT);

        // And: A token0 sale filled at least 2 wei above its value, the fill an int128.
        sold = bound(
            sold,
            1,
            FixedPointMathLib.min(state.deposit0, FullMath.mulDiv(Constants.MAX_FUZZED_AMOUNT - 2, 1 << 192, priceX192))
        );
        uint256 least = FullMath.mulDiv(sold, priceX192, 1 << 192) + 2;
        bought = bound(
            bought, least, FixedPointMathLib.min(least + Constants.MAX_SETTLEMENT_AMOUNT, Constants.MAX_FUZZED_AMOUNT)
        );
        (state.swap0, state.swap1) = (-int256(sold), int256(bought));
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (uint256 shares0,,,) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The deposit settles at the existing value rounded up, levied nothing.
        uint256 value0 = FullMath.mulDiv(state.deposit0, priceX192, 1 << 192);
        uint256 value = FullMath.mulDivRoundingUp(state.held0, priceX192, 1 << 192) + state.held1 + bought
            - FullMath.mulDiv(sold, priceX192, 1 << 192);
        assertEq(shares0, value0 == 0 ? 0 : FullMath.mulDiv(value0, state.supply, value));
    }

    function testFuzz_Success_getSettlementAmountsOut_ZeroWithoutAnExcessSide(
        uint256 supply,
        uint256 held0,
        uint256 held1,
        uint256 shares,
        bool sells,
        uint256 amountIn,
        uint256 fee
    ) public view {
        // Given: A core at a trusted price of one, and a costly swap in either direction.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.supply = bound(supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = bound(held0, 2, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held1 = bound(held1, 2, Constants.MAX_SETTLEMENT_AMOUNT);
        amountIn = bound(amountIn, 1, (sells ? state.held0 : state.held1) / 2);
        fee = bound(fee, 0, amountIn);
        (state.swap0, state.swap1) =
            sells ? (-int256(amountIn), int256(amountIn - fee)) : (int256(amountIn - fee), -int256(amountIn));
        uint256 value = state.held0 + state.held1 - fee;

        // And: A token0 redeem and a token0 deposit of its redeem value, needing no swap.
        state.redeem0 = bound(shares, 1, state.supply);
        state.deposit0 = FullMath.mulDiv(state.redeem0, value, state.supply);
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (uint256 shares0,, uint256 assets0,) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: Both settle at the existing aLP's value per share, levied nothing.
        assertEq(shares0, state.deposit0 == 0 ? 0 : FullMath.mulDiv(state.deposit0, state.supply, value));
        assertEq(assets0, FullMath.mulDiv(state.redeem0, value, state.supply));
    }

    function testFuzz_Success_getSettlementAmountsOut_ZeroFromACoreLeftWorthNothing(
        uint256 supply,
        uint256 held0,
        uint256 shares,
        bool isToken0
    ) public view {
        // Given: A core at a trusted price of one holding only token0, and a supply.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.supply = bound(supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = bound(held0, 1, Constants.MAX_SETTLEMENT_AMOUNT);

        // And: A sale of all of it for nothing.
        state.swap0 = -int256(state.held0);

        // And: A pending redeem in either vault.
        shares = bound(shares, 1, state.supply);
        if (isToken0) state.redeem0 = shares;
        else state.redeem1 = shares;
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        uint256[4] memory out;
        (out[0], out[1], out[2], out[3]) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The redeem is paid nothing, and nothing is minted or left.
        assertEq(out[0], 0);
        assertEq(out[1], 0);
        assertEq(out[2], 0);
        assertEq(out[3], 0);
        assertEq(planCacheLib.getValueAfter(cache), 0);
    }

    function testFuzz_Success_getSettlementAmountsOut_ZeroWhenTheSwapLostMoreThanTheValue(
        uint256 supply,
        uint256 held0,
        uint256 shares0,
        uint256 shares1,
        uint256 sold,
        uint256 bought
    ) public view {
        // Given: A core at a trusted price of one holding only token0, and a supply.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.supply = bound(supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = bound(held0, 1, Constants.MAX_SETTLEMENT_AMOUNT);

        // And: A sale that lost more than the value before it.
        bought = bound(bought, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        sold = bound(sold, state.held0 + bought + 1, Constants.MAX_FUZZED_AMOUNT);
        (state.swap0, state.swap1) = (-int256(sold), int256(bought));

        // And: A pending redeem in both vaults.
        state.redeem0 = bound(shares0, 1, state.supply);
        state.redeem1 = bound(shares1, 1, state.supply);
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        uint256[4] memory out;
        (out[0], out[1], out[2], out[3]) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: With no value left, the redeems are levied nothing and paid nothing.
        assertEq(out[0], 0);
        assertEq(out[1], 0);
        assertEq(out[2], 0);
        assertEq(out[3], 0);
    }

    function testFuzz_Success_getSettlementAmountsOut_TheWholeCostWhenTheSwapIsSmaller(
        uint256 held0,
        uint256 held1,
        uint256 shares,
        uint256 spent,
        uint256 fee
    ) public view {
        // Given: A core at a price of one, a share worth one with the levies back.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.held1 = bound(held1, 64, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = bound(held0, 0, state.held1);
        state.supply = state.held0 + state.held1;

        // And: A pending redeem paid in token0.
        state.redeem0 = bound(shares, 64, state.supply);

        // And: A purchase of token0 smaller than the net swap, paying a fee.
        spent = bound(spent, 2, FixedPointMathLib.min(state.held1 / 2, state.redeem0 / 16));
        fee = bound(fee, 0, spent - 1);
        (state.swap0, state.swap1) = (int256(spent - fee), -int256(spent));
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (,, uint256 assets0,) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The redeem pays the swap's whole cost.
        assertEq(assets0, state.redeem0 - fee);
    }

    function testFuzz_Success_getSettlementAmountsOut_TheAverageRateWhenTheSwapIsLarger(
        uint256 held0,
        uint256 held1,
        uint256 deposit,
        uint256 sold,
        uint256 fee
    ) public view {
        // Given: A core at a trusted price of one, and a pending token0 deposit.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.held0 = bound(held0, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held1 = bound(held1, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        state.deposit0 = bound(deposit, 1, Constants.MAX_SETTLEMENT_AMOUNT);

        // And: A token0 sale larger than the deposit and the net swap, paying a fee.
        sold = bound(sold, state.deposit0 + 1, state.deposit0 + state.held0);
        fee = bound(fee, 0, FixedPointMathLib.min(sold / 2, state.held0 + state.held1 - 1));
        (state.swap0, state.swap1) = (-int256(sold), int256(sold - fee));

        // And: A supply at which a share is worth one at the existing aLP's value.
        uint256 value = state.held0 + state.held1 - fee;
        state.supply = value;
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (uint256 shares0,,,) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The deposit pays the swap's average rate on its part, rounded up.
        uint256 left1 = state.held1 + sold - fee;
        uint256 swap = FullMath.mulDiv(state.deposit0, left1, state.held0 + state.deposit0 - sold + left1);
        uint256 levy = FixedPointMathLib.min(FullMath.mulDivRoundingUp(fee, swap, sold), state.deposit0);
        assertEq(shares0, FullMath.mulDiv(state.deposit0 - levy, state.supply, value + levy));
    }

    function testFuzz_Success_getSettlementAmountsOut_NeverAboveTheSwapCost(
        uint256 supply,
        uint256 held0,
        uint256 held1,
        uint256 deposit0,
        uint256 deposit1,
        uint256 shares0,
        uint256 shares1,
        bool sells,
        uint256 amountIn,
        uint256 amountOut
    ) public view {
        // Given: A core at a trusted price of one.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.supply = bound(supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = bound(held0, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held1 = bound(held1, 1, Constants.MAX_SETTLEMENT_AMOUNT);

        // And: A deposit and a redeem in each vault, and a swap of any size, side, fill.
        state.deposit0 = bound(deposit0, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.deposit1 = bound(deposit1, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        state.redeem0 = bound(shares0, 0, state.supply / 2);
        state.redeem1 = bound(shares1, 0, state.supply / 2);
        amountOut = bound(amountOut, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        amountIn = bound(amountIn, 1, sells ? state.held0 : state.held1);
        (state.swap0, state.swap1) =
            sells ? (-int256(amountIn), int256(amountOut)) : (int256(amountOut), -int256(amountIn));
        uint256 start = state.held0 + state.held1 + amountOut - amountIn;
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        uint256[4] memory out;
        (out[0], out[1], out[2], out[3]) = planCacheLib.getSettlementAmountsOut(cache);

        // And: Taking the payouts off the tokens held, each within them.
        (cache.amount0, cache.amount1) = (cache.amount0 - int256(out[2]), cache.amount1 - int256(out[3]));
        // Hole: the payouts, an output, exceed a token held.
        vm.assume(cache.amount0 >= 0 && cache.amount1 >= 0);

        // Then: Stayers gain at most the cost, the redeems' gain, two wei and floors.
        uint256 cost = sells
            ? FixedPointMathLib.zeroFloorSub(amountIn + 1, amountOut)
            : FixedPointMathLib.zeroFloorSub(amountIn, amountOut);
        uint256 gain = FixedPointMathLib.zeroFloorSub(amountOut, amountIn);
        uint256 supplyAfter = state.supply - state.redeem0 - state.redeem1 + out[0] + out[1];
        uint256 rest = mulmod(start + cost + 2, supplyAfter + 2, state.supply) + 2 * state.supply
            + (state.redeem0 + state.redeem1) * gain;
        assertLe(
            planCacheLib.getValueAfter(cache),
            FullMath.mulDiv(start + cost + 2, supplyAfter + 2, state.supply) + rest / state.supply
        );
    }

    function testFuzz_Success_getSettlementAmountsOut_NoFlowPaysMoreThanRhoPlusTauOfItsSwap_Sale(
        uint256 sqrtPrice,
        uint256 held1,
        uint256 deposit,
        uint16 maxSwapCostBps,
        int256 deviation,
        uint256 amountIn
    ) public view {
        // Given: A trusted price in the band, a spot in the deviation band, a swap cost.
        SettlementState memory state;
        state.sqrtPrice = uint160(
            bound(
                sqrtPrice,
                TickMath.getSqrtPriceAtTick(-TickMath.getTickAtSqrtPrice(Constants.BOUND_SQRT_PRICE_UPPER)),
                Constants.BOUND_SQRT_PRICE_UPPER
            )
        );
        deviation = bound(deviation, -int256(Constants.WIDE_DEVIATION), int256(Constants.WIDE_DEVIATION));
        uint256 spot = deviation >= 0
            ? FullMath.mulDiv(state.sqrtPrice, 1e18 + uint256(deviation), 1e18)
            : FullMath.mulDiv(state.sqrtPrice, 1e18, 1e18 + uint256(-deviation));
        maxSwapCostBps = uint16(bound(maxSwapCostBps, 0, ConfigLib.BPS_DENOMINATOR - 1));

        // And: A lone token0 deposit into a token1 core, a sale at the spot floor.
        uint256 priceX192 = uint256(state.sqrtPrice) * state.sqrtPrice;
        uint256 floor1 = 16 * FullMath.mulDivRoundingUp(1, priceX192, 1 << 192);
        state.deposit0 =
            bound(deposit, FullMath.mulDivRoundingUp(floor1, 1 << 192, priceX192), Constants.MAX_SETTLEMENT_AMOUNT);
        uint256 flow = FullMath.mulDiv(state.deposit0, priceX192, 1 << 192);
        state.held1 = bound(held1, floor1, Constants.MAX_SETTLEMENT_AMOUNT);
        uint256 most = FullMath.mulDiv(FixedPointMathLib.min(flow, state.held1) / 8, 1 << 192, priceX192);
        amountIn = bound(amountIn, FullMath.mulDivRoundingUp(1, 1 << 192, priceX192), most);
        state.swap0 = -int256(amountIn);
        state.swap1 = int256(
            FixedPointMathLib.fullMulDivUp(
                FullMath.mulDiv(amountIn, spot * spot, 1 << 192), 10_000 - maxSwapCostBps, 10_000
            )
        );

        // And: A supply at which a share is worth one with the swap's cost back.
        uint256 shares0;
        {
            PlanCache memory cache = setSettlementState(state);
            cache.supplyBefore = state.held1
                + FixedPointMathLib.max(uint256(state.swap1), FullMath.mulDivRoundingUp(amountIn, priceX192, 1 << 192))
                - FullMath.mulDiv(amountIn, priceX192, 1 << 192);

            // When: Reading the settlement.
            (shares0,,,) = planCacheLib.getSettlementAmountsOut(cache);
        }

        // Then: The deposit pays under rho plus tau of its swap, plus their wei and eps.
        uint256 rate;
        uint256 eps = 2e18;
        {
            uint256 sigma = FullMath.mulDiv(FullMath.mulDiv(spot, 1e18, state.sqrtPrice), spot, state.sqrtPrice);
            rate = FixedPointMathLib.divUp(uint256(maxSwapCostBps) * 1e18, 10_000)
                + (sigma >= 1e18
                        ? 0
                        : FixedPointMathLib.divUp((10_000 - uint256(maxSwapCostBps)) * (1e18 - sigma), 10_000));
        }
        uint256 swap;
        {
            uint256 left0 = FullMath.mulDiv(state.deposit0 - amountIn, priceX192, 1 << 192);
            uint256 left1 = state.held1 + uint256(state.swap1);
            swap = FixedPointMathLib.fullMulDivUp(flow, left1, left0 + left1);
        }
        assertLt((flow - shares0) * 1e18, rate * swap + rate + eps + 2e18);
    }

    function testFuzz_Success_getSettlementAmountsOut_NoFlowPaysMoreThanRhoPlusTauOfItsSwap_Purchase(
        uint256 sqrtPrice,
        uint256 held0,
        uint256 deposit,
        uint16 maxSwapCostBps,
        int256 deviation,
        uint256 amountIn
    ) public view {
        // Given: A trusted price in the band, a spot in the deviation band, a swap cost.
        SettlementState memory state;
        state.sqrtPrice = uint160(
            bound(
                sqrtPrice,
                TickMath.getSqrtPriceAtTick(-TickMath.getTickAtSqrtPrice(Constants.BOUND_SQRT_PRICE_UPPER)),
                Constants.BOUND_SQRT_PRICE_UPPER
            )
        );
        deviation = bound(deviation, -int256(Constants.WIDE_DEVIATION), int256(Constants.WIDE_DEVIATION));
        uint256 spot = deviation >= 0
            ? FullMath.mulDiv(state.sqrtPrice, 1e18 + uint256(deviation), 1e18)
            : FullMath.mulDiv(state.sqrtPrice, 1e18, 1e18 + uint256(-deviation));
        maxSwapCostBps = uint16(bound(maxSwapCostBps, 0, ConfigLib.BPS_DENOMINATOR - 1));

        // And: A lone token1 deposit into a token0 core, a purchase at the spot floor.
        uint256 priceX192 = uint256(state.sqrtPrice) * state.sqrtPrice;
        state.deposit1 = bound(deposit, 16, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = bound(held0, FullMath.mulDivRoundingUp(16, 1 << 192, priceX192), Constants.MAX_SETTLEMENT_AMOUNT);
        uint256 flow = FullMath.mulDiv(state.held0, priceX192, 1 << 192);
        amountIn = bound(amountIn, 1, FixedPointMathLib.min(state.deposit1, flow) / 16);
        flow = state.deposit1;
        state.swap1 = -int256(amountIn);
        state.swap0 = int256(
            FixedPointMathLib.fullMulDivUp(
                FullMath.mulDiv(amountIn, 1 << 192, spot * spot), 10_000 - maxSwapCostBps, 10_000
            )
        );
        // Hole: the token0 bought, an output of spot and cost, is worth under a wei.
        vm.assume(FullMath.mulDiv(uint256(state.swap0), priceX192, 1 << 192) != 0);

        // And: A supply at which a share is worth one with the swap's cost back.
        uint256 shares1;
        {
            PlanCache memory cache = setSettlementState(state);
            cache.supplyBefore = FullMath.mulDivRoundingUp(state.held0, priceX192, 1 << 192)
                + FullMath.mulDivRoundingUp(uint256(state.swap0), priceX192, 1 << 192)
                - FixedPointMathLib.min(amountIn, FullMath.mulDiv(uint256(state.swap0), priceX192, 1 << 192));

            // When: Reading the settlement.
            (, shares1,,) = planCacheLib.getSettlementAmountsOut(cache);
        }

        // Then: The deposit pays under rho plus tau of its swap, plus their wei and eps.
        uint256 rate;
        uint256 eps;
        {
            uint256 sigma = FixedPointMathLib.fullMulDivUp(spot, 1e18, state.sqrtPrice);
            sigma = FixedPointMathLib.fullMulDivUp(sigma, sigma, 1e18);
            uint256 scale = FixedPointMathLib.divUp(10_000 * 1e18, 10_000 - uint256(maxSwapCostBps));
            rate = FixedPointMathLib.divUp(uint256(maxSwapCostBps) * 1e18, 10_000 - uint256(maxSwapCostBps))
                + (sigma <= 1e18 ? 0 : FixedPointMathLib.fullMulDivUp(scale, sigma - 1e18, 1e18));
            eps = FixedPointMathLib.fullMulDivUp(state.sqrtPrice, state.sqrtPrice, 1 << 96);
            eps = FixedPointMathLib.fullMulDivUp(eps, 1e18, 1 << 96) + scale;
            eps = FixedPointMathLib.fullMulDivUp(sigma, eps, 1e18);
        }
        uint256 swap;
        {
            uint256 left0 = FullMath.mulDiv(state.held0 + uint256(state.swap0), priceX192, 1 << 192);
            uint256 left1 = state.deposit1 - amountIn;
            swap = FixedPointMathLib.fullMulDivUp(flow, left0, left0 + left1);
        }
        assertLt((flow - shares1) * 1e18, rate * swap + rate + eps + 2e18);
    }

    function testFuzz_Success_getSettlementAmountsOut_LevyNeverExceedsTheFlow(uint256 held0, uint256 sold) public view {
        // Given: A core holding token0 at a price of one, a share worth one.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.held0 = bound(held0, 3, Constants.MAX_SETTLEMENT_AMOUNT);
        state.supply = state.held0 + 1;

        // And: A token0 sale for nothing, and a token1 redeem whose value is the sale.
        sold = bound(sold, 1, state.held0 / 3);
        (state.swap0, state.swap1) = (-int256(sold), 0);
        state.redeem1 = FixedPointMathLib.divUp(sold * state.supply, state.held0 - sold);
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (,,, uint256 assets1) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The redeem is levied its redeem value, at the value plus that levy.
        uint256 redeemValue1 = FullMath.mulDiv(state.redeem1, state.held0 - sold, state.supply);
        assertEq(
            assets1, FullMath.mulDiv(state.redeem1, state.held0 - sold + redeemValue1, state.supply) - redeemValue1
        );

        // And: That levy is the swap's whole cost.
        assertEq(redeemValue1, sold);
    }

    function testFuzz_Success_getSettlementAmountsOut_RoundsAgainstFlows_Sale(
        uint256 held1,
        uint256 deposit,
        uint256 shares,
        uint256 sold
    ) public view {
        // Given: A core holding token1 at a price of four, a share worth one.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96 * 2;
        state.held1 = bound(held1, 16, Constants.MAX_SETTLEMENT_AMOUNT);
        state.supply = state.held1;

        // And: A token0 deposit, and a smaller token0 redeem.
        state.deposit0 = bound(deposit, 4, state.held1);
        state.redeem0 = bound(shares, 0, state.deposit0);

        // And: A token0 sale a wei under its value, no larger than the net swap.
        sold = bound(sold, 1, FixedPointMathLib.min(state.deposit0, state.held1 / 4) / 4);
        (state.swap0, state.swap1) = (-int256(sold), int256(4 * sold - 1));
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (uint256 shares0,, uint256 assets0,) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The deposit is levied the swap's whole wei of cost.
        assertEq(shares0, 4 * state.deposit0 - 1);

        // And: The redeem's token0 is rounded down.
        assertEq(assets0, state.redeem0 / 4);
    }

    function testFuzz_Success_getSettlementAmountsOut_RoundsAgainstFlows_Purchase(
        uint256 held0,
        uint256 deposit,
        uint256 spent,
        uint256 remainder
    ) public view {
        // Given: A core holding token0 at a price of a quarter, a share worth one.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96 / 2;
        state.held0 = 4 * bound(held0, 8, Constants.MAX_SETTLEMENT_AMOUNT);
        state.supply = state.held0 / 4;

        // And: A token1 deposit.
        state.deposit1 = bound(deposit, 8, Constants.MAX_SETTLEMENT_AMOUNT);

        // And: A token0 purchase within the net swap, filled under a wei from the price.
        spent = bound(spent, 2, FixedPointMathLib.min(state.deposit1, state.supply) / 4);
        remainder = bound(remainder, 1, 3);
        (state.swap0, state.swap1) = (int256(4 * (spent - 1) + remainder), -int256(spent));
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (, uint256 shares1,,) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The deposit is levied a wei, token0 valued down, at the value up.
        assertEq(shares1, FullMath.mulDiv(state.deposit1 - 1, state.supply, state.supply + 1));
    }

    function testFuzz_Success_getSettlementAmountsOut_RedeemPaidTheValueRoundedDownBesideAToken0Deposit(
        uint256 supply,
        uint256 held0,
        uint256 held1,
        uint256 deposit,
        uint256 remainder0,
        uint256 remainder1
    ) public view {
        // Given: A core at a price of a quarter, its token0 a part of a wei over whole.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96 / 2;
        held0 = bound(held0, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        remainder0 = bound(remainder0, 1, 3);
        state.held0 = 4 * held0 + remainder0;
        state.held1 = bound(held1, 0, Constants.MAX_SETTLEMENT_AMOUNT);

        // And: A token0 deposit whose part of a wei completes a wei, without a swap.
        deposit = bound(deposit, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        remainder1 = bound(remainder1, 4 - remainder0, 3);
        state.deposit0 = 4 * deposit + remainder1;

        // And: A token1 redeem of the whole supply.
        state.supply = bound(supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.redeem1 = state.supply;
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (,,, uint256 assets1) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The redeem is paid the existing value rounded down, none of the deposit.
        assertEq(assets1, held0 + state.held1);
    }

    function testFuzz_Success_getSettlementAmountsOut_DepositMintedAtTheValueRoundedUp(
        uint256 supply,
        uint256 held0,
        uint256 held1,
        uint256 remainder,
        uint256 deposit
    ) public view {
        // Given: A core at a price of a quarter, its token0 a part of a wei over whole.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96 / 2;
        held0 = bound(held0, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = 4 * held0 + bound(remainder, 1, 3);
        state.held1 = bound(held1, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        uint256 value = held0 + state.held1;

        // And: A token1 deposit a wei of value moves by a share or more, no swap.
        state.supply = bound(supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        uint256 least = FixedPointMathLib.divUp(value * (value + 1), state.supply);
        state.deposit1 = bound(deposit, least, least + Constants.MAX_SETTLEMENT_AMOUNT);
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (, uint256 shares1,,) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The deposit is minted at the existing aLP's value rounded up.
        assertEq(shares1, FullMath.mulDiv(state.deposit1, state.supply, value + 1));

        // And: Fewer shares than at that value rounded down.
        assertLt(shares1, FullMath.mulDiv(state.deposit1, state.supply, value));
    }

    function testFuzz_Success_getSettlementAmountsOut_StayersKeepTheValuePerShare(
        uint256 supply,
        uint256 shares,
        uint256 held0,
        uint256 held1,
        uint256 remainder,
        uint256 deposit
    ) public view {
        // Given: A core at a price of a quarter, its token0 a part of a wei over whole.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96 / 2;
        held0 = bound(held0, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        remainder = bound(remainder, 1, 3);
        state.held0 = 4 * held0 + remainder;
        state.held1 = bound(held1, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        uint256 value = held0 + state.held1;

        // And: A token1 redeem of part of the supply.
        state.supply = bound(supply, 2, Constants.MAX_SETTLEMENT_AMOUNT);
        state.redeem1 = bound(shares, 1, state.supply - 1);

        // And: A token1 deposit the part moves past the redeem's rounding, no swap.
        uint256 least = FixedPointMathLib.divUp(4 * value * (value + 1 + 2 * state.supply), state.supply);
        state.deposit1 = bound(deposit, least, least + Constants.MAX_SETTLEMENT_AMOUNT);
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (, uint256 shares1,, uint256 assets1) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The aLP left keeps the value per share or more, in quarter wei.
        uint256 valueBefore = 4 * value + remainder;
        uint256 valueLeft = valueBefore + 4 * state.deposit1 - 4 * assets1;
        assertGe(valueLeft * state.supply, valueBefore * (state.supply - state.redeem1 + shares1));

        // And: Less with the deposit minted at the value rounded down.
        shares1 = FullMath.mulDiv(state.deposit1, state.supply, value);
        assertLt(valueLeft * state.supply, valueBefore * (state.supply - state.redeem1 + shares1));
    }

    function testFuzz_Success_getSettlementAmountsOut_RedeemLeviedTheSwapCostRoundedUp(
        uint256 held,
        uint256 shares,
        uint256 sold,
        uint256 remainder,
        uint256 bought
    ) public view {
        // Given: Token0 held at a price of a quarter, a part of a wei over whole.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96 / 2;
        sold = bound(sold, 2, Constants.MAX_SETTLEMENT_AMOUNT);
        remainder = bound(remainder, 1, 3);
        held = bound(held, 4 * sold + 4, 4 * sold + Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = 4 * held + remainder;

        // And: A sale of that part and a whole value, at most its value rounded down.
        bought = bound(bought, 0, sold);
        (state.swap0, state.swap1) = (-int256(4 * sold + remainder), int256(bought));

        // And: A token1 redeem of half the supply, worth the token1 bought and more.
        state.redeem1 = bound(shares, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.supply = 2 * state.redeem1;
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (,,, uint256 assets1) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The redeem pays the swap's whole cost, the token0 sold valued up.
        assertEq(assets1, held / 2 - (sold + 1 - bought));
    }

    function testFuzz_Success_getSettlementAmountsOut_Token0HeldValuedOnce(
        uint256 supply,
        uint256 held,
        uint256 deposit
    ) public view {
        // Given: A core holding only token0 at a price of a quarter, its value floored.
        SettlementState memory state;
        state.sqrtPrice = SQRT_PRICE_ONE_X96 / 2;
        held = bound(held, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = 4 * held + 3;
        state.supply = bound(supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);

        // And: A token0 deposit whose value rounds down too, without a swap.
        deposit = bound(deposit, 0, Constants.MAX_SETTLEMENT_AMOUNT);
        state.deposit0 = 4 * deposit + 3;
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (uint256 shares0,,,) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: The deposit settles at the value per share, the token0 held floored once.
        assertEq(shares0, deposit == 0 ? 0 : FullMath.mulDiv(deposit, state.supply, held + 1));
    }

    function testFuzz_Success_getSettlementAmountsOut_TrustedPriceAboveUint128(
        uint256 exponent,
        uint256 supply,
        uint256 held0,
        uint256 held1,
        uint256 deposit,
        uint256 shares
    ) public view {
        // Given: A trusted sqrt price of a power of two above 2^128.
        SettlementState memory state;
        exponent = bound(exponent, 129, 150);
        state.sqrtPrice = uint160(1 << exponent);
        uint256 shift = 2 * exponent - 192;

        // And: Holdings whose values stay below 2^126.
        state.supply = bound(supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held0 = bound(held0, 1, 1 << (124 - shift));
        state.held1 = bound(held1, 0, 1 << 124);

        // And: A token0 deposit and a token0 redeem, without a swap.
        state.deposit0 = bound(deposit, 1, 1 << (124 - shift));
        state.redeem0 = bound(shares, 0, state.supply);
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (uint256 shares0,, uint256 assets0,) = planCacheLib.getSettlementAmountsOut(cache);

        // Then: Both settle at the existing aLP's value per share.
        uint256 value = state.held1 + (state.held0 << shift);
        assertEq(shares0, FullMath.mulDiv(state.deposit0 << shift, state.supply, value));
        assertEq(assets0, FullMath.mulDiv(state.redeem0, value, state.supply) >> shift);
    }

    function testFuzz_Success_getSettlementAmountsOut_ANegativeToken0AmountHoldsNoToken0(
        SettlementState memory state,
        uint256 bought,
        uint256 fee,
        uint256 short
    ) public view {
        // Given: A core at a price of one holding token1, a pending token1 deposit.
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.supply = bound(state.supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.deposit1 = bound(state.deposit1, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        (state.held0, state.deposit0, state.redeem0, state.redeem1, state.other1) = (0, 0, 0, 0, 0);

        // And: A purchase of token0 at a fee, the core's value after it positive.
        bought = bound(bought, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        fee = bound(fee, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.held1 = bound(state.held1, bought + fee + 1, bought + fee + Constants.MAX_SETTLEMENT_AMOUNT);
        (state.swap0, state.swap1) = (int256(bought), -int256(bought + fee));

        // And: More token0 spent than the purchase bought.
        state.other0 = -int256(bought + bound(short, 1, Constants.MAX_SETTLEMENT_AMOUNT));
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (uint256 shares0, uint256 shares1, uint256 assets0, uint256 assets1) =
            planCacheLib.getSettlementAmountsOut(cache);

        // Then: Without token0 held, the deposit needed no purchase and pays no levy.
        assertEq(shares1, FullMath.mulDiv(state.deposit1, state.supply, state.held1 - fee));
        assertEq(shares0, 0);
        assertEq(assets0, 0);
        assertEq(assets1, 0);
    }

    function testFuzz_Success_getSettlementAmountsOut_ANegativeToken1AmountHoldsNoToken1(
        SettlementState memory state,
        uint256 sold,
        uint256 fee,
        uint256 short
    ) public view {
        // Given: A core at a price of one holding token0, a pending token0 deposit.
        state.sqrtPrice = SQRT_PRICE_ONE_X96;
        state.supply = bound(state.supply, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        state.deposit0 = bound(state.deposit0, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        (state.held1, state.deposit1, state.redeem0, state.redeem1, state.other0) = (0, 0, 0, 0, 0);

        // And: A sale of token0 at a fee, the core's value after it positive.
        sold = bound(sold, 1, Constants.MAX_SETTLEMENT_AMOUNT);
        fee = bound(fee, 1, sold);
        state.held0 = bound(state.held0, sold + 1, sold + Constants.MAX_SETTLEMENT_AMOUNT);
        (state.swap0, state.swap1) = (-int256(sold), int256(sold - fee));

        // And: More token1 spent than the sale returned.
        state.other1 = -int256(sold - fee + bound(short, 1, Constants.MAX_SETTLEMENT_AMOUNT));
        PlanCache memory cache = setSettlementState(state);

        // When: Reading the settlement.
        (uint256 shares0, uint256 shares1, uint256 assets0, uint256 assets1) =
            planCacheLib.getSettlementAmountsOut(cache);

        // Then: Without token1 held, the deposit needed no sale and pays no levy.
        assertEq(shares0, FullMath.mulDiv(state.deposit0, state.supply, state.held0 - fee));
        assertEq(shares1, 0);
        assertEq(assets0, 0);
        assertEq(assets1, 0);
    }
}
