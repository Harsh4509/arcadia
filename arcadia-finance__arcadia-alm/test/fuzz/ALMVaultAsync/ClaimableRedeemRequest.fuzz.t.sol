/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultAsync_Fuzz_Test } from "./_ALMVaultAsync.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";

/**
 * @notice Fuzz tests for the function "claimableRedeemRequest" of contract "ALMVaultAsync".
 */
contract ClaimableRedeemRequest_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultAsync_Fuzz_Test) {
        ALMVaultAsync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_claimableRedeemRequest_CoreNotDeployed(
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

        // When: Reading claimableRedeemRequest() on one of its asynchronous vaults.
        // Then: It reverts without data, the read of the core finding no code.
        vm.expectRevert(bytes(""));
        ALMVaultAsync(vault).claimableRedeemRequest(requestId, controller_);
    }

    function testFuzz_Success_claimableRedeemRequest_ZeroBeforeSettlement(
        PoolState memory poolState,
        uint256 amount,
        address stranger,
        bool isToken0,
        uint256 requestId
    ) public {
        // Given: A redeem pending for the controller, and an account with no record.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        amount = bound(amount, 1, Constants.MAX_FUZZED_AMOUNT);
        requestRedeemFor(isToken0, controller, amount);
        vm.assume(stranger != controller);
        requestId = bound(requestId, 1, type(uint256).max);

        // When: Reading the claimable amount under request id 0 and a nonzero id.
        // Then: Nothing is claimable before a settlement.
        assertEq(vault.claimableRedeemRequest(0, controller), 0);
        assertEq(vault.claimableRedeemRequest(requestId, controller), 0);
        assertEq(vault.claimableRedeemRequest(0, stranger), 0);
        assertEq(vault.claimableRedeemRequest(requestId, stranger), 0);
    }

    function testFuzz_Success_claimableRedeemRequest_IsTheSettledInput(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 amount,
        bool isToken0,
        uint256 requestId
    ) public {
        // Given: A seeded core, and a redeem the keeper settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        uint256 settled = setRedeemClaimable(poolState, range, isToken0, controller, amount);
        requestId = bound(requestId, 1, type(uint256).max);

        // When: Reading the claimable amount under request id 0 and a nonzero id.
        // Then: It is the settled input, added by the view before the record is credited.
        assertEq(asyncVaultFor(isToken0).claimableRedeemRequest(0, controller), settled);
        assertEq(asyncVaultFor(isToken0).claimableRedeemRequest(requestId, controller), settled);
    }

    function testFuzz_Success_claimableRedeemRequest_UnaffectedByTheCoreLock(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0
    ) public {
        // Given: A seeded core, and a redeem the keeper settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        uint256 claimableIn = setRedeemClaimable(poolState, range, isToken0, controller, shares);

        // When: A router reads claimableRedeemRequest while a keeper plan holds the lock.
        (bool success, bytes memory result) =
            readDuringPlan(address(vault), abi.encodeCall(vault.claimableRedeemRequest, (0, controller)));

        // Then: It answers as it does outside the plan.
        assertTrue(success);
        assertEq(abi.decode(result, (uint256)), claimableIn);
    }
}
