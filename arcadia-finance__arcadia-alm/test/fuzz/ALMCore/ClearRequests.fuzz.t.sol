/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ALMCoreExtension } from "../../utils/extensions/ALMCoreExtension.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { CalldataLogic } from "../../../src/core/libraries/logic/CalldataLogic.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { CommandLogic } from "../../../src/core/libraries/logic/CommandLogic.sol";
import { Constants } from "../../utils/Constants.sol";
import { Epoch, Record } from "../../../src/core/types/State.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { LockProbeRouterMock } from "../../utils/mocks/LockProbeRouterMock.sol";
import { Plan } from "../../utils/Plan.sol";
import { PlanCacheLib } from "../../../src/core/types/PlanCache.sol";
import { PoolTokensLib } from "../../../src/core/libraries/state/PoolTokensLib.sol";
import { QueueLib } from "../../../src/core/libraries/state/QueueLib.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { ShareLib } from "../../../src/core/libraries/state/ShareLib.sol";
import { VmSafe } from "@forge-std/Vm.sol";

/**
 * @notice Fuzz tests for the command "CLEAR_REQUESTS" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unused-return)
contract ClearRequests_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_clearRequests_InvalidPayload(
        PoolState memory poolState,
        uint256 length,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A clear payload whose length is not a queue plus whole controllers.
        length = partialEntriesLength(length);
        Plan.Steps memory plan = Plan.init().add(CommandLogic.CLEAR_REQUESTS, new bytes(length));
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

    function testFuzz_Revert_clearRequests_Paused_Deposit(
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
        Plan.Steps memory plan = Plan.init().clearRequests(true, true, Plan.one(accountB)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper clears the deposit.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.Paused.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_clearRequests_TotalCapExceeded(
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

        // And: A total cap one share short of the supply the deposit settles to.
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        uint256 supply = almCore.totalSupply();
        uint256 depositValue = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
        uint256 shares = depositValue.fullMulDiv(
            supply,
            amount1 + almCore.bufferAmount1()
                + CLMath.convert(poolState.sqrtPrice, true, amount0 + almCore.bufferAmount0(), true)
        );
        vm.prank(factory);
        almCore.setTotalCap(supply + shares - 1);
        Plan.Steps memory plan = Plan.init().clearRequests(true, true, Plan.one(accountB)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper clears the deposit.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ShareLib.TotalCapExceeded.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // And: The deposit stays pending.
        Record memory record = almCore.depositRecord(asyncVault0, accountB);
        assertEq(record.epoch, 0);
        assertEq(record.amountIn, queueState.deposit0);
    }

    function testFuzz_Revert_clearRequests_ZeroValue(
        PoolState memory poolState,
        uint256 assets,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding nothing, and a pending token1 deposit.
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        recordDepositAt(asyncVault1, controller, bound(assets, 1, Constants.MAX_FUZZED_AMOUNT / 4));
        Plan.Steps memory plan = Plan.init().clearRequests(false, true, Plan.one(controller)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper clears the deposit.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(PlanCacheLib.ZeroValue.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_clearRequests_ZeroSupply(
        PoolState memory poolState,
        uint256 buffer1,
        uint256 assets,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core holding token1 and no aLP, and a pending token1 deposit.
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        buffer1 = bound(buffer1, 1, Constants.MAX_FUZZED_AMOUNT / 4);
        token1.mint(address(almCore), buffer1);
        almCore.setBuffers(0, buffer1);
        recordDepositAt(asyncVault1, controller, bound(assets, 1, Constants.MAX_FUZZED_AMOUNT / 4));
        Plan.Steps memory plan = Plan.init().clearRequests(false, true, Plan.one(controller)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper clears the deposit.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(PlanCacheLib.ZeroSupply.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_clearRequests_InsufficientBuffer(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool at a price of one, where moving buffer value keeps the value.
        poolState.sqrtPrice = SQRT_PRICE_ONE_X96;
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenBufferPaysShares(coreState, poolState, range, 1, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests with a token0 redeem worth an asset, at most the buffers.
        uint256 value;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = amount0 + amount1 + almCore.bufferAmount0() + almCore.bufferAmount1();
        }
        uint256 supply = almCore.totalSupply();
        givenValidQueueState(queueState, 0, 0);
        uint256 floor = supply.divUp(value);
        uint256 ceiling = (almCore.bufferAmount0() + almCore.bufferAmount1()).fullMulDiv(supply, value);
        ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
        queueState.redeem0 = bound(queueState.redeem0, floor, ceiling);
        setQueueState(queueState);

        // And: A token0 buffer one asset short of the payout, the rest moved to token1.
        (uint256 buffer0, uint256 buffer1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        uint256 assets = queueState.redeem0.fullMulDiv(value, supply);
        token0.mint(address(almCore), (assets - 1).zeroFloorSub(buffer0));
        token1.mint(address(almCore), (buffer0 + buffer1 - assets + 1).zeroFloorSub(buffer1));
        almCore.setBuffers(assets - 1, buffer0 + buffer1 - assets + 1);
        Plan.Steps memory plan = Plan.init().clearRequests(true, false, Plan.one(controller)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper clears the redeem.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(PoolTokensLib.InsufficientBuffer.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // And: The redeem stays pending, its shares in escrow.
        Record memory record = almCore.redeemRecord(asyncVault0, controller);
        assertEq(record.epoch, 0);
        assertEq(record.amountIn, queueState.redeem0);
        assertEq(almCore.balanceOf(address(almCore)), queueState.redeem0 + queueState.redeem1);
    }

    function testFuzz_Success_clearRequests_SkipsANonPendingEntry_Deposit(
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

        // And: Pending requests with a token0 deposit, none of the controller's.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        uint32 nextEpoch;
        {
            (uint32 pendingEpoch,) = almCore.pendingEpochs(asyncVault0);
            (uint32 lastClearedEpoch,) = almCore.lastClearedEpochs(asyncVault0);
            nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
        }

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears both.
        Plan.Steps memory plan = Plan.init().clearRequests(true, true, Plan.two(controller, accountB)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(true, true, true, true, address(almCore));
        emit IALMCoreEvents.DepositCleared(asyncVault0, accountB, queueState.deposit0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The empty record is untouched.
        Record memory skipped = almCore.depositRecord(asyncVault0, controller);
        assertEq(skipped.epoch, 0);
        assertEq(skipped.amountIn, 0);

        // And: The pending deposit is cleared, alone in the cleared epoch.
        assertEq(almCore.depositRecord(asyncVault0, accountB).epoch, nextEpoch);
        assertEq(almCore.depositEpoch(asyncVault0, nextEpoch).amountIn, queueState.deposit0);
    }

    function testFuzz_Success_clearRequests_LateUnnamedRequestStaysOutOfTheSettlement_Deposit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 lateAssets,
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

        // And: Pending requests, the token0 deposit split with a late part worth a share.
        uint256 cap;
        uint256 supply = almCore.totalSupply();
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        amount0 += almCore.bufferAmount0();
        amount1 += almCore.bufferAmount1();
        {
            uint256 priceX192 = poolState.sqrtPrice * poolState.sqrtPrice;
            uint256 valueUp = amount1 + CLMath.convert(poolState.sqrtPrice, true, amount0, true);
            uint256 least = (uint256(1).fullMulDivUp(priceX192, 1 << 192) * supply + 1)
            .divUp(amount1 + token0ToToken1(poolState.sqrtPrice, amount0));
            least = least.fullMulDivUp(valueUp, supply).fullMulDivUp(1 << 192, priceX192);
            givenValidQueueState(queueState, FixedPointMathLib.max(least, 2), 0);
        }
        uint256 shares = token0ToToken1(poolState.sqrtPrice, queueState.deposit0)
            .fullMulDiv(supply, amount1 + CLMath.convert(poolState.sqrtPrice, true, amount0, true));
        uint256 named = (shares * (amount1 + token0ToToken1(poolState.sqrtPrice, amount0))).zeroFloorSub(1) / supply;
        named = token1ToToken0(poolState.sqrtPrice, named);
        lateAssets = bound(
            lateAssets, FixedPointMathLib.max(queueState.deposit0.zeroFloorSub(named), 1), queueState.deposit0 - 1
        );
        queueState.deposit0 -= lateAssets;

        // And: A total cap with room for exactly the named deposit's shares.
        uint256 depositValue = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
        cap = supply
            + depositValue.fullMulDiv(supply, amount1 + CLMath.convert(poolState.sqrtPrice, true, amount0, true));
        setQueueState(queueState);
        recordDepositAt(asyncVault0, secondController, lateAssets);
        vm.prank(factory);
        almCore.setTotalCap(cap);

        // And: A whole-epoch clear on it, which the late deposit pushes past the cap.
        Plan.Steps memory whole = Plan.init().clearAllRequests(true, true).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectRevert(ShareLib.TotalCapExceeded.selector);
        almCore.execute(whole.commands, whole.inputs, trustedSqrtPriceX96);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the named deposit only.
        runPlan(Plan.init().clearRequests(true, true, Plan.one(accountB)).settleRequests());

        // Then: The settlement fills the cap exactly.
        assertEq(almCore.totalSupply(), cap);

        // And: The late deposit stays pending in the pending epoch, escrowed.
        Record memory late = almCore.depositRecord(asyncVault0, secondController);
        assertEq(late.epoch, 0);
        assertEq(late.amountIn, lateAssets);
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountIn, lateAssets);
        assertEq(almCore.getEscrowed0(), lateAssets);
    }

    function testFuzz_Success_clearRequests_TwoCommandsShareTheClearedEpoch_Deposit(
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
        (uint32 pendingEpoch,) = almCore.pendingEpochs(asyncVault0);
        (uint32 lastClearedEpoch,) = almCore.lastClearedEpochs(asyncVault0);
        uint32 nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears them in two commands of one plan.
        runPlan(
            Plan.init()
                .clearRequests(true, true, Plan.one(accountB))
                .clearRequests(true, true, Plan.one(controller))
                .settleRequests()
        );

        // Then: One fresh id is drawn, and both deposits sit in it.
        (uint32 pendingEpochAfter,) = almCore.pendingEpochs(asyncVault0);
        (uint32 lastClearedEpochAfter,) = almCore.lastClearedEpochs(asyncVault0);
        assertEq(lastClearedEpochAfter, nextEpoch);
        assertEq(FixedPointMathLib.max(pendingEpochAfter, lastClearedEpochAfter) + 1, nextEpoch + 1);
        assertEq(almCore.depositRecord(asyncVault0, accountB).epoch, nextEpoch);
        assertEq(almCore.depositRecord(asyncVault0, controller).epoch, nextEpoch);
        assertEq(almCore.depositEpoch(asyncVault0, nextEpoch).amountIn, queueState.deposit0 + secondAssets);

        // And: The pending epoch stays pending and empty.
        assertEq(pendingEpochAfter, pendingEpoch);
        assertEq(almCore.depositEpoch(asyncVault0, pendingEpoch).amountIn, 0);
    }

    function testFuzz_Success_clearRequests_AfterAWholeClearClearsNothing_Deposit(
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
        (uint32 pendingEpoch,) = almCore.pendingEpochs(asyncVault0);
        (uint32 lastClearedEpoch,) = almCore.lastClearedEpochs(asyncVault0);
        uint256 nextEpoch = FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1;

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears all deposits, then names the deposit, logging no clear.
        Plan.Steps memory plan =
            Plan.init().clearAllRequests(true, true).clearRequests(true, true, Plan.one(accountB)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(false, false, false, false, address(almCore), 0);
        emit IALMCoreEvents.DepositCleared(asyncVault0, accountB, 0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The deposit settled in the old pending epoch, and only one id was drawn.
        (uint32 pendingEpochAfter,) = almCore.pendingEpochs(asyncVault0);
        (uint32 lastClearedEpochAfter,) = almCore.lastClearedEpochs(asyncVault0);
        assertEq(lastClearedEpochAfter, pendingEpoch);
        assertEq(FixedPointMathLib.max(pendingEpochAfter, lastClearedEpochAfter) + 1, nextEpoch + 1);
        assertEq(almCore.depositRecord(asyncVault0, accountB).epoch, pendingEpoch);
        assertEq(almCore.depositEpoch(asyncVault0, pendingEpoch).amountIn, queueState.deposit0);
    }

    function testFuzz_Success_clearRequests_SettlesTheClearedEpochAtTheEnd_Deposit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range, and a wei of token1 for a probing swap to sell.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        fundBuffer(0, 1);
        uint256 out0 = token1ToToken0(poolState.sqrtPrice, 1) + 1;

        // And: Pending requests, a deposit at the token0 vault among them.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        uint256 supplyBefore = almCore.totalSupply();
        uint256 escrowBefore = almCore.balanceOf(address(almCore));
        uint32 nextEpoch;
        {
            (uint32 pendingEpoch,) = almCore.pendingEpochs(asyncVault0);
            (uint32 lastClearedEpoch,) = almCore.lastClearedEpochs(asyncVault0);
            nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
        }

        uint256 shares;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 depositValue = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
            uint256 value = amount1 + (almCore.bufferAmount1() - 1)
                + CLMath.convert(poolState.sqrtPrice, true, amount0 + almCore.bufferAmount0(), true)
                + CLMath.convert(poolState.sqrtPrice, true, out0, true);
            shares = depositValue.fullMulDiv(supplyBefore, value);
        }

        // And: A token1 sale after the clear reading the supply, then the epoch.
        LockProbeRouterMock router = new LockProbeRouterMock();
        Plan.Steps memory plan;
        bytes memory data = abi.encodeCall(
            LockProbeRouterMock.swap, (address(token1), address(token0), 1, out0, address(routerTrampoline))
        );
        plan = Plan.init()
            .clearRequests(true, true, Plan.one(accountB))
            .swapViaRouter(address(router), 1, false, 0, data)
            .settleRequests();
        uint256 supplyDuring;
        uint256 snapshot = vm.snapshotState();
        router.arm(address(almCore), abi.encodeWithSignature("totalSupply()"));
        runPlan(plan);
        supplyDuring = abi.decode(router.result(), (uint256));
        vm.revertToState(snapshot);
        router.arm(address(almCore), abi.encodeCall(ALMCoreExtension.depositEpoch, (asyncVault0, nextEpoch)));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the deposit and swaps.
        runPlan(plan);

        // Then: During the plan, nothing is minted and the cleared epoch has no output.
        assertEq(supplyDuring, supplyBefore);
        assertEq(abi.decode(router.result(), (Epoch)).amountOut, 0);

        // And: After it, the cleared epoch holds its shares, minted to escrow.
        assertEq(almCore.depositEpoch(asyncVault0, nextEpoch).amountOut, shares);
        assertEq(almCore.totalSupply(), supplyBefore + shares);
        assertEq(almCore.balanceOf(address(almCore)), escrowBefore + shares);
    }

    function testFuzz_Success_clearRequests_SettlesOnlyTheClearedQueue(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 amount,
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

        // And: A pending deposit at the token0 vault.
        givenValidQueueState(queueState, 1, 1);
        amount = bound(amount, 1, queueState.deposit0);
        recordDepositAt(asyncVault0, accountB, amount);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears it.
        vm.recordLogs();
        runPlan(Plan.init().clearRequests(true, true, Plan.one(accountB)).settleRequests());

        // Then: Only the token0 deposit epoch settles.
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        (uint256 deposits, uint256 redeems) = (0, 0);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == IALMCoreEvents.DepositEpochSettled.selector) ++deposits;
            if (logs[i].topics[0] == IALMCoreEvents.RedeemEpochSettled.selector) ++redeems;
        }
        assertEq(deposits, 1);
        assertEq(redeems, 0);
    }

    function testFuzz_Success_clearRequests_SettlesEqualDepositsInBothVaults(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 amount,
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

        // And: Pending deposits of one amount at both vaults.
        givenValidQueueState(queueState, 1, 1);
        amount = bound(amount, 1, FixedPointMathLib.min(queueState.deposit0, queueState.deposit1));
        recordDepositAt(asyncVault0, accountB, amount);
        recordDepositAt(asyncVault1, accountB, amount);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears both.
        vm.recordLogs();
        runPlan(
            Plan.init()
                .clearRequests(true, true, Plan.one(accountB))
                .clearRequests(false, true, Plan.one(accountB))
                .settleRequests()
        );

        // Then: Both deposit epochs settle.
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        (uint256 deposits, uint256 redeems) = (0, 0);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == IALMCoreEvents.DepositEpochSettled.selector) ++deposits;
            if (logs[i].topics[0] == IALMCoreEvents.RedeemEpochSettled.selector) ++redeems;
        }
        assertEq(deposits, 2);
        assertEq(redeems, 0);
    }

    function testFuzz_Success_clearRequests_SettlesAToken1DepositAndAToken0RedeemOfOneAmount(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 amount,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range, its buffers each paying four shares.
        givenValidRangeState(range, poolState, false);
        givenBufferPaysShares(coreState, poolState, range, 4, 4);
        setCoreState(coreState);
        setRangeState(range);

        // And: A redeem cap a quarter of either buffer pays.
        uint256 ceiling;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 value = amount1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
            ceiling = FixedPointMathLib.min(
                almCore.bufferAmount1().fullMulDiv(almCore.totalSupply(), 4 * value),
                token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0())
                    .fullMulDiv(almCore.totalSupply(), 4 * value)
            );
        }

        // And: A token1 deposit and a token0 redeem of one amount.
        givenValidQueueState(queueState, 1, 1);
        amount = bound(amount, 1, FixedPointMathLib.min(queueState.deposit1, ceiling));
        recordDepositAt(asyncVault1, accountB, amount);
        recordRedeemAt(asyncVault0, accountC, amount);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears both.
        vm.recordLogs();
        runPlan(
            Plan.init()
                .clearRequests(false, true, Plan.one(accountB))
                .clearRequests(true, false, Plan.one(accountC))
                .settleRequests()
        );

        // Then: The deposit epoch and the redeem epoch settle.
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        (uint256 deposits, uint256 redeems) = (0, 0);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == IALMCoreEvents.DepositEpochSettled.selector) ++deposits;
            if (logs[i].topics[0] == IALMCoreEvents.RedeemEpochSettled.selector) ++redeems;
        }
        assertEq(deposits, 1);
        assertEq(redeems, 1);
    }

    function testFuzz_Success_clearRequests_SettlesEqualRedeemsInBothVaults(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 amount,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range, its buffers each paying four shares.
        givenValidRangeState(range, poolState, false);
        givenBufferPaysShares(coreState, poolState, range, 4, 4);
        setCoreState(coreState);
        setRangeState(range);

        // And: A redeem cap a quarter of either buffer pays.
        uint256 ceiling;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 value = amount1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
            ceiling = FixedPointMathLib.min(
                almCore.bufferAmount1().fullMulDiv(almCore.totalSupply(), 4 * value),
                token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0())
                    .fullMulDiv(almCore.totalSupply(), 4 * value)
            );
        }

        // And: Pending redeems of one amount at both vaults.
        amount = bound(amount, 1, ceiling);
        recordRedeemAt(asyncVault0, accountC, amount);
        recordRedeemAt(asyncVault1, accountC, amount);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears both.
        vm.recordLogs();
        runPlan(
            Plan.init()
                .clearRequests(true, false, Plan.one(accountC))
                .clearRequests(false, false, Plan.one(accountC))
                .settleRequests()
        );

        // Then: Both redeem epochs settle.
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        (uint256 deposits, uint256 redeems) = (0, 0);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == IALMCoreEvents.DepositEpochSettled.selector) ++deposits;
            if (logs[i].topics[0] == IALMCoreEvents.RedeemEpochSettled.selector) ++redeems;
        }
        assertEq(deposits, 0);
        assertEq(redeems, 2);
    }

    function testFuzz_Success_clearRequests_SumsTheNamedDeposits(
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

        // And: Pending deposits of two controllers at the token0 vault.
        givenValidQueueState(queueState, 2, 1);
        uint256 first = queueState.deposit0 / 2;
        uint256 second = queueState.deposit0 - first;
        recordDepositAt(asyncVault0, accountB, first);
        recordDepositAt(asyncVault0, accountC, second);
        address[] memory controllers = new address[](2);
        (controllers[0], controllers[1]) = (accountB, accountC);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears both.
        vm.recordLogs();
        runPlan(Plan.init().clearRequests(true, true, controllers).settleRequests());

        // Then: The settled epoch holds both deposits.
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        uint256 assets;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == IALMCoreEvents.DepositEpochSettled.selector) {
                (assets,) = abi.decode(logs[i].data, (uint256, uint256));
            }
        }
        assertEq(assets, first + second);
    }

    function testFuzz_Success_clearRequests_EmitsDepositCleared(
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

        // When: The keeper clears the deposit.
        Plan.Steps memory plan = Plan.init().clearRequests(true, true, Plan.one(accountB)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(true, true, true, true, address(almCore));
        emit IALMCoreEvents.DepositCleared(asyncVault0, accountB, queueState.deposit0);
        // Then: The clear is logged at the core.
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_clearRequests_EmitsDepositEpochSettledAtTheClearedId(
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
        {
            (uint32 pendingEpoch,) = almCore.pendingEpochs(asyncVault0);
            (uint32 lastClearedEpoch,) = almCore.lastClearedEpochs(asyncVault0);
            nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
        }
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
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the deposit.
        Plan.Steps memory plan = Plan.init().clearRequests(true, true, Plan.one(accountB)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(true, true, true, true, address(almCore));
        emit IALMCoreEvents.DepositEpochSettled(asyncVault0, nextEpoch, queueState.deposit0, shares);
        // Then: The settlement is logged at the fresh cleared id.
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_clearRequests_KeepsTheTwoVaultsApart_Deposit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 assets1,
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

        // And: Pending requests, one controller's deposit at each vault among them.
        givenValidQueueState(queueState, 1, 1);
        setQueueState(queueState);
        assets1 = bound(assets1, 1, queueState.deposit1);
        recordDepositAt(asyncVault1, accountB, assets1);
        (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = almCore.pendingEpochs(asyncVault1);
        (uint32 lastClearedDepositEpoch, uint32 lastClearedRedeemEpoch) = almCore.lastClearedEpochs(asyncVault1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the controller at the token0 vault.
        runPlan(Plan.init().clearRequests(true, true, Plan.one(accountB)).settleRequests());

        // Then: The token1 vault's deposit stays pending, escrowed in its pending epoch.
        Record memory record = almCore.depositRecord(asyncVault1, accountB);
        assertEq(record.epoch, pendingDepositEpoch);
        assertEq(record.amountIn, assets1);
        assertEq(almCore.depositEpoch(asyncVault1, pendingDepositEpoch).amountIn, assets1 + queueState.deposit1);
        assertEq(almCore.getEscrowed1(), assets1 + queueState.deposit1);

        // And: The token1 vault drew no id.
        (uint32 pendingDepositEpochAfter, uint32 pendingRedeemEpochAfter) = almCore.pendingEpochs(asyncVault1);
        (uint32 lastClearedDepositEpochAfter, uint32 lastClearedRedeemEpochAfter) =
            almCore.lastClearedEpochs(asyncVault1);
        assertEq(pendingDepositEpochAfter, pendingDepositEpoch);
        assertEq(pendingRedeemEpochAfter, pendingRedeemEpoch);
        assertEq(lastClearedDepositEpochAfter, lastClearedDepositEpoch);
        assertEq(lastClearedRedeemEpochAfter, lastClearedRedeemEpoch);
    }

    function testFuzz_Success_clearRequests_ClearedRequestIsClaimableAfterThePlan_Deposit(
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

        // And: Pending requests with a token0 deposit the keeper cleared.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
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
        runPlan(Plan.init().clearRequests(true, true, Plan.one(accountB)).settleRequests());

        // When: The vault claims the whole deposit for the controller.
        vm.prank(asyncVault0);
        uint256 claimed = almCore.claimDepositRequest(accountB, queueState.deposit0, type(uint256).max, accountB);

        // Then: The controller is paid the cleared epoch's shares.
        assertEq(claimed, shares);
        assertEq(almCore.balanceOf(accountB), shares);

        // And: Its record and pending aLP are released.
        assertEq(almCore.depositRecord(asyncVault0, accountB).amountIn, 0);
        assertEq(almCore.pendingShares_(accountB), 0);
    }

    function testFuzz_Success_clearRequests_ClearedRequestIsNoLongerCancelable_Deposit(
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

        // And: Pending requests with a token0 deposit the keeper cleared.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        runPlan(Plan.init().clearRequests(true, true, Plan.one(accountB)).settleRequests());

        // When: The vault cancels the deposit.
        // Then: It reverts.
        vm.prank(asyncVault0);
        vm.expectRevert(QueueLib.RequestNotPending.selector);
        almCore.cancelDepositRequest(0, accountB, accountB);
    }

    function testFuzz_Success_clearRequests_Token1VaultClearsItsOwnSide_Deposit(
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
        uint256 supply = almCore.totalSupply();
        (uint256 buffer0Before, uint256 buffer1Before) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        uint32 nextEpoch;
        {
            (uint32 pendingEpoch,) = almCore.pendingEpochs(asyncVault1);
            (uint32 lastClearedEpoch,) = almCore.lastClearedEpochs(asyncVault1);
            nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
        }

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the deposit at the token1 vault.
        runPlan(Plan.init().clearRequests(false, true, Plan.one(accountC)).settleRequests());

        // Then: The deposit settles in the token1 cleared epoch at the start value.
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        uint256 value =
            amount1 + buffer1Before + CLMath.convert(poolState.sqrtPrice, true, amount0 + buffer0Before, true);
        assertEq(almCore.depositRecord(asyncVault1, accountC).epoch, nextEpoch);
        Epoch memory epoch = almCore.depositEpoch(asyncVault1, nextEpoch);
        assertEq(epoch.amountIn, queueState.deposit1);
        assertEq(epoch.amountOut, queueState.deposit1.fullMulDiv(supply, value));

        // And: The assets moved from the token1 escrow to the token1 buffer.
        assertEq(almCore.getEscrowed1(), 0);
        assertEq(almCore.bufferAmount1(), buffer1Before + queueState.deposit1);

        // And: The token0 side is untouched.
        assertEq(almCore.bufferAmount0(), buffer0Before);
        (uint32 pendingDepositEpoch0, uint32 pendingRedeemEpoch0) = almCore.pendingEpochs(asyncVault0);
        (uint32 lastClearedDepositEpoch0, uint32 lastClearedRedeemEpoch0) = almCore.lastClearedEpochs(asyncVault0);
        assertEq(pendingDepositEpoch0, 0);
        assertEq(pendingRedeemEpoch0, 0);
        assertEq(lastClearedDepositEpoch0, 0);
        assertEq(lastClearedRedeemEpoch0, 0);
    }

    function testFuzz_Success_clearRequests_DuplicateControllerClearsOnce_Deposit(
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
        uint256 supply = almCore.totalSupply();
        uint256 buffer0Before = almCore.bufferAmount0();
        uint32 nextEpoch;
        {
            (uint32 pendingEpoch,) = almCore.pendingEpochs(asyncVault0);
            (uint32 lastClearedEpoch,) = almCore.lastClearedEpochs(asyncVault0);
            nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
        }
        uint256 shares;
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        uint256 depositValue = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
        shares = depositValue.fullMulDiv(
            supply,
            amount1 + almCore.bufferAmount1() + CLMath.convert(poolState.sqrtPrice, true, amount0 + buffer0Before, true)
        );

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper names the controller twice in one clear, logging one clear.
        Plan.Steps memory plan = Plan.init().clearRequests(true, true, Plan.two(accountB, accountB)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(true, true, true, true, address(almCore), 1);
        emit IALMCoreEvents.DepositCleared(asyncVault0, accountB, queueState.deposit0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The deposit is cleared and settled once.
        Epoch memory epoch = almCore.depositEpoch(asyncVault0, nextEpoch);
        assertEq(epoch.amountIn, queueState.deposit0);
        assertEq(epoch.amountOut, shares);
        assertEq(almCore.bufferAmount0(), buffer0Before + queueState.deposit0);
        assertEq(almCore.totalSupply(), supply + shares);
    }

    function testFuzz_Success_clearRequests_SkipsASettledRecordFromAnEarlierPlan_Deposit(
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

        // And: Pending requests with a token0 deposit an earlier plan cleared.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        uint32 nextEpoch;
        {
            (uint32 pendingEpoch,) = almCore.pendingEpochs(asyncVault0);
            (uint32 lastClearedEpoch,) = almCore.lastClearedEpochs(asyncVault0);
            nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
        }
        runPlan(Plan.init().clearRequests(true, true, Plan.one(accountB)).settleRequests());
        Epoch memory epochBefore = almCore.depositEpoch(asyncVault0, nextEpoch);
        uint256 supply = almCore.totalSupply();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper names it again in a later plan, logging no clear.
        Plan.Steps memory plan = Plan.init().clearRequests(true, true, Plan.one(accountB)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(false, false, false, false, address(almCore), 0);
        emit IALMCoreEvents.DepositCleared(asyncVault0, accountB, 0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The record and its settled epoch are untouched, and nothing is minted.
        Record memory record = almCore.depositRecord(asyncVault0, accountB);
        assertEq(record.epoch, nextEpoch);
        assertEq(record.amountIn, queueState.deposit0);
        Epoch memory epoch = almCore.depositEpoch(asyncVault0, nextEpoch);
        assertEq(epoch.amountIn, epochBefore.amountIn);
        assertEq(epoch.amountOut, epochBefore.amountOut);
        assertEq(almCore.totalSupply(), supply);
    }

    function testFuzz_Success_clearRequests_EmptyPayloadIsANoOp_Deposit(
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
        uint256 supply = almCore.totalSupply();
        (uint32 pendingEpoch,) = almCore.pendingEpochs(asyncVault0);
        (uint32 lastClearedEpoch,) = almCore.lastClearedEpochs(asyncVault0);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the vault naming no controller.
        runPlan(Plan.init().clearRequests(true, true, Plan.none()).settleRequests());

        // Then: The epochs, the supply and the escrow are unchanged.
        (uint32 pendingEpochAfter,) = almCore.pendingEpochs(asyncVault0);
        (uint32 lastClearedEpochAfter,) = almCore.lastClearedEpochs(asyncVault0);
        assertEq(pendingEpochAfter, pendingEpoch);
        assertEq(lastClearedEpochAfter, lastClearedEpoch);
        assertEq(almCore.totalSupply(), supply);
        assertEq(almCore.getEscrowed0(), queueState.deposit0);

        // And: The deposit stays pending.
        assertEq(almCore.depositRecord(asyncVault0, accountB).epoch, pendingEpoch);
        assertEq(almCore.depositEpoch(asyncVault0, pendingEpoch).amountIn, queueState.deposit0);
    }

    function testFuzz_Success_clearRequests_CancelInTheSamePlanSkipsTheCleared(
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
        {
            (uint32 pendingEpoch,) = almCore.pendingEpochs(asyncVault0);
            (uint32 lastClearedEpoch,) = almCore.lastClearedEpochs(asyncVault0);
            nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
        }

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the deposit, then cancels it in the same plan.
        runPlan(
            Plan.init()
                .clearRequests(true, true, Plan.one(accountB))
                .cancelRequests(true, true, Plan.one(accountB))
                .settleRequests()
        );

        // Then: Nothing is paid back, and the deposit sits in the cleared epoch.
        assertEq(token0.balanceOf(accountB), 0);
        assertEq(almCore.depositRecord(asyncVault0, accountB).epoch, nextEpoch);
        assertEq(almCore.depositEpoch(asyncVault0, nextEpoch).amountIn, queueState.deposit0);
    }

    function testFuzz_Success_clearRequests_DepositWorthLessThanAShareSettlesToZeroShares(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range, each of its aLP worth more than a token0 wei.
        givenValidRangeState(range, poolState, false);
        givenShareWorthMoreThanToken0(coreState, poolState, range);
        setCoreState(coreState);
        setRangeState(range);
        uint256 supply = almCore.totalSupply();
        uint256 buffer0Before = almCore.bufferAmount0();

        // And: A pending token0 deposit worth less than one aLP.
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        uint256 value = amount1 + almCore.bufferAmount1() + token0ToToken1(poolState.sqrtPrice, amount0 + buffer0Before);
        uint256 ceiling = FixedPointMathLib.fullMulDivUp(
            (value - 1) / supply + 1, 1 << 192, poolState.sqrtPrice * poolState.sqrtPrice
        ) - 1;
        assets = bound(assets, 1, FixedPointMathLib.min(ceiling, Constants.MAX_FUZZED_AMOUNT / 4));
        recordDepositAt(asyncVault0, controller, assets);
        uint32 nextEpoch;
        {
            (uint32 pendingEpoch,) = almCore.pendingEpochs(asyncVault0);
            (uint32 lastClearedEpoch,) = almCore.lastClearedEpochs(asyncVault0);
            nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
        }

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the deposit.
        runPlan(Plan.init().clearRequests(true, true, Plan.one(controller)).settleRequests());

        // Then: The cleared epoch settles to zero shares, and nothing is minted.
        Epoch memory epoch = almCore.depositEpoch(asyncVault0, nextEpoch);
        assertEq(epoch.amountIn, assets);
        assertEq(epoch.amountOut, 0);
        assertEq(almCore.totalSupply(), supply);
        assertEq(almCore.balanceOf(address(almCore)), 0);

        // And: The assets moved from escrow to the buffer.
        assertEq(almCore.getEscrowed0(), 0);
        assertEq(almCore.bufferAmount0(), buffer0Before + assets);
    }

    function testFuzz_Success_clearRequests_SkipsANonPendingEntry_Redeem(
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
        uint32 nextEpoch;
        {
            (, uint32 pendingEpoch) = almCore.pendingEpochs(asyncVault0);
            (, uint32 lastClearedEpoch) = almCore.lastClearedEpochs(asyncVault0);
            nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
        }

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears both.
        Plan.Steps memory plan = Plan.init().clearRequests(true, false, Plan.two(accountB, controller)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(true, true, true, true, address(almCore));
        emit IALMCoreEvents.RedeemCleared(asyncVault0, controller, queueState.redeem0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The empty record is untouched.
        Record memory skipped = almCore.redeemRecord(asyncVault0, accountB);
        assertEq(skipped.epoch, 0);
        assertEq(skipped.amountIn, 0);

        // And: The pending redeem is cleared, alone in the cleared epoch.
        assertEq(almCore.redeemRecord(asyncVault0, controller).epoch, nextEpoch);
        assertEq(almCore.redeemEpoch(asyncVault0, nextEpoch).amountIn, queueState.redeem0);
    }

    function testFuzz_Success_clearRequests_LateUnnamedRequestStaysOutOfTheSettlement_Redeem(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 lateShares,
        ConfigState memory configState
    ) public {
        // Given: A pool at a price of one, where moving buffer value keeps the value.
        poolState.sqrtPrice = SQRT_PRICE_ONE_X96;
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenBufferPaysShares(coreState, poolState, range, 2, 0);
        setCoreState(coreState);
        setRangeState(range);
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        (uint256 buffer0, uint256 buffer1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        uint256 value = amount0 + amount1 + buffer0 + buffer1;
        uint256 supply = almCore.totalSupply();

        // And: The token0 redeem the buffers pay, split with a late unnamed controller.
        givenValidQueueState(queueState, 0, 0);
        uint256 ceiling =
            FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, (buffer0 + buffer1).fullMulDiv(supply, value));
        queueState.redeem0 = bound(queueState.redeem0, supply.divUp(value) + 1, ceiling);
        lateShares = bound(lateShares, supply.divUp(value), queueState.redeem0 - 1);
        queueState.redeem0 -= lateShares;
        setQueueState(queueState);
        vm.prank(users.steward);
        almCore.transfer(secondController, lateShares);
        vm.prank(asyncVault0);
        almCore.recordRedeemRequest(secondController, secondController, secondController, lateShares);

        // And: A token0 buffer of exactly the named redeem's payout, the rest in token1.
        uint256 assets = queueState.redeem0.fullMulDiv(value, supply);
        token0.mint(address(almCore), assets.zeroFloorSub(buffer0));
        token1.mint(address(almCore), (buffer0 + buffer1 - assets).zeroFloorSub(buffer1));
        almCore.setBuffers(assets, buffer0 + buffer1 - assets);

        // And: A whole-epoch clear on it, which the late redeem pushes past the buffer.
        Plan.Steps memory whole = Plan.init().clearAllRequests(true, false).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectRevert(PoolTokensLib.InsufficientBuffer.selector);
        almCore.execute(whole.commands, whole.inputs, trustedSqrtPriceX96);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the named redeem only.
        runPlan(Plan.init().clearRequests(true, false, Plan.one(controller)).settleRequests());

        // Then: The settlement empties the token0 buffer, burning only the named shares.
        assertEq(almCore.bufferAmount0(), 0);
        assertEq(almCore.balanceOf(address(almCore)), lateShares + queueState.redeem1);

        // And: The late redeem stays pending in the pending epoch.
        Record memory late = almCore.redeemRecord(asyncVault0, secondController);
        assertEq(late.epoch, 0);
        assertEq(late.amountIn, lateShares);
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountIn, lateShares);
    }

    function testFuzz_Success_clearRequests_TwoCommandsShareTheClearedEpoch_Redeem(
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
        givenBufferPaysShares(coreState, poolState, range, 2, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, the token0 redeem split over two controllers.
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
        queueState.redeem0 = bound(queueState.redeem0, 2, ceiling);
        secondShares = bound(secondShares, 1, queueState.redeem0 - 1);
        queueState.redeem0 -= secondShares;
        setQueueState(queueState);
        vm.prank(users.steward);
        almCore.transfer(accountB, secondShares);
        vm.prank(asyncVault0);
        almCore.recordRedeemRequest(accountB, accountB, accountB, secondShares);
        (, uint32 pendingEpoch) = almCore.pendingEpochs(asyncVault0);
        (, uint32 lastClearedEpoch) = almCore.lastClearedEpochs(asyncVault0);
        uint32 nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears them in two commands of one plan.
        runPlan(
            Plan.init()
                .clearRequests(true, false, Plan.one(controller))
                .clearRequests(true, false, Plan.one(accountB))
                .settleRequests()
        );

        // Then: One fresh id is drawn, and both redeems sit in it.
        (, uint32 pendingEpochAfter) = almCore.pendingEpochs(asyncVault0);
        (, uint32 lastClearedEpochAfter) = almCore.lastClearedEpochs(asyncVault0);
        assertEq(lastClearedEpochAfter, nextEpoch);
        assertEq(FixedPointMathLib.max(pendingEpochAfter, lastClearedEpochAfter) + 1, nextEpoch + 1);
        assertEq(almCore.redeemRecord(asyncVault0, controller).epoch, nextEpoch);
        assertEq(almCore.redeemRecord(asyncVault0, accountB).epoch, nextEpoch);
        assertEq(almCore.redeemEpoch(asyncVault0, nextEpoch).amountIn, queueState.redeem0 + secondShares);

        // And: The pending epoch stays pending and empty.
        assertEq(pendingEpochAfter, pendingEpoch);
        assertEq(almCore.redeemEpoch(asyncVault0, pendingEpoch).amountIn, 0);
    }

    function testFuzz_Success_clearRequests_AfterAWholeClearClearsNothing_Redeem(
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
        (, uint32 pendingEpoch) = almCore.pendingEpochs(asyncVault0);
        (, uint32 lastClearedEpoch) = almCore.lastClearedEpochs(asyncVault0);
        uint256 nextEpoch = FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1;

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears all redeems, then names the redeem, logging no clear.
        Plan.Steps memory plan =
            Plan.init().clearAllRequests(true, false).clearRequests(true, false, Plan.one(controller)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(false, false, false, false, address(almCore), 0);
        emit IALMCoreEvents.RedeemCleared(asyncVault0, controller, 0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The redeem settled in the old pending epoch, and only one id was drawn.
        (, uint32 pendingEpochAfter) = almCore.pendingEpochs(asyncVault0);
        (, uint32 lastClearedEpochAfter) = almCore.lastClearedEpochs(asyncVault0);
        assertEq(lastClearedEpochAfter, pendingEpoch);
        assertEq(FixedPointMathLib.max(pendingEpochAfter, lastClearedEpochAfter) + 1, nextEpoch + 1);
        assertEq(almCore.redeemRecord(asyncVault0, controller).epoch, pendingEpoch);
        assertEq(almCore.redeemEpoch(asyncVault0, pendingEpoch).amountIn, queueState.redeem0);
    }

    function testFuzz_Success_clearRequests_SettlesTheClearedEpochAtTheEnd_Redeem(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range, and a wei of token0 for a probing swap to sell.
        givenValidRangeState(range, poolState, false);
        givenBufferPaysShares(coreState, poolState, range, 1, 0);
        setCoreState(coreState);
        setRangeState(range);
        fundBuffer(1, 0);
        uint256 out1 = token0ToToken1(poolState.sqrtPrice, 1) + 1;

        // And: Pending requests with a token0 redeem its buffer pays after the swap.
        givenValidQueueState(queueState, 0, 0);
        uint256 value;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = amount1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
            uint256 ceiling = token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() - 1)
                .fullMulDiv(almCore.totalSupply(), value);
            ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
            queueState.redeem0 = bound(queueState.redeem0, 1, ceiling);
        }
        setQueueState(queueState);
        uint256 assets =
            token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, almCore.totalSupply()));
        uint32 nextEpoch;
        {
            (, uint32 pendingEpoch) = almCore.pendingEpochs(asyncVault0);
            (, uint32 lastClearedEpoch) = almCore.lastClearedEpochs(asyncVault0);
            nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
        }

        // And: A token0 sale after the clear reading the escrow, then the epoch.
        LockProbeRouterMock router = new LockProbeRouterMock();
        Plan.Steps memory plan;
        bytes memory data = abi.encodeCall(
            LockProbeRouterMock.swap, (address(token0), address(token1), 1, out1, address(routerTrampoline))
        );
        plan = Plan.init()
            .clearRequests(true, false, Plan.one(controller))
            .swapViaRouter(address(router), 1, true, 0, data)
            .settleRequests();
        uint256 escrowDuring;
        uint256 snapshot = vm.snapshotState();
        router.arm(address(almCore), abi.encodeWithSignature("balanceOf(address)", address(almCore)));
        runPlan(plan);
        escrowDuring = abi.decode(router.result(), (uint256));
        vm.revertToState(snapshot);
        router.arm(address(almCore), abi.encodeCall(ALMCoreExtension.redeemEpoch, (asyncVault0, nextEpoch)));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the redeem and swaps.
        runPlan(plan);

        // Then: During the plan the shares stay in escrow, the epoch has no output.
        assertEq(escrowDuring, queueState.redeem0 + queueState.redeem1);
        assertEq(abi.decode(router.result(), (Epoch)).amountOut, 0);

        // And: After it, the shares are burned, the epoch holding their pre-swap value.
        assertEq(almCore.balanceOf(address(almCore)), queueState.redeem1);
        assertEq(almCore.redeemEpoch(asyncVault0, nextEpoch).amountOut, assets);
    }

    function testFuzz_Success_clearRequests_EmitsRedeemCleared(
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

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the redeem.
        Plan.Steps memory plan = Plan.init().clearRequests(true, false, Plan.one(controller)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(true, true, true, true, address(almCore));
        emit IALMCoreEvents.RedeemCleared(asyncVault0, controller, queueState.redeem0);
        // Then: The clear is logged at the core.
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_clearRequests_EmitsRedeemEpochSettledAtTheClearedId(
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
        }
        uint256 ceiling =
            token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0()).fullMulDiv(almCore.totalSupply(), value);
        ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
        queueState.redeem0 = bound(queueState.redeem0, 1, ceiling);
        setQueueState(queueState);
        uint32 nextEpoch;
        {
            (, uint32 pendingEpoch) = almCore.pendingEpochs(asyncVault0);
            (, uint32 lastClearedEpoch) = almCore.lastClearedEpochs(asyncVault0);
            nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
        }
        uint256 assets =
            token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, almCore.totalSupply()));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the redeem.
        Plan.Steps memory plan = Plan.init().clearRequests(true, false, Plan.one(controller)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(true, true, true, true, address(almCore));
        emit IALMCoreEvents.RedeemEpochSettled(asyncVault0, nextEpoch, assets, queueState.redeem0);
        // Then: The settlement is logged at the fresh cleared id.
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_clearRequests_KeepsTheTwoVaultsApart_Redeem(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 shares1,
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

        // And: Pending requests and one controller's redeem at each vault.
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
        shares1 = bound(shares1, 1, almCore.totalSupply());
        recordRedeemAt(asyncVault1, controller, shares1);
        (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = almCore.pendingEpochs(asyncVault1);
        (uint32 lastClearedDepositEpoch, uint32 lastClearedRedeemEpoch) = almCore.lastClearedEpochs(asyncVault1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the controller at the token0 vault.
        runPlan(Plan.init().clearRequests(true, false, Plan.one(controller)).settleRequests());

        // Then: The token1 redeem stays in its pending epoch, its shares in escrow.
        Record memory record = almCore.redeemRecord(asyncVault1, controller);
        assertEq(record.epoch, pendingRedeemEpoch);
        assertEq(record.amountIn, shares1);
        assertEq(almCore.redeemEpoch(asyncVault1, pendingRedeemEpoch).amountIn, shares1 + queueState.redeem1);
        assertEq(almCore.balanceOf(address(almCore)), shares1 + queueState.redeem1);

        // And: The token1 vault drew no id.
        (uint32 pendingDepositEpochAfter, uint32 pendingRedeemEpochAfter) = almCore.pendingEpochs(asyncVault1);
        (uint32 lastClearedDepositEpochAfter, uint32 lastClearedRedeemEpochAfter) =
            almCore.lastClearedEpochs(asyncVault1);
        assertEq(pendingDepositEpochAfter, pendingDepositEpoch);
        assertEq(pendingRedeemEpochAfter, pendingRedeemEpoch);
        assertEq(lastClearedDepositEpochAfter, lastClearedDepositEpoch);
        assertEq(lastClearedRedeemEpochAfter, lastClearedRedeemEpoch);
    }

    function testFuzz_Success_clearRequests_ClearedRequestIsClaimableAfterThePlan_Redeem(
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
        givenBufferPaysShares(coreState, poolState, range, 1, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests with a token0 redeem its buffer pays, the keeper cleared.
        givenValidQueueState(queueState, 0, 0);
        uint256 value;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = amount1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
        }
        uint256 ceiling =
            token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0()).fullMulDiv(almCore.totalSupply(), value);
        ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
        queueState.redeem0 = bound(queueState.redeem0, 1, ceiling);
        setQueueState(queueState);
        uint256 settled =
            token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, almCore.totalSupply()));
        runPlan(Plan.init().clearRequests(true, false, Plan.one(controller)).settleRequests());

        // When: The vault claims the whole redeem for the controller.
        vm.prank(asyncVault0);
        uint256 assets = almCore.claimRedeemRequest(controller, queueState.redeem0, type(uint256).max, accountB);

        // Then: The controller is paid the cleared epoch's assets.
        assertEq(assets, settled);
        assertEq(token0.balanceOf(accountB), settled);

        // And: Its record and pending aLP are released.
        assertEq(almCore.redeemRecord(asyncVault0, controller).amountIn, 0);
        assertEq(almCore.pendingShares_(controller), 0);
    }

    function testFuzz_Success_clearRequests_ClearedRequestIsNoLongerCancelable_Redeem(
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
        givenBufferPaysShares(coreState, poolState, range, 1, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests with a token0 redeem its buffer pays, the keeper cleared.
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

        // When: The vault cancels the redeem.
        // Then: It reverts.
        vm.prank(asyncVault0);
        vm.expectRevert(QueueLib.RequestNotPending.selector);
        almCore.cancelRedeemRequest(0, controller, controller);
    }

    function testFuzz_Success_clearRequests_RedeemUnderPause(
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
        }
        uint256 ceiling =
            token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0()).fullMulDiv(almCore.totalSupply(), value);
        ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
        queueState.redeem0 = bound(queueState.redeem0, 1, ceiling);
        setQueueState(queueState);
        uint256 supply = almCore.totalSupply();
        uint32 nextEpoch;
        {
            (, uint32 pendingEpoch) = almCore.pendingEpochs(asyncVault0);
            (, uint32 lastClearedEpoch) = almCore.lastClearedEpochs(asyncVault0);
            nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
        }

        // And: A paused core.
        vm.prank(factory);
        almCore.pause();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the redeem.
        runPlan(Plan.init().clearRequests(true, false, Plan.one(controller)).settleRequests());

        // Then: The clear ran and settled at the start value per share.
        assertEq(almCore.redeemRecord(asyncVault0, controller).epoch, nextEpoch);
        assertEq(
            almCore.redeemEpoch(asyncVault0, nextEpoch).amountOut,
            token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, supply))
        );
    }

    function testFuzz_Success_clearRequests_Token1VaultClearsItsOwnSide_Redeem(
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
        givenBufferPaysShares(coreState, poolState, range, 0, 1);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a token1 redeem the token1 buffer pays among them.
        givenValidQueueState(queueState, 0, 0);
        uint256 value;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = amount1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
            uint256 ceiling = FixedPointMathLib.min(
                almCore.balanceOf(users.steward) / 2, almCore.bufferAmount1().fullMulDiv(almCore.totalSupply(), value)
            );
            queueState.redeem1 = bound(queueState.redeem1, 1, ceiling);
        }
        setQueueState(queueState);
        uint256 supply = almCore.totalSupply();
        (uint256 buffer0Before, uint256 buffer1Before) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        uint32 nextEpoch;
        {
            (, uint32 pendingEpoch) = almCore.pendingEpochs(asyncVault1);
            (, uint32 lastClearedEpoch) = almCore.lastClearedEpochs(asyncVault1);
            nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
        }

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the redeem at the token1 vault.
        runPlan(Plan.init().clearRequests(false, false, Plan.one(secondController)).settleRequests());

        // Then: The redeem settles in the token1 cleared epoch at the start value.
        uint256 assets = queueState.redeem1.fullMulDiv(value, supply);
        assertEq(almCore.redeemRecord(asyncVault1, secondController).epoch, nextEpoch);
        Epoch memory epoch = almCore.redeemEpoch(asyncVault1, nextEpoch);
        assertEq(epoch.amountIn, queueState.redeem1);
        assertEq(epoch.amountOut, assets);

        // And: The shares are burned, the assets moved from the token1 buffer to escrow.
        assertEq(almCore.balanceOf(address(almCore)), queueState.redeem0);
        assertEq(almCore.totalSupply(), supply - queueState.redeem1);
        assertEq(almCore.bufferAmount1(), buffer1Before - assets);
        assertEq(almCore.getEscrowed1(), queueState.deposit1 + assets);

        // And: The token0 side is untouched.
        assertEq(almCore.bufferAmount0(), buffer0Before);
        (uint32 pendingDepositEpoch0, uint32 pendingRedeemEpoch0) = almCore.pendingEpochs(asyncVault0);
        (uint32 lastClearedDepositEpoch0, uint32 lastClearedRedeemEpoch0) = almCore.lastClearedEpochs(asyncVault0);
        assertEq(pendingDepositEpoch0, 0);
        assertEq(pendingRedeemEpoch0, 0);
        assertEq(lastClearedDepositEpoch0, 0);
        assertEq(lastClearedRedeemEpoch0, 0);
    }

    function testFuzz_Success_clearRequests_DuplicateControllerClearsOnce_Redeem(
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
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper names the controller twice in one clear, logging one clear.
        Plan.Steps memory plan =
            Plan.init().clearRequests(true, false, Plan.two(controller, controller)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(true, true, true, true, address(almCore), 1);
        emit IALMCoreEvents.RedeemCleared(asyncVault0, controller, queueState.redeem0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The redeem is cleared, burned and paid once.
        Epoch memory epoch = almCore.redeemEpoch(asyncVault0, nextEpoch);
        assertEq(epoch.amountIn, queueState.redeem0);
        assertEq(epoch.amountOut, token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, supply)));
        assertEq(almCore.totalSupply(), supply - queueState.redeem0);
        assertEq(almCore.getEscrowed0(), queueState.deposit0 + epoch.amountOut);
    }

    function testFuzz_Success_clearRequests_SkipsASettledRecordFromAnEarlierPlan_Redeem(
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

        // And: Pending requests with a token0 redeem its buffer pays, since cleared.
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
        uint32 nextEpoch;
        {
            (, uint32 pendingEpoch) = almCore.pendingEpochs(asyncVault0);
            (, uint32 lastClearedEpoch) = almCore.lastClearedEpochs(asyncVault0);
            nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
        }
        runPlan(Plan.init().clearRequests(true, false, Plan.one(controller)).settleRequests());
        Epoch memory epochBefore = almCore.redeemEpoch(asyncVault0, nextEpoch);
        uint256 supply = almCore.totalSupply();
        uint256 buffer0Before = almCore.bufferAmount0();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper names it again in a later plan, logging no clear.
        Plan.Steps memory plan = Plan.init().clearRequests(true, false, Plan.one(controller)).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(false, false, false, false, address(almCore), 0);
        emit IALMCoreEvents.RedeemCleared(asyncVault0, controller, 0);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The record and its settled epoch are untouched, and nothing is paid.
        Record memory record = almCore.redeemRecord(asyncVault0, controller);
        assertEq(record.epoch, nextEpoch);
        assertEq(record.amountIn, queueState.redeem0);
        Epoch memory epoch = almCore.redeemEpoch(asyncVault0, nextEpoch);
        assertEq(epoch.amountIn, epochBefore.amountIn);
        assertEq(epoch.amountOut, epochBefore.amountOut);
        assertEq(almCore.totalSupply(), supply);
        assertEq(almCore.bufferAmount0(), buffer0Before);
    }

    function testFuzz_Success_clearRequests_EmptyPayloadIsANoOp_Redeem(
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
        (uint256 buffer0Before, uint256 buffer1Before) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        (, uint32 pendingEpoch) = almCore.pendingEpochs(asyncVault0);
        (, uint32 lastClearedEpoch) = almCore.lastClearedEpochs(asyncVault0);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the vault naming no controller.
        runPlan(Plan.init().clearRequests(true, false, Plan.none()).settleRequests());

        // Then: The epochs, the escrowed shares and the buffers are unchanged.
        (, uint32 pendingEpochAfter) = almCore.pendingEpochs(asyncVault0);
        (, uint32 lastClearedEpochAfter) = almCore.lastClearedEpochs(asyncVault0);
        assertEq(pendingEpochAfter, pendingEpoch);
        assertEq(lastClearedEpochAfter, lastClearedEpoch);
        assertEq(almCore.balanceOf(address(almCore)), queueState.redeem0 + queueState.redeem1);
        assertEq(almCore.bufferAmount0(), buffer0Before);
        assertEq(almCore.bufferAmount1(), buffer1Before);

        // And: The redeem stays pending.
        assertEq(almCore.redeemRecord(asyncVault0, controller).epoch, pendingEpoch);
        assertEq(almCore.redeemEpoch(asyncVault0, pendingEpoch).amountIn, queueState.redeem0);
    }

    function testFuzz_Success_clearRequests_RedeemWorthLessThanAnAssetSettlesToZeroAssets(
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
        givenShareWorthLessThanToken0(coreState, poolState, range);
        setCoreState(coreState);
        setRangeState(range);
        uint256 supply = almCore.totalSupply();
        uint256 buffer0Before = almCore.bufferAmount0();

        // And: Pending requests, a token0 redeem worth less than one asset among them.
        givenValidQueueState(queueState, 0, 0);
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        uint256 value = amount1 + almCore.bufferAmount1() + token0ToToken1(poolState.sqrtPrice, amount0 + buffer0Before);
        uint256 asset = FixedPointMathLib.fullMulDivUp(1, poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192);
        uint256 ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, (asset * supply - 1) / value);
        queueState.redeem0 = bound(queueState.redeem0, 1, ceiling);
        setQueueState(queueState);
        uint32 nextEpoch;
        {
            (, uint32 pendingEpoch) = almCore.pendingEpochs(asyncVault0);
            (, uint32 lastClearedEpoch) = almCore.lastClearedEpochs(asyncVault0);
            nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
        }

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the redeem.
        runPlan(Plan.init().clearRequests(true, false, Plan.one(controller)).settleRequests());

        // Then: The cleared epoch settles to zero assets, and the shares are burned.
        Epoch memory epoch = almCore.redeemEpoch(asyncVault0, nextEpoch);
        assertEq(epoch.amountIn, queueState.redeem0);
        assertEq(epoch.amountOut, 0);
        assertEq(almCore.totalSupply(), supply - queueState.redeem0);
        assertEq(almCore.balanceOf(address(almCore)), queueState.redeem1);

        // And: Nothing left the buffer.
        assertEq(almCore.bufferAmount0(), buffer0Before);
        assertEq(almCore.getEscrowed0(), queueState.deposit0);
    }
}
