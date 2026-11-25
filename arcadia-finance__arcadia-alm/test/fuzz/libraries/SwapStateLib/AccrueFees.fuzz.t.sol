/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SwapState } from "../../../../src/vaults/types/SwapState.sol";
import { SwapStateLib_Fuzz_Test } from "./_SwapStateLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "accrueFees" of library "SwapStateLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract AccrueFees_SwapStateLib_Fuzz_Test is SwapStateLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_accrueFees_FeesPastInt256(
        SwapState memory state,
        Snapshot memory snapshot,
        bool zeroForOne,
        uint256 feesIn
    ) public {
        // Given: A fee share past the int256 maximum.
        feesIn = bound(feesIn, uint256(type(int256).max) + 1, type(uint256).max);

        // When: Accruing it.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        swapStateLib.accrueFees(state, snapshot, zeroForOne, feesIn);
    }

    function testFuzz_Success_accrueFees_Token0(SwapState memory state, Snapshot memory snapshot, uint256 feesIn)
        public
        view
    {
        // Given: The core's constants and fees, each within a uint128 of zero.
        state.position.constant0 = bound(state.position.constant0, type(int128).min, type(int128).max);
        state.position.constant1 = bound(state.position.constant1, type(int128).min, type(int128).max);
        snapshot.fees0 = bound(snapshot.fees0, 0, type(uint128).max);
        snapshot.fees1 = bound(snapshot.fees1, 0, type(uint128).max);

        // And: A token0 fee share within a uint128.
        feesIn = bound(feesIn, 1, type(uint128).max);

        // When: Accruing it on a token0 sale.
        (SwapState memory stateAfter, Snapshot memory snapshotAfter) =
            swapStateLib.accrueFees(state, snapshot, true, feesIn);

        // Then: The core's token0 fees rise by it, as does the token0 its position holds.
        assertEq(snapshotAfter.fees0, snapshot.fees0 + feesIn);
        assertEq(stateAfter.position.constant0, state.position.constant0 - int256(feesIn));

        // And: Its token1 is untouched.
        assertEq(snapshotAfter.fees1, snapshot.fees1);
        assertEq(stateAfter.position.constant1, state.position.constant1);
    }

    function testFuzz_Success_accrueFees_Token1(SwapState memory state, Snapshot memory snapshot, uint256 feesIn)
        public
        view
    {
        // Given: The core's constants and fees, each within a uint128 of zero.
        state.position.constant0 = bound(state.position.constant0, type(int128).min, type(int128).max);
        state.position.constant1 = bound(state.position.constant1, type(int128).min, type(int128).max);
        snapshot.fees0 = bound(snapshot.fees0, 0, type(uint128).max);
        snapshot.fees1 = bound(snapshot.fees1, 0, type(uint128).max);

        // And: A token1 fee share within a uint128.
        feesIn = bound(feesIn, 1, type(uint128).max);

        // When: Accruing it on a token1 sale.
        (SwapState memory stateAfter, Snapshot memory snapshotAfter) =
            swapStateLib.accrueFees(state, snapshot, false, feesIn);

        // Then: The core's token1 fees rise by it, as does the token1 its position holds.
        assertEq(snapshotAfter.fees1, snapshot.fees1 + feesIn);
        assertEq(stateAfter.position.constant1, state.position.constant1 - int256(feesIn));

        // And: Its token0 is untouched.
        assertEq(snapshotAfter.fees0, snapshot.fees0);
        assertEq(stateAfter.position.constant0, state.position.constant0);
    }
}
