/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Epoch, Record } from "../../../../src/core/types/State.sol";
import { QueueLib } from "../../../../src/core/libraries/state/QueueLib.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";

/**
 * @notice Fuzz tests for the function "record" of library "QueueLib".
 */
contract Record_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_record_ZeroController(uint32 pendingEpoch, uint256 amount) public {
        // Given: A request for no controller.

        // When: Recording it.
        // Then: It reverts.
        vm.expectRevert(QueueLib.ZeroAddress.selector);
        queueLib.record(0, pendingEpoch, address(0), amount, 0);
    }

    function testFuzz_Revert_record_ZeroAmount(uint32 pendingEpoch, address controller) public {
        // Given: A request of nothing for a controller.
        vm.assume(controller != address(0));

        // When: Recording it.
        // Then: It reverts.
        vm.expectRevert(QueueLib.ZeroAmount.selector);
        queueLib.record(0, pendingEpoch, controller, 0, 0);
    }

    function testFuzz_Revert_record_AmountPastUint128(
        uint32 pendingEpoch,
        address controller,
        uint256 amount,
        uint256 requestPendingShares
    ) public {
        // Given: A request for a controller past the uint128 maximum.
        vm.assume(controller != address(0));
        amount = bound(amount, uint256(type(uint128).max) + 1, type(uint256).max);

        // When: Recording it.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        queueLib.record(0, pendingEpoch, controller, amount, requestPendingShares);
    }

    function testFuzz_Revert_record_PendingSharesPastUint96(
        uint32 pendingEpoch,
        address controller,
        uint256 amount,
        uint96 pendingShares,
        uint256 requestPendingShares
    ) public {
        // Given: A record with pending aLP, and a request taking it past a uint96.
        vm.assume(controller != address(0));
        amount = bound(amount, 1, type(uint128).max - 1);
        queueLib.setRecord(0, Record({ epoch: pendingEpoch, amountIn: 1, pendingShares: pendingShares }));
        requestPendingShares =
            bound(requestPendingShares, uint256(type(uint96).max - pendingShares) + 1, type(uint128).max);

        // When: Recording it.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        queueLib.record(0, pendingEpoch, controller, amount, requestPendingShares);
    }

    function testFuzz_Success_record_EmptyRecord(
        uint32 pendingEpoch,
        address controller,
        uint256 amount,
        uint128 amountIn,
        uint96 requestPendingShares
    ) public {
        // Given: An empty record and a pending epoch with the input of earlier records.
        vm.assume(controller != address(0));
        amount = bound(amount, 1, type(uint128).max);
        amountIn = uint128(bound(amountIn, 0, type(uint128).max - amount));
        queueLib.setEpoch(Epoch({ amountIn: amountIn, amountOut: 0 }));

        // When: Recording a request in the pending epoch.
        queueLib.record(0, pendingEpoch, controller, amount, requestPendingShares);

        // Then: The record sits in the pending epoch with the amount and the pending aLP.
        Record memory record_ = queueLib.getRecord(0);
        assertEq(record_.epoch, pendingEpoch);
        assertEq(record_.amountIn, amount);
        assertEq(record_.pendingShares, requestPendingShares);

        // And: The epoch input rises by the amount.
        assertEq(queueLib.getEpoch().amountIn, uint256(amountIn) + amount);
    }

    function testFuzz_Success_record_PendingRecord(
        uint32 pendingEpoch,
        address controller,
        uint256 amount,
        uint128 pending,
        uint128 amountIn,
        uint96 pendingShares,
        uint256 requestPendingShares
    ) public {
        // Given: A pending record in the pending epoch, counted in its input.
        vm.assume(controller != address(0));
        pending = uint128(bound(pending, 1, type(uint128).max - 1));
        amountIn = uint128(bound(amountIn, pending, type(uint128).max - 1));
        amount = bound(amount, 1, type(uint128).max - amountIn);
        requestPendingShares = bound(requestPendingShares, 0, type(uint96).max - pendingShares);
        queueLib.setRecord(0, Record({ epoch: pendingEpoch, amountIn: pending, pendingShares: pendingShares }));
        queueLib.setEpoch(Epoch({ amountIn: amountIn, amountOut: 0 }));

        // When: Recording a second request in the same epoch.
        queueLib.record(0, pendingEpoch, controller, amount, requestPendingShares);

        // Then: The record and its pending aLP top up in the pending epoch.
        Record memory record_ = queueLib.getRecord(0);
        assertEq(record_.epoch, pendingEpoch);
        assertEq(record_.amountIn, uint256(pending) + amount);
        assertEq(record_.pendingShares, uint256(pendingShares) + requestPendingShares);

        // And: The epoch input rises by the amount.
        assertEq(queueLib.getEpoch().amountIn, uint256(amountIn) + amount);
    }
}
