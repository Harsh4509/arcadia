/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultAsync_Fuzz_Test } from "./_ALMVaultAsync.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC7540Operator } from "../../../src/vaults/abstracts/tokens/ERC7540Operator.sol";
import { QueueLib } from "../../../src/core/libraries/state/QueueLib.sol";

/**
 * @notice Fuzz tests for the function "cancelRedeemRequest" of contract "ALMVaultAsync".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract CancelRedeemRequest_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultAsync_Fuzz_Test) {
        ALMVaultAsync_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_cancelRedeemRequest_Unauthorized(
        uint256 amount,
        address caller,
        bool isToken0,
        uint256 requestId
    ) public {
        // Given: A pending redeem, and a caller that is not its controller or operator.
        amount = bound(amount, 1, Constants.MAX_FUZZED_AMOUNT);
        requestRedeemFor(isToken0, controller, amount);
        vm.assume(caller != controller);

        // When: The caller cancels it.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC7540Operator.Unauthorized.selector);
        asyncVaultFor(isToken0).cancelRedeemRequest(requestId, controller, caller);
    }

    function testFuzz_Revert_cancelRedeemRequest_RequestNotPending(uint256 requestId, bool isToken0) public {
        // Given: The vaults over a pool, and a controller with no request.

        // When: A controller cancels it.
        // Then: It reverts.
        vm.prank(controller);
        vm.expectRevert(QueueLib.RequestNotPending.selector);
        asyncVaultFor(isToken0).cancelRedeemRequest(requestId, controller, controller);
    }

    function testFuzz_Success_cancelRedeemRequest(uint256 amount, bool isToken0, uint256 requestId) public {
        // Given: A pending redeem.
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        amount = bound(amount, 1, Constants.MAX_FUZZED_AMOUNT);
        requestRedeemFor(isToken0, controller, amount);

        // When: The controller cancels it to another account, under any request id.
        vm.prank(controller);
        vm.expectEmit(address(vault));
        emit ALMVaultAsync.RedeemRequestCanceled(controller, 0, secondController, amount);
        uint256 returned = vault.cancelRedeemRequest(requestId, controller, secondController);

        // Then: The receiver got the shares back, and nothing is pending.
        assertEq(returned, amount);
        assertEq(almCore.balanceOf(secondController), amount);
        assertEq(almCore.balanceOf(address(almCore)), 0);
        assertEq(vault.pendingRedeemRequest(requestId, controller), 0);
    }

    function testFuzz_Success_cancelRedeemRequest_ByOperator(uint256 amount, bool isToken0, uint256 requestId) public {
        // Given: A pending redeem, and the controller's operator.
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        amount = bound(amount, 1, Constants.MAX_FUZZED_AMOUNT);
        requestRedeemFor(isToken0, controller, amount);
        vm.prank(controller);
        vault.setOperator(secondController, true);

        // When: The operator cancels it to itself.
        vm.prank(secondController);
        vault.cancelRedeemRequest(requestId, controller, secondController);

        // Then: The operator holds the shares.
        assertEq(almCore.balanceOf(secondController), amount);
    }
}
