/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { MintOptimizationMath_Fuzz_Test } from "./_MintOptimizationMath.fuzz.t.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getMintAmountOut" of library "MintOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetMintAmountOut_MintOptimizationMath_Fuzz_Test is MintOptimizationMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getMintAmountOut_ZeroWithoutATokenOutCost(MintState memory state, uint256 shares)
        public
        view
    {
        // Given: Only tokenIn idle, any spot and a mint of the supply at most.
        if (state.zeroForOne) state.idle1 = 0;
        else state.idle0 = 0;
        state.supply = uint128(bound(state.supply, 1, type(uint128).max));
        state.sqrtPriceX96 = uint160(bound(state.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        shares = bound(shares, 0, state.supply);

        // When: Calculating the mint's tokenOut.
        (uint256 amountOut, uint256 activeLiquidityDelta) = optimizationMath.getMintAmountOut(
            snapshotOf(new PricedRange[](0), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee),
            state.sqrtPriceX96,
            state.zeroForOne,
            shares
        );

        // Then: The mint takes no tokenOut, and no liquidity.
        assertEq(amountOut, 0);
        assertEq(activeLiquidityDelta, 0);
    }

    function testFuzz_Success_getMintAmountOut_TheMintsTokenOutAndTheMarginsOfItsCeilings(
        MintState memory state,
        RangeState memory range,
        uint256 shares
    ) public view {
        // Given: A range around spot, idle tokens and a mint of the supply at most.
        PricedRange[] memory priced = givenValidRange(state, range);
        shares = bound(shares, 0, state.supply);

        // When: Calculating the mint's tokenOut.
        (uint256 amountOut, uint256 activeLiquidityDelta) = optimizationMath.getMintAmountOut(
            snapshotOf(priced, state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee),
            state.sqrtPriceX96,
            state.zeroForOne,
            shares
        );

        // Then: Zero without a cost, else the cost, n and for token0 its ceiling over J0.
        uint256 cost = pullOut(state, priced, state.sqrtPriceX96, shares);
        uint256 expected;
        if (cost > 0) {
            uint256 floor = FullMath.mulDiv(state.sqrtPriceX96, state.sqrtPriceX96, 1 << 96);
            expected = cost + priced.length + (state.zeroForOne ? 0 : FixedPointMathLib.divUp(cost, floor));
        }
        assertEq(amountOut, expected);

        // And: The liquidity is the mint's in the ranges the buy trades against.
        assertEq(
            activeLiquidityDelta,
            snapshotLib.getMintLiquidityDelta(priced, state.sqrtPriceX96, shares, state.supply, state.zeroForOne)
        );
    }
}
