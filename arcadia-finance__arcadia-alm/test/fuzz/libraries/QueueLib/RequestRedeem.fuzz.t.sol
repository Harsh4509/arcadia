/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { QueueLib } from "../../../../src/core/libraries/state/QueueLib.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";
import { Record, ShareAccount } from "../../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "requestRedeem" of library "QueueLib".
 */
contract RequestRedeem_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_requestRedeem_ZeroAmount(address vault, address controller) public {
        // Given: A controller.
        vm.assume(controller != address(0));

        // When: Requesting a redeem of no shares.
        // Then: It reverts.
        vm.expectRevert(QueueLib.ZeroAmount.selector);
        queueLib.requestRedeem(vault, controller, 0);
    }

    function testFuzz_Success_requestRedeem_RecordsTheShares(
        address vault,
        address controller,
        uint32 pendingEpoch,
        uint256 shares
    ) public {
        // Given: A controller with no record.
        vm.assume(controller != address(0));
        queueLib.setPendingEpochs(vault, 0, pendingEpoch);

        // And: A non-zero request.
        shares = bound(shares, 1, type(uint128).max);

        // When: Requesting the redeem.
        queueLib.requestRedeem(vault, controller, shares);

        // Then: The record sits in the pending epoch with the shares.
        Record memory record = queueLib.getRedeemRecord(vault, controller);
        assertEq(record.epoch, pendingEpoch);
        assertEq(record.amountIn, shares);
        assertEq(record.pendingShares, 0);
        assertEq(queueLib.getRedeemEpoch(vault, pendingEpoch).amountIn, shares);

        // And: The shares are pending on the controller.
        assertEq(queueLib.getShareAccount(controller).pendingShares, shares);
    }

    function testFuzz_Success_requestRedeem_AddsToThePendingShares(
        address vault,
        address controller,
        ShareAccount memory shareAccount,
        uint256 shares
    ) public {
        // Given: A controller with pending aLP already, and no record.
        vm.assume(controller != address(0));
        shareAccount.pendingShares = uint128(bound(shareAccount.pendingShares, 1, type(uint128).max - 1));
        queueLib.setShareAccount(controller, shareAccount);

        // And: A non-zero request within the rest of a uint128.
        shares = bound(shares, 1, type(uint128).max - shareAccount.pendingShares);

        // When: Requesting the redeem.
        queueLib.requestRedeem(vault, controller, shares);

        // Then: The shares are added to the controller's pending aLP.
        assertEq(queueLib.getShareAccount(controller).pendingShares, shareAccount.pendingShares + shares);
    }
}
