/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultAsync_Fuzz_Test } from "./_ALMVaultAsync.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";

/**
 * @notice Fuzz tests for the function "claimableDepositRequest" of contract "ALMVaultAsync".
 */
contract ClaimableDepositRequest_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultAsync_Fuzz_Test) {
        ALMVaultAsync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_claimableDepositRequest_CoreNotDeployed(
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

        // When: Reading claimableDepositRequest() on one of its asynchronous vaults.
        // Then: It reverts without data, the read of the core finding no code.
        vm.expectRevert(bytes(""));
        ALMVaultAsync(vault).claimableDepositRequest(requestId, controller_);
    }

    function testFuzz_Success_claimableDepositRequest_ZeroBeforeSettlement(
        PoolState memory poolState,
        uint256 amount,
        address stranger,
        bool isToken0,
        uint256 requestId
    ) public {
        // Given: A deposit pending for the controller, and an account with no record.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        amount = bound(amount, 1, Constants.MAX_FUZZED_AMOUNT);
        requestDepositFor(isToken0, controller, amount);
        vm.assume(stranger != controller);
        requestId = bound(requestId, 1, type(uint256).max);

        // When: Reading the claimable amount under request id 0 and a nonzero id.
        // Then: Nothing is claimable before a settlement.
        assertEq(vault.claimableDepositRequest(0, controller), 0);
        assertEq(vault.claimableDepositRequest(requestId, controller), 0);
        assertEq(vault.claimableDepositRequest(0, stranger), 0);
        assertEq(vault.claimableDepositRequest(requestId, stranger), 0);
    }

    function testFuzz_Success_claimableDepositRequest_IsTheSettledInput(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        bool isToken0,
        uint256 requestId
    ) public {
        // Given: A seeded core, and a deposit the keeper settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        uint256 settled = setDepositClaimable(poolState, range, queueState, isToken0, controller);
        requestId = bound(requestId, 1, type(uint256).max);

        // When: Reading the claimable amount under request id 0 and a nonzero id.
        // Then: It is the settled input, added by the view before the record is credited.
        assertEq(asyncVaultFor(isToken0).claimableDepositRequest(0, controller), settled);
        assertEq(asyncVaultFor(isToken0).claimableDepositRequest(requestId, controller), settled);
    }

    function testFuzz_Success_claimableDepositRequest_UnaffectedByTheCoreLock(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        bool isToken0
    ) public {
        // Given: A seeded core, and a deposit the keeper settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        uint256 claimableIn = setDepositClaimable(poolState, range, queueState, isToken0, controller);

        // When: A router reads claimableDepositRequest while a plan holds the lock.
        (bool success, bytes memory result) =
            readDuringPlan(address(vault), abi.encodeCall(vault.claimableDepositRequest, (0, controller)));

        // Then: It answers as it does outside the plan.
        assertTrue(success);
        assertEq(abi.decode(result, (uint256)), claimableIn);
    }
}
