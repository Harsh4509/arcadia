/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Snapshot } from "../../../src/vaults/types/Snapshot.sol";
import { StepComputations, SwapState, SwapStateLib } from "../../../src/vaults/types/SwapState.sol";

contract SwapStateLibExtension {
    function getSwapState(Snapshot memory snapshot, address pool, bool zeroForOne)
        external
        view
        returns (SwapState memory state)
    {
        state = SwapStateLib.getSwapState(snapshot, pool, zeroForOne);
    }

    function setNextTick(SwapState memory state, address pool, bool zeroForOne, uint160 sqrtPriceLimitX96)
        external
        view
        returns (StepComputations memory step)
    {
        SwapStateLib.setNextTick(step, state, pool, zeroForOne, sqrtPriceLimitX96);
    }

    function computeSwapStep(SwapState memory state, StepComputations memory step, bool zeroForOne, bool roundUp)
        external
        pure
        returns (StepComputations memory)
    {
        SwapStateLib.computeSwapStep(state, step, zeroForOne, roundUp);
        return step;
    }

    function getStepFees(SwapState memory state, StepComputations memory step, bool roundUp)
        external
        pure
        returns (uint256 fees)
    {
        fees = SwapStateLib.getStepFees(state, step, roundUp);
    }

    function accrueFees(SwapState memory state, Snapshot memory snapshot, bool zeroForOne, uint256 feesIn)
        external
        pure
        returns (SwapState memory, Snapshot memory)
    {
        SwapStateLib.accrueFees(state, snapshot, zeroForOne, feesIn);
        return (state, snapshot);
    }

    function crossTick(
        SwapState memory state,
        StepComputations memory step,
        Snapshot memory snapshot,
        address pool,
        bool zeroForOne,
        uint160 sqrtPriceLimitX96
    ) external view returns (bool crossed, SwapState memory) {
        crossed = SwapStateLib.crossTick(state, step, snapshot, pool, zeroForOne, sqrtPriceLimitX96);
        return (crossed, state);
    }
}
