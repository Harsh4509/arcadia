/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultAsync_Fuzz_Test } from "./_ALMVaultAsync.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";

/**
 * @notice Fuzz tests for the function "pendingDepositRequest" of contract "ALMVaultAsync".
 */
contract PendingDepositRequest_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultAsync_Fuzz_Test) {
        ALMVaultAsync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_pendingDepositRequest_CoreNotDeployed(
        PoolState memory poolState,
        bool isToken0,
        uint256 requestId,
        address controller_
    ) public {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        address[4] memory list = halfCreatedVaults();
        address vault = list[isToken0 ? Constants.CONTRACT_ASYNC_VAULT0 : Constants.CONTRACT_ASYNC_VAULT1];

        // When: Reading pendingDepositRequest() on one of its asynchronous vaults.
        // Then: It reverts without data, the read of the core finding no code.
        vm.expectRevert(bytes(""));
        ALMVaultAsync(vault).pendingDepositRequest(requestId, controller_);
    }

    function testFuzz_Success_pendingDepositRequest_OnlyForItsController(
        PoolState memory poolState,
        uint256 assets,
        address stranger,
        bool isToken0,
        uint256 requestId
    ) public {
        // Given: A deposit pending for the controller, and an account with no record.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        assets = bound(assets, 1, Constants.MAX_FUZZED_AMOUNT);
        requestDepositFor(isToken0, controller, assets);
        vm.assume(stranger != controller);
        requestId = bound(requestId, 1, type(uint256).max);

        // When: Reading the pending amount under request id 0 and a nonzero id.
        // Then: The controller sees the record, and a second account sees nothing.
        assertEq(vault.pendingDepositRequest(0, controller), assets);
        assertEq(vault.pendingDepositRequest(requestId, controller), assets);
        assertEq(vault.pendingDepositRequest(0, stranger), 0);
        assertEq(vault.pendingDepositRequest(requestId, stranger), 0);
    }

    function testFuzz_Success_pendingDepositRequest_ZeroOnceSettled(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        bool isToken0,
        uint256 requestId
    ) public {
        // Given: A seeded core, and a deposit record the keeper settled.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        setDepositSettled(poolState, range, queueState, isToken0, controller);
        requestId = bound(requestId, 1, type(uint256).max);

        // When: Reading the pending amount under request id 0 and a nonzero id.
        // Then: Nothing is pending any more.
        assertEq(asyncVaultFor(isToken0).pendingDepositRequest(0, controller), 0);
        assertEq(asyncVaultFor(isToken0).pendingDepositRequest(requestId, controller), 0);
    }

    function testFuzz_Success_pendingDepositRequest_UnaffectedByTheCoreLock(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        bool isToken0
    ) public {
        // Given: A seeded core, and a deposit pending for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        givenValidQueueState(queueState, isToken0 ? 1 : 0, isToken0 ? 0 : 1);
        uint256 assets = isToken0 ? queueState.deposit0 : queueState.deposit1;
        requestDepositFor(isToken0, controller, assets);

        // When: A router reads pendingDepositRequest during a keeper plan.
        (bool success, bytes memory result) =
            readDuringPlan(address(vault), abi.encodeCall(vault.pendingDepositRequest, (0, controller)));

        // Then: It answers as it does outside the plan.
        assertTrue(success);
        assertEq(abi.decode(result, (uint256)), assets);
    }
}
