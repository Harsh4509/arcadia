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
 * @notice Fuzz tests for the function "cancelDepositRequest" of contract "ALMVaultAsync".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract CancelDepositRequest_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultAsync_Fuzz_Test) {
        ALMVaultAsync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_cancelDepositRequest_Unauthorized(
        PoolState memory poolState,
        uint256 amount,
        address caller,
        bool isToken0,
        uint256 requestId
    ) public {
        // Given: A pending deposit, and a caller that is not its controller or operator.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        amount = bound(amount, 1, Constants.MAX_FUZZED_AMOUNT);
        requestDepositFor(isToken0, controller, amount);
        vm.assume(caller != controller);

        // When: The caller cancels it.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC7540Operator.Unauthorized.selector);
        asyncVaultFor(isToken0).cancelDepositRequest(requestId, controller, caller);
    }

    function testFuzz_Revert_cancelDepositRequest_RequestNotPending(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        bool isToken0,
        uint256 requestId
    ) public {
        // Given: A seeded core, and a deposit the keeper has settled.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        setDepositSettled(poolState, range, queueState, isToken0, controller);

        // When: The controller cancels it.
        // Then: It reverts, a filled request being claimed rather than cancelled.
        vm.prank(controller);
        vm.expectRevert(QueueLib.RequestNotPending.selector);
        asyncVaultFor(isToken0).cancelDepositRequest(requestId, controller, controller);
    }

    function testFuzz_Success_cancelDepositRequest(
        PoolState memory poolState,
        uint256 amount,
        bool isToken0,
        uint256 requestId
    ) public {
        // Given: A pending deposit.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        amount = bound(amount, 1, Constants.MAX_FUZZED_AMOUNT);
        requestDepositFor(isToken0, controller, amount);

        // When: The controller cancels it to another account, under any request id.
        vm.prank(controller);
        vm.expectEmit(address(vault));
        emit ALMVaultAsync.DepositRequestCanceled(controller, 0, secondController, amount);
        uint256 returned = vault.cancelDepositRequest(requestId, controller, secondController);

        // Then: The receiver got the asset back, and nothing is pending.
        assertEq(returned, amount);
        assertEq((isToken0 ? token0 : token1).balanceOf(secondController), amount);
        assertEq(vault.pendingDepositRequest(requestId, controller), 0);
    }

    function testFuzz_Success_cancelDepositRequest_ByOperator(
        PoolState memory poolState,
        uint256 amount,
        bool isToken0,
        uint256 requestId
    ) public {
        // Given: A pending deposit, and the controller's operator.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        amount = bound(amount, 1, Constants.MAX_FUZZED_AMOUNT);
        requestDepositFor(isToken0, controller, amount);
        vm.prank(controller);
        vault.setOperator(secondController, true);

        // When: The operator cancels it to itself.
        vm.prank(secondController);
        vault.cancelDepositRequest(requestId, controller, secondController);

        // Then: The operator holds the asset.
        assertEq((isToken0 ? token0 : token1).balanceOf(secondController), amount);
    }
}
