/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { BalanceRouterMock } from "../../utils/mocks/BalanceRouterMock.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { CommandLogic } from "../../../src/core/libraries/logic/CommandLogic.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { Epoch } from "../../../src/core/types/State.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { LockProbeRouterMock } from "../../utils/mocks/LockProbeRouterMock.sol";
import { Plan } from "../../utils/Plan.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";

/**
 * @notice Fuzz tests for the command "SETTLE_REQUESTS" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unused-return)
contract SettleEpochs_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_settleEpochs_InvalidOrder_AClearWithoutASettlement(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        bool isToken0,
        bool isDeposit
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, Constants.DEAD_SHARES + 2, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, one in the queue the plan clears.
        givenAPendingRequest(queueState, isToken0, isDeposit);
        setQueueState(queueState);

        // When: The keeper clears the queue without settling it.
        // Then: It reverts.
        expectInvalidOrder(Plan.init().clearAllRequests(isToken0, isDeposit), sqrtPriceX96(pool));
    }

    function testFuzz_Revert_settleEpochs_InvalidOrder_ABuildupBeforeTheSettlement(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 trustedSqrtPriceX96,
        bool isToken0,
        bool isDeposit
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding the tokens of a range around spot.
        givenValidRangeState(range, poolState, true, false);
        givenValidCoreState(coreState, poolState, range, Constants.DEAD_SHARES + 2, 0, 0);
        setCoreState(coreState);

        // And: Pending requests, one in the queue the plan clears.
        givenAPendingRequest(queueState, isToken0, isDeposit);
        setQueueState(queueState);

        // When: The keeper clears the queue, opens a range with the buffer, then settles.
        // Then: It reverts.
        Plan.Steps memory plan =
            openWholeBuffer(Plan.init().clearAllRequests(isToken0, isDeposit), range).settleRequests();
        expectInvalidOrder(plan, givenTrustedPrice(trustedSqrtPriceX96));
    }

    function testFuzz_Revert_settleEpochs_InvalidOrder_ABuildupBeforeTheSettlementOfTwoQueues(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 trustedSqrtPriceX96
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding the tokens of a range around spot.
        givenValidRangeState(range, poolState, true, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: A pending token0 deposit and a token1 redeem.
        givenValidQueueState(queueState, 1, 0, Constants.QUEUE_DEPOSIT0 | Constants.QUEUE_REDEEM1);
        setQueueState(queueState);

        // When: The keeper clears both, opens a range with the buffer, then settles.
        // Then: It reverts.
        Plan.Steps memory plan = openWholeBuffer(
                Plan.init().clearAllRequests(true, true).clearAllRequests(false, false), range
            )
            .settleRequests();
        expectInvalidOrder(plan, givenTrustedPrice(trustedSqrtPriceX96));
    }

    function testFuzz_Revert_settleEpochs_InvalidOrder_AQueueStepAfterTheSettlement(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint8 command,
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

        // And: A settlement, then a clear or cancel step.
        command = uint8(bound(command, CommandLogic.CLEAR_REQUESTS, CommandLogic.CANCEL_REQUESTS));
        Plan.Steps memory plan = Plan.init().settleRequests().add(command, "");
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute().
        // Then: It reverts before the queue step decodes its payload.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.InvalidOrder.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_settleEpochs_InvalidOrder_AClearAfterASwap(
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        uint256 amountIn,
        uint256 trustedSqrtPriceX96,
        uint16 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a buffer and a pending token0 deposit.
        RangeState memory range;
        givenValidCoreState(coreState, poolState, range, 0, leastSwapIn(true), 0);
        setCoreState(coreState);
        givenValidQueueState(queueState, 1, 0, Constants.QUEUE_DEPOSIT0);
        setQueueState(queueState);

        // And: A sale of buffered token0 at spot, at a trusted price inside the band.
        uint160 trusted = givenTrustedPrice(trustedSqrtPriceX96);
        amountIn = bound(
            amountIn,
            leastSwapIn(true),
            FixedPointMathLib.min(
                almCore.bufferAmount0(),
                token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT - almCore.bufferAmount1())
            )
        );
        maxSwapCostBps = uint16(
            bound(
                maxSwapCostBps,
                leastSwapCostBps(true, amountIn, token0ToToken1(poolState.sqrtPrice, amountIn)),
                ConfigLib.BPS_DENOMINATOR - 1
            )
        );
        Plan.Steps memory swap = Plan.init()
            .swapBalance(
                address(new BalanceRouterMock()),
                address(token0),
                address(token1),
                address(routerTrampoline),
                true,
                amountIn,
                poolState.sqrtPrice,
                0
            );
        uint256 snapshot = vm.snapshotState();

        // When: The keeper clears and settles the deposit after the swap.
        // Then: It reverts.
        expectInvalidOrder(swap.clearAllRequests(true, true).settleRequests(), trusted);

        // And: With the clear first, the same steps settle the deposit.
        vm.revertToState(snapshot);
        Plan.Steps memory plan =
            Plan.init().clearAllRequests(true, true).add(uint8(swap.commands[0]), swap.inputs[0]).settleRequests();
        setPlanLimitsAtTheSwapCost(plan.commands.length, maxSwapCostBps, trusted);
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, trusted);
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountIn, queueState.deposit0);
        assertEq(almCore.getEscrowed0(), 0);
    }

    function testFuzz_Revert_settleEpochs_InvalidOrder_ABuildupBetweenTheSwapAndTheSettlement(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 amountIn,
        uint256 trustedSqrtPriceX96,
        uint16 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding the tokens of a range around spot.
        givenValidRangeState(range, poolState, true, false);
        givenValidCoreState(coreState, poolState, range, 0, leastSwapIn(true), 0);
        setCoreState(coreState);

        // And: A pending token0 deposit of up to the range's token0.
        givenValidQueueState(queueState, 1, 0, Constants.QUEUE_DEPOSIT0);
        givenDepositWithinTheRange(queueState, range);
        setQueueState(queueState);

        // And: A plan that clears the deposit and sells buffered token0 at spot.
        uint160 trusted = givenTrustedPrice(trustedSqrtPriceX96);
        amountIn = bound(
            amountIn,
            leastSwapIn(true),
            FixedPointMathLib.min(
                almCore.bufferAmount0(),
                token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT - almCore.bufferAmount1())
            )
        );
        maxSwapCostBps = uint16(
            bound(
                maxSwapCostBps,
                leastSwapCostBps(true, amountIn, token0ToToken1(poolState.sqrtPrice, amountIn)),
                ConfigLib.BPS_DENOMINATOR - 1
            )
        );
        Plan.Steps memory swap = Plan.init()
            .clearAllRequests(true, true)
            .swapBalance(
                address(new BalanceRouterMock()),
                address(token0),
                address(token1),
                address(routerTrampoline),
                true,
                amountIn,
                poolState.sqrtPrice,
                0
            );
        uint256 snapshot = vm.snapshotState();

        // When: The keeper opens a range between the swap and the settlement.
        // Then: It reverts at the buildup step.
        expectInvalidOrder(openWholeBuffer(swap, range).settleRequests(), trusted);

        // And: With the settlement right after the swap, the plan settles.
        vm.revertToState(snapshot);
        Plan.Steps memory plan = openWholeBuffer(swap.settleRequests(), range);
        setPlanLimitsAtTheSwapCost(plan.commands.length, maxSwapCostBps, trusted);
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, trusted);
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountIn, queueState.deposit0);
        assertEq(almCore.getRangesLength(), 1);
    }

    function testFuzz_Success_settleEpochs_ABuildupAfterTheSettlementKeepsTheDepositAndRedeemValue(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 trustedSqrtPriceX96
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding the tokens of a range around spot.
        givenValidRangeState(range, poolState, true, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: A token0 deposit within the range, a token1 redeem the buffer pays.
        uint160 trusted = givenTrustedPrice(trustedSqrtPriceX96);
        givenValidQueueState(queueState, 1, 0, Constants.QUEUE_DEPOSIT0 | Constants.QUEUE_REDEEM1);
        givenDepositWithinTheRange(queueState, range);
        {
            uint256 value = FixedPointMathLib.max(vaultValue(trusted, true), vaultValue(sqrtPriceX96(pool), true));
            uint256 payable1 = almCore.bufferAmount1().fullMulDiv(almCore.totalSupply(), value);
            if (queueState.redeem1 > payable1) queueState.redeem1 = bound(queueState.redeem1, 0, payable1);
        }
        setQueueState(queueState);

        // When: The keeper clears both, settles, then opens a range with the buffer.
        uint256 valueBefore = vaultValue(trusted, false);
        uint256 supplyBefore = almCore.totalSupply();
        uint256 roundingUp = almCore.bufferAmount0().fullMulDivUp(uint256(trusted) * trusted, 1 << 192)
            - token0ToToken1(trusted, almCore.bufferAmount0());
        {
            Plan.Steps memory plan = openWholeBuffer(
                Plan.init().clearAllRequests(true, true).clearAllRequests(false, false).settleRequests(), range
            );
            setPlanLimitsAtTheSwapCost(plan.commands.length, 0, trusted);
            vm.prank(users.keeper);
            almCore.execute(plan.commands, plan.inputs, trusted);
        }

        // Then: The deposit's value, its aLP and the payout, at the trusted price.
        uint256 depositValue = token0ToToken1(trusted, queueState.deposit0);
        uint256 valueAfter = vaultValue(trusted, false);
        uint256 supplyAfter = almCore.totalSupply();
        uint256 payout = almCore.redeemEpoch(asyncVault1, 0).amountOut;
        uint256 shares = almCore.depositEpoch(asyncVault0, 0).amountOut;
        uint256 loss = (valueBefore + depositValue).zeroFloorSub(valueAfter + payout);

        // And: The redeem is paid its start value, exactly.
        assertEq(payout, valueBefore.fullMulDiv(queueState.redeem1, supplyBefore));

        // And: The deposit is minted at the start value rounded up, exactly.
        assertEq(shares, depositValue == 0 ? 0 : depositValue.fullMulDiv(supplyBefore, valueBefore + roundingUp));

        // And: The deposit loses at most its part of the loss, a start share and the rounding.
        assertGe(
            shares.fullMulDiv(valueAfter, supplyAfter) + loss.fullMulDivUp(shares, supplyAfter)
                + valueBefore.divUp(supplyBefore) + roundingUp,
            depositValue
        );

        // And: The remaining holders lose at most their part of the loss.
        assertGe(
            (supplyAfter - shares).fullMulDiv(valueAfter, supplyAfter)
                + loss.fullMulDivUp(supplyAfter - shares, supplyAfter),
            valueBefore.fullMulDiv(supplyBefore - queueState.redeem1, supplyBefore)
        );
    }

    function testFuzz_Success_settleEpochs_FullExitLeavesTheDeadShares(
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding only a token0 buffer.
        RangeState memory range;
        givenValidCoreState(coreState, poolState, range, Constants.DEAD_SHARES + 1, 0, 0);
        setCoreState(coreState);
        almCore.setBuffers(almCore.bufferAmount0(), 0);
        uint256 held0 = almCore.bufferAmount0();

        // And: Pending requests, token0 redeems of every aLP but the dead shares.
        givenValidQueueState(queueState, 0, 0, Constants.ALL_QUEUES ^ Constants.QUEUE_REDEEM1);
        setQueueState(queueState);
        uint256 stewardShares = almCore.balanceOf(users.steward);
        vm.prank(asyncVault0);
        almCore.recordRedeemRequest(users.steward, users.steward, users.steward, stewardShares);
        uint256 supply = almCore.totalSupply();
        uint256 redeemed = supply - Constants.DEAD_SHARES;
        uint256 assets = token1ToToken0(
            poolState.sqrtPrice, redeemed.fullMulDiv(token0ToToken1(poolState.sqrtPrice, held0), supply)
        );
        // A hole: an exit leaving the dead shares less than a token1 wei.
        vm.assume(token0ToToken1(poolState.sqrtPrice, held0 - assets) != 0);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the redeems.
        runPlan(Plan.init().clearAllRequests(true, false).settleRequests());

        // Then: The redeemers are paid at the start value per share.
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountOut, assets);

        // And: Only the dead shares remain, keeping their value per share.
        assertEq(almCore.totalSupply(), Constants.DEAD_SHARES);
        assertEq(almCore.bufferAmount0(), held0 - assets);
        assertGe((held0 - assets) * supply, held0 * Constants.DEAD_SHARES);
    }

    function testFuzz_Success_settleEpochs_MatchedFlowsWithoutASwapAtTheStartValue(
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
        givenValidCoreState(coreState, poolState, range, Constants.DEAD_SHARES + 4, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        uint256 supply = almCore.totalSupply();

        // And: A pending deposit in each vault worth one to half the seed receiver's aLP.
        uint256 value;
        uint256 valueUp;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = amount1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
            valueUp = amount1 + almCore.bufferAmount1()
                + CLMath.convert(poolState.sqrtPrice, true, amount0 + almCore.bufferAmount0(), true);
        }
        {
            uint256 least1 = value.divUp(supply);
            uint256 least0 = least1.fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice);
            givenValidQueueState(queueState, least0, least1, Constants.QUEUE_DEPOSIT0 | Constants.QUEUE_DEPOSIT1);
            uint256 ceiling1 = (almCore.balanceOf(users.steward) / 2).fullMulDiv(value, supply);
            uint256 ceiling0 = token1ToToken0(poolState.sqrtPrice, ceiling1);
            // And: Room for a deposit of each token, the coarse seed (audit doc 6.1) excluded.
            vm.assume(least0 <= ceiling0 && least1 <= ceiling1);
            if (queueState.deposit0 > ceiling0) queueState.deposit0 = bound(queueState.deposit0, least0, ceiling0);
            if (queueState.deposit1 > ceiling1) queueState.deposit1 = bound(queueState.deposit1, least1, ceiling1);
        }

        // And: A pending redeem of each deposit's value.
        queueState.redeem0 = token0ToToken1(poolState.sqrtPrice, queueState.deposit0).fullMulDiv(supply, value);
        queueState.redeem1 = queueState.deposit1.fullMulDiv(supply, value);
        setQueueState(queueState);

        // And: Payouts at the aLP's value rounded down, the shares at it rounded up.
        uint256 assets0 = token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, supply));
        uint256 assets1 = queueState.redeem1.fullMulDiv(value, supply);
        uint256 shares0 = token0ToToken1(poolState.sqrtPrice, queueState.deposit0).fullMulDiv(supply, valueUp);
        uint256 shares1 = queueState.deposit1.fullMulDiv(supply, valueUp);
        (uint256 buffer0, uint256 buffer1) = (almCore.bufferAmount0(), almCore.bufferAmount1());

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(4, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles all four without a swap.
        // Then: It emits the redeem settlements, then the deposit settlements.
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.RedeemEpochSettled(asyncVault0, 0, assets0, queueState.redeem0);
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.RedeemEpochSettled(asyncVault1, 0, assets1, queueState.redeem1);
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.DepositEpochSettled(asyncVault0, 0, queueState.deposit0, shares0);
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.DepositEpochSettled(asyncVault1, 0, queueState.deposit1, shares1);
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .clearAllRequests(true, false)
                .clearAllRequests(false, true)
                .clearAllRequests(false, false)
                .settleRequests()
        );

        // And: Every flow settles at the existing aLP's value per share, levied nothing.
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountOut, shares0);
        assertEq(almCore.depositEpoch(asyncVault1, 0).amountOut, shares1);
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountOut, assets0);
        assertEq(almCore.redeemEpoch(asyncVault1, 0).amountOut, assets1);

        // And: The payouts sit in token escrow, the minted shares in aLP escrow.
        assertEq(almCore.getEscrowed0(), assets0);
        assertEq(almCore.getEscrowed1(), assets1);
        assertEq(almCore.balanceOf(address(almCore)), shares0 + shares1);

        // And: The buffers take in the deposits and pay out the redeems.
        assertEq(almCore.bufferAmount0(), buffer0 + queueState.deposit0 - assets0);
        assertEq(almCore.bufferAmount1(), buffer1 + queueState.deposit1 - assets1);
    }

    function testFuzz_Success_settleEpochs_SettlesAListClearAndAWholeClearOfDifferentQueues(
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
        uint256 supply = almCore.totalSupply();

        // And: Pending requests with a token0 deposit and a token0 redeem they pay.
        givenValidQueueState(queueState, 1, 0);
        uint256 assets;
        uint256 depositShares;
        {
            uint256 value;
            uint256 valueUp;
            {
                (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                    uint160(poolState.sqrtPrice),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                value = amount1 + almCore.bufferAmount1()
                    + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
                valueUp = amount1 + almCore.bufferAmount1()
                    + CLMath.convert(poolState.sqrtPrice, true, amount0 + almCore.bufferAmount0(), true);
            }
            uint256 ceiling = token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() + queueState.deposit0)
                .fullMulDiv(supply, value);
            ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
            queueState.redeem0 = bound(queueState.redeem0, 1, ceiling);

            // And: The payout at the aLP's value rounded down, the shares rounded up.
            assets = token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, supply));
            depositShares = token0ToToken1(poolState.sqrtPrice, queueState.deposit0).fullMulDiv(supply, valueUp);
        }
        setQueueState(queueState);
        (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = almCore.pendingEpochs(asyncVault0);
        uint32 nextDepositEpoch;
        uint256 nextRedeemEpoch;
        {
            (uint32 lastClearedDepositEpoch, uint32 lastClearedRedeemEpoch) = almCore.lastClearedEpochs(asyncVault0);
            nextDepositEpoch =
                SafeCastLib.toUint32(FixedPointMathLib.max(pendingDepositEpoch, lastClearedDepositEpoch) + 1);
            nextRedeemEpoch = FixedPointMathLib.max(pendingRedeemEpoch, lastClearedRedeemEpoch) + 1;
        }

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the deposit by name and all redeems.
        // Then: It settles the redeem at the pending id, then the deposit at a fresh id.
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.RedeemEpochSettled(asyncVault0, pendingRedeemEpoch, assets, queueState.redeem0);
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.DepositEpochSettled(asyncVault0, nextDepositEpoch, queueState.deposit0, depositShares);
        runPlan(
            Plan.init().clearRequests(true, true, Plan.one(accountB)).clearAllRequests(true, false).settleRequests()
        );

        // And: Each queue's cleared epoch holds its flow's output.
        assertEq(almCore.redeemEpoch(asyncVault0, pendingRedeemEpoch).amountOut, assets);
        assertEq(almCore.depositEpoch(asyncVault0, nextDepositEpoch).amountOut, depositShares);

        // And: The deposit queue keeps its pending epoch, the redeem queue starts anew.
        (uint32 pendingDepositEpochAfter, uint32 pendingRedeemEpochAfter) = almCore.pendingEpochs(asyncVault0);
        assertEq(pendingDepositEpochAfter, pendingDepositEpoch);
        assertEq(pendingRedeemEpochAfter, nextRedeemEpoch);
    }

    function testFuzz_Success_settleEpochs_StrategySwapLeavesTheQueuesAndCostsTheHolders(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        bool zeroForOne,
        uint256 amountIn,
        uint256 fee,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 2, 2);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a deposit at the token0 vault among them.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        (uint256 buffer0, uint256 buffer1) = (almCore.bufferAmount0(), almCore.bufferAmount1());

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);

        // And: A swap of the buffer either way, its fee within the max swap cost.
        uint256 amountOut;
        {
            uint256 room = zeroForOne
                ? token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT - buffer1)
                : token0ToToken1(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT - buffer0);
            amountIn = bound(amountIn, 1, FixedPointMathLib.min(zeroForOne ? buffer0 : buffer1, room));
        }
        amountOut =
            zeroForOne ? token0ToToken1(poolState.sqrtPrice, amountIn) : token1ToToken0(poolState.sqrtPrice, amountIn);
        fee = bound(fee, 0, maxSwapLoss(amountOut, configState.maxSwapCostBps));
        amountOut -= fee;

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(1, zeroForOne ? fee : token0ToToken1(poolState.sqrtPrice, fee + 1)),
            leastSwapCostBps(zeroForOne, amountIn, amountOut)
        );
        setPlanLimits(configState);

        // When: The keeper swaps in a plan without a clear step.
        {
            LockProbeRouterMock router = new LockProbeRouterMock();
            bytes memory data = abi.encodeCall(
                LockProbeRouterMock.swap,
                (
                    zeroForOne ? address(token0) : address(token1),
                    zeroForOne ? address(token1) : address(token0),
                    amountIn,
                    amountOut,
                    address(routerTrampoline)
                )
            );
            runPlan(Plan.init().swapViaRouter(address(router), amountIn, zeroForOne, 0, data));
        }

        // Then: The deposit epoch stays pending and unsettled, and no aLP is minted.
        {
            (uint32 pendingDeposit, uint32 pendingRedeem) = almCore.pendingEpochs(asyncVault0);
            assertEq(pendingDeposit, 0);
            assertEq(pendingRedeem, 0);
            Epoch memory epoch = almCore.depositEpoch(asyncVault0, 0);
            assertEq(epoch.amountIn, queueState.deposit0);
            assertEq(epoch.amountOut, 0);
        }
        assertEq(almCore.totalSupply(), coreState.supply);

        // And: The holders bear the swap's cost.
        assertEq(almCore.bufferAmount0(), zeroForOne ? buffer0 - amountIn : buffer0 + amountOut);
        assertEq(almCore.bufferAmount1(), zeroForOne ? buffer1 + amountOut : buffer1 - amountIn);
    }

    function testFuzz_Success_settleEpochs_EntrantIntoAToken0CorePaysTheAverageRateOnItsShare(
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        uint256 sold,
        uint256 fee,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding only a token0 buffer since a plan, and a max swap cost.
        {
            RangeState memory range;
            givenValidCoreState(
                coreState,
                poolState,
                range,
                0,
                uint256(1).fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice),
                0
            );
        }
        setCoreState(coreState);
        almCore.setBuffers(almCore.bufferAmount0(), 0);
        runPlan(Plan.init());
        givenValidPlanLimits(configState, 0, 1);
        setPlanLimits(configState);

        // And: Pending requests, a deposit at the token0 vault among them.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        uint256 held0 = almCore.bufferAmount0() + queueState.deposit0;

        // And: A sale of token0, paying a fee within the max swap cost.
        sold = bound(
            sold, 1, FixedPointMathLib.min(held0, token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT))
        );
        uint256 swapped = token0ToToken1(poolState.sqrtPrice, sold);
        fee = bound(
            fee,
            0,
            swapped
                - swapped.fullMulDivUp(
                    ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps, ConfigLib.BPS_DENOMINATOR
                )
        );

        // And: The deposit's levy, the swap's cost pro rata to its part of the swap.
        uint256 depositValue = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
        uint256 value;
        uint256 levy;
        {
            uint256 cost = CLMath.convert(poolState.sqrtPrice, true, sold, true) - (swapped - fee);
            // A hole: holders whose token0 is worth no more than the sale costs.
            vm.assume(token0ToToken1(poolState.sqrtPrice, held0 - queueState.deposit0) > cost);
            value = CLMath.convert(poolState.sqrtPrice, true, held0 - queueState.deposit0, true) - fee;
            uint256 heldIn = token0ToToken1(poolState.sqrtPrice, held0 - sold);
            if (swapped != 0 && heldIn + swapped - fee != 0) {
                uint256 depositSwap = depositValue.fullMulDiv(swapped - fee, heldIn + swapped - fee);
                if (depositSwap != 0) {
                    levy = FixedPointMathLib.min(
                        cost.fullMulDivUp(FixedPointMathLib.min(depositSwap, swapped), swapped), depositValue
                    );
                }
            }
        }

        Plan.Steps memory plan;
        {
            LockProbeRouterMock router = new LockProbeRouterMock();
            bytes memory data = abi.encodeCall(
                LockProbeRouterMock.swap,
                (address(token0), address(token1), sold, swapped - fee, address(routerTrampoline))
            );
            plan = Plan.init()
                .clearAllRequests(true, true)
                .swapViaRouter(address(router), sold, true, 0, data)
                .settleRequests();
        }

        // And: A max shortfall above the plan's loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, fee), configState.maxSwapCostBps);
        setPlanLimits(configState);

        // When: The keeper settles the deposit and sells token0.
        runPlan(plan);

        // Then: The entrant pays the swap's rate on its own part of the swap.
        assertEq(
            almCore.depositEpoch(asyncVault0, 0).amountOut,
            (depositValue - levy).fullMulDiv(coreState.supply, value + levy)
        );

        // And: The buffers keep the unsold token0 and the proceeds, the aLP minted.
        assertEq(almCore.bufferAmount0(), held0 - sold);
        assertEq(almCore.bufferAmount1(), swapped - fee);
        assertEq(almCore.totalSupply(), coreState.supply + almCore.depositEpoch(asyncVault0, 0).amountOut);
    }

    function testFuzz_Success_settleEpochs_EntrantIntoAToken1CorePaysTheWholeSwap(
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        uint256 fee,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding only a token1 buffer since a plan, and a max swap cost.
        RangeState memory range;
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        almCore.setBuffers(0, almCore.bufferAmount1());
        runPlan(Plan.init());
        uint256 held1 = almCore.bufferAmount1();
        givenValidPlanLimits(configState, 0, 1);
        setPlanLimits(configState);

        // And: Pending requests, a deposit at the token0 vault among them.
        givenValidQueueState(queueState, 1, 0);
        {
            uint256 ceiling = token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT - held1);
            if (queueState.deposit0 > ceiling) queueState.deposit0 = bound(queueState.deposit0, 1, ceiling);
        }
        setQueueState(queueState);
        uint256 supply = almCore.totalSupply();

        // And: The deposit sold whole for token1, paying a fee within the max swap cost.
        uint256 swapped = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
        fee = bound(
            fee,
            0,
            swapped
                - swapped.fullMulDivUp(
                    ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps, ConfigLib.BPS_DENOMINATOR
                )
        );
        LockProbeRouterMock router = new LockProbeRouterMock();
        bytes memory data = abi.encodeCall(
            LockProbeRouterMock.swap,
            (address(token0), address(token1), queueState.deposit0, swapped - fee, address(routerTrampoline))
        );
        uint256 cost = CLMath.convert(poolState.sqrtPrice, true, queueState.deposit0, true) - swapped + fee;
        // A hole: a token1 buffer no larger than the sale costs.
        vm.assume(held1 > cost);

        // And: A max shortfall above the plan's loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, fee), configState.maxSwapCostBps);
        setPlanLimits(configState);

        // When: The keeper settles the deposit and sells it.
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .swapViaRouter(address(router), queueState.deposit0, true, 0, data)
                .settleRequests()
        );

        // Then: The entrant pays the swap's cost, its fee and its token0 rounding.
        uint256 levy = swapped == 0 ? 0 : FixedPointMathLib.min(cost, swapped);
        assertEq(
            almCore.depositEpoch(asyncVault0, 0).amountOut, (swapped - levy).fullMulDiv(supply, held1 - fee + levy)
        );
    }

    function testFuzz_Success_settleEpochs_DepositWithoutASwapPaysNothing(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        bool isToken0,
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

        // And: Pending requests, a deposit at either vault among them.
        givenValidQueueState(queueState, isToken0 ? 1 : 0, isToken0 ? 0 : 1);
        setQueueState(queueState);
        uint256 shares;
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        amount0 += almCore.bufferAmount0();
        amount1 += almCore.bufferAmount1();
        uint256 depositValue = isToken0 ? token0ToToken1(poolState.sqrtPrice, queueState.deposit0) : queueState.deposit1;
        uint256 value = amount1 + CLMath.convert(poolState.sqrtPrice, true, amount0, true);
        shares = depositValue.fullMulDiv(almCore.totalSupply(), value);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles it without a swap.
        runPlan(Plan.init().clearAllRequests(isToken0, true).settleRequests());

        // Then: The deposit settles at the aLP's value per share, levied nothing.
        assertEq(almCore.depositEpoch(isToken0 ? asyncVault0 : asyncVault1, 0).amountOut, shares);
    }

    function testFuzz_Success_settleEpochs_RedeemerOfABalancedCorePaysTheWholePurchase(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 spent,
        uint256 fee,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range, and a max swap cost.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 2);
        setCoreState(coreState);
        setRangeState(range);
        givenValidPlanLimits(configState, 0, 1);
        setPlanLimits(configState);

        // And: A purchase of token0, paying a fee within the max swap cost.
        {
            uint256 room = FixedPointMathLib.min(
                almCore.bufferAmount1(),
                token0ToToken1(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT - almCore.bufferAmount0())
            );
            spent = bound(spent, 1, room);
            uint256 fair = token1ToToken0(poolState.sqrtPrice, spent);
            fee = bound(
                fee,
                0,
                fair
                    - fair.fullMulDivUp(
                        ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps, ConfigLib.BPS_DENOMINATOR
                    )
            );
        }
        uint256 assets;
        {
            uint256 held0;
            uint256 held1;
            uint256 cost;
            uint256 value;
            cost = spent - token0ToToken1(poolState.sqrtPrice, token1ToToken0(poolState.sqrtPrice, spent) - fee);
            (held0, held1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = held1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, held0 + almCore.bufferAmount0()) - cost;
            held0 = token0ToToken1(
                poolState.sqrtPrice, held0 + almCore.bufferAmount0() + token1ToToken0(poolState.sqrtPrice, spent) - fee
            );
            held1 = held1 + almCore.bufferAmount1() - spent;

            // And: Pending requests, a token0 redeem the token0 buffer pays among them.
            givenValidQueueState(queueState, 0, 0);
            {
                uint256 ceiling = almCore.bufferAmount0() + token1ToToken0(poolState.sqrtPrice, spent) - fee;
                ceiling = token0ToToken1(poolState.sqrtPrice, ceiling);
                ceiling = ceiling.fullMulDiv(almCore.totalSupply(), held0 + held1);
                ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
                // A hole: a token0 buffer after the purchase worth less than a share.
                vm.assume(ceiling != 0);
                queueState.redeem0 = bound(queueState.redeem0, 1, ceiling);
            }
            setQueueState(queueState);

            // And: The payout, the redeem's value less the cost of its part of the swap.
            {
                uint256 swapped = spent - cost;
                uint256 supply = almCore.totalSupply();
                uint256 redeemValue = queueState.redeem0.fullMulDiv(value, supply);
                uint256 redeemSwap = held0.zeroFloorSub(redeemValue) + held1;
                redeemSwap = redeemSwap == 0 ? 0 : redeemValue.fullMulDiv(held1, redeemSwap);
                uint256 levy;
                if (cost != 0 && swapped != 0 && redeemSwap != 0) {
                    levy = cost.fullMulDivUp(FixedPointMathLib.min(redeemSwap, swapped), swapped);
                    levy = FixedPointMathLib.min(levy, redeemValue);
                }
                assets = (value + levy).fullMulDiv(queueState.redeem0, supply) - levy;
            }
        }
        assets = token1ToToken0(poolState.sqrtPrice, assets);

        // And: A max shortfall above the plan's loss.
        givenValidPlanLimits(
            configState, leastShortfallBps(1, token0ToToken1(poolState.sqrtPrice, fee + 1)), configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The keeper settles the redeem and buys token0.
        uint256 bought = token1ToToken0(poolState.sqrtPrice, spent) - fee;
        LockProbeRouterMock router = new LockProbeRouterMock();
        bytes memory data = abi.encodeCall(
            LockProbeRouterMock.swap, (address(token1), address(token0), spent, bought, address(routerTrampoline))
        );
        runPlan(
            Plan.init()
                .clearAllRequests(true, false)
                .swapViaRouter(address(router), spent, false, 0, data)
                .settleRequests()
        );

        // Then: The redeemer is paid its value less the cost of its part of the swap.
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountOut, assets);
    }

    function testFuzz_Success_settleEpochs_ExcessDepositAndRedeemSplitTheCostProRata(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 sold,
        uint256 fee,
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

        // And: Pending requests, a token0 deposit among them.
        givenValidQueueState(queueState, 1, 0);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);

        // And: A sale of token0 with the deposit, its fee within the max swap cost.
        uint256 heldIn;
        uint256 held1;
        uint256 swapped;
        sold = bound(
            sold,
            1,
            FixedPointMathLib.min(
                almCore.bufferAmount0() + queueState.deposit0,
                token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT - almCore.bufferAmount1())
            )
        );
        swapped = token0ToToken1(poolState.sqrtPrice, sold);
        fee = bound(fee, 0, maxSwapLoss(swapped, configState.maxSwapCostBps));
        uint256 valueBefore;
        uint256 valueUp;
        (heldIn, held1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        valueBefore =
            held1 + almCore.bufferAmount1() + token0ToToken1(poolState.sqrtPrice, heldIn + almCore.bufferAmount0());
        valueUp = held1 + almCore.bufferAmount1()
            + CLMath.convert(poolState.sqrtPrice, true, heldIn + almCore.bufferAmount0(), true);
        heldIn = token0ToToken1(poolState.sqrtPrice, heldIn + almCore.bufferAmount0() + queueState.deposit0 - sold);
        held1 = held1 + almCore.bufferAmount1() + swapped - fee;
        uint256 cost = CLMath.convert(poolState.sqrtPrice, true, sold, true) - (swapped - fee);
        // A hole: a sale costing the whole vault value.
        vm.assume(valueBefore.zeroFloorSub(cost) != 0);
        valueUp -= fee;
        uint256 depositValue = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);

        // And: A token1 redeem the token1 buffer pays, selling token0 as well.
        {
            uint256 ceiling =
                (almCore.bufferAmount1() + swapped - fee).fullMulDiv(almCore.totalSupply(), held1 + heldIn);
            ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
            // A hole: a token1 buffer after the sale worth less than a share.
            vm.assume(ceiling != 0);
            queueState.redeem1 = bound(queueState.redeem1, 1, ceiling);
        }
        setQueueState(queueState);
        uint256 supply = almCore.totalSupply();

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, leastShortfallBps(3, fee), leastSwapCostBps(true, sold, swapped - fee));
        setPlanLimits(configState);
        uint256 redeemValue = queueState.redeem1.fullMulDiv(valueBefore.zeroFloorSub(cost), almCore.totalSupply());

        // When: The keeper settles both and sells token0.
        {
            LockProbeRouterMock router = new LockProbeRouterMock();
            uint256 amountIn = sold;
            uint256 amountOut = swapped - fee;
            bytes memory data = abi.encodeCall(
                LockProbeRouterMock.swap,
                (address(token0), address(token1), amountIn, amountOut, address(routerTrampoline))
            );
            Plan.Steps memory plan = Plan.init().clearAllRequests(true, true).clearAllRequests(false, false);
            runPlan(plan.swapViaRouter(address(router), amountIn, true, 0, data).settleRequests());
        }

        // Then: Both legs pay the cost pro rata to their part of the swap.
        uint256 depositLevy;
        uint256 redeemLevy;
        {
            uint256 redeemSwap;
            uint256 depositSwap;
            {
                uint256 heldAfter = heldIn + held1.zeroFloorSub(redeemValue);
                redeemSwap = heldAfter == 0 ? 0 : redeemValue.fullMulDiv(heldIn, heldAfter);
                depositSwap = heldAfter == 0 ? 0 : depositValue.fullMulDiv(held1.zeroFloorSub(redeemValue), heldAfter);
            }
            if (swapped != 0 && depositSwap + redeemSwap != 0) {
                uint256 levy = cost.fullMulDivUp(FixedPointMathLib.min(depositSwap + redeemSwap, swapped), swapped);
                depositLevy = levy.fullMulDivUp(depositSwap, depositSwap + redeemSwap);
                redeemLevy = levy.fullMulDivUp(redeemSwap, depositSwap + redeemSwap);
            }
        }
        depositLevy = FixedPointMathLib.min(depositLevy, depositValue);
        redeemLevy = FixedPointMathLib.min(redeemLevy, redeemValue);
        assertEq(
            almCore.depositEpoch(asyncVault0, 0).amountOut,
            (depositValue - depositLevy).fullMulDiv(supply, valueUp + depositLevy + redeemLevy)
        );

        // And: The redeem is paid at most its start value, less its levy.
        valueBefore = FixedPointMathLib.min(valueBefore.zeroFloorSub(cost) + depositLevy + redeemLevy, valueBefore);
        uint256 payout1 = queueState.redeem1;
        payout1 = payout1.fullMulDiv(valueBefore, supply) - redeemLevy;
        assertEq(almCore.redeemEpoch(asyncVault1, 0).amountOut, payout1);
    }

    function testFuzz_Success_settleEpochs_SwapAgainstTheFlowsLeviesNothing(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 spent,
        uint256 fee,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 2);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a deposit at the token0 vault among them.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);

        // And: A strategy purchase of token0, its fee within the max swap cost.
        uint256 bought;
        {
            uint256 room = FixedPointMathLib.min(
                almCore.bufferAmount1(),
                token0ToToken1(
                    poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT - almCore.bufferAmount0() - queueState.deposit0
                )
            );
            spent = bound(spent, 1, room);
            bought = token1ToToken0(poolState.sqrtPrice, spent);
            fee = bound(fee, 0, maxSwapLoss(bought, configState.maxSwapCostBps));
            bought -= fee;
        }
        uint256 shares;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 depositValue = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
            uint256 value = amount1 + almCore.bufferAmount1() - spent
                + CLMath.convert(poolState.sqrtPrice, true, amount0 + almCore.bufferAmount0(), true)
                + CLMath.convert(poolState.sqrtPrice, true, bought, true);
            // A hole: a vault worth two wei or less after the purchase.
            vm.assume(value > 2);
            shares = depositValue.fullMulDiv(almCore.totalSupply(), value);
        }

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(2, token0ToToken1(poolState.sqrtPrice, fee + 1)),
            leastSwapCostBps(false, spent, bought)
        );
        setPlanLimits(configState);

        // When: The keeper settles the deposit and buys token0.
        {
            LockProbeRouterMock router = new LockProbeRouterMock();
            bytes memory data = abi.encodeCall(
                LockProbeRouterMock.swap, (address(token1), address(token0), spent, bought, address(routerTrampoline))
            );
            runPlan(
                Plan.init()
                    .clearAllRequests(true, true)
                    .swapViaRouter(address(router), spent, false, 0, data)
                    .settleRequests()
            );
        }

        // Then: The deposit settles at the value per share after the swap, unlevied.
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountOut, shares);
    }

    function testFuzz_Success_settleEpochs_FillAtOrBetterThanThePriceLeviesNothing(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 sold,
        uint256 gain,
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

        // And: A sale of token0 filled at least 2 wei above its value at the price.
        uint256 amountOut;
        {
            sold = bound(
                sold,
                1,
                FixedPointMathLib.min(
                    almCore.bufferAmount0() + queueState.deposit0,
                    token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT - almCore.bufferAmount1() - 2)
                )
            );
            uint256 swapped = token0ToToken1(poolState.sqrtPrice, sold);
            gain = bound(gain, 2, Constants.MAX_FUZZED_AMOUNT - almCore.bufferAmount1() - swapped);
            amountOut = swapped + gain;
        }
        Plan.Steps memory plan;
        {
            LockProbeRouterMock router = new LockProbeRouterMock();
            bytes memory data = abi.encodeCall(
                LockProbeRouterMock.swap, (address(token0), address(token1), sold, amountOut, address(routerTrampoline))
            );
            plan = Plan.init()
                .clearAllRequests(true, true)
                .swapViaRouter(address(router), sold, true, 0, data)
                .settleRequests();
        }
        uint256 shares;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 depositValue = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
            uint256 value = amount1 + almCore.bufferAmount1() + amountOut
                + CLMath.convert(poolState.sqrtPrice, true, amount0 + almCore.bufferAmount0(), true)
                - token0ToToken1(poolState.sqrtPrice, sold);
            shares = depositValue.fullMulDiv(almCore.totalSupply(), value);
        }

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the deposit and sells token0.
        runPlan(plan);

        // Then: The deposit settles at the value per share with the gain, unlevied.
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountOut, shares);
    }

    function testFuzz_Success_settleEpochs_NearFullExitPaysTheStartValue(
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding only a token0 buffer.
        RangeState memory range;
        givenValidCoreState(coreState, poolState, range, 2 * Constants.DEAD_SHARES + 1, 0, 0);
        setCoreState(coreState);
        almCore.setBuffers(almCore.bufferAmount0(), 0);
        uint256 held0 = almCore.bufferAmount0();
        uint256 supply = almCore.totalSupply();

        // And: Pending requests with a token0 redeem of all but twice the dead shares.
        givenValidQueueState(queueState, 0, 0, Constants.ALL_QUEUES ^ Constants.QUEUE_REDEEM1);
        queueState.redeem0 =
            bound(queueState.redeem0, supply - 2 * Constants.DEAD_SHARES, almCore.balanceOf(users.steward));
        setQueueState(queueState);
        uint256 assets = token1ToToken0(
            poolState.sqrtPrice, queueState.redeem0.fullMulDiv(token0ToToken1(poolState.sqrtPrice, held0), supply)
        );
        // A hole: an exit leaving the dead shares less than a token1 wei.
        vm.assume(token0ToToken1(poolState.sqrtPrice, held0 - assets) != 0);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the redeem.
        runPlan(Plan.init().clearAllRequests(true, false).settleRequests());

        // Then: The redeemer is paid at the existing aLP's value per share.
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountOut, assets);

        // And: The few stayers keep their value per share, up to the payout's floors.
        assertEq(almCore.totalSupply(), supply - queueState.redeem0);
        assertEq(almCore.bufferAmount0(), held0 - assets);
        assertGe((held0 - assets) * supply, held0 * (supply - queueState.redeem0));
        assertLe(
            (held0 - assets) * supply,
            held0 * (supply - queueState.redeem0)
                + (supply + queueState.redeem0).fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice)
                + supply - 1
        );
    }

    function testFuzz_Success_settleEpochs_ASecondSettlementAfterTheSwapIsANoOp(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 spent,
        uint256 fee,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 2);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a deposit at the token0 vault among them.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);

        // And: A strategy purchase of token0, paying a fee within the max swap cost.
        uint256 bought;
        {
            uint256 room = FixedPointMathLib.min(
                almCore.bufferAmount1(),
                token0ToToken1(
                    poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT - almCore.bufferAmount0() - queueState.deposit0
                )
            );
            spent = bound(spent, 1, room);
            bought = token1ToToken0(poolState.sqrtPrice, spent);
            fee = bound(fee, 0, maxSwapLoss(bought, configState.maxSwapCostBps));
            bought -= fee;
        }
        LockProbeRouterMock router = new LockProbeRouterMock();
        bytes memory data = abi.encodeCall(
            LockProbeRouterMock.swap, (address(token1), address(token0), spent, bought, address(routerTrampoline))
        );

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(3, token0ToToken1(poolState.sqrtPrice, fee + 1)),
            leastSwapCostBps(false, spent, bought)
        );
        setPlanLimits(configState);

        // And: The state after a plan that clears, buys token0 and settles once.
        Plan.Steps memory plan = Plan.init()
            .clearAllRequests(true, true)
            .swapViaRouter(address(router), spent, false, 0, data)
            .settleRequests();
        uint256 snapshot = vm.snapshotState();
        runPlan(plan);
        uint256[5] memory once = [
            almCore.depositEpoch(asyncVault0, 0).amountOut,
            almCore.totalSupply(),
            almCore.balanceOf(address(almCore)),
            almCore.bufferAmount0(),
            almCore.bufferAmount1()
        ];
        vm.revertToState(snapshot);

        // When: The keeper runs the same plan with a second settlement.
        runPlan(plan.settleRequests());

        // Then: The settled shares, the supply, the escrow and the buffer are the same.
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountOut, once[0]);
        assertEq(almCore.totalSupply(), once[1]);
        assertEq(almCore.balanceOf(address(almCore)), once[2]);
        assertEq(almCore.bufferAmount0(), once[3]);
        assertEq(almCore.bufferAmount1(), once[4]);
    }

    function testFuzz_Success_settleEpochs_RunsOnAPausedCore(
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

        // And: A token0 redeem the token0 buffer pays, and no other request.
        givenValidQueueState(queueState, 0, 0, Constants.QUEUE_REDEEM0);
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 value = amount1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
            uint256 ceiling =
                token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0()).fullMulDiv(almCore.totalSupply(), value);
            ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
            queueState.redeem0 = bound(queueState.redeem0, 1, ceiling);
        }
        setQueueState(queueState);
        uint256 supply = almCore.totalSupply();

        // And: A paused core.
        vm.prank(factory);
        almCore.pause();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears and settles the redeems.
        runPlan(Plan.init().clearAllRequests(true, false).settleRequests());

        // Then: The redeem's aLP is burned and its payout sits in escrow.
        assertEq(almCore.totalSupply(), supply - queueState.redeem0);
        assertEq(almCore.getEscrowed0(), almCore.redeemEpoch(asyncVault0, 0).amountOut);
    }
}
