/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PricedRange } from "../../../src/vaults/types/PricedRange.sol";
import { Snapshot } from "../../../src/vaults/types/Snapshot.sol";
import { StepComputations, SwapState } from "../../../src/vaults/types/SwapState.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { WithdrawOptimizationMath } from "../../../src/vaults/libraries/math/WithdrawOptimizationMath.sol";

/**
 * @notice Symbolic tests for the library "WithdrawOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract WithdrawOptimizationMath_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getNextSqrtPrice_MovesPastTheStartAndAtMostToTheTarget(
        SwapState memory state,
        StepComputations memory step,
        uint256 sqrtPriceDelta,
        bool zeroForOne
    ) public pure {
        // Given: A pool price, a distinct target in the swap's direction, any move.
        vm.assume(state.sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && state.sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE);
        vm.assume(
            step.sqrtPriceTargetX96 >= TickMath.MIN_SQRT_PRICE && step.sqrtPriceTargetX96 <= TickMath.MAX_SQRT_PRICE
        );
        vm.assume(
            zeroForOne ? step.sqrtPriceTargetX96 < state.sqrtPriceX96 : step.sqrtPriceTargetX96 > state.sqrtPriceX96
        );

        // When: Moving the price by the move.
        uint160 sqrtPriceNew = WithdrawOptimizationMath.getNextSqrtPrice(zeroForOne, state, step, sqrtPriceDelta);

        // Then: It is past the step's start and at most at its target.
        if (zeroForOne) {
            assertGe(sqrtPriceNew, step.sqrtPriceTargetX96);
            assertLt(sqrtPriceNew, state.sqrtPriceX96);
        } else {
            assertGt(sqrtPriceNew, state.sqrtPriceX96);
            assertLe(sqrtPriceNew, step.sqrtPriceTargetX96);
        }
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getQuadraticCoefficients_TheQuadraticCoefficientIsNonNegative(
        SwapState memory state,
        uint256 amountOutLeft,
        uint256 holdingsIn,
        uint256 holdingsOut,
        uint256 amountIn,
        bool zeroForOne
    ) public pure {
        // Given: One range, prices, liquidity and holdings whose normalized terms fit.
        vm.assume(state.sqrtPriceX96 >= 1 << 64 && state.sqrtPriceX96 < 1 << 128 && state.fee < 1e6);
        vm.assume(state.liquidity < 1 << 100 && state.position.liquidity <= state.liquidity);
        uint256 holdings = holdingsIn > holdingsOut ? holdingsIn : holdingsOut;
        vm.assume(holdings < 1 << 128 && amountIn <= holdingsIn && amountOutLeft <= holdings);
        vm.assume(state.position.liquidity < holdings << 40);
        Snapshot memory snapshot;
        snapshot.ranges = new PricedRange[](1);

        // When: Taking the quadratic's coefficients.
        (int256 quadraticCoefficient,,) = WithdrawOptimizationMath.getQuadraticCoefficients(
            snapshot, zeroForOne, amountOutLeft, holdingsIn, holdingsOut, state, amountIn
        );

        // Then: The quadratic coefficient is non-negative.
        assertGe(quadraticCoefficient, 0);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getSqrtPrice_MovesPastTheStartAndAtMostToTheTarget(
        SwapState memory state,
        StepComputations memory step,
        uint256 amountOutLeft,
        uint256 holdingsIn,
        uint256 holdingsOut,
        uint256 amountIn,
        bool zeroForOne
    ) public pure {
        // Given: The coefficients' domain, a distinct target in the swap's direction.
        vm.assume(state.sqrtPriceX96 >= 1 << 64 && state.sqrtPriceX96 < 1 << 128 && state.fee < 1e6);
        vm.assume(state.liquidity < 1 << 100 && state.position.liquidity <= state.liquidity);
        uint256 holdings = holdingsIn > holdingsOut ? holdingsIn : holdingsOut;
        vm.assume(holdings < 1 << 128 && amountIn <= holdingsIn && amountOutLeft <= holdings);
        vm.assume(state.position.liquidity < holdings << 40);
        vm.assume(step.sqrtPriceTargetX96 >= 1 << 64 && step.sqrtPriceTargetX96 < 1 << 128);
        vm.assume(
            zeroForOne ? step.sqrtPriceTargetX96 < state.sqrtPriceX96 : step.sqrtPriceTargetX96 > state.sqrtPriceX96
        );
        Snapshot memory snapshot;
        snapshot.ranges = new PricedRange[](1);

        // When: Solving for the price where the sale's cost starts to set the shares.
        uint160 sqrtPriceNew = WithdrawOptimizationMath.getSqrtPrice(
            snapshot, zeroForOne, amountOutLeft, holdingsIn, holdingsOut, state, step, amountIn
        );

        // Then: It is past the step's start and at most at its target.
        if (zeroForOne) {
            assertGe(sqrtPriceNew, step.sqrtPriceTargetX96);
            assertLt(sqrtPriceNew, state.sqrtPriceX96);
        } else {
            assertGt(sqrtPriceNew, state.sqrtPriceX96);
            assertLe(sqrtPriceNew, step.sqrtPriceTargetX96);
        }
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getSharesForAmounts_AreAtMostTheSupplyOrNone(
        SwapState memory state,
        StepComputations memory step,
        uint256 amountOut,
        uint256 holdingsIn,
        uint256 holdingsOut,
        uint256 amountIn,
        uint256 supply,
        bool zeroForOne
    ) public pure {
        // Given: One range, a step in the swap's direction, uint128 amounts.
        vm.assume(state.sqrtPriceX96 >= 1 << 64 && state.sqrtPriceX96 < 1 << 128 && state.fee < 1e6);
        vm.assume(step.sqrtPriceTargetX96 >= 1 << 64 && step.sqrtPriceTargetX96 < 1 << 128);
        vm.assume(
            zeroForOne ? step.sqrtPriceTargetX96 <= state.sqrtPriceX96 : step.sqrtPriceTargetX96 >= state.sqrtPriceX96
        );
        vm.assume(state.liquidity != 0 && state.liquidity < 1 << 100 && state.position.liquidity <= state.liquidity);
        vm.assume(amountOut < 1 << 128 && state.amountOut < 1 << 128 && amountIn < 1 << 128 && supply < 1 << 128);
        vm.assume(holdingsIn != 0 && holdingsIn < 1 << 128 && holdingsOut < 1 << 128);
        Snapshot memory snapshot;
        snapshot.ranges = new PricedRange[](1);
        snapshot.supply = supply;

        // When: Taking the shares that fund the sale and pay the amount.
        (uint256 shares,,,) = WithdrawOptimizationMath.getSharesForAmounts(
            snapshot, zeroForOne, amountOut, holdingsIn, holdingsOut, state, step, amountIn
        );

        // Then: They are at most the whole supply, or none pay.
        assertTrue(shares == type(uint256).max || shares <= supply);
    }
}
