/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { MintOptimizationMathExtension } from "../../../utils/extensions/MintOptimizationMathExtension.sol";
import { OptimizationMath_Fuzz_Test } from "../_OptimizationMath.fuzz.t.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Common logic needed by all "MintOptimizationMath" fuzz tests.
 */
// forge-lint: disable-next-item(unsafe-typecast)
abstract contract MintOptimizationMath_Fuzz_Test is OptimizationMath_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    MintOptimizationMathExtension internal optimizationMath;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(OptimizationMath_Fuzz_Test) {
        OptimizationMath_Fuzz_Test.setUp();
        optimizationMath = new MintOptimizationMathExtension();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function givenValidRange(MintState memory state, RangeState memory range)
        internal
        pure
        returns (PricedRange[] memory priced)
    {
        // And: A range around a spot price in the band.
        givenValidState(state, range, false);
        RangeState[] memory ranges = new RangeState[](1);
        ranges[0] = range;
        priced = pricedOf(ranges);
    }

    function givenValidBuy(MintState memory state, PricedRange[] memory priced, uint256 shares, uint160 sqrtPriceEnd)
        internal
        view
    {
        // And: Other liquidity selling the pull, its rounding and a wei per step.
        (uint256 cost0, uint256 cost1) = snapshotLib.getMintAmounts(
            priced, state.sqrtPriceX96, state.idle0, state.idle1, shares, state.supply, state.zeroForOne
        );
        uint256 most = state.zeroForOne
            ? cost1 + priced.length + 1
            : cost0 + priced.length + 1
                + cost0.divUp(uint256(state.sqrtPriceX96).fullMulDiv(state.sqrtPriceX96, 1 << 96));
        most += FixedPointMathLib.dist(
            TickMath.getTickAtSqrtPrice(sqrtPriceEnd), TickMath.getTickAtSqrtPrice(state.sqrtPriceX96)
        ) / uint24(Constants.BITMAP_WORD_TICKS) + 2 + 2 * priced.length;
        uint256 rangesLiquidity;
        for (uint256 i; i < priced.length; ++i) {
            rangesLiquidity += priced[i].liquidity;
        }
        uint256 least = rangesLiquidity
            + (state.zeroForOne
                    ? (most + 1).fullMulDivUp(1 << 96, state.sqrtPriceX96 - sqrtPriceEnd)
                    : (most + 1)
                        .fullMulDivUp(state.sqrtPriceX96, 1 << 96)
                        .fullMulDivUp(sqrtPriceEnd, sqrtPriceEnd - state.sqrtPriceX96));
        // And: Hole: a buy whose other liquidity overflows a uint128.
        vm.assume(least <= type(uint128).max);
        state.liquidity = uint128(bound(state.liquidity, least, type(uint128).max));
    }

    function pullOut(MintState memory state, PricedRange[] memory priced, uint160 sqrtPriceX96, uint256 shares)
        internal
        view
        returns (uint256 pull)
    {
        // The tokenOut a mint of the shares pulls at a price.
        (uint256 pull0, uint256 pull1) = snapshotLib.getMintAmounts(
            priced, sqrtPriceX96, state.idle0, state.idle1, shares, state.supply, state.zeroForOne
        );
        pull = state.zeroForOne ? pull1 : pull0;
    }
}
