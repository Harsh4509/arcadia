/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Claimable } from "../../../../src/core/types/State.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { QueueLib } from "../../../../src/core/libraries/state/QueueLib.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "takeClaimable" of library "QueueLib".
 */
contract TakeClaimable_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_takeClaimable_EmptyPile(uint256 amountIn, uint256 maxAmountOut) public {
        // Given: An empty pile.
        queueLib.setClaimable(Claimable({ amountIn: 0, amountOut: 0 }));

        // When: Taking any amount of it.
        // Then: It reverts.
        vm.expectRevert(QueueLib.InsufficientClaimable.selector);
        queueLib.takeClaimable(amountIn, maxAmountOut);
    }

    function testFuzz_Revert_takeClaimable_EmptyPile_NothingTaken(uint256 maxAmountOut) public {
        // Given: An empty pile.
        queueLib.setClaimable(Claimable({ amountIn: 0, amountOut: 0 }));

        // When: Taking none of it.
        // Then: It reverts.
        vm.expectRevert(QueueLib.InsufficientClaimable.selector);
        queueLib.takeClaimable(0, maxAmountOut);
    }

    function testFuzz_Revert_takeClaimable_InputAboveThePile(
        Claimable memory claimable,
        uint256 amountIn,
        uint256 maxAmountOut
    ) public {
        // Given: A pile, and an input above its claimable input.
        queueLib.setClaimable(claimable);
        amountIn = bound(amountIn, uint256(claimable.amountIn) + 1, type(uint256).max);

        // When: Taking it.
        // Then: It reverts.
        vm.expectRevert(QueueLib.InsufficientClaimable.selector);
        queueLib.takeClaimable(amountIn, maxAmountOut);
    }

    function testFuzz_Success_takeClaimable_AtTheFilledRate(Claimable memory claimable, uint256 amountIn) public {
        // Given: A pile with claimable input, and an input within it.
        claimable.amountIn = uint128(bound(claimable.amountIn, 1, type(uint128).max));
        queueLib.setClaimable(claimable);
        amountIn = bound(amountIn, 0, claimable.amountIn);

        // When: Taking it with no cap on the output.
        uint256 amountOut = queueLib.takeClaimable(amountIn, type(uint256).max);

        // Then: It claims its pro-rata output rounded down, and the pile shrinks by both.
        assertEq(amountOut, amountIn * claimable.amountOut / claimable.amountIn);
        Claimable memory claimableAfter = queueLib.getClaimable();
        assertEq(claimableAfter.amountIn, claimable.amountIn - amountIn);
        assertEq(claimableAfter.amountOut, claimable.amountOut - amountOut);
    }

    function testFuzz_Success_takeClaimable_CapsTheOutput(
        Claimable memory claimable,
        uint256 amountIn,
        uint256 maxAmountOut
    ) public {
        // Given: A pile with both sides, an input worth output and a cap below its share.
        claimable.amountIn = uint128(bound(claimable.amountIn, 1, type(uint128).max));
        claimable.amountOut = uint128(bound(claimable.amountOut, 1, type(uint128).max));
        queueLib.setClaimable(claimable);
        amountIn = bound(amountIn, FixedPointMathLib.divUp(claimable.amountIn, claimable.amountOut), claimable.amountIn);
        uint256 floorOut = amountIn * claimable.amountOut / claimable.amountIn;
        maxAmountOut = bound(maxAmountOut, 0, floorOut - 1);

        // When: Taking it.
        uint256 amountOut = queueLib.takeClaimable(amountIn, maxAmountOut);

        // Then: It claims exactly the cap, and the pile shrinks by the input and the cap.
        assertEq(amountOut, maxAmountOut);
        Claimable memory claimableAfter = queueLib.getClaimable();
        assertEq(claimableAfter.amountIn, claimable.amountIn - amountIn);
        assertEq(claimableAfter.amountOut, claimable.amountOut - maxAmountOut);
    }

    function testFuzz_Success_takeClaimable_AllEmptiesThePile(Claimable memory claimable) public {
        // Given: A pile with claimable input.
        claimable.amountIn = uint128(bound(claimable.amountIn, 1, type(uint128).max));
        queueLib.setClaimable(claimable);

        // When: Taking all of it with no cap.
        uint256 amountOut = queueLib.takeClaimable(claimable.amountIn, type(uint256).max);

        // Then: The whole output is claimed and the pile is empty.
        assertEq(amountOut, claimable.amountOut);
        Claimable memory claimableAfter = queueLib.getClaimable();
        assertEq(claimableAfter.amountIn, 0);
        assertEq(claimableAfter.amountOut, 0);
    }

    function testFuzz_Success_takeClaimable_RemainingRateNeverDrops(
        Claimable memory claimable,
        uint256 amountIn,
        uint256 maxAmountOut
    ) public {
        // Given: A pile with claimable input, an input within it and any cap.
        claimable.amountIn = uint128(bound(claimable.amountIn, 1, type(uint128).max));
        queueLib.setClaimable(claimable);
        amountIn = bound(amountIn, 0, claimable.amountIn);

        // When: Taking it.
        queueLib.takeClaimable(amountIn, maxAmountOut);

        // Then: The output left per input left is at least the pile's rate before.
        Claimable memory claimableAfter = queueLib.getClaimable();
        assertGe(
            uint256(claimableAfter.amountOut) * claimable.amountIn,
            uint256(claimable.amountOut) * claimableAfter.amountIn
        );
    }

    function testFuzz_Success_takeClaimable_ZeroInputReleasesTheDust(uint128 claimableOut, uint256 maxAmountOut)
        public
    {
        // Given: A pile of output left with no input, as after a partial mint rounded up.
        claimableOut = uint128(bound(claimableOut, 1, type(uint128).max));
        queueLib.setClaimable(Claimable({ amountIn: 0, amountOut: claimableOut }));

        // When: Taking no input under a cap.
        uint256 amountOut = queueLib.takeClaimable(0, maxAmountOut);

        // Then: It claims the output up to the cap.
        uint256 expected = maxAmountOut < claimableOut ? maxAmountOut : claimableOut;
        assertEq(amountOut, expected);
        assertEq(queueLib.getClaimable().amountOut, claimableOut - expected);
    }
}
