/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Snapshot } from "../../../src/vaults/types/Snapshot.sol";
import { StepComputations, SwapState, SwapStateLib } from "../../../src/vaults/types/SwapState.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Symbolic tests for the library "SwapStateLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract SwapStateLib_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                              HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function stateOf(uint128 liquidity, uint256 feeShare, uint256 unstakedLiquidity)
        internal
        pure
        returns (SwapState memory state)
    {
        (state.liquidity, state.feeShare, state.position.unstakedLiquidity) = (liquidity, feeShare, unstakedLiquidity);
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getStepFees_RoundedUpIsTheCeiledShare(
        uint256 feeAmount,
        uint128 liquidity,
        uint256 feeShare,
        uint128 unstakedLiquidity
    ) public pure {
        // Given: Fee < 2^64, pool liquidity, share below one, core unstaked liquidity.
        vm.assume(feeAmount < 1 << 64 && liquidity != 0 && feeShare <= 1e10);
        SwapState memory state = stateOf(liquidity, feeShare, unstakedLiquidity);
        StepComputations memory step;
        step.feeAmount = feeAmount;

        // When: Taking the step's fees rounded up.
        // Then: They are the unstaked liquidity's share of the fee, rounded up.
        assertEq(
            SwapStateLib.getStepFees(state, step, true),
            (feeAmount * feeShare * unstakedLiquidity + 1e10 * uint256(liquidity) - 1) / (1e10 * uint256(liquidity))
        );
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getStepFees_RoundedDownIsTheFlooredShare(
        uint256 feeAmount,
        uint128 liquidity,
        uint256 feeShare,
        uint128 unstakedLiquidity
    ) public pure {
        // Given: Fee < 2^64, pool liquidity, share below one, core unstaked liquidity.
        vm.assume(feeAmount < 1 << 64 && liquidity != 0 && feeShare <= 1e10);
        SwapState memory state = stateOf(liquidity, feeShare, unstakedLiquidity);
        StepComputations memory step;
        step.feeAmount = feeAmount;

        // When: Taking the step's fees rounded down.
        // Then: They are the unstaked liquidity's share of the fee, rounded down.
        assertEq(
            SwapStateLib.getStepFees(state, step, false),
            feeAmount * feeShare * unstakedLiquidity / (1e10 * uint256(liquidity))
        );
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getStepFees_RoundedUpExceedsRoundedDownByAtMostOne(
        uint256 feeAmount,
        uint128 liquidity,
        uint256 feeShare,
        uint128 unstakedLiquidity
    ) public pure {
        // Given: Fee < 2^64, pool liquidity, share below one, core unstaked liquidity.
        vm.assume(feeAmount < 1 << 64 && liquidity != 0 && feeShare <= 1e10);
        SwapState memory state = stateOf(liquidity, feeShare, unstakedLiquidity);
        StepComputations memory step;
        step.feeAmount = feeAmount;

        // When: Taking the step's fees both ways.
        uint256 feesUp = SwapStateLib.getStepFees(state, step, true);
        uint256 feesDown = SwapStateLib.getStepFees(state, step, false);

        // Then: Rounded up is rounded down or one more.
        assertLe(feesDown, feesUp);
        assertLe(feesUp, feesDown + 1);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getStepFees_NeverExceedTheStepsFee(
        uint256 feeAmount,
        uint128 liquidity,
        uint256 feeShare,
        uint128 unstakedLiquidity,
        bool roundUp
    ) public pure {
        // Given: Fee below 2^64, pool liquidity, share below one, unstaked within pool's.
        vm.assume(feeAmount < 1 << 64 && liquidity != 0 && feeShare <= 1e10 && unstakedLiquidity <= liquidity);
        SwapState memory state = stateOf(liquidity, feeShare, unstakedLiquidity);
        StepComputations memory step;
        step.feeAmount = feeAmount;

        // When: Taking the step's fees either way.
        // Then: They are at most the step's fee.
        assertLe(SwapStateLib.getStepFees(state, step, roundUp), feeAmount);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getStepFees_AreNothingWithoutUnstakedLiquidity(
        uint256 feeAmount,
        uint128 liquidity,
        uint256 feeShare,
        bool roundUp
    ) public pure {
        // Given: Fee below 2^64, pool liquidity, share below one, no unstaked liquidity.
        vm.assume(feeAmount < 1 << 64 && liquidity != 0 && feeShare <= 1e10);
        SwapState memory state = stateOf(liquidity, feeShare, 0);
        StepComputations memory step;
        step.feeAmount = feeAmount;

        // When: Taking the step's fees either way.
        // Then: They are zero.
        assertEq(SwapStateLib.getStepFees(state, step, roundUp), 0);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getStepFees_AreMonotoneInTheFee(
        uint256 feeAmountLow,
        uint256 feeAmountHigh,
        uint128 liquidity,
        uint256 feeShare,
        uint128 unstakedLiquidity,
        bool roundUp
    ) public pure {
        // Given: Two ordered fees below 2^64, pool liquidity, share < one, core unstaked.
        vm.assume(feeAmountLow <= feeAmountHigh && feeAmountHigh < 1 << 64 && liquidity != 0 && feeShare <= 1e10);
        SwapState memory state = stateOf(liquidity, feeShare, unstakedLiquidity);
        StepComputations memory step;

        // When: Taking the step's fees for both.
        step.feeAmount = feeAmountLow;
        uint256 feesLow = SwapStateLib.getStepFees(state, step, roundUp);
        step.feeAmount = feeAmountHigh;
        uint256 feesHigh = SwapStateLib.getStepFees(state, step, roundUp);

        // Then: The larger fee gives at least the smaller one's share.
        assertLe(feesLow, feesHigh);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_computeSwapStep_OneForZero_TheFeeIsThePoolsFeeOnTheInput(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        uint24 fee
    ) public pure {
        // Given: Price below a target of at most one, liquidity < 2^63, fee below one.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= sqrtPriceTargetX96);
        vm.assume(sqrtPriceTargetX96 <= 1 << 96 && fee < 1e6 && liquidity < 1 << 63);
        SwapState memory state;
        (state.sqrtPriceX96, state.liquidity, state.fee) = (sqrtPriceX96, liquidity, fee);
        StepComputations memory step;
        step.sqrtPriceTargetX96 = sqrtPriceTargetX96;

        // When: Computing the step as the pool does.
        SwapStateLib.computeSwapStep(state, step, false, true);

        // Then: Its fee is the pool's fee on its input, rounded up.
        assertEq(step.feeAmount, (step.amountIn * fee + (1e6 - fee) - 1) / (1e6 - fee));
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_computeSwapStep_OneForZero_TheGrossInputNetOfTheFeeCoversTheInput(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        uint24 fee
    ) public pure {
        // Given: Price below a target of at most one, liquidity < 2^63, fee below one.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= sqrtPriceTargetX96);
        vm.assume(sqrtPriceTargetX96 <= 1 << 96 && fee < 1e6 && liquidity < 1 << 63);
        SwapState memory state;
        (state.sqrtPriceX96, state.liquidity, state.fee) = (sqrtPriceX96, liquidity, fee);
        StepComputations memory step;
        step.sqrtPriceTargetX96 = sqrtPriceTargetX96;

        // When: Stepping as the pool does, and taking the pool's fee off the gross input.
        SwapStateLib.computeSwapStep(state, step, false, true);
        uint256 net = (step.amountIn + step.feeAmount) * (1e6 - fee) / 1e6;

        // Then: The net input reaches the step's input.
        assertGe(net, step.amountIn);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_computeSwapStep_OneForZero_RoundedUpDominatesRoundedDown(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        uint24 fee
    ) public pure {
        // Given: Price below a target of at most one, liquidity < 2^63, fee below one.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= sqrtPriceTargetX96);
        vm.assume(sqrtPriceTargetX96 <= 1 << 96 && fee < 1e6 && liquidity < 1 << 63);
        SwapState memory state;
        (state.sqrtPriceX96, state.liquidity, state.fee) = (sqrtPriceX96, liquidity, fee);
        StepComputations memory stepUp;
        StepComputations memory stepDown;
        (stepUp.sqrtPriceTargetX96, stepDown.sqrtPriceTargetX96) = (sqrtPriceTargetX96, sqrtPriceTargetX96);

        // When: Computing the step both ways.
        SwapStateLib.computeSwapStep(state, stepUp, false, true);
        SwapStateLib.computeSwapStep(state, stepDown, false, false);

        // Then: Rounded up takes at least rounded down's input and fee, same output.
        assertGe(stepUp.amountIn, stepDown.amountIn);
        assertGe(stepUp.feeAmount, stepDown.feeAmount);
        assertEq(stepUp.amountOut, stepDown.amountOut);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_computeSwapStep_TheFeeOnAWeiMoreInputRoundedUpExceedsRoundedDownByAtMostTwo(
        uint64 amountIn,
        uint24 fee
    ) public pure {
        // Given: A step's input rounded down and a fee of at most 10%.
        vm.assume(fee <= 100_000);

        // When: Taking the fee rounded up on a wei more input, rounded down on the input.
        uint256 feeUp = (uint256(amountIn) + 1) * fee / (1e6 - fee);
        if ((uint256(amountIn) + 1) * fee % (1e6 - fee) != 0) ++feeUp;
        uint256 feeDown = uint256(amountIn) * fee / (1e6 - fee);

        // Then: The first is at most two wei above the second.
        assertLe(feeUp, feeDown + 2);
    }

    function prove_accrueFees_MoveTheFeeIntoThePositionAndTheSnapshot(
        int256 constant0,
        int256 constant1,
        uint256 fees0,
        uint256 fees1,
        bool zeroForOne,
        uint256 feesIn
    ) public pure {
        // Given: A position with constants, a snapshot with fees, a fee that fits both.
        vm.assume(feesIn < 1 << 255 && fees0 <= type(uint256).max - feesIn && fees1 <= type(uint256).max - feesIn);
        vm.assume(constant0 >= type(int256).min + int256(feesIn) && constant1 >= type(int256).min + int256(feesIn));
        SwapState memory state;
        (state.position.constant0, state.position.constant1) = (constant0, constant1);
        Snapshot memory snapshot;
        (snapshot.fees0, snapshot.fees1) = (fees0, fees1);

        // When: Accruing the fee.
        SwapStateLib.accrueFees(state, snapshot, zeroForOne, feesIn);

        // Then: TokenIn's constant drops and its fees rise by the fee, tokenOut's stay.
        assertEq(state.position.constant0, zeroForOne ? constant0 - int256(feesIn) : constant0);
        assertEq(state.position.constant1, zeroForOne ? constant1 : constant1 - int256(feesIn));
        assertEq(snapshot.fees0, zeroForOne ? fees0 + feesIn : fees0);
        assertEq(snapshot.fees1, zeroForOne ? fees1 : fees1 + feesIn);
    }
}
