/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { EquivalentPositionMathExtension } from "../../../utils/extensions/EquivalentPositionMathExtension.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { LiquidityAmounts } from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Common logic needed by all "EquivalentPositionMath" fuzz tests.
 */
abstract contract EquivalentPositionMath_Fuzz_Test is Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                 STRUCTS
    ////////////////////////////////////////////////////////////// */

    // Three ranges and a buffer, as a test stages them.
    struct HoldingState {
        int24[3] ticksLower;
        int24[3] ticksUpper;
        uint128[3] liquidities;
        uint128 buffer0;
        uint128 buffer1;
    }

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    EquivalentPositionMathExtension internal equivalentPositionMath;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();
        equivalentPositionMath = new EquivalentPositionMathExtension();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function pushRange(int24 tickLower, int24 tickUpper, uint128 liquidity) internal {
        equivalentPositionMath.pushRange(
            PricedRange({
                liquidity: liquidity,
                unstakedLiquidity: liquidity,
                sqrtPriceLowerX96: TickMath.getSqrtPriceAtTick(tickLower),
                sqrtPriceUpperX96: TickMath.getSqrtPriceAtTick(tickUpper)
            })
        );
    }

    function assertHoldsTheRanges(
        HoldingState memory state,
        uint160 sqrtPriceBuiltX96,
        uint160 sqrtPriceX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure {
        // Each token tops the holdings by a wei at most per floor taken at the build.
        uint256 bound0;
        uint256 bound1;
        uint256 touching;
        for (uint256 i; i < state.liquidities.length; ++i) {
            if (state.liquidities[i] == 0) continue;
            {
                (uint256 range0, uint256 range1) = LiquidityAmounts.getAmountsForLiquidity(
                    sqrtPriceX96,
                    TickMath.getSqrtPriceAtTick(state.ticksLower[i]),
                    TickMath.getSqrtPriceAtTick(state.ticksUpper[i]),
                    state.liquidities[i]
                );
                assertGe(amount0, range0);
                assertGe(amount1, range1);
                (amount0, amount1) = (amount0 - range0, amount1 - range1);
            }
            uint160 lower = TickMath.getSqrtPriceAtTick(state.ticksLower[i]);
            uint160 upper = TickMath.getSqrtPriceAtTick(state.ticksUpper[i]);
            if (sqrtPriceBuiltX96 < lower) {
                ++bound0;
            } else if (sqrtPriceBuiltX96 <= upper) {
                ++touching;
                if (sqrtPriceBuiltX96 < upper) ++bound0;
                if (sqrtPriceBuiltX96 > lower) ++bound1;
            }
        }
        if (touching > 0) (bound0, bound1) = (bound0 + touching - 1, bound1 + touching - 1);
        assertGe(amount0, state.buffer0);
        assertLe(amount0 - state.buffer0, bound0);
        assertGe(amount1, state.buffer1);
        assertLe(amount1 - state.buffer1, bound1);
    }
}
