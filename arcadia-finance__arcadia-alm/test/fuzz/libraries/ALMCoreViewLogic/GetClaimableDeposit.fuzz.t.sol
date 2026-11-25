/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { Claimable, Epoch, Record } from "../../../../src/core/types/State.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { Constants } from "../../../utils/Constants.sol";
import { Plan } from "../../../utils/Plan.sol";

/**
 * @notice Fuzz tests for the function "getClaimableDeposit" of library "ALMCoreViewLogic".
 */
contract GetClaimableDeposit_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getClaimableDeposit_ZeroBeforeSettlement(PoolState memory poolState, uint256 assets)
        public
    {
        // Given: A deposit recorded but not settled.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        recordDepositAt(asyncVault0, controller, bound(assets, 1, Constants.MAX_FUZZED_AMOUNT));

        // When: Reading the claimable side.
        (uint128 amountIn, uint128 amountOut) =
            coreViewLogic.getClaimableDeposit(address(almCore), asyncVault0, controller);

        // Then: Nothing is claimable.
        assertEq(amountIn, 0);
        assertEq(amountOut, 0);
    }

    function testFuzz_Success_getClaimableDeposit_IsWhatSettlementCredits(
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

        // And: Pending requests with a token0 deposit the keeper settled.
        givenValidQueueState(queueState, 0, 0);
        setQueueState(queueState);
        uint256 supplyBefore = almCore.totalSupply();
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());

        // When: Reading the claimable side.
        (uint128 amountIn, uint128 amountOut) =
            coreViewLogic.getClaimableDeposit(address(almCore), asyncVault0, accountB);

        // Then: It is the settled asset and the shares the settlement minted for it.
        assertEq(amountIn, queueState.deposit0);
        assertEq(amountOut, almCore.totalSupply() - supplyBefore);
    }

    function testFuzz_Success_getClaimableDeposit_ReadsApartFromTheRedeemSide(
        PoolState memory poolState,
        address vault,
        address controller_,
        Claimable memory deposit,
        Claimable memory redeem
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A claimable deposit and redeem for one vault and controller.
        almCore.setClaimableDeposit(vault, controller_, deposit);
        almCore.setClaimableRedeem(vault, controller_, redeem);

        // When: Reading the deposit queue.
        (uint128 amountIn, uint128 amountOut) = coreViewLogic.getClaimableDeposit(address(almCore), vault, controller_);

        // Then: Both halves read back, free of the redeem queue.
        assertEq(amountIn, deposit.amountIn);
        assertEq(amountOut, deposit.amountOut);
    }

    function testFuzz_Success_getClaimableDeposit_AddsASettledRecordToTheClaimablePile(
        PoolState memory poolState,
        Claimable memory claimable,
        Record memory record,
        Epoch memory epoch,
        uint32 pendingEpoch
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A claimable pile already credited to the controller.
        claimable.amountIn = uint128(bound(claimable.amountIn, 0, type(uint64).max));
        claimable.amountOut = uint128(bound(claimable.amountOut, 0, type(uint64).max));
        almCore.setClaimableDeposit(asyncVault0, accountB, claimable);

        // And: An uncredited record settled earlier, its batch at least its input.
        pendingEpoch = uint32(bound(pendingEpoch, 1, type(uint32).max));
        record.epoch = uint32(bound(record.epoch, 0, pendingEpoch - 1));
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint64).max));
        epoch.amountIn = uint128(bound(epoch.amountIn, record.amountIn, type(uint64).max));
        epoch.amountOut = uint128(bound(epoch.amountOut, 0, type(uint64).max));
        almCore.setPendingEpochs(asyncVault0, pendingEpoch, 0);
        almCore.setDepositRecord(asyncVault0, accountB, record);
        almCore.setDepositEpoch(asyncVault0, record.epoch, epoch);

        // When: Reading the claimable side.
        (uint128 amountIn, uint128 amountOut) =
            coreViewLogic.getClaimableDeposit(address(almCore), asyncVault0, accountB);

        // Then: The pile plus the record's input and its pro rata share of the output.
        assertEq(amountIn, uint256(claimable.amountIn) + record.amountIn);
        assertEq(
            amountOut, uint256(claimable.amountOut) + FullMath.mulDiv(record.amountIn, epoch.amountOut, epoch.amountIn)
        );
    }
}
