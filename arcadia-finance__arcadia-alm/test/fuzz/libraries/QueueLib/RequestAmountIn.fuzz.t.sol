/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "requestAmountIn" of library "QueueLib".
 */
contract RequestAmountIn_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_requestAmountIn_ZeroBatchAmountOut(uint256 amountOut, uint256 batchAmountIn) public {
        // Given: A batch with no output.

        // When: Pricing an output against it.
        // Then: It reverts.
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        queueLib.requestAmountIn(amountOut, batchAmountIn, 0);
    }

    function testFuzz_Success_requestAmountIn_RoundsUp(uint128 amountOut, uint128 batchAmountIn, uint128 batchAmountOut)
        public
        view
    {
        // Given: An output within a batch with output.
        batchAmountOut = uint128(bound(batchAmountOut, 1, type(uint128).max));
        amountOut = uint128(bound(amountOut, 0, batchAmountOut));

        // When: Pricing it.
        uint256 amountIn = queueLib.requestAmountIn(amountOut, batchAmountIn, batchAmountOut);

        // Then: It is the output's part of the batch input, rounded up.
        uint256 product = uint256(amountOut) * batchAmountIn;
        assertEq(amountIn, product / batchAmountOut + (product % batchAmountOut == 0 ? 0 : 1));
    }

    function testFuzz_Success_requestAmountIn_NeverBelowTheBatchRate(
        uint128 amountOut,
        uint128 batchAmountIn,
        uint128 batchAmountOut
    ) public view {
        // Given: An output within a batch with output.
        batchAmountOut = uint128(bound(batchAmountOut, 1, type(uint128).max));
        amountOut = uint128(bound(amountOut, 0, batchAmountOut));

        // When: Pricing it.
        uint256 amountIn = queueLib.requestAmountIn(amountOut, batchAmountIn, batchAmountOut);

        // Then: The pair is at or below the batch rate, and the input within the batch's.
        assertLe(uint256(amountOut) * batchAmountIn, amountIn * batchAmountOut);
        assertLe(amountIn, batchAmountIn);
    }
}
