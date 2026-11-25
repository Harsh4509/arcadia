/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "requestAmountOut" of library "QueueLib".
 */
contract RequestAmountOut_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_requestAmountOut_ZeroBatchAmountIn(uint256 amountIn, uint256 batchAmountOut) public {
        // Given: A batch with no input.

        // When: Splitting a request against it.
        // Then: It reverts.
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        queueLib.requestAmountOut(amountIn, 0, batchAmountOut);
    }

    function testFuzz_Success_requestAmountOut_SplitsProRata(
        uint128 amountIn,
        uint64 batchAmountOut,
        uint256 batchAmountIn
    ) public view {
        // Given: A request and a batch rate at which it is not dust.
        amountIn = uint128(bound(amountIn, 1, type(uint128).max));
        batchAmountOut = uint64(bound(batchAmountOut, 1, type(uint64).max));
        batchAmountIn = bound(batchAmountIn, 1, uint256(amountIn) * batchAmountOut);

        // When: Splitting it.
        uint256 amountOut = queueLib.requestAmountOut(amountIn, batchAmountIn, batchAmountOut);

        // Then: It takes its amount at the batch rate, rounded down.
        assertEq(amountOut, uint256(amountIn) * batchAmountOut / batchAmountIn);
    }

    function testFuzz_Success_requestAmountOut_Dust(uint64 amountIn, uint64 batchAmountOut, uint256 batchAmountIn)
        public
        view
    {
        // Given: A request whose share of the batch floors to zero.
        batchAmountIn = bound(batchAmountIn, uint256(amountIn) * batchAmountOut + 1, type(uint256).max);

        // When: Splitting it.
        uint256 amountOut = queueLib.requestAmountOut(amountIn, batchAmountIn, batchAmountOut);

        // Then: It returns zero.
        assertEq(amountOut, 0);
    }
}
