/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ALMCoreExtension } from "../../utils/extensions/ALMCoreExtension.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { Epoch } from "../../../src/core/types/State.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { LockProbeRouterMock } from "../../utils/mocks/LockProbeRouterMock.sol";
import { Plan } from "../../utils/Plan.sol";
import { PlanCacheLib } from "../../../src/core/types/PlanCache.sol";
import { PoolTokensLib } from "../../../src/core/libraries/state/PoolTokensLib.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { ShareLib } from "../../../src/core/libraries/state/ShareLib.sol";

/**
 * @notice Fuzz tests for the command "CLEAR_ALL_REQUESTS" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unused-return, unsafe-typecast)
contract ClearAllRequests_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_clearAllRequests_Paused_Deposit(
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
        Plan.Steps memory plan = Plan.init().clearAllRequests(true, true).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.Paused.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_clearAllRequests_AlreadyCleared_Deposit(
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

        // And: A plan that clears the first by name, then all deposits.
        Plan.Steps memory plan =
            Plan.init().clearRequests(true, true, Plan.one(accountB)).clearAllRequests(true, true).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.AlreadyCleared.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_clearAllRequests_AlreadyCleared_Token1Vault_Deposit(
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

        // And: Pending requests, the token1 vault's deposit split over two controllers.
        givenValidQueueState(queueState, 0, 2);
        secondAssets = bound(secondAssets, 1, queueState.deposit1 - 1);
        queueState.deposit1 -= secondAssets;
        setQueueState(queueState);
        recordDepositAt(asyncVault1, controller, secondAssets);

        // And: A plan that clears the first by name, then all token1 deposits.
        Plan.Steps memory plan =
            Plan.init().clearRequests(false, true, Plan.one(accountC)).clearAllRequests(false, true).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.AlreadyCleared.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_clearAllRequests_ZeroValue(
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
        Plan.Steps memory plan = Plan.init().clearAllRequests(false, true).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(PlanCacheLib.ZeroValue.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_clearAllRequests_ZeroSupply(
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
        Plan.Steps memory plan = Plan.init().clearAllRequests(false, true).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(PlanCacheLib.ZeroSupply.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_clearAllRequests_TotalCapExceeded(
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

        // And: A total cap one share short of the supply the epoch settles to.
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
        Plan.Steps memory plan = Plan.init().clearAllRequests(true, true).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ShareLib.TotalCapExceeded.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_clearAllRequests_AlreadyCleared_Redeem(
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

        // And: A plan that clears the first by name, then all redeems.
        Plan.Steps memory plan =
            Plan.init().clearRequests(true, false, Plan.one(controller)).clearAllRequests(true, false).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.AlreadyCleared.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_clearAllRequests_AlreadyCleared_Token1Vault_Redeem(
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

        // And: A plan clearing the first by name, then all token1 vault redeems.
        Plan.Steps memory plan = Plan.init()
            .clearRequests(false, false, Plan.one(secondController))
            .clearAllRequests(false, false)
            .settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.AlreadyCleared.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_clearAllRequests_InsufficientBuffer(
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
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        (uint256 buffer0, uint256 buffer1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        uint256 value = amount0 + amount1 + buffer0 + buffer1;
        uint256 supply = almCore.totalSupply();
        givenValidQueueState(queueState, 0, 0);
        uint256 floor = supply.divUp(value);
        uint256 ceiling =
            FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, (buffer0 + buffer1).fullMulDiv(supply, value));
        queueState.redeem0 = bound(queueState.redeem0, floor, ceiling);
        setQueueState(queueState);

        // And: A token0 buffer one asset short of the payout, the rest in token1.
        uint256 assets = queueState.redeem0.fullMulDiv(value, supply);
        token0.mint(address(almCore), (assets - 1).zeroFloorSub(buffer0));
        token1.mint(address(almCore), (buffer0 + buffer1 - assets + 1).zeroFloorSub(buffer1));
        almCore.setBuffers(assets - 1, buffer0 + buffer1 - assets + 1);
        Plan.Steps memory plan = Plan.init().clearAllRequests(true, false).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(PoolTokensLib.InsufficientBuffer.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_clearAllRequests_InsufficientBuffer_DrainedAfterTheStep(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range, spare token0 worth half an amount at most, a wei to sell.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        {
            (uint256 amount0,) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            coreState.buffer0 = FixedPointMathLib.min(
                coreState.buffer0,
                amount0 + token1ToToken0(poolState.sqrtPrice, (Constants.MAX_FUZZED_AMOUNT - coreState.buffer1) / 2)
            );
        }
        setCoreState(coreState);
        setRangeState(range);
        fundBuffer(1, 0);

        // And: A sale of the whole token0 buffer at the price after the settle.
        uint256 out;
        Plan.Steps memory plan;
        {
            uint256 sold = almCore.bufferAmount0();
            out = token0ToToken1(poolState.sqrtPrice, sold);
            LockProbeRouterMock router = new LockProbeRouterMock();
            bytes memory data = abi.encodeCall(
                LockProbeRouterMock.swap, (address(token0), address(token1), sold, out, address(routerTrampoline))
            );
            plan = Plan.init()
                .clearAllRequests(true, false)
                .swapViaRouter(address(router), sold, true, 0, data)
                .settleRequests();
        }

        // And: Pending requests with a token0 redeem worth an asset at the end value.
        givenValidQueueState(queueState, 0, 0);
        {
            uint256 value;
            {
                (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                    uint160(poolState.sqrtPrice),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                value = amount1 + almCore.bufferAmount1() + out + token0ToToken1(poolState.sqrtPrice, amount0);
            }
            uint256 floor = FixedPointMathLib.fullMulDivUp(1, poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192);
            floor = floor.fullMulDivUp(almCore.totalSupply(), value);
            // And: A seed receiver holding twice the shares an asset is worth.
            vm.assume(floor <= almCore.balanceOf(users.steward) / 2);
            queueState.redeem0 = bound(queueState.redeem0, floor, almCore.balanceOf(users.steward) / 2);
        }
        setQueueState(queueState);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs the plan.
        // Then: It reverts when the payout finds the buffer short.
        vm.prank(users.keeper);
        vm.expectRevert(PoolTokensLib.InsufficientBuffer.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_clearAllRequests_EmptyEpochIsANoOp_Deposit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with an empty deposit epoch.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Plan.Steps memory plan = Plan.init().clearAllRequests(true, true).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        (uint32 pendingDepositEpochBefore,) = almCore.pendingEpochs(asyncVault0);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears all deposits.
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The epoch stays pending.
        (uint32 pendingDepositEpoch,) = almCore.pendingEpochs(asyncVault0);
        assertEq(pendingDepositEpoch, pendingDepositEpochBefore);
    }

    function testFuzz_Success_clearAllRequests_AfterAListClearOfEveryRequestIsANoOp_Deposit(
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
        uint32 nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);
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

        // When: The keeper clears the deposit by name, then all deposits.
        runPlan(Plan.init().clearRequests(true, true, Plan.one(accountB)).clearAllRequests(true, true).settleRequests());

        // Then: The pending epoch stays, the deposit settled in the list clear's id.
        (uint32 pendingEpochAfter,) = almCore.pendingEpochs(asyncVault0);
        (uint32 lastClearedEpochAfter,) = almCore.lastClearedEpochs(asyncVault0);
        assertEq(pendingEpochAfter, pendingEpoch);
        assertEq(lastClearedEpochAfter, nextEpoch);
        assertEq(FixedPointMathLib.max(pendingEpochAfter, lastClearedEpochAfter) + 1, uint256(nextEpoch) + 1);
        assertEq(almCore.depositEpoch(asyncVault0, nextEpoch).amountIn, queueState.deposit0);
        assertEq(almCore.depositEpoch(asyncVault0, nextEpoch).amountOut, shares);
    }

    function testFuzz_Success_clearAllRequests_SecondClearIsANoOp(
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
        uint256 shares;
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        uint256 depositValue = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
        shares = depositValue.fullMulDiv(
            supply,
            amount1 + almCore.bufferAmount1()
                + CLMath.convert(poolState.sqrtPrice, true, amount0 + almCore.bufferAmount0(), true)
        );
        Plan.Steps memory plan = Plan.init().clearAllRequests(true, true).clearAllRequests(true, true).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        (uint32 pendingDepositEpochBefore,) = almCore.pendingEpochs(asyncVault0);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears all deposits of the vault twice in one plan.
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: Only the first clear moved the epoch.
        (uint32 pendingDepositEpoch,) = almCore.pendingEpochs(asyncVault0);
        assertEq(pendingDepositEpoch, pendingDepositEpochBefore + 1);

        // And: The deposit settled once, at the start value per share.
        assertEq(almCore.depositEpoch(asyncVault0, pendingDepositEpochBefore).amountOut, shares);
        assertEq(almCore.totalSupply(), supply + shares);
    }

    function testFuzz_Success_clearAllRequests_SettlesTheEpoch_Deposit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 received,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range, earning only the reward below.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        mockEarned(gauge, address(almCore), 0);

        // And: Pending requests, a deposit at the token0 vault among them.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        uint256 supplyBefore = almCore.totalSupply();
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 escrowBefore = almCore.balanceOf(address(almCore));
        uint256 shares;
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        uint256 depositValue = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
        shares = depositValue.fullMulDiv(
            supplyBefore,
            amount1 + almCore.bufferAmount1() + CLMath.convert(poolState.sqrtPrice, true, amount0 + buffer0Before, true)
        );

        // And: An uncredited reward, its reward per share a uint128 with half to spare.
        received = bound(
            received,
            1,
            FixedPointMathLib.min(supplyBefore.fullMulDiv(type(uint128).max / 2, 1e18), Constants.MAX_FUZZED_AMOUNT)
        );
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());

        // Then: The epoch stores the deposit's shares at the start supply and value.
        Epoch memory epoch = almCore.depositEpoch(asyncVault0, 0);
        assertEq(epoch.amountIn, queueState.deposit0);
        assertEq(epoch.amountOut, shares);

        // And: The checkpoint raised the accumulator over the supply before the mint.
        uint256 net = received - received * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        assertEq(almCore.rewardPerShare_(), net.fullMulDiv(1e18, supplyBefore));

        // And: The checkpoint counted the net reward as claimed and as the high water.
        assertEq(almCore.getLastRewardBalance(), received);
        assertEq(almCore.getClaimedCumulative(), net);
        assertEq(almCore.getRewardHighWater(), net);

        // And: The assets moved from escrow to the buffer.
        assertEq(almCore.getEscrowed0(), 0);
        assertEq(almCore.bufferAmount0(), buffer0Before + queueState.deposit0);

        // And: The shares are minted to the core.
        assertEq(almCore.totalSupply(), supplyBefore + shares);
        assertEq(almCore.balanceOf(address(almCore)), escrowBefore + shares);
        assertEq(almCore.claimableSharesOf_(accountB), 0);

        // And: The next epoch is the pending one.
        (uint32 pendingDepositEpoch,) = almCore.pendingEpochs(asyncVault0);
        assertEq(pendingDepositEpoch, 1);
    }

    function testFuzz_Success_clearAllRequests_EmitsDepositEpochSettled(
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

        // When: The keeper settles the epoch.
        Plan.Steps memory plan = Plan.init().clearAllRequests(true, true).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(true, true, true, true, address(almCore));
        emit IALMCoreEvents.DepositEpochSettled(asyncVault0, 0, queueState.deposit0, shares);
        // Then: The settlement is logged at the core.
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_clearAllRequests_AtTotalCap(
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

        // And: A total cap with room for exactly the supply the epoch settles to.
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        uint256 supply = almCore.totalSupply();
        uint256 depositValue = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
        uint256 cap = supply
            + depositValue.fullMulDiv(
                supply,
                amount1 + almCore.bufferAmount1()
                    + CLMath.convert(poolState.sqrtPrice, true, amount0 + almCore.bufferAmount0(), true)
            );
        vm.prank(factory);
        almCore.setTotalCap(cap);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());

        // Then: The settlement fills the cap exactly.
        assertEq(almCore.totalSupply(), cap);
    }

    function testFuzz_Success_clearAllRequests_PastPerUserCap(
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

        // And: Pending requests with a token0 deposit, and a per user cap of nothing.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        uint256 escrowBefore = almCore.balanceOf(address(almCore));
        vm.prank(factory);
        almCore.setPerUserCap(0);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());

        // Then: The epoch is settled and its shares are minted to the core.
        (uint32 pendingDepositEpoch,) = almCore.pendingEpochs(asyncVault0);
        assertEq(pendingDepositEpoch, 1);
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountIn, queueState.deposit0);
        assertEq(almCore.balanceOf(address(almCore)), escrowBefore + almCore.depositEpoch(asyncVault0, 0).amountOut);
    }

    function testFuzz_Success_clearAllRequests_GasFlatInControllers(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 controllers,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price, and a vault holding a range.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: The token0 vault's deposit, held by one controller, then split over many.
        controllers = bound(controllers, 2, Constants.MAX_FUZZED_CONTROLLERS);
        givenValidQueueState(queueState, controllers, 0);
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        uint256 snapshot = vm.snapshotState();
        uint256 usedByOne;
        for (uint256 count = 1; count <= controllers; count += controllers - 1) {
            vm.revertToState(snapshot);
            uint256 share = queueState.deposit0 / count;
            for (uint256 i; i < count; ++i) {
                recordDepositAt(
                    asyncVault0,
                    address(uint160(uint256(keccak256(abi.encode(i))))),
                    i == 0 ? queueState.deposit0 - share * (count - 1) : share
                );
            }
            setPlanLimits(configState);

            // When: The keeper settles the epoch.
            runPlan(Plan.init().clearAllRequests(true, true).settleRequests());

            // Then: The settlement costs the same gas for every split.
            if (count == 1) usedByOne = vm.lastFrameGas().gasTotalUsed;
            else assertEq(vm.lastFrameGas().gasTotalUsed, usedByOne);
        }
    }

    function testFuzz_Success_clearAllRequests_SurvivesACancelBeforeThePlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 canceled,
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

        // And: Pending requests, the token0 deposit split with one that cancelled.
        givenValidQueueState(queueState, 2, 0);
        canceled = bound(canceled, 1, queueState.deposit0 - 1);
        queueState.deposit0 -= canceled;
        setQueueState(queueState);
        recordDepositAt(asyncVault0, controller, canceled);
        vm.prank(asyncVault0);
        almCore.cancelDepositRequest(0, controller, controller);
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

        // When: The keeper settles the epoch.
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());

        // Then: The epoch converted only the remaining deposit, at the end value.
        Epoch memory epoch = almCore.depositEpoch(asyncVault0, 0);
        assertEq(epoch.amountIn, queueState.deposit0);
        assertEq(epoch.amountOut, shares);
    }

    function testFuzz_Success_clearAllRequests_KeepsTheTwoVaultsApart(
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

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the token0 vault's epoch.
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());

        // Then: Only that vault's epoch is settled.
        (uint32 depositEpoch0,) = almCore.pendingEpochs(asyncVault0);
        (uint32 depositEpoch1,) = almCore.pendingEpochs(asyncVault1);
        assertEq(depositEpoch0, 1);
        assertEq(depositEpoch1, 0);
        assertEq(almCore.depositEpoch(asyncVault1, 0).amountIn, assets1 + queueState.deposit1);
        assertEq(almCore.getEscrowed1(), assets1 + queueState.deposit1);
    }

    function testFuzz_Success_clearAllRequests_ProtocolAccruesOnEveryShareTheCoreHolds(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 own,
        uint256 received
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range, earning only the reward below.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        mockEarned(gauge, address(almCore), 0);

        // And: Pending requests, a settled deposit, and core-held aLP within the cap.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        uint256 held = queueState.redeem0 + queueState.redeem1;
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        uint256 depositValue = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
        held += depositValue.fullMulDiv(
            almCore.totalSupply(),
            amount1 + almCore.bufferAmount1()
                + CLMath.convert(poolState.sqrtPrice, true, amount0 + almCore.bufferAmount0(), true)
        );
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());
        own = bound(own, 1, (almCore.totalCap_() - almCore.totalSupply()) / 4);
        almCore.mintShares(address(almCore), own);
        held += own;
        uint256 protocolFeesBefore = almCore.getProtocolFeesReward();
        uint256 supply = almCore.totalSupply();

        // And: A reward that keeps the reward per share a uint128 with half to spare.
        received = bound(
            received,
            1,
            FixedPointMathLib.min(supply.fullMulDiv(type(uint128).max / 2, 1e18), Constants.MAX_FUZZED_AMOUNT)
        );
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);

        // When: The core is accrued.
        almCore.updateRewards(address(almCore));

        // Then: The protocol earned the fee and the accrual of every core-held share.
        uint256 fee = received * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        assertEq(
            almCore.getProtocolFeesReward(),
            protocolFeesBefore + fee + held.fullMulDiv((received - fee).fullMulDiv(1e18, supply), 1e18)
        );
    }

    function testFuzz_Success_clearAllRequests_RewardAroundAnUnstakeIsCreditedOnce(
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

        // And: A vault holding a range with a staked leg.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                1,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, the token0 vault's deposit split over two controllers.
        givenValidQueueState(queueState, 2, 0);
        secondAssets = bound(secondAssets, 1, queueState.deposit0 - 1);
        queueState.deposit0 -= secondAssets;
        setQueueState(queueState);
        recordDepositAt(asyncVault0, controller, secondAssets);

        // And: Emissions at the ceiling, earned outside the penalty window.
        addEmissionsToGaugeCL(pool, gauge, Constants.MAX_EMISSIONS);
        closePenaltyWindow(gauge);

        // And: A plan that clears the epoch, unstakes the range and settles the epoch.
        Range memory staked = almCore.getRange(range.index);
        Plan.Steps memory plan = Plan.init().clearAllRequests(true, true);
        plan = plan.unstake(range.index, staked.stakedTokenId, staked.stakedLiquidity, 0, 0, false).settleRequests();
        uint256 earned = gauge.earned(address(almCore));
        uint256 stewardShares = almCore.balanceOf(users.steward);
        uint256 rewardPerShare = (earned - earned * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR)
        .fullMulDiv(1e18, almCore.totalSupply());

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch and unstakes, the gauge paying out.
        runPlan(plan);

        // Then: The unstake delivered the reward the gauge had reported earned.
        assertEq(ERC20Mock(almCore.REWARD_TOKEN_()).balanceOf(address(almCore)), earned);

        // And: The seed holder is credited once, on the supply before the settle.
        almCore.updateRewards(users.steward);
        assertEq(almCore.getPendingReward(users.steward), stewardShares.fullMulDiv(rewardPerShare, 1e18));
    }

    function testFuzz_Success_clearAllRequests_SettlesAfterThePreCredit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 window,
        uint256 joinedAfter,
        uint256 emissions,
        uint16 feeBps,
        uint256 pick,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge hiding the staked emissions for a fuzzed window, a fuzzed fee.
        window = bound(window, 2, type(uint40).max);
        setPenaltyConfig(window, MAX_PIPS);
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        uint16 protocolSwapFeeBps = almCore.protocolSwapFeeBps_();
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, protocolSwapFeeBps, users.feeRecipient);

        // And: A vault holding a range whose staked leg opens its penalty window now.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests with a token0 deposit, and the supply it mints over.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        uint256 supply = almCore.totalSupply();
        uint256 rewardPerShare = almCore.rewardPerShare_();

        // And: Hidden emissions lifting the reward per share a unit, in the window.
        emissions = bound(
            emissions,
            FixedPointMathLib.fullMulDivUp(
                supply / 1e18 + 1,
                ConfigLib.BPS_DENOMINATOR,
                ConfigLib.BPS_DENOMINATOR - almCore.protocolEmissionFeeBps_()
            ),
            Constants.MAX_EMISSIONS
        );
        joinedAfter = bound(joinedAfter, 1, window - 1);
        accrueForBlocks(pool, gauge, joinedAfter, emissions);

        // And: A chain that mints.
        setMintableStatus(pick);
        uint256 hidden = hiddenEmissions(gauge, address(almCore), almCore.stakedTokenIds());
        hidden -= hidden * feeBps / ConfigLib.BPS_DENOMINATOR;

        // And: Net hidden emissions lifting the reward per share.
        vm.assume(FixedPointMathLib.fullMulDiv(hidden, 1e18, supply) > 0);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());

        // Then: The pre-credit raised the reward per share over the supply before it.
        assertEq(almCore.rewardPerShare_(), rewardPerShare + FixedPointMathLib.fullMulDiv(hidden, 1e18, supply));

        // And: The pre-credit holds the hidden emissions, net of the fee.
        assertEq(almCore.getPreCredited(), hidden);
    }

    function testFuzz_Success_clearAllRequests_CountsTheGaugeOnAnyChainStatus_Deposit(
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
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a deposit at the token0 vault among them.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        uint256 supplyBefore = almCore.totalSupply();

        // And: A reward, gauge emissions and a window end, on a fuzzed chain status.
        uint256 unsaturated =
            FixedPointMathLib.min(supplyBefore.fullMulDiv(type(uint128).max / 2, 1e18), Constants.MAX_FUZZED_AMOUNT);
        received = bound(received, 1, unsaturated);
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);
        earned = bound(earned, 0, unsaturated);
        mockEarned(gauge, address(almCore), earned);
        windowEnd = uint48(bound(windowEnd, 1, type(uint48).max));
        almCore.setWindowEnd(windowEnd);
        setAnyStatus(status);

        // And: The net reward counted, the gauge's part included.
        uint256 feeBps = almCore.protocolEmissionFeeBps_();
        uint256 netReceived = received - received * feeBps / ConfigLib.BPS_DENOMINATOR;
        uint256 counted = netReceived + earned - earned * feeBps / ConfigLib.BPS_DENOMINATOR;

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());

        // Then: The reward per share counts the reward over the supply before the mint.
        assertEq(almCore.rewardPerShare_(), counted.fullMulDiv(1e18, supplyBefore));

        // And: The high water counts the gauge and the measured, claimed reward.
        assertEq(almCore.getRewardHighWater(), counted);
        assertEq(almCore.getLastRewardBalance(), received);
        assertEq(almCore.getClaimedCumulative(), netReceived);

        // And: The window end is folded.
        assertEq(almCore.getWindowEnd(), 0);
    }

    function testFuzz_Success_clearAllRequests_SettlesTheEpochAtTheEnd(
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
        uint256 shares;
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        uint256 depositValue = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
        shares = depositValue.fullMulDiv(
            supplyBefore,
            amount1 + almCore.bufferAmount1() - 1
                + CLMath.convert(poolState.sqrtPrice, true, amount0 + almCore.bufferAmount0(), true)
                + CLMath.convert(poolState.sqrtPrice, true, out0, true)
        );

        // And: A token1 sale after the settle reading the supply, then the epoch.
        LockProbeRouterMock router = new LockProbeRouterMock();
        bytes memory data = abi.encodeCall(
            LockProbeRouterMock.swap, (address(token1), address(token0), 1, out0, address(routerTrampoline))
        );
        uint256 snapshot = vm.snapshotState();
        router.arm(address(almCore), abi.encodeWithSignature("totalSupply()"));
        runPlan(
            Plan.init().clearAllRequests(true, true).swapViaRouter(address(router), 1, false, 0, data).settleRequests()
        );
        uint256 supplyDuring = abi.decode(router.result(), (uint256));
        vm.revertToState(snapshot);
        router.arm(address(almCore), abi.encodeCall(ALMCoreExtension.depositEpoch, (asyncVault0, 0)));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(4, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch and swaps.
        runPlan(
            Plan.init().clearAllRequests(true, true).swapViaRouter(address(router), 1, false, 0, data).settleRequests()
        );

        // Then: During the plan, nothing is minted and the cleared epoch has no output.
        assertEq(supplyDuring, supplyBefore);
        assertEq(abi.decode(router.result(), (Epoch)).amountOut, 0);

        // And: After it, the epoch holds its shares, minted to escrow.
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountOut, shares);
        assertEq(almCore.totalSupply(), supplyBefore + shares);
        assertEq(almCore.balanceOf(address(almCore)), escrowBefore + shares);
    }

    function testFuzz_Success_clearAllRequests_AssetsUsableByALaterStep(
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
        uint256 amountIn = almCore.bufferAmount0() + queueState.deposit0;

        // And: A sale whose output fits an amount over the token1 buffer.
        uint256 out = token0ToToken1(poolState.sqrtPrice, amountIn);
        vm.assume(out <= Constants.MAX_FUZZED_AMOUNT - almCore.bufferAmount1());

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles, then sells more token0 than the buffer held.
        LockProbeRouterMock router = new LockProbeRouterMock();
        bytes memory data = abi.encodeCall(
            LockProbeRouterMock.swap, (address(token0), address(token1), amountIn, out, address(routerTrampoline))
        );
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .swapViaRouter(address(router), amountIn, true, 0, data)
                .settleRequests()
        );

        // Then: The sale took the deposited assets out of the buffer.
        assertEq(almCore.bufferAmount0(), 0);
    }

    function testFuzz_Success_clearAllRequests_NetOfRedeemsForTheCap(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range, and a token0 buffer paying shares worth a token0 wei.
        givenValidRangeState(range, poolState, false);
        givenBufferPaysShares(
            coreState,
            poolState,
            range,
            uint256(1).fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192) + 1,
            0
        );
        setCoreState(coreState);
        setRangeState(range);
        uint256 supply = almCore.totalSupply();

        // And: Pending requests with a token0 deposit and a token0 redeem worth more.
        givenValidQueueState(queueState, 1, 0);
        uint256 minted;
        {
            (uint256 amount0, uint256 value) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            amount0 += almCore.bufferAmount0();
            value += almCore.bufferAmount1();
            queueState.deposit0 = bound(
                queueState.deposit0,
                1,
                token1ToToken0(
                    poolState.sqrtPrice,
                    (almCore.balanceOf(users.steward) / 2)
                    .fullMulDiv(value + token0ToToken1(poolState.sqrtPrice, amount0), supply)
                )
            );
            value += CLMath.convert(poolState.sqrtPrice, true, amount0, true);
            minted = token0ToToken1(poolState.sqrtPrice, queueState.deposit0).fullMulDiv(supply, value);
            amount0 = token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() + queueState.deposit0)
                .fullMulDiv(supply, value);
            queueState.redeem0 = bound(
                queueState.redeem0,
                FixedPointMathLib.max(minted, 1),
                FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, amount0)
            );
        }
        setQueueState(queueState);

        // And: A total cap at the supply.
        vm.prank(factory);
        almCore.setTotalCap(supply);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles both in one plan.
        runPlan(Plan.init().clearAllRequests(true, true).clearAllRequests(true, false).settleRequests());

        // Then: The deposit's shares at the start value fit the room the redeem made.
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountOut, minted);
        assertEq(almCore.totalSupply(), supply - queueState.redeem0 + minted);
        assertLe(almCore.totalSupply(), supply);
    }

    function testFuzz_Success_clearAllRequests_CancelAfterTheSettleIsANoOp_Deposit(
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

        // When: The keeper settles the epoch, then cancels the deposit in the same plan.
        runPlan(
            Plan.init().clearAllRequests(true, true).cancelRequests(true, true, Plan.one(accountB)).settleRequests()
        );

        // Then: The cancel skipped the settled record, the epoch settled its input.
        assertEq(token0.balanceOf(accountB), 0);
        Epoch memory epoch = almCore.depositEpoch(asyncVault0, 0);
        assertEq(epoch.amountIn, queueState.deposit0);
        assertEq(epoch.amountOut, shares);
    }

    function testFuzz_Success_clearAllRequests_Token1VaultSettlesItsOwnSide_Deposit(
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
        uint256 escrowBefore = almCore.balanceOf(address(almCore));
        (uint256 buffer0Before, uint256 buffer1Before) = (almCore.bufferAmount0(), almCore.bufferAmount1());

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the token1 vault's epoch.
        runPlan(Plan.init().clearAllRequests(false, true).settleRequests());

        // Then: The epoch converts the deposit at the start value, minted to escrow.
        uint256 shares;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            shares = queueState.deposit1
                .fullMulDiv(
                    supply,
                    amount1 + buffer1Before + CLMath.convert(poolState.sqrtPrice, true, amount0 + buffer0Before, true)
                );
        }
        Epoch memory epoch = almCore.depositEpoch(asyncVault1, 0);
        assertEq(epoch.amountIn, queueState.deposit1);
        assertEq(epoch.amountOut, shares);
        assertEq(almCore.balanceOf(address(almCore)), escrowBefore + shares);
        assertEq(almCore.totalSupply(), supply + shares);

        // And: The assets moved from the token1 escrow to the token1 buffer.
        assertEq(almCore.getEscrowed1(), 0);
        assertEq(almCore.bufferAmount1(), buffer1Before + queueState.deposit1);
        (uint32 pendingDepositEpoch,) = almCore.pendingEpochs(asyncVault1);
        assertEq(pendingDepositEpoch, 1);

        // And: The token0 side is untouched.
        assertEq(almCore.bufferAmount0(), buffer0Before);
        (uint32 pendingDepositEpoch0, uint32 pendingRedeemEpoch0) = almCore.pendingEpochs(asyncVault0);
        (uint32 lastClearedDepositEpoch0, uint32 lastClearedRedeemEpoch0) = almCore.lastClearedEpochs(asyncVault0);
        assertEq(pendingDepositEpoch0, 0);
        assertEq(pendingRedeemEpoch0, 0);
        assertEq(lastClearedDepositEpoch0, 0);
        assertEq(lastClearedRedeemEpoch0, 0);
    }

    function testFuzz_Success_clearAllRequests_DepositWorthLessThanAShareSettlesToZeroShares(
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

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());

        // Then: The epoch settles to zero shares, and nothing is minted.
        Epoch memory epoch = almCore.depositEpoch(asyncVault0, 0);
        assertEq(epoch.amountIn, assets);
        assertEq(epoch.amountOut, 0);
        assertEq(almCore.totalSupply(), supply);
        assertEq(almCore.balanceOf(address(almCore)), 0);

        // And: The assets moved from escrow to the buffer.
        assertEq(almCore.getEscrowed0(), 0);
        assertEq(almCore.bufferAmount0(), buffer0Before + assets);
    }

    function testFuzz_Success_clearAllRequests_FullExitLeavesTheDeadShares(
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding only a token1 buffer, with aLP over the dead shares.
        RangeState memory range;
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        almCore.setBuffers(0, almCore.bufferAmount1());
        uint256 held1 = almCore.bufferAmount1();

        // And: Pending requests, token1 redeems of every aLP but the dead shares.
        givenValidQueueState(queueState, 0, 0);
        queueState.redeem0 = 0;
        setQueueState(queueState);
        uint256 stewardShares = almCore.balanceOf(users.steward);
        vm.prank(asyncVault1);
        almCore.recordRedeemRequest(users.steward, users.steward, users.steward, stewardShares);
        uint256 supply = almCore.totalSupply();
        uint256 redeemed = supply - Constants.DEAD_SHARES;

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        runPlan(Plan.init().clearAllRequests(false, false).settleRequests());

        // Then: The redeemers are paid at the start value per share.
        uint256 assets = redeemed.fullMulDiv(held1, supply);
        assertEq(almCore.redeemEpoch(asyncVault1, 0).amountIn, redeemed);
        assertEq(almCore.redeemEpoch(asyncVault1, 0).amountOut, assets);
        assertEq(almCore.bufferAmount1(), held1 - assets);
        assertEq(almCore.getEscrowed1(), queueState.deposit1 + assets);

        // And: Only the dead shares remain.
        assertEq(almCore.totalSupply(), Constants.DEAD_SHARES);
        assertEq(almCore.balanceOf(deadAddress), Constants.DEAD_SHARES);
    }

    function testFuzz_Success_clearAllRequests_EmptyEpochIsANoOp_Redeem(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with an empty redeem epoch.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Plan.Steps memory plan = Plan.init().clearAllRequests(true, false).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        (, uint32 pendingRedeemEpochBefore) = almCore.pendingEpochs(asyncVault0);
        uint256 supply = almCore.totalSupply();
        (uint256 buffer0Before, uint256 buffer1Before) = (almCore.bufferAmount0(), almCore.bufferAmount1());

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears all redeems.
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The epoch stays pending.
        (, uint32 pendingRedeemEpoch) = almCore.pendingEpochs(asyncVault0);
        assertEq(pendingRedeemEpoch, pendingRedeemEpochBefore);

        // And: No share is burned and nothing leaves the buffers.
        assertEq(almCore.totalSupply(), supply);
        assertEq(almCore.balanceOf(address(almCore)), 0);
        assertEq(almCore.bufferAmount0(), buffer0Before);
        assertEq(almCore.bufferAmount1(), buffer1Before);
    }

    function testFuzz_Success_clearAllRequests_AfterAListClearOfEveryRequestIsANoOp_Redeem(
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
        uint256 assets =
            token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, almCore.totalSupply()));
        (, uint32 pendingEpoch) = almCore.pendingEpochs(asyncVault0);
        (, uint32 lastClearedEpoch) = almCore.lastClearedEpochs(asyncVault0);
        uint32 nextEpoch = SafeCastLib.toUint32(FixedPointMathLib.max(pendingEpoch, lastClearedEpoch) + 1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the redeem by name, then all redeems.
        runPlan(
            Plan.init().clearRequests(true, false, Plan.one(controller)).clearAllRequests(true, false).settleRequests()
        );

        // Then: The pending epoch stays, the redeem settled in the list clear's id.
        (, uint32 pendingEpochAfter) = almCore.pendingEpochs(asyncVault0);
        (, uint32 lastClearedEpochAfter) = almCore.lastClearedEpochs(asyncVault0);
        assertEq(pendingEpochAfter, pendingEpoch);
        assertEq(lastClearedEpochAfter, nextEpoch);
        assertEq(FixedPointMathLib.max(pendingEpochAfter, lastClearedEpochAfter) + 1, uint256(nextEpoch) + 1);
        assertEq(almCore.redeemEpoch(asyncVault0, nextEpoch).amountIn, queueState.redeem0);
        assertEq(almCore.redeemEpoch(asyncVault0, nextEpoch).amountOut, assets);
    }

    function testFuzz_Success_clearAllRequests_SettlesTheEpoch_Redeem(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 received,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range, earning only the reward below.
        givenValidRangeState(range, poolState, false);
        givenBufferPaysShares(coreState, poolState, range, 1, 0);
        setCoreState(coreState);
        setRangeState(range);
        mockEarned(gauge, address(almCore), 0);

        // And: Pending requests, a token0 redeem the token0 buffer pays among them.
        givenValidQueueState(queueState, 0, 0);
        uint256 assets;
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
            assets = token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, almCore.totalSupply()));
        }
        setQueueState(queueState);
        uint256 supplyBefore = almCore.totalSupply();
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 feesBefore = almCore.getProtocolFeesReward();

        // And: An uncredited reward, its reward per share a uint128 with half to spare.
        received = bound(
            received,
            1,
            FixedPointMathLib.min(supplyBefore.fullMulDiv(type(uint128).max / 2, 1e18), Constants.MAX_FUZZED_AMOUNT)
        );
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        runPlan(Plan.init().clearAllRequests(true, false).settleRequests());

        // Then: The epoch stores the shares' value at the starting supply and value.
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountIn, queueState.redeem0);
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountOut, assets);

        // And: The checkpoint raised the accumulator over the supply before the burn.
        uint256 protocolFee = received * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        uint256 net = received - protocolFee;
        uint256 rewardPerShare = net.fullMulDiv(1e18, supplyBefore);
        assertEq(almCore.rewardPerShare_(), rewardPerShare);

        // And: The protocol took its fee and what the escrow earned up to the burn.
        protocolFee += (queueState.redeem0 + queueState.redeem1).fullMulDiv(rewardPerShare, 1e18);
        assertEq(almCore.getProtocolFeesReward() - feesBefore, protocolFee);

        // And: The checkpoint counted the net reward as claimed and as the high water.
        assertEq(almCore.getLastRewardBalance(), received);
        assertEq(almCore.getClaimedCumulative(), net);
        assertEq(almCore.getRewardHighWater(), net);

        // And: The shares are burned.
        assertEq(almCore.totalSupply(), supplyBefore - queueState.redeem0);
        assertEq(almCore.balanceOf(address(almCore)), queueState.redeem1);

        // And: The assets moved from the buffer to escrow.
        assertEq(almCore.bufferAmount0(), buffer0Before - assets);
        assertEq(almCore.getEscrowed0(), queueState.deposit0 + assets);

        // And: The next epoch is the pending one.
        (, uint32 pendingRedeemEpoch) = almCore.pendingEpochs(asyncVault0);
        assertEq(pendingRedeemEpoch, 1);
    }

    function testFuzz_Success_clearAllRequests_EmitsRedeemEpochSettled(
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
        uint256 assets =
            token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, almCore.totalSupply()));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        Plan.Steps memory plan = Plan.init().clearAllRequests(true, false).settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(true, true, true, true, address(almCore));
        emit IALMCoreEvents.RedeemEpochSettled(asyncVault0, 0, assets, queueState.redeem0);
        // Then: The settlement is logged at the core.
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_clearAllRequests_AtTheBuffer(
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

        // And: Pending requests, a token0 redeem the buffers pay among them.
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        (uint256 buffer0, uint256 buffer1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        uint256 value = amount0 + amount1 + buffer0 + buffer1;
        uint256 supply = almCore.totalSupply();
        givenValidQueueState(queueState, 0, 0);
        uint256 ceiling =
            FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, (buffer0 + buffer1).fullMulDiv(supply, value));
        queueState.redeem0 = bound(queueState.redeem0, 1, ceiling);
        setQueueState(queueState);

        // And: A token0 buffer of exactly the payout, the rest in token1.
        uint256 assets = queueState.redeem0.fullMulDiv(value, supply);
        token0.mint(address(almCore), assets.zeroFloorSub(buffer0));
        token1.mint(address(almCore), (buffer0 + buffer1 - assets).zeroFloorSub(buffer1));
        almCore.setBuffers(assets, buffer0 + buffer1 - assets);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        runPlan(Plan.init().clearAllRequests(true, false).settleRequests());

        // Then: The settlement empties the token0 buffer exactly.
        assertEq(almCore.bufferAmount0(), 0);
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountOut, assets);
    }

    function testFuzz_Success_clearAllRequests_RedeemUnderPause(
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

        // And: A paused core.
        vm.prank(factory);
        almCore.pause();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        runPlan(Plan.init().clearAllRequests(true, false).settleRequests());

        // Then: The settlement ran and paid the start value per share.
        (, uint32 pendingRedeemEpoch) = almCore.pendingEpochs(asyncVault0);
        assertEq(pendingRedeemEpoch, 1);
        assertEq(
            almCore.redeemEpoch(asyncVault0, 0).amountOut,
            token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, supply))
        );
        assertEq(almCore.totalSupply(), supply - queueState.redeem0);
    }

    function testFuzz_Success_clearAllRequests_EscrowCreditedToTheProtocolForTheHiddenPart(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 window,
        uint256 joinedAfter,
        uint256 emissions,
        uint16 feeBps,
        uint256 pick,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge hiding the staked emissions for a fuzzed window, a fuzzed fee.
        window = bound(window, 2, type(uint40).max);
        setPenaltyConfig(window, MAX_PIPS);
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        {
            uint16 protocolSwapFeeBps = almCore.protocolSwapFeeBps_();
            vm.prank(factory);
            almCore.setProtocolFees(feeBps, protocolSwapFeeBps, users.feeRecipient);
        }

        // And: A vault holding a range whose staked leg opens its penalty window now.
        givenValidRangeState(range, poolState, false);
        givenBufferPaysShares(coreState, poolState, range, 1, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Redeems recorded before any emission, the token0 one paid by its buffer.
        givenValidQueueState(queueState, 0, 0);
        {
            uint256 value;
            {
                (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                    uint160(poolState.sqrtPrice),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                value = amount1 + almCore.bufferAmount1()
                    + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
            }
            uint256 ceiling =
                token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0()).fullMulDiv(almCore.totalSupply(), value);
            ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
            queueState.redeem0 = bound(queueState.redeem0, 1, ceiling);
        }
        setQueueState(queueState);
        uint256 supply = almCore.totalSupply();

        // And: Hidden emissions lifting the reward per share a unit, in the window.
        emissions = bound(
            emissions,
            FixedPointMathLib.fullMulDivUp(
                supply / 1e18 + 1,
                ConfigLib.BPS_DENOMINATOR,
                ConfigLib.BPS_DENOMINATOR - almCore.protocolEmissionFeeBps_()
            ),
            Constants.MAX_EMISSIONS
        );
        joinedAfter = bound(joinedAfter, 1, window - 1);
        accrueForBlocks(pool, gauge, joinedAfter, emissions);

        // And: A chain that mints.
        setMintableStatus(pick);
        uint256 hidden = hiddenEmissions(gauge, address(almCore), almCore.stakedTokenIds());
        hidden -= hidden * feeBps / ConfigLib.BPS_DENOMINATOR;

        // And: The protocol fees with the escrow's pre-credit share, on the prior supply.
        uint256 protocolFees = almCore.getProtocolFeesReward()
            + (queueState.redeem0 + queueState.redeem1).fullMulDiv(hidden.fullMulDiv(1e18, supply), 1e18);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles, then the vault credits the settled record.
        runPlan(Plan.init().clearAllRequests(true, false).settleRequests());
        vm.prank(asyncVault0);
        almCore.claimRedeemRequest(controller, 0, 0, accountA);

        // Then: The protocol gets the escrow's pre-credit share, on the prior supply.
        assertEq(almCore.getProtocolFeesReward(), protocolFees);
        assertEq(almCore.getPendingReward(controller), 0);

        // And: The pre-credit holds the hidden emissions, net of the fee.
        assertEq(almCore.getPreCredited(), hidden);
    }

    function testFuzz_Success_clearAllRequests_CountsTheGaugeOnAnyChainStatus_Redeem(
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
        givenBufferPaysShares(coreState, poolState, range, 1, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a token0 redeem the token0 buffer pays among them.
        givenValidQueueState(queueState, 0, 0);
        {
            uint256 value;
            {
                (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                    uint160(poolState.sqrtPrice),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                value = amount1 + almCore.bufferAmount1()
                    + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
            }
            uint256 ceiling =
                token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0()).fullMulDiv(almCore.totalSupply(), value);
            ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
            queueState.redeem0 = bound(queueState.redeem0, 1, ceiling);
        }
        setQueueState(queueState);
        uint256 supplyBefore = almCore.totalSupply();

        // And: A reward, gauge emissions and a window end, on a fuzzed chain status.
        uint256 unsaturated =
            FixedPointMathLib.min(supplyBefore.fullMulDiv(type(uint128).max / 2, 1e18), Constants.MAX_FUZZED_AMOUNT);
        received = bound(received, 1, unsaturated);
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);
        earned = bound(earned, 0, unsaturated);
        mockEarned(gauge, address(almCore), earned);
        windowEnd = uint48(bound(windowEnd, 1, type(uint48).max));
        almCore.setWindowEnd(windowEnd);
        setAnyStatus(status);

        // And: The net reward counted, the gauge's part included.
        uint256 feeBps = almCore.protocolEmissionFeeBps_();
        uint256 netReceived = received - received * feeBps / ConfigLib.BPS_DENOMINATOR;
        uint256 counted = netReceived + earned - earned * feeBps / ConfigLib.BPS_DENOMINATOR;

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        runPlan(Plan.init().clearAllRequests(true, false).settleRequests());

        // Then: The reward per share counts the reward over the supply before the burn.
        assertEq(almCore.rewardPerShare_(), counted.fullMulDiv(1e18, supplyBefore));

        // And: The high water counts the gauge and the measured, claimed reward.
        assertEq(almCore.getRewardHighWater(), counted);
        assertEq(almCore.getLastRewardBalance(), received);
        assertEq(almCore.getClaimedCumulative(), netReceived);

        // And: The window end is folded.
        assertEq(almCore.getWindowEnd(), 0);
    }

    function testFuzz_Success_clearAllRequests_PaidAtTheEnd(
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
        uint256 supply = almCore.totalSupply();

        // And: A token0 sale after the settle reading the escrow, then the epoch.
        LockProbeRouterMock router = new LockProbeRouterMock();
        bytes memory data = abi.encodeCall(
            LockProbeRouterMock.swap, (address(token0), address(token1), 1, out1, address(routerTrampoline))
        );
        uint256 snapshot = vm.snapshotState();
        router.arm(address(almCore), abi.encodeWithSignature("balanceOf(address)", address(almCore)));
        runPlan(
            Plan.init().clearAllRequests(true, false).swapViaRouter(address(router), 1, true, 0, data).settleRequests()
        );
        uint256 escrowDuring = abi.decode(router.result(), (uint256));
        vm.revertToState(snapshot);
        router.arm(address(almCore), abi.encodeCall(ALMCoreExtension.redeemEpoch, (asyncVault0, 0)));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(4, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch and swaps.
        runPlan(
            Plan.init().clearAllRequests(true, false).swapViaRouter(address(router), 1, true, 0, data).settleRequests()
        );

        // Then: Mid-plan the shares stay in escrow and the cleared epoch has no output.
        assertEq(escrowDuring, queueState.redeem0 + queueState.redeem1);
        assertEq(abi.decode(router.result(), (Epoch)).amountOut, 0);

        // And: After it, the shares are burned, the epoch holding their pre-swap value.
        assertEq(almCore.balanceOf(address(almCore)), queueState.redeem1);
        assertEq(
            almCore.redeemEpoch(asyncVault0, 0).amountOut,
            token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, supply))
        );
    }

    function testFuzz_Success_clearAllRequests_BufferRaisedAfterTheStep(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 spent,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range, and a token0 buffer a token1 buffer can outweigh.
        givenValidRangeState(range, poolState, false);
        {
            uint256 floor0;
            uint256 ceiling0;
            uint256 top0;
            uint256 most;
            uint256 principal0;
            {
                uint256 ceiling1;
                (floor0, ceiling1) = amountsRoundedUp(
                    sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
                );
                ceiling0 = floor0 + (floor0 > 0 ? floor0 : Constants.MAX_FUZZED_AMOUNT / 4);
                ceiling1 += 2 + (ceiling1 > 0 ? ceiling1 : Constants.MAX_FUZZED_AMOUNT / 4);
                (top0, most, principal0,) = stagedAmounts(poolState, range, ceiling0, ceiling1);
            }
            floor0 = FixedPointMathLib.max(floor0, 1);
            most = (2 * principal0 + most.fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice))
            .zeroFloorSub(3);
            most = most >= top0 ? ceiling0 : FixedPointMathLib.max(floor0, ceiling0 - (top0 - most));
            coreState.buffer0 = bound(coreState.buffer0, floor0, most);
        }

        // And: A token1 buffer outweighing token0, buying the completing wei.
        {
            uint256 ceiling1;
            uint256 top1;
            uint256 least;
            {
                (, ceiling1) = amountsRoundedUp(
                    sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
                );
                ceiling1 += 2 + (ceiling1 > 0 ? ceiling1 : Constants.MAX_FUZZED_AMOUNT / 4);
                uint256 amount0;
                uint256 principal0;
                (amount0, top1, principal0, least) = stagedAmounts(poolState, range, coreState.buffer0, ceiling1);
                uint256 price = poolState.sqrtPrice * poolState.sqrtPrice;
                uint256 worth = FixedPointMathLib.fullMulDivUp(amount0 - principal0 + 1, price, 1 << 192);
                least += FixedPointMathLib.fullMulDivUp(worth, 1 << 192, price)
                    .zeroFloorSub(amount0 - principal0 + 1)
                    .fullMulDivUp(price, 1 << 192);
                least = FixedPointMathLib.max(least, (2 * worth + 1).zeroFloorSub(amount0.fullMulDiv(price, 1 << 192)));
            }
            // And: A token1 buffer that can buy the completing wei.
            vm.assume(least <= top1);
            (, uint256 floor1) = amountsRoundedUp(
                sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            coreState.buffer1 =
                bound(coreState.buffer1, FixedPointMathLib.max(floor1 + 2, ceiling1 - (top1 - least)), ceiling1);
        }

        // And: A token0 redeem over the token0 buffer, and a purchase covering it.
        {
            uint256 ceiling = FixedPointMathLib.max(
                FixedPointMathLib.min(
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                    Constants.MAX_FUZZED_AMOUNT
                ),
                Constants.DEAD_SHARES
            );
            uint256 buffer0;
            uint256 room;
            uint256 total;
            {
                uint256 principal0;
                (buffer0, total, principal0, room) =
                    stagedAmounts(poolState, range, coreState.buffer0, coreState.buffer1);
                room = total - room;
                total += token0ToToken1(poolState.sqrtPrice, buffer0);
                buffer0 -= principal0;
            }
            uint256 price = poolState.sqrtPrice * poolState.sqrtPrice;
            room = FixedPointMathLib.min(room, (Constants.MAX_FUZZED_AMOUNT - buffer0 - 1).fullMulDiv(price, 1 << 192));
            {
                uint256 worth = FixedPointMathLib.fullMulDivUp(buffer0 + 1, price, 1 << 192);
                uint256 afforded = (buffer0 + room.fullMulDiv(1 << 192, price) + 1).fullMulDiv(price, 1 << 192);
                {
                    uint256 most = FixedPointMathLib.min(
                        (ceiling - Constants.DEAD_SHARES) / 2, afforded.fullMulDiv(ceiling, total)
                    );
                    queueState.redeem0 = bound(
                        queueState.redeem0,
                        FixedPointMathLib.min(
                            FixedPointMathLib.fullMulDivUp(Constants.DEAD_SHARES, worth, total - 2 * worth), most
                        ),
                        most
                    );
                }
                {
                    uint256 floor = FixedPointMathLib.max(
                        Constants.DEAD_SHARES + 2 * queueState.redeem0, queueState.redeem0.fullMulDivUp(total, afforded)
                    );
                    ceiling = FixedPointMathLib.min(ceiling, queueState.redeem0.fullMulDiv(total, worth));
                    // And: A supply pricing the redeem over the buffer.
                    vm.assume(floor <= ceiling);
                    coreState.supply = bound(coreState.supply, floor, ceiling);
                }
            }
            {
                uint256 least = queueState.redeem0.fullMulDivUp(total, coreState.supply);
                least = least.fullMulDivUp(1 << 192, price).zeroFloorSub(buffer0 + 1).fullMulDivUp(price, 1 << 192);
                spent = bound(spent, FixedPointMathLib.max(least, 1), room);
            }
        }
        setCoreState(coreState);
        setRangeState(range);
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 bought = token1ToToken0(poolState.sqrtPrice, spent) + 1;

        // And: Pending requests, the token0 redeem among them.
        givenValidQueueState(queueState, 0, 0);
        uint256 value;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = amount1 + almCore.bufferAmount1() + token0ToToken1(poolState.sqrtPrice, amount0 + buffer0Before);
        }
        uint256 assets =
            token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, almCore.totalSupply()));
        setQueueState(queueState);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch, then buys token0.
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

        // Then: The payout is the pre-swap value, drawing on the token0 bought later.
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountOut, assets);
        assertGt(assets, buffer0Before);
    }

    function testFuzz_Success_clearAllRequests_RedeemersBearTheStrategysShareOfTheSwap(
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

        // And: A vault holding a range, each buffer paying a share.
        givenValidRangeState(range, poolState, false);
        givenBufferPaysShares(coreState, poolState, range, 1, 1);
        setCoreState(coreState);
        setRangeState(range);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);

        // And: A token0 purchase the redeem's way, its fee within the max swap cost.
        {
            uint256 room = FixedPointMathLib.min(
                almCore.bufferAmount1(),
                token0ToToken1(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT - almCore.bufferAmount0())
            );
            spent = bound(spent, 2, room);
            uint256 most = FixedPointMathLib.min(
                spent - 1,
                maxSwapLoss(spent, configState.maxSwapCostBps)
                    .zeroFloorSub(2 * uint256(1).fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192) + 2)
            );
            fee = bound(fee, FixedPointMathLib.min(1, most), most);
        }
        uint256 held0;
        uint256 held1;
        uint256 cost;
        uint256 value;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            held0 = token0ToToken1(
                poolState.sqrtPrice,
                amount0 + almCore.bufferAmount0() + token1ToToken0(poolState.sqrtPrice, spent - fee)
            );
            held1 = amount1 + almCore.bufferAmount1() - spent;
            cost = spent - token0ToToken1(poolState.sqrtPrice, token1ToToken0(poolState.sqrtPrice, spent - fee));
            value = amount1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0()) - cost;
        }

        // And: Pending requests, a token0 redeem the token0 buffer pays among them.
        givenValidQueueState(queueState, 0, 0);
        {
            uint256 ceiling = almCore.bufferAmount0() + token1ToToken0(poolState.sqrtPrice, spent - fee);
            ceiling = token0ToToken1(poolState.sqrtPrice, ceiling).fullMulDiv(almCore.totalSupply(), held0 + held1);
            ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
            queueState.redeem0 = bound(queueState.redeem0, 1, ceiling);
        }
        setQueueState(queueState);

        // And: The payout, the redeem's value less the rate on its part of the swap.
        uint256 assets;
        {
            uint256 supply = almCore.totalSupply();
            uint256 levy;
            {
                uint256 swapped = spent - cost;
                uint256 redeemValue = queueState.redeem0.fullMulDiv(value, supply);
                uint256 heldAfter = held0.zeroFloorSub(redeemValue) + held1;
                uint256 redeemSwap = heldAfter == 0 ? 0 : redeemValue.fullMulDiv(held1, heldAfter);
                if (cost != 0 && swapped != 0 && redeemSwap != 0) {
                    levy = cost.fullMulDivUp(FixedPointMathLib.min(redeemSwap, swapped), swapped);
                    levy = FixedPointMathLib.min(levy, redeemValue);
                }
            }
            assets = token1ToToken0(poolState.sqrtPrice, (value + levy).fullMulDiv(queueState.redeem0, supply) - levy);
        }

        // And: Plan limits above the swap's cost and the plan's loss.
        uint256 bought = token1ToToken0(poolState.sqrtPrice, spent - fee);
        givenValidPlanLimits(configState, leastShortfallBps(2, fee), leastSwapCostBps(false, spent, bought));
        setPlanLimits(configState);

        // When: The keeper settles the epoch and swaps.
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

        // Then: The redeemer pays the swap's rate on its part of the swap.
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountOut, assets);
    }

    function testFuzz_Success_clearAllRequests_CancelAfterTheSettleIsANoOp_Redeem(
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
        uint256 assets =
            token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, almCore.totalSupply()));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch, then cancels the redeem in the same plan.
        runPlan(
            Plan.init().clearAllRequests(true, false).cancelRequests(true, false, Plan.one(controller)).settleRequests()
        );

        // Then: The cancel skipped the settled record, the epoch paid its whole input.
        assertEq(almCore.balanceOf(controller), 0);
        assertEq(almCore.balanceOf(address(almCore)), queueState.redeem1);
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountOut, assets);
    }

    function testFuzz_Success_clearAllRequests_Token1VaultSettlesItsOwnSide_Redeem(
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
        }
        uint256 ceiling = FixedPointMathLib.min(
            almCore.balanceOf(users.steward) / 2, almCore.bufferAmount1().fullMulDiv(almCore.totalSupply(), value)
        );
        queueState.redeem1 = bound(queueState.redeem1, 1, ceiling);
        setQueueState(queueState);
        uint256 supply = almCore.totalSupply();
        (uint256 buffer0Before, uint256 buffer1Before) = (almCore.bufferAmount0(), almCore.bufferAmount1());

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the token1 vault's epoch.
        runPlan(Plan.init().clearAllRequests(false, false).settleRequests());

        // Then: The epoch pays the start value from the token1 buffer into escrow.
        uint256 assets = queueState.redeem1.fullMulDiv(value, supply);
        Epoch memory epoch = almCore.redeemEpoch(asyncVault1, 0);
        assertEq(epoch.amountIn, queueState.redeem1);
        assertEq(epoch.amountOut, assets);
        assertEq(almCore.bufferAmount1(), buffer1Before - assets);
        assertEq(almCore.getEscrowed1(), queueState.deposit1 + assets);

        // And: The shares are burned.
        assertEq(almCore.balanceOf(address(almCore)), queueState.redeem0);
        assertEq(almCore.totalSupply(), supply - queueState.redeem1);
        (, uint32 pendingRedeemEpoch) = almCore.pendingEpochs(asyncVault1);
        assertEq(pendingRedeemEpoch, 1);

        // And: The token0 side is untouched.
        assertEq(almCore.bufferAmount0(), buffer0Before);
        (uint32 pendingDepositEpoch0, uint32 pendingRedeemEpoch0) = almCore.pendingEpochs(asyncVault0);
        (uint32 lastClearedDepositEpoch0, uint32 lastClearedRedeemEpoch0) = almCore.lastClearedEpochs(asyncVault0);
        assertEq(pendingDepositEpoch0, 0);
        assertEq(pendingRedeemEpoch0, 0);
        assertEq(lastClearedDepositEpoch0, 0);
        assertEq(lastClearedRedeemEpoch0, 0);
    }

    function testFuzz_Success_clearAllRequests_RedeemWorthLessThanAnAssetSettlesToZeroAssets(
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

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch.
        runPlan(Plan.init().clearAllRequests(true, false).settleRequests());

        // Then: The epoch settles to zero assets, and the shares are burned.
        Epoch memory epoch = almCore.redeemEpoch(asyncVault0, 0);
        assertEq(epoch.amountIn, queueState.redeem0);
        assertEq(epoch.amountOut, 0);
        assertEq(almCore.totalSupply(), supply - queueState.redeem0);
        assertEq(almCore.balanceOf(address(almCore)), queueState.redeem1);

        // And: Nothing left the buffer.
        assertEq(almCore.bufferAmount0(), buffer0Before);
        assertEq(almCore.getEscrowed0(), queueState.deposit0);
    }
}
