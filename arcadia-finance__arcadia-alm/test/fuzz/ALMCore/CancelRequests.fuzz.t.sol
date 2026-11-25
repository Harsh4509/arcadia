/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { CalldataLogic } from "../../../src/core/libraries/logic/CalldataLogic.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { CommandLogic } from "../../../src/core/libraries/logic/CommandLogic.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { Epoch, Record } from "../../../src/core/types/State.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { Plan } from "../../utils/Plan.sol";
import { RejectingERC20Mock } from "../../utils/mocks/RejectingERC20Mock.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";

/**
 * @notice Fuzz tests for the command "CANCEL_REQUESTS" of contract "ALMCore".
 */
contract CancelRequests_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    using FixedPointMathLib for uint256;
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_cancelRequests_InvalidPayload(
        PoolState memory poolState,
        uint256 length,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A cancel payload that is not a queue plus whole controllers.
        length = partialEntriesLength(length);
        Plan.Steps memory plan = Plan.init().add(CommandLogic.CANCEL_REQUESTS, new bytes(length));
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_cancelRequests_TransferFailed(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a deposit at the token0 vault among them.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);

        // And: A token0 that refuses transfers to the controller.
        vm.etch(address(token0), address(new RejectingERC20Mock(token0.decimals())).code);
        RejectingERC20Mock(address(token0)).reject(accountB);
        Plan.Steps memory plan = Plan.init().cancelRequests(true, true, Plan.one(accountB));
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper cancels the deposit.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // And: The deposit stays pending and escrowed.
        Record memory record = almCore.depositRecord(asyncVault0, accountB);
        assertEq(record.epoch, 0);
        assertEq(record.amountIn, queueState.deposit0);
        assertEq(almCore.getEscrowed0(), queueState.deposit0);
    }

    function testFuzz_Success_cancelRequests_CancelsTheWholeRequest(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 secondAssets,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, the token0 vault's deposit split over two controllers.
        givenValidQueueState(queueState, 2, 0);
        secondAssets = bound(secondAssets, 1, queueState.deposit0 - 1);
        queueState.deposit0 -= secondAssets;
        setQueueState(queueState);
        recordDepositAt(asyncVault0, controller, secondAssets);
        uint256 secondPending = almCore.pendingShares_(controller);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper cancels the first.
        Plan.Steps memory plan = Plan.init().cancelRequests(true, true, Plan.one(accountB));
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(true, true, true, true, address(almCore));
        emit IALMCoreEvents.DepositCanceled(asyncVault0, accountB, queueState.deposit0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The record is empty, its pending aLP released and its assets paid back.
        Record memory record = almCore.depositRecord(asyncVault0, accountB);
        assertEq(record.amountIn, 0);
        assertEq(record.pendingShares, 0);
        assertEq(almCore.pendingShares_(accountB), 0);
        assertEq(token0.balanceOf(accountB), queueState.deposit0);

        // And: The epoch input and the escrow keep only the second deposit.
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountIn, secondAssets);
        assertEq(almCore.getEscrowed0(), secondAssets);
        assertEq(almCore.depositRecord(asyncVault0, controller).amountIn, secondAssets);
        assertEq(almCore.pendingShares_(controller), secondPending);
    }

    function testFuzz_Success_cancelRequests_SkipsAnEmptyRecord_Deposit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, none a deposit of the controller.
        givenValidQueueState(queueState, 0, 0);
        setQueueState(queueState);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper cancels for it, logging no cancel.
        Plan.Steps memory plan = Plan.init().cancelRequests(true, true, Plan.one(controller));
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(false, false, false, false, address(almCore), 0);
        emit IALMCoreEvents.DepositCanceled(asyncVault0, controller, 0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: Nothing is paid, and no cancel was logged.
        assertEq(token0.balanceOf(controller), 0);
    }

    function testFuzz_Success_cancelRequests_SkipsASettledRecord_Deposit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests with a token0 deposit an earlier plan settled.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        runPlan(Plan.init().clearRequests(true, true, Plan.one(accountB)).settleRequests());

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper cancels for it, logging no cancel.
        Plan.Steps memory plan = Plan.init().cancelRequests(true, true, Plan.one(accountB));
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(false, false, false, false, address(almCore), 0);
        emit IALMCoreEvents.DepositCanceled(asyncVault0, accountB, 0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The record is untouched, nothing is paid and no cancel is logged.
        assertEq(almCore.depositRecord(asyncVault0, accountB).amountIn, queueState.deposit0);
        assertEq(token0.balanceOf(accountB), 0);
    }

    function testFuzz_Success_cancelRequests_UnderPause_Deposit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a deposit at the token0 vault among them.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);

        // And: A paused core.
        vm.prank(factory);
        almCore.pause();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper cancels it.
        runPlan(Plan.init().cancelRequests(true, true, Plan.one(accountB)));

        // Then: The cancel ran.
        assertEq(almCore.depositRecord(asyncVault0, accountB).amountIn, 0);
        assertEq(token0.balanceOf(accountB), queueState.deposit0);
    }

    function testFuzz_Success_cancelRequests_ThenSettle(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 secondAssets,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price, and a vault holding a range.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, the token0 vault's deposit split over two controllers.
        givenValidQueueState(queueState, 2, 0);
        secondAssets = bound(secondAssets, 1, queueState.deposit0 - 1);
        queueState.deposit0 -= secondAssets;
        setQueueState(queueState);
        recordDepositAt(asyncVault0, controller, secondAssets);
        uint256 shares;
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        uint256 depositValue = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
        shares = depositValue.fullMulDiv(
            almCore.totalSupply(),
            amount1 + almCore.bufferAmount1()
                + CLMath.convert(poolState.sqrtPrice, true, amount0 + almCore.bufferAmount0(), true)
        );

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper cancels the second, then clears all deposits.
        runPlan(
            Plan.init().cancelRequests(true, true, Plan.one(controller)).clearAllRequests(true, true).settleRequests()
        );

        // Then: The epoch converted only the first, at the start value per share.
        Epoch memory settled = almCore.depositEpoch(asyncVault0, 0);
        assertEq(settled.amountIn, queueState.deposit0);
        assertEq(settled.amountOut, shares);
    }

    function testFuzz_Success_cancelRequests_Token1VaultPaysToken1(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a deposit at the token1 vault among them.
        givenValidQueueState(queueState, 0, 1);
        setQueueState(queueState);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper cancels it at the token1 vault.
        runPlan(Plan.init().cancelRequests(false, true, Plan.one(accountC)));

        // Then: The controller is paid back its token1, and no token0.
        assertEq(token1.balanceOf(accountC), queueState.deposit1);
        assertEq(token0.balanceOf(accountC), 0);

        // And: The record, pending aLP, epoch input and token1 escrow are empty.
        assertEq(almCore.depositRecord(asyncVault1, accountC).amountIn, 0);
        assertEq(almCore.pendingShares_(accountC), 0);
        assertEq(almCore.depositEpoch(asyncVault1, 0).amountIn, 0);
        assertEq(almCore.getEscrowed1(), 0);
    }

    function testFuzz_Success_cancelRequests_DuplicateControllerPaysOnce(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a deposit at the token0 vault among them.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper names the controller twice in one cancel, logging one cancel.
        Plan.Steps memory plan = Plan.init().cancelRequests(true, true, Plan.two(accountB, accountB));
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(true, true, true, true, address(almCore), 1);
        emit IALMCoreEvents.DepositCanceled(asyncVault0, accountB, queueState.deposit0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The controller is paid back once, and the escrow is empty.
        assertEq(token0.balanceOf(accountB), queueState.deposit0);
        assertEq(almCore.getEscrowed0(), 0);
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountIn, 0);
    }

    function testFuzz_Success_cancelRequests_EmptyPayloadIsANoOp_Deposit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a deposit at the token0 vault among them.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        uint256 pending = almCore.pendingShares_(accountB);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper cancels at the vault naming no controller.
        runPlan(Plan.init().cancelRequests(true, true, Plan.none()));

        // Then: The deposit stays pending and escrowed, and nothing is paid.
        Record memory record = almCore.depositRecord(asyncVault0, accountB);
        assertEq(record.epoch, 0);
        assertEq(record.amountIn, queueState.deposit0);
        assertEq(almCore.pendingShares_(accountB), pending);
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountIn, queueState.deposit0);
        assertEq(almCore.getEscrowed0(), queueState.deposit0);
        assertEq(token0.balanceOf(accountB), 0);
    }

    function testFuzz_Success_cancelRequests_ClearedInTheSamePlanIsSkipped_Deposit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a deposit at the token0 vault among them.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        uint32 nextEpoch;
        (uint32 pendingEpoch,) = almCore.pendingEpochs(asyncVault0);
        (uint32 lastClearedEpoch,) = almCore.lastClearedEpochs(asyncVault0);
        nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears, then cancels the deposit, logging no cancel.
        Plan.Steps memory plan = Plan.init()
            .clearRequests(true, true, Plan.one(accountB))
            .cancelRequests(true, true, Plan.one(accountB))
            .settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(false, false, false, false, address(almCore), 0);
        emit IALMCoreEvents.DepositCanceled(asyncVault0, accountB, 0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: Nothing is paid back, and the deposit settled in the cleared epoch.
        assertEq(token0.balanceOf(accountB), 0);
        Record memory record = almCore.depositRecord(asyncVault0, accountB);
        assertEq(record.epoch, nextEpoch);
        assertEq(record.amountIn, queueState.deposit0);
        assertEq(almCore.getEscrowed0(), 0);
    }

    function testFuzz_Success_cancelRequests_ReturnsTheShares(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 secondShares,
        uint256 received,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range, earning only the reward below.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 4, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        mockEarned(gauge, address(almCore), 0);

        // And: Pending requests, the token0 vault's redeem split over two controllers.
        givenValidQueueState(queueState, 0, 0);
        queueState.redeem0 = bound(queueState.redeem0, 2, almCore.balanceOf(users.steward) / 2);
        secondShares = bound(secondShares, 1, queueState.redeem0 - 1);
        queueState.redeem0 -= secondShares;
        setQueueState(queueState);
        vm.prank(users.steward);
        almCore.transfer(accountB, secondShares);
        vm.prank(asyncVault0);
        almCore.recordRedeemRequest(accountB, accountB, accountB, secondShares);

        // And: An uncredited reward, its reward per share a uint128 with half to spare.
        received = bound(
            received,
            1,
            FixedPointMathLib.min(
                almCore.totalSupply().fullMulDiv(type(uint128).max / 2, 1e18), Constants.MAX_FUZZED_AMOUNT
            )
        );
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);
        uint256 protocolFee = received * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        uint256 net = received - protocolFee;
        uint256 rewardPerShare = net.fullMulDiv(1e18, almCore.totalSupply());
        uint256 protocolFeesBefore = almCore.getProtocolFeesReward();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper cancels the first.
        Plan.Steps memory plan = Plan.init().cancelRequests(true, false, Plan.one(controller));
        vm.expectEmit(true, true, true, true, address(almCore));
        emit IALMCoreEvents.RedeemCanceled(asyncVault0, controller, queueState.redeem0);
        runPlan(plan);

        // Then: The shares are back, and the escrow earned up to the accumulator.
        assertEq(almCore.balanceOf(controller), queueState.redeem0);
        assertEq(almCore.getPendingReward(controller), 0);
        assertEq(
            almCore.getProtocolFeesReward(),
            protocolFeesBefore + protocolFee
                + (queueState.redeem0 + secondShares + queueState.redeem1).fullMulDiv(rewardPerShare, 1e18)
        );

        // And: The record is empty, the epoch input and the core's balance fall by it.
        assertEq(almCore.redeemRecord(asyncVault0, controller).amountIn, 0);
        assertEq(almCore.pendingShares_(controller), 0);
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountIn, secondShares);
        assertEq(almCore.balanceOf(address(almCore)), secondShares + queueState.redeem1);

        // And: The core and the controller were checkpointed at the new reward per share.
        assertEq(almCore.getProtocolRewardSnapshot(), rewardPerShare);
        assertEq(almCore.getRewardSnapshot(controller), rewardPerShare);

        // And: The checkpoint counted the net reward as claimed and as the high water.
        assertEq(almCore.getLastRewardBalance(), received);
        assertEq(almCore.getClaimedCumulative(), net);
        assertEq(almCore.getRewardHighWater(), net);
    }

    function testFuzz_Success_cancelRequests_CountsTheGaugeOnAnyChainStatus(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 received,
        uint256 earned,
        uint48 windowEnd,
        uint256 status,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range with no staked leg.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = 0;
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 2, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a redeem at the token0 vault among them.
        givenValidQueueState(queueState, 0, 0);
        queueState.redeem0 = bound(queueState.redeem0, 1, almCore.balanceOf(users.steward) / 2);
        setQueueState(queueState);

        // And: A reward, gauge emissions and a window end, on a fuzzed chain status.
        uint256 unsaturated = FixedPointMathLib.min(
            almCore.totalSupply().fullMulDiv(type(uint128).max / 2, 1e18), Constants.MAX_FUZZED_AMOUNT
        );
        received = bound(received, 1, unsaturated);
        earned = bound(earned, 0, unsaturated);
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);
        mockEarned(gauge, address(almCore), earned);
        windowEnd = uint48(bound(windowEnd, 1, type(uint48).max));
        almCore.setWindowEnd(windowEnd);
        setAnyStatus(status);

        // And: The net reward counted, the gauge's part included.
        uint256 feeBps = almCore.protocolEmissionFeeBps_();
        uint256 netReceived = received - received * feeBps / ConfigLib.BPS_DENOMINATOR;
        uint256 counted = netReceived + earned - earned * feeBps / ConfigLib.BPS_DENOMINATOR;
        uint256 rewardPerShare = counted.fullMulDiv(1e18, almCore.totalSupply());
        uint256 protocolFees = almCore.getProtocolFeesReward() + received * feeBps / ConfigLib.BPS_DENOMINATOR
            + (queueState.redeem0 + queueState.redeem1).fullMulDiv(rewardPerShare, 1e18);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper cancels the redeem.
        runPlan(Plan.init().cancelRequests(true, false, Plan.one(controller)));

        // Then: The reward per share and high water count the gauge on any chain status.
        assertEq(almCore.rewardPerShare_(), rewardPerShare);
        assertEq(almCore.getRewardHighWater(), counted);

        // And: The received reward is measured and claimed on every status.
        assertEq(almCore.getLastRewardBalance(), received);
        assertEq(almCore.getClaimedCumulative(), netReceived);

        // And: The escrow earned up to that reward per share, plus the fee.
        assertEq(almCore.getPendingReward(controller), 0);
        assertEq(almCore.getProtocolFeesReward(), protocolFees);

        // And: The window end is folded.
        assertEq(almCore.getWindowEnd(), 0);
    }

    function testFuzz_Success_cancelRequests_SkipsAnEmptyRecord_Redeem(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, none a redeem of the controller.
        givenValidQueueState(queueState, 0, 0);
        setQueueState(queueState);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper cancels for it, logging no cancel.
        Plan.Steps memory plan = Plan.init().cancelRequests(true, false, Plan.one(accountB));
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(false, false, false, false, address(almCore), 0);
        emit IALMCoreEvents.RedeemCanceled(asyncVault0, accountB, 0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: Nothing is returned, and no cancel was logged.
        assertEq(almCore.balanceOf(accountB), 0);
    }

    function testFuzz_Success_cancelRequests_SkipsASettledRecord_Redeem(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenBufferPaysShares(coreState, poolState, range, 1, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests with a token0 redeem its buffer pays, since settled.
        givenValidQueueState(queueState, 0, 0);
        uint256 ceiling;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 value = amount1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
            ceiling =
                token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0()).fullMulDiv(almCore.totalSupply(), value);
        }
        ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
        queueState.redeem0 = bound(queueState.redeem0, 1, ceiling);
        setQueueState(queueState);
        runPlan(Plan.init().clearRequests(true, false, Plan.one(controller)).settleRequests());

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper cancels for it, logging no cancel.
        Plan.Steps memory plan = Plan.init().cancelRequests(true, false, Plan.one(controller));
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(false, false, false, false, address(almCore), 0);
        emit IALMCoreEvents.RedeemCanceled(asyncVault0, controller, 0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The record is untouched, nothing is returned and no cancel is logged.
        assertEq(almCore.redeemRecord(asyncVault0, controller).amountIn, queueState.redeem0);
        assertEq(almCore.balanceOf(controller), 0);
    }

    function testFuzz_Success_cancelRequests_UnderPause_Redeem(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 2, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a redeem at the token0 vault among them.
        givenValidQueueState(queueState, 0, 0);
        queueState.redeem0 = bound(queueState.redeem0, 1, almCore.balanceOf(users.steward) / 2);
        setQueueState(queueState);

        // And: A paused core.
        vm.prank(factory);
        almCore.pause();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper cancels it.
        runPlan(Plan.init().cancelRequests(true, false, Plan.one(controller)));

        // Then: The cancel ran.
        assertEq(almCore.redeemRecord(asyncVault0, controller).amountIn, 0);
        assertEq(almCore.balanceOf(controller), queueState.redeem0);
    }

    function testFuzz_Success_cancelRequests_Token1VaultReturnsTheShares(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 secondShares,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 4, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, the token1 vault's redeem split over two controllers.
        givenValidQueueState(queueState, 0, 0);
        queueState.redeem1 = bound(queueState.redeem1, 2, almCore.balanceOf(users.steward) / 2);
        secondShares = bound(secondShares, 1, queueState.redeem1 - 1);
        queueState.redeem1 -= secondShares;
        setQueueState(queueState);
        vm.prank(users.steward);
        almCore.transfer(accountB, secondShares);
        vm.prank(asyncVault1);
        almCore.recordRedeemRequest(accountB, accountB, accountB, secondShares);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper cancels the first at the token1 vault.
        runPlan(Plan.init().cancelRequests(false, false, Plan.one(secondController)));

        // Then: The shares are back in the controller's balance.
        assertEq(almCore.balanceOf(secondController), queueState.redeem1);

        // And: The record is empty, the epoch and escrow keep only the second redeem.
        assertEq(almCore.redeemRecord(asyncVault1, secondController).amountIn, 0);
        assertEq(almCore.pendingShares_(secondController), 0);
        assertEq(almCore.redeemEpoch(asyncVault1, 0).amountIn, secondShares);
        assertEq(almCore.balanceOf(address(almCore)), secondShares + queueState.redeem0);

        // And: The token0 vault's redeem epoch is untouched.
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountIn, queueState.redeem0);
    }

    function testFuzz_Success_cancelRequests_DuplicateControllerReturnsOnce(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 2, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a redeem at the token0 vault among them.
        givenValidQueueState(queueState, 0, 0);
        queueState.redeem0 = bound(queueState.redeem0, 1, almCore.balanceOf(users.steward) / 2);
        setQueueState(queueState);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper names the controller twice in one cancel, logging one cancel.
        Plan.Steps memory plan = Plan.init().cancelRequests(true, false, Plan.two(controller, controller));
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(true, true, true, true, address(almCore), 1);
        emit IALMCoreEvents.RedeemCanceled(asyncVault0, controller, queueState.redeem0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The shares are returned once, and the token0 vault's escrow is empty.
        assertEq(almCore.balanceOf(controller), queueState.redeem0);
        assertEq(almCore.balanceOf(address(almCore)), queueState.redeem1);
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountIn, 0);
    }

    function testFuzz_Success_cancelRequests_EmptyPayloadIsANoOp_Redeem(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 2, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a redeem at the token0 vault among them.
        givenValidQueueState(queueState, 0, 0);
        queueState.redeem0 = bound(queueState.redeem0, 1, almCore.balanceOf(users.steward) / 2);
        setQueueState(queueState);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper cancels at the vault naming no controller.
        runPlan(Plan.init().cancelRequests(true, false, Plan.none()));

        // Then: The redeem stays pending, its shares in escrow.
        Record memory record = almCore.redeemRecord(asyncVault0, controller);
        assertEq(record.epoch, 0);
        assertEq(record.amountIn, queueState.redeem0);
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountIn, queueState.redeem0);
        assertEq(almCore.balanceOf(address(almCore)), queueState.redeem0 + queueState.redeem1);
        assertEq(almCore.balanceOf(controller), 0);
    }

    function testFuzz_Success_cancelRequests_ClearedInTheSamePlanIsSkipped_Redeem(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenBufferPaysShares(coreState, poolState, range, 1, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a token0 redeem the token0 buffer pays among them.
        givenValidQueueState(queueState, 0, 0);
        uint256 value;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = amount1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
            uint256 ceiling =
                token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0()).fullMulDiv(almCore.totalSupply(), value);
            ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
            queueState.redeem0 = bound(queueState.redeem0, 1, ceiling);
        }
        setQueueState(queueState);
        uint256 supply = almCore.totalSupply();
        uint32 nextEpoch;
        {
            (, uint32 pendingEpoch) = almCore.pendingEpochs(asyncVault0);
            (, uint32 lastClearedEpoch) = almCore.lastClearedEpochs(asyncVault0);
            nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
        }

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears, then cancels the redeem, logging no cancel.
        Plan.Steps memory plan = Plan.init()
            .clearRequests(true, false, Plan.one(controller))
            .cancelRequests(true, false, Plan.one(controller))
            .settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(false, false, false, false, address(almCore), 0);
        emit IALMCoreEvents.RedeemCanceled(asyncVault0, controller, 0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: No share is returned, and the redeem settled in the cleared epoch.
        assertEq(almCore.balanceOf(controller), 0);
        assertEq(almCore.redeemRecord(asyncVault0, controller).epoch, nextEpoch);
        assertEq(
            almCore.redeemEpoch(asyncVault0, nextEpoch).amountOut,
            token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, supply))
        );
        assertEq(almCore.totalSupply(), supply - queueState.redeem0);
    }
}
