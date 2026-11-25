/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { AsyncVaultGuard } from "../../../src/core/abstracts/mixins/AsyncVaultGuard.sol";
import { QueueLib } from "../../../src/core/libraries/state/QueueLib.sol";
import { Record } from "../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "cancelDepositRequest" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unused-return)
contract CancelDepositRequest_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_cancelDepositRequest_OnlyAsyncVault(
        PoolState memory poolState,
        address caller,
        address controller,
        address owner_
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        vm.assume(controller != address(0));

        // And: A caller that is neither asynchronous vault.
        vm.assume(caller != asyncVault0 && caller != asyncVault1);

        // When: Calling cancelDepositRequest().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(AsyncVaultGuard.OnlyAsyncVault.selector);
        almCore.cancelDepositRequest(1, controller, owner_);
    }

    function testFuzz_Revert_cancelDepositRequest_NotPending_Empty(
        PoolState memory poolState,
        address controller,
        address owner_,
        uint256 requestId
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        vm.assume(controller != address(0));

        // And: A controller with an empty record.

        // When: The vault cancels for it.
        // Then: It reverts.
        vm.prank(asyncVault0);
        vm.expectRevert(QueueLib.RequestNotPending.selector);
        almCore.cancelDepositRequest(requestId, controller, owner_);
    }

    function testFuzz_Revert_cancelDepositRequest_NotPending_Settled(
        PoolState memory poolState,
        address controller,
        address owner_,
        uint128 assets,
        uint32 recordEpoch,
        uint256 requestId
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A deposit record in an epoch that is no longer the pending one.
        assets = uint128(bound(assets, 1, type(uint128).max));
        recordEpoch = uint32(bound(recordEpoch, 0, type(uint32).max - 1));
        almCore.setDepositRecord(
            asyncVault0, controller, Record({ epoch: recordEpoch, amountIn: assets, pendingShares: 0 })
        );
        almCore.setPendingEpochs(asyncVault0, recordEpoch + 1, 0);

        // When: The vault cancels for it.
        // Then: It reverts.
        vm.prank(asyncVault0);
        vm.expectRevert(QueueLib.RequestNotPending.selector);
        almCore.cancelDepositRequest(requestId, controller, owner_);
    }

    function testFuzz_Success_cancelDepositRequest_RefundsFromEscrow(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        address controller_,
        address owner_,
        uint256 assets
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, the token0 deposit split with the controller, escrowed.
        vm.assume(controller_ != address(0) && controller_ != address(almCore));
        vm.assume(
            controller_ != accountB && controller_ != accountC && controller_ != controller
                && controller_ != secondController
        );
        vm.assume(owner_ != address(0) && owner_ != address(almCore));
        givenValidQueueState(queueState, 2, 0);
        assets = bound(assets, 1, queueState.deposit0 - 1);
        queueState.deposit0 -= assets;
        setQueueState(queueState);
        recordDepositAt(asyncVault0, controller_, assets);
        uint256 balanceBefore = token0.balanceOf(owner_);

        // When: The vault cancels the controller's.
        vm.prank(asyncVault0);
        uint256 refunded = almCore.cancelDepositRequest(0, controller_, owner_);

        // Then: The receiver is paid the record and the escrow falls by it.
        assertEq(refunded, assets);
        assertEq(token0.balanceOf(owner_), balanceBefore + assets);
        uint256 escrowed0 = almCore.getEscrowed0();
        assertEq(escrowed0, queueState.deposit0);
        assertEq(almCore.getEscrowed1(), queueState.deposit1);

        // And: The record and the pending aLP are empty, and the epoch input falls by it.
        assertEq(almCore.depositRecord(asyncVault0, controller_).amountIn, 0);
        assertEq(almCore.depositRecord(asyncVault0, controller_).pendingShares, 0);
        assertEq(almCore.pendingShares_(controller_), 0);
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountIn, queueState.deposit0);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0() + almCore.getProtocolFees0() + escrowed0);
    }

    function testFuzz_Success_cancelDepositRequest_LeavesTheSecondVaultAlone(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        address controller_,
        address owner_
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: The controller has a pending deposit at both asynchronous vaults.
        vm.assume(controller_ != address(0) && controller_ != address(almCore));
        vm.assume(owner_ != address(0) && owner_ != address(almCore));
        givenValidQueueState(queueState, 1, 1);
        (uint256 assets0, uint256 assets1) = (queueState.deposit0, queueState.deposit1);
        (queueState.deposit0, queueState.deposit1) = (0, 0);
        setQueueState(queueState);
        recordDepositAt(asyncVault0, controller_, assets0);
        recordDepositAt(asyncVault1, controller_, assets1);
        uint256 balanceBefore = token1.balanceOf(owner_);

        // When: Only the token0 vault cancels.
        vm.prank(asyncVault0);
        almCore.cancelDepositRequest(0, controller_, owner_);

        // Then: The token1 record and its escrow still stand.
        assertEq(almCore.depositRecord(asyncVault1, controller_).amountIn, assets1);
        assertEq(almCore.getEscrowed0(), 0);
        assertEq(almCore.getEscrowed1(), assets1);
        assertEq(token1.balanceOf(owner_), balanceBefore);
    }

    function testFuzz_Success_cancelDepositRequest_AboveTheCap(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests with a token0 deposit, then a per user cap of nothing.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        vm.prank(factory);
        almCore.setPerUserCap(0);

        // When: The vault cancels it to the controller.
        vm.prank(asyncVault0);
        almCore.cancelDepositRequest(0, accountB, accountB);

        // Then: It is not checked.
        assertEq(token0.balanceOf(accountB), queueState.deposit0);
    }
}
