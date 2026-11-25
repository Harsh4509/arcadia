/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Claimable, Epoch, Record } from "../../../src/core/types/State.sol";
import { QueueLib } from "../../../src/core/libraries/state/QueueLib.sol";
import { QueueLibExtension } from "../../utils/extensions/QueueLibExtension.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { stdError } from "@forge-std/StdError.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";

/**
 * @notice Symbolic tests for the library "QueueLib".
 */
contract QueueLib_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    QueueLibExtension internal queueLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public {
        queueLib = new QueueLibExtension();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function prove_startClearedEpoch_SucceedsIffTheNextIdFitsUint32(
        address vault,
        uint32 pendingEpoch,
        uint32 lastClearedEpoch
    ) public {
        // Given: Any pending and last cleared epoch of a deposit queue.
        queueLib.setPendingEpochs(vault, pendingEpoch, 0);
        queueLib.setLastClearedEpochs(vault, lastClearedEpoch, 0);
        uint256 highest = pendingEpoch > lastClearedEpoch ? pendingEpoch : lastClearedEpoch;

        // When: Starting a cleared epoch under the next id.
        (bool success, bytes memory result) =
            address(queueLib).call(abi.encodeCall(QueueLibExtension.startClearedEpoch, (vault, true)));

        // Then: It succeeds iff the highest id is below uint32 max, and takes the next.
        assertEq(success, highest < type(uint32).max);
        if (success) assertEq(queueLib.getLastClearedDepositEpoch(vault), highest + 1);
        else assertEq(result, stdError.arithmeticError);
    }

    function prove_isPending_isSettled_PartitionTheNonEmptyRecords(
        uint256 recordEpoch,
        uint256 pendingEpoch,
        uint256 amountIn
    ) public pure {
        // Given: Any record.
        // When: Classifying it.
        bool pending = QueueLib.isPending(recordEpoch, pendingEpoch, amountIn);
        bool settled = QueueLib.isSettled(recordEpoch, pendingEpoch, amountIn);

        // Then: A non-empty record is exactly one of both, an empty one neither.
        assertFalse(pending && settled);
        assertEq(pending || settled, amountIn != 0);
    }

    function prove_requirePending_RevertsIffTheRecordIsNotAnAmountInThePendingEpoch(
        uint256 recordEpoch,
        uint256 pendingEpoch,
        uint256 amountIn
    ) public view {
        // Given: Any record.
        // When: Requiring it to be pending.
        (bool success, bytes memory result) = address(queueLib)
            .staticcall(abi.encodeCall(QueueLibExtension.requirePending, (recordEpoch, pendingEpoch, amountIn)));

        // Then: It succeeds exactly for an amount in the pending epoch.
        assertEq(success, amountIn != 0 && recordEpoch == pendingEpoch);
        if (!success) assertEq(result, abi.encodeWithSelector(QueueLib.RequestNotPending.selector));
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_requestAmountOut_IsTheFlooredProRataShare(
        uint256 amountIn,
        uint256 batchAmountIn,
        uint256 batchAmountOut
    ) public pure {
        // Given: Any uint128 request and batch, with a non-empty batch input.
        vm.assume(amountIn <= type(uint128).max && batchAmountIn <= type(uint128).max);
        vm.assume(batchAmountOut <= type(uint128).max && batchAmountIn != 0);

        // When: Taking the request's output.
        // Then: It is the request's share of the batch output, rounded down.
        assertEq(
            QueueLib.requestAmountOut(amountIn, batchAmountIn, batchAmountOut),
            amountIn * batchAmountOut / batchAmountIn
        );
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_requestAmountOut_NeverExceedsTheBatch(
        uint256 amountIn,
        uint256 batchAmountIn,
        uint256 batchAmountOut
    ) public pure {
        // Given: A uint128 batch and a request within its input.
        vm.assume(batchAmountIn <= type(uint128).max && batchAmountOut <= type(uint128).max);
        vm.assume(amountIn <= batchAmountIn && batchAmountIn != 0);

        // When: Taking the request's output.
        // Then: It is at most the batch's output.
        assertLe(QueueLib.requestAmountOut(amountIn, batchAmountIn, batchAmountOut), batchAmountOut);
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_requestAmountOut_IsMonotoneInTheRequest(
        uint256 amountInLow,
        uint256 amountInHigh,
        uint256 batchAmountIn,
        uint256 batchAmountOut
    ) public pure {
        // Given: Two uint128 requests in order on the same uint128 batch.
        vm.assume(amountInHigh <= type(uint128).max && amountInLow <= amountInHigh);
        vm.assume(batchAmountIn <= type(uint128).max && batchAmountOut <= type(uint128).max && batchAmountIn != 0);

        // When: Taking both outputs.
        // Then: The larger request gets at least the smaller one's output.
        assertLe(
            QueueLib.requestAmountOut(amountInLow, batchAmountIn, batchAmountOut),
            QueueLib.requestAmountOut(amountInHigh, batchAmountIn, batchAmountOut)
        );
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_requestAmountIn_IsTheCeiledProRataInput(
        uint256 amountOut,
        uint256 batchAmountIn,
        uint256 batchAmountOut
    ) public pure {
        // Given: Any uint128 output and batch, with a non-empty batch output.
        vm.assume(amountOut <= type(uint128).max && batchAmountIn <= type(uint128).max);
        vm.assume(batchAmountOut <= type(uint128).max && batchAmountOut != 0);
        uint256 amountInFloored = amountOut * batchAmountIn / batchAmountOut;

        // When: Taking the input the output costs.
        uint256 amountIn = QueueLib.requestAmountIn(amountOut, batchAmountIn, batchAmountOut);

        // Then: It is the output's share of the batch input, rounded up.
        unchecked {
            assertEq(amountIn, amountInFloored + (mulmod(amountOut, batchAmountIn, batchAmountOut) == 0 ? 0 : 1));
        }
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_requestAmountIn_OfTheOutputNeverExceedsTheRequest(
        uint256 amountIn,
        uint256 batchAmountIn,
        uint256 batchAmountOut
    ) public pure {
        // Given: A request within a uint128 batch with both sides non-empty.
        vm.assume(batchAmountIn <= type(uint128).max && batchAmountOut <= type(uint128).max);
        vm.assume(amountIn <= batchAmountIn && batchAmountOut != 0);

        // When: Pricing the request's output back into input.
        uint256 amountOut = QueueLib.requestAmountOut(amountIn, batchAmountIn, batchAmountOut);
        vm.assume(amountOut <= type(uint128).max);

        // Then: It costs at most the request.
        assertLe(QueueLib.requestAmountIn(amountOut, batchAmountIn, batchAmountOut), amountIn);
    }

    function prove_record_SucceedsIffTheRequestIsValidAndTheSumsFit(
        Record memory stored,
        Epoch memory storedEpoch,
        uint32 pendingEpoch,
        address controller,
        uint256 amountIn,
        uint256 pendingShares
    ) public {
        // Given: Any record and pending epoch.
        queueLib.setRecord(0, stored);
        queueLib.setEpoch(storedEpoch);
        bool fits = uint256(stored.amountIn) + amountIn <= type(uint128).max
            && uint256(stored.pendingShares) + pendingShares <= type(uint96).max
            && uint256(storedEpoch.amountIn) + amountIn <= type(uint128).max;

        // When: Adding a request to the record.
        (bool success, bytes memory result) = address(queueLib)
            .call(abi.encodeCall(QueueLibExtension.record, (0, pendingEpoch, controller, amountIn, pendingShares)));

        // Then: It succeeds exactly when the controller's and amount's sums fit, adds it.
        assertEq(success, controller != address(0) && amountIn != 0 && fits);
        if (success) {
            Record memory record_ = queueLib.getRecord(0);
            assertEq(record_.epoch, pendingEpoch);
            assertEq(record_.amountIn, uint256(stored.amountIn) + amountIn);
            assertEq(record_.pendingShares, uint256(stored.pendingShares) + pendingShares);
            assertEq(queueLib.getEpoch().amountIn, uint256(storedEpoch.amountIn) + amountIn);
        } else if (controller == address(0)) {
            assertEq(result, abi.encodeWithSelector(QueueLib.ZeroAddress.selector));
        } else if (amountIn == 0) {
            assertEq(result, abi.encodeWithSelector(QueueLib.ZeroAmount.selector));
        } else {
            assertEq(result, abi.encodeWithSelector(SafeCastLib.Overflow.selector));
        }
    }

    function prove_cancel_TakesTheRecordOutOfTheEpochAndEmptiesIt(Record memory stored, Epoch memory storedEpoch)
        public
    {
        // Given: A record within its epoch.
        vm.assume(stored.amountIn <= storedEpoch.amountIn);
        queueLib.setRecord(0, stored);
        queueLib.setEpoch(storedEpoch);

        // When: Cancelling the record.
        uint256 shares = queueLib.cancel(0);

        // Then: Its pending shares are released, the epoch drops it, the record is empty.
        assertEq(shares, stored.pendingShares);
        assertEq(queueLib.getEpoch().amountIn, storedEpoch.amountIn - stored.amountIn);
        assertEq(queueLib.getEpoch().amountOut, storedEpoch.amountOut);
        Record memory record_ = queueLib.getRecord(0);
        assertEq(record_.epoch, 0);
        assertEq(record_.amountIn, 0);
        assertEq(record_.pendingShares, 0);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_creditSettled_MovesTheRecordsProRataOutputIntoTheClaimablePile(
        Record memory stored,
        Epoch memory storedEpoch,
        Claimable memory storedClaimable
    ) public {
        // Given: A record in a settled non-empty epoch, a claimable pile with room.
        vm.assume(stored.amountIn <= storedEpoch.amountIn && storedEpoch.amountIn != 0);
        uint256 amountOut = uint256(stored.amountIn) * storedEpoch.amountOut / storedEpoch.amountIn;
        vm.assume(uint256(storedClaimable.amountIn) + stored.amountIn <= type(uint128).max);
        vm.assume(uint256(storedClaimable.amountOut) + amountOut <= type(uint128).max);
        queueLib.setRecord(0, stored);
        queueLib.setEpoch(storedEpoch);
        queueLib.setClaimable(storedClaimable);

        // When: Crediting the record.
        (uint256 amountOut_, uint256 pendingShares) = queueLib.creditSettled(0);

        // Then: Floored pro rata output and input go from epoch to pile, record empty.
        assertEq(amountOut_, amountOut);
        assertEq(pendingShares, stored.pendingShares);
        assertEq(queueLib.getEpoch().amountIn, storedEpoch.amountIn - stored.amountIn);
        assertEq(queueLib.getEpoch().amountOut, storedEpoch.amountOut - amountOut);
        assertEq(queueLib.getClaimable().amountIn, uint256(storedClaimable.amountIn) + stored.amountIn);
        assertEq(queueLib.getClaimable().amountOut, uint256(storedClaimable.amountOut) + amountOut);
        Record memory record_ = queueLib.getRecord(0);
        assertEq(record_.epoch, 0);
        assertEq(record_.amountIn, 0);
        assertEq(record_.pendingShares, 0);
    }

    function prove_takeClaimable_SucceedsIffTheInputIsCoveredAndThePileIsNotEmpty(
        Claimable memory stored,
        uint256 amountIn,
        uint256 maxAmountOut
    ) public {
        // Given: Any claimable pile.
        queueLib.setClaimable(stored);

        // When: Taking from the pile.
        (bool success, bytes memory result) =
            address(queueLib).call(abi.encodeCall(QueueLibExtension.takeClaimable, (amountIn, maxAmountOut)));

        // Then: It succeeds exactly when the pile covers the input and is not empty.
        assertEq(success, amountIn <= stored.amountIn && (stored.amountIn != 0 || stored.amountOut != 0));
        if (!success) assertEq(result, abi.encodeWithSelector(QueueLib.InsufficientClaimable.selector));
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_takeClaimable_TakesTheFlooredProRataOutputCappedAtTheMax(
        Claimable memory stored,
        uint256 amountIn,
        uint256 maxAmountOut
    ) public {
        // Given: A pile with input, and a claim within it.
        vm.assume(stored.amountIn != 0 && amountIn <= stored.amountIn);
        queueLib.setClaimable(stored);
        uint256 proRata = amountIn * stored.amountOut / stored.amountIn;
        uint256 expected = proRata < maxAmountOut ? proRata : maxAmountOut;

        // When: Taking from the pile.
        uint256 amountOut = queueLib.takeClaimable(amountIn, maxAmountOut);

        // Then: The floored pro rata share capped at the max, both leave the pile.
        assertEq(amountOut, expected);
        assertEq(queueLib.getClaimable().amountIn, stored.amountIn - amountIn);
        assertEq(queueLib.getClaimable().amountOut, stored.amountOut - expected);
    }

    function prove_takeClaimable_WithoutInputHandsOutTheOutputUpToTheMax(Claimable memory stored, uint256 maxAmountOut)
        public
    {
        // Given: A pile without input but with output.
        vm.assume(stored.amountIn == 0 && stored.amountOut != 0);
        queueLib.setClaimable(stored);
        uint256 expected = stored.amountOut < maxAmountOut ? stored.amountOut : maxAmountOut;

        // When: Taking nothing from the pile.
        uint256 amountOut = queueLib.takeClaimable(0, maxAmountOut);

        // Then: The whole output leaves the pile, up to the max.
        assertEq(amountOut, expected);
        assertEq(queueLib.getClaimable().amountIn, 0);
        assertEq(queueLib.getClaimable().amountOut, stored.amountOut - expected);
    }
}
