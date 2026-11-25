/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { BalanceRouterMock } from "../../utils/mocks/BalanceRouterMock.sol";
import { CalldataLogic } from "../../../src/core/libraries/logic/CalldataLogic.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { CommandLogic } from "../../../src/core/libraries/logic/CommandLogic.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { IMetadexCLGauge } from "../../../src/interfaces/IMetadexCLGauge.sol";
import { IMetadexCLPositionManager } from "../../../src/interfaces/IMetadexCLPositionManager.sol";
import { IMetadexSwapRouter } from "../../utils/fixtures/metadex/interfaces/IMetadexSwapRouter.sol";
import { Plan } from "../../utils/Plan.sol";
import { PlanCacheLib } from "../../../src/core/types/PlanCache.sol";
import { PoolTokensLib } from "../../../src/core/libraries/state/PoolTokensLib.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { RangesLib } from "../../../src/core/libraries/state/RangesLib.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";
import { stdError } from "@forge-std/StdError.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "execute" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events, uninitialized-local, unsafe-typecast)
contract Execute_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_execute_OnlyKeeper(
        PoolState memory poolState,
        address caller,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A caller that is not a keeper.
        vm.assume(caller != users.keeper);
        Plan.Steps memory plan = Plan.init();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ALMKeeperExtension.OnlyKeeper.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_OnlyKeeper_Removed(PoolState memory poolState, ConfigState memory configState)
        public
    {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The factory removed the keeper from its keeper set.
        deployer.setIsKeeper(address(almCore), users.keeper, false);
        Plan.Steps memory plan = Plan.init();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The removed keeper calls execute().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.OnlyKeeper.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_InvalidPrice_Zero(PoolState memory poolState, ConfigState memory configState)
        public
    {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A plan and a zero trusted price.
        Plan.Steps memory plan = Plan.init();

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.InvalidPrice.selector);
        almCore.execute(plan.commands, plan.inputs, 0);
    }

    function testFuzz_Revert_execute_LengthMismatch(
        PoolState memory poolState,
        uint8 extra,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: More commands than payloads.
        extra = uint8(bound(extra, 1, type(uint8).max));
        Plan.Steps memory plan = Plan.init();
        bytes memory commands = plan.commands;
        for (uint256 i; i < extra; ++i) {
            commands = abi.encodePacked(commands, CommandLogic.COLLECT);
        }
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.LengthMismatch.selector);
        almCore.execute(commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_LengthMismatch_MoreInputs(
        PoolState memory poolState,
        uint8 extra,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: More payloads than commands.
        extra = uint8(bound(extra, 1, type(uint8).max));
        Plan.Steps memory plan = Plan.init();
        bytes[] memory inputs = new bytes[](extra);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.LengthMismatch.selector);
        almCore.execute(plan.commands, inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_PlanTooSoon(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint32 interval,
        uint256 elapsed,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A clock past a plan interval, and a plan that ran less than that ago.
        interval = uint32(bound(interval, 1, (type(uint32).max - vm.getBlockTimestamp()) / 2));
        elapsed = bound(elapsed, 0, interval - 1);
        vm.warp(vm.getBlockTimestamp() + interval);
        givenValidPlanLimits(configState, 0, 0);
        vm.prank(factory);
        almCore.setPlanLimits(configState.maxShortfallBps, configState.maxSwapCostBps, interval);
        runPlan(Plan.init());
        vm.warp(vm.getBlockTimestamp() + elapsed);
        Plan.Steps memory plan = Plan.init();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // When: The keeper runs the next plan.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.PlanTooSoon.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_PlanTooSoon_OneSecondShort(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint32 interval,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A clock past a plan interval, and a plan that ran one second short of it.
        interval = uint32(bound(interval, 1, (type(uint32).max - vm.getBlockTimestamp()) / 2));
        vm.warp(vm.getBlockTimestamp() + interval);
        givenValidPlanLimits(configState, 0, 0);
        vm.prank(factory);
        almCore.setPlanLimits(configState.maxShortfallBps, configState.maxSwapCostBps, interval);
        runPlan(Plan.init());
        vm.warp(vm.getBlockTimestamp() + interval - 1);
        Plan.Steps memory plan = Plan.init();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // When: The keeper runs the next plan.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.PlanTooSoon.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_Paused(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 pick,
        bytes memory payload,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, and a paused core.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        vm.prank(factory);
        almCore.pause();

        // And: A plan of one step a paused core refuses, whatever its payload.
        uint8[6] memory refused = [
            CommandLogic.OPEN_RANGE,
            CommandLogic.INCREASE_LIQUIDITY,
            CommandLogic.STAKE,
            CommandLogic.INCREASE_STAKED_LIQUIDITY,
            CommandLogic.SWAP_VIA_POOL,
            CommandLogic.SWAP_VIA_ROUTER
        ];
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = payload;
        bytes memory commands = abi.encodePacked(refused[bound(pick, 0, refused.length - 1)]);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.Paused.selector);
        almCore.execute(commands, inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_PriceDeviation(
        PoolState memory poolState,
        uint160 offset,
        ConfigState memory configState,
        uint256 maxTwapFromTrusted
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A stale trusted price, outside the spot band and inside the TWAP band.
        uint256 mean = almCore.meanSqrtPriceX96_();
        offset = uint160(
            bound(
                offset,
                uint256(sqrtPriceX96(pool)).divUp(1e18),
                FixedPointMathLib.min(type(uint160).max, mean.fullMulDiv(1e18 + uint256(type(uint64).max), 1e18))
                    - sqrtPriceX96(pool)
            )
        );
        Plan.Steps memory plan = Plan.init();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool) + offset;
        setTrustedDeviation(
            outsideBand(configState.maxDeviation, sqrtDeviation(trustedSqrtPriceX96, sqrtPriceX96(pool), false)),
            insideBand(maxTwapFromTrusted, sqrtDeviation(trustedSqrtPriceX96, mean, true))
        );

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ConfigLib.PriceDeviation.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_PriceDeviation_Twap(
        PoolState memory poolState,
        uint160 offset,
        ConfigState memory configState,
        uint256 maxSpotFromTrusted
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A trusted price off the TWAP, inside the spot band, outside the TWAP band.
        uint160 meanSqrtPriceX96 = almCore.meanSqrtPriceX96_();
        offset = uint160(
            bound(
                offset,
                uint256(meanSqrtPriceX96).divUp(1e18),
                FixedPointMathLib.min(
                    type(uint160).max, uint256(sqrtPriceX96(pool)).fullMulDiv(1e18 + uint256(type(uint64).max), 1e18)
                ) - meanSqrtPriceX96
            )
        );
        Plan.Steps memory plan = Plan.init();
        uint160 trustedSqrtPriceX96 = meanSqrtPriceX96 + offset;
        setTrustedDeviation(
            insideBand(maxSpotFromTrusted, sqrtDeviation(trustedSqrtPriceX96, sqrtPriceX96(pool), true)),
            outsideBand(configState.maxDeviation, sqrtDeviation(trustedSqrtPriceX96, meanSqrtPriceX96, false))
        );

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ConfigLib.PriceDeviation.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_UnknownCommand(
        PoolState memory poolState,
        uint8 kind,
        uint8 place,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A byte outside the opcode table, its kind or place past the last.
        uint8[4] memory last = [
            CommandLogic.SETTLE_REQUESTS,
            CommandLogic.EMERGENCY_UNSTAKE,
            CommandLogic.SWAP_VIA_ROUTER,
            CommandLogic.INCREASE_STAKED_LIQUIDITY
        ];
        kind = uint8(bound(kind, 0, 15));
        place = uint8(bound(place, kind < last.length ? (last[kind] & 0x0f) + 1 : 0, 15));
        Plan.Steps memory plan = Plan.init().add((kind << 4) | place, "");
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.UnknownCommand.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_InvalidPayload(
        PoolState memory poolState,
        bytes memory payload,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A payload that is not the length its command fixes.
        vm.assume(payload.length != CalldataLogic.COLLECT_LENGTH);
        Plan.Steps memory plan = Plan.init().add(CommandLogic.COLLECT, payload);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_InvalidPayload_SwapViaRouter(
        PoolState memory poolState,
        uint256 length,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A router swap payload with no router calldata after its fixed fields.
        bytes memory payload = new bytes(bound(length, 0, CalldataLogic.SWAP_VIA_ROUTER_LENGTH));
        Plan.Steps memory plan = Plan.init().add(CommandLogic.SWAP_VIA_ROUTER, payload);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_InvalidPayload_ClearAllRequests(
        PoolState memory poolState,
        bytes memory payload,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A whole-queue clear payload of any length but a queue's.
        vm.assume(payload.length != CalldataLogic.QUEUE_LENGTH);
        Plan.Steps memory plan = Plan.init().add(CommandLogic.CLEAR_ALL_REQUESTS, payload);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_InvalidPayload_EmergencyUnstake(
        PoolState memory poolState,
        bytes memory payload,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emergency unstake payload of any length but a range key's.
        vm.assume(payload.length != CalldataLogic.CLOSE_RANGE_LENGTH);
        Plan.Steps memory plan = Plan.init().add(CommandLogic.EMERGENCY_UNSTAKE, payload);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_RangeMismatch_EmergencyUnstake(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint96 tokenId,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A step naming any other token id.
        vm.assume(tokenId != range.stakedTokenId);
        Plan.Steps memory plan = Plan.init().emergencyUnstake(range.index, tokenId);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, range.index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_RangeNotStaked_EmergencyUnstake(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false, false);

        // And: No staked leg, and the gauge's emergency withdraw enabled.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        clGaugeFactory.setEmergencyWithdrawEnabled(true);
        Plan.Steps memory plan = Plan.init().emergencyUnstake(range.index, range.stakedTokenId);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(RangesLib.RangeNotStaked.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_RangeNotStaked_DrainedSideInsideTheWindow(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge penalising an early unstake over a fuzzed window.
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 1, MAX_PIPS));

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        uint256 stakedBlock = almCore.getRange(range.index).stakedBlock;

        // And: The staked side drained by an unstake taking the penalty, the window open.
        runPlan(Plan.init().unstake(range.index, range.stakedTokenId, Sentinels.RANGE_LIQUIDITY, 0, 0, true));
        assertEq(almCore.getRange(range.index).stakedTokenId, 0);
        assertEq(almCore.getRange(range.index).stakedBlock, stakedBlock);
        assertTrue(almCore.isPenaltyWindowOpen(range.index));

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper unstakes the drained side again, refusing the penalty.
        Plan.Steps memory plan = Plan.init()
            .unstake(range.index, almCore.getRange(range.index).stakedTokenId, Sentinels.RANGE_LIQUIDITY, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(RangesLib.RangeNotStaked.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_NotEnabled_EmergencyUnstake(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Plan.Steps memory plan = Plan.init().emergencyUnstake(range.index, range.stakedTokenId);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(bytes("NE"));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_SwapViaRouter_TransferFailed(
        PoolState memory poolState,
        uint256 amountIn,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A token0 amountIn to the router above the core's whole token0 balance.
        amountIn = bound(amountIn, token0.balanceOf(address(almCore)) + 1, type(uint128).max);
        Plan.Steps memory plan = Plan.init().swapViaRouter(address(SWAP_ROUTER), amountIn, true, 0, hex"00");
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs the swap.
        // Then: It reverts on paying the trampoline.
        vm.prank(users.keeper);
        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_SwapViaRouter_ArithmeticError_InputWithinTheEscrow(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 amountIn,
        uint256 fee,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, its spare token0 half an amount at most.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        {
            (uint256 amount0,) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            coreState.buffer0 = FixedPointMathLib.min(
                coreState.buffer0,
                amount0
                    + FixedPointMathLib.max(
                        amount0 > 0 ? 0 : 1, token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 2)
                    )
            );
        }
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a token0 deposit among them the core holds in escrow.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);

        // And: A token0 input above the buffer, within the balance and the max cost.
        amountIn = bound(
            amountIn,
            almCore.bufferAmount0() + 1,
            FixedPointMathLib.max(
                almCore.bufferAmount0() + 1,
                FixedPointMathLib.min(
                    token0.balanceOf(address(almCore)),
                    token1ToToken0(sqrtPriceX96(pool), (Constants.MAX_FUZZED_AMOUNT - 1) * ConfigLib.BPS_DENOMINATOR)
                )
            )
        );

        // And: Plan limits, and a router fill at the price less a fee within them.
        uint160 sqrtPrice = sqrtPriceX96(pool);
        {
            uint256 amountOut = amountIn.fullMulDiv(uint256(sqrtPrice) * sqrtPrice, 1 << 192);
            uint256 least = amountOut > Constants.MAX_FUZZED_AMOUNT
                ? MAX_PIPS - (Constants.MAX_FUZZED_AMOUNT - 1).fullMulDiv(MAX_PIPS, amountOut)
                : 0;
            givenValidPlanLimits(configState, 0, least.fullMulDivUp(ConfigLib.BPS_DENOMINATOR, MAX_PIPS));
            fee = bound(fee, least, MAX_PIPS * configState.maxSwapCostBps / ConfigLib.BPS_DENOMINATOR);
        }
        setPlanLimits(configState);
        Plan.Steps memory plan = Plan.init()
            .swapBalance(
                address(new BalanceRouterMock()),
                address(token0),
                address(token1),
                address(routerTrampoline),
                true,
                amountIn,
                sqrtPrice,
                fee
            );

        // When: The keeper swaps via the router.
        // Then: The buffer ledger underflows.
        vm.prank(users.keeper);
        vm.expectRevert(stdError.arithmeticError);
        almCore.execute(plan.commands, plan.inputs, sqrtPrice);
    }

    function testFuzz_Success_execute_CollectAfterAnOpenBalanceMintLeavesThePayout(
        uint256 tokenId,
        uint256 fees,
        RangeState memory range,
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range above the price, taking only token0.
        {
            int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
            int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
            range.tickLower = int24(bound(range.tickLower, compressed + 1, band - 2)) * poolState.tickSpacing;
        }
        givenValidRangeState(range, poolState, false);
        (uint256 quarter0,) = amountsRoundedDown(
            uint160(poolState.sqrtPrice),
            range.tickLower,
            range.tickUpper,
            liquidityCeiling(range.tickLower, range.tickUpper, 0) / 4
        );
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);

        // And: A supply with aLP to redeem, each worth a quarter room's token0 at most.
        {
            uint256 supplyFloor = FixedPointMathLib.max(
                almCore.DEAD_SHARES_() + 2,
                (coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0 + 1) + 4)
                .divUp(token0ToToken1(poolState.sqrtPrice, quarter0))
            );
            coreState.supply = bound(
                coreState.supply,
                supplyFloor,
                FixedPointMathLib.max(
                    supplyFloor,
                    FixedPointMathLib.min(
                        coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                        Constants.MAX_FUZZED_AMOUNT
                    )
                )
            );
        }
        setCoreState(coreState);
        setRangeState(range);

        // And: The most token0 an open balance mint leaves past a liquidity unit's.
        uint256 slack1;
        (uint256 unit0,) = amountsRoundedUp(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, 1);
        slack1 = unit0
            + (almCore.bufferAmount0() + 3 * quarter0 + 2 * unit0 + 6)
            .fullMulDivUp(
                1 << 96,
                uint256(TickMath.getSqrtPriceAtTick(range.tickLower)) * TickMath.getSqrtPriceAtTick(range.tickUpper)
            );
        slack1 = (slack1 + 1).fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192);

        // And: Pending deposits, the token0 one within the room, and no token1 redeem.
        givenValidQueueState(
            queueState, 0, 0, Constants.QUEUE_DEPOSIT0 | Constants.QUEUE_DEPOSIT1 | Constants.QUEUE_REDEEM0
        );
        queueState.deposit0 = bound(queueState.deposit0, 0, quarter0);

        // And: A token0 redeem whose share of the fees passes the mint's slack.
        uint256 value;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = amount1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
        }
        {
            uint256 ceiling = token0ToToken1(poolState.sqrtPrice, quarter0).fullMulDiv(coreState.supply, value + 2);
            ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
            queueState.redeem0 = bound(
                queueState.redeem0,
                slack1.fullMulDivUp(
                    coreState.supply,
                    Constants.MAX_FUZZED_AMOUNT
                        - uint256(2).fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192) - 1
                ),
                ceiling
            );
        }

        // And: A token0 buffer paying the redeem, its open balance a unit's.
        {
            (uint256 amount0,) = amountsRoundedUp(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, 1);
            amount0 += (value + 2)
                .fullMulDivUp(queueState.redeem0, coreState.supply)
                .fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice) + 3;
            fundBuffer(amount0.fullMulDivUp(coreState.supply, coreState.supply - queueState.redeem0), 0);
        }
        setQueueState(queueState);
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = amount1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
        }

        // And: A position paying token1 fees whose share passes the mint's slack.
        tokenId = bound(tokenId, POSITION_MANAGER.totalSupply() + 2, type(uint96).max);
        fees = bound(
            fees,
            uint256(2).fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192)
                + slack1.fullMulDivUp(coreState.supply, queueState.redeem0),
            Constants.MAX_FUZZED_AMOUNT
        );
        token1.mint(address(almCore), fees);
        vm.mockCall(
            address(POSITION_MANAGER),
            abi.encodeCall(
                IMetadexCLPositionManager.collect,
                (IMetadexCLPositionManager.CollectParams({
                        tokenId: tokenId,
                        recipient: address(almCore),
                        amount0Max: type(uint128).max,
                        amount1Max: type(uint128).max
                    }))
            ),
            abi.encode(uint256(0), fees)
        );
        Plan.Steps memory plan = Plan.init()
            .clearAllRequests(true, true)
            .clearAllRequests(false, true)
            .clearAllRequests(true, false)
            .clearAllRequests(false, false)
            .settleRequests()
            .openRange(
                range.tickLower,
                range.tickUpper,
                Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                0,
                0
            )
            .collect(tokenId);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper mints the open buffer of token0, then collects.
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The redeem is paid its share of the settled value, before the mint.
        assertEq(
            almCore.redeemEpoch(asyncVault0, 0).amountOut,
            token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, coreState.supply))
        );

        // And: The fees stay in the buffer.
        assertGe(almCore.bufferAmount1(), fees);
    }

    function testFuzz_Revert_execute_AccountingMismatch(
        PoolState memory poolState,
        uint256 overstated,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A buffer recorded above the token balance the core actually holds.
        overstated = bound(overstated, 1, type(uint128).max - almCore.bufferAmount0());
        almCore.setBuffers(almCore.bufferAmount0() + overstated, almCore.bufferAmount1());
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        Plan.Steps memory plan = Plan.init();

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs any plan, which checks solvency at its end.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(PoolTokensLib.AccountingMismatch.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_AccountingMismatch_Token1(
        PoolState memory poolState,
        uint256 overstated,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A token1 buffer recorded above the token1 balance the core actually holds.
        overstated = bound(overstated, 1, type(uint128).max - almCore.bufferAmount1());
        almCore.setBuffers(almCore.bufferAmount0(), almCore.bufferAmount1() + overstated);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        Plan.Steps memory plan = Plan.init();

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs any plan, which checks solvency at its end.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(PoolTokensLib.AccountingMismatch.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_MaxShortfallExceeded(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 amountIn,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        givenSpacingRoom(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A token0 swap inside the tick spacing, its pool fee a token1 wei at least.
        uint256 sqrtPrice = sqrtPriceX96(pool);
        uint256 least = uint256(1).fullMulDivUp(1 << 192, sqrtPrice * sqrtPrice).fullMulDivUp(MAX_PIPS, pool.fee());
        amountIn = FixedPointMathLib.max(spacingSwapIn(amountIn, true), least);
        fundBuffer(amountIn, 0);
        Plan.Steps memory plan = Plan.init().swapViaPool(true, amountIn, priceLimit(true), 0);

        // And: A max swap cost the swap fits, a max shortfall its loss exceeds.
        uint256 amountOut = poolSwapOut(true, amountIn);
        givenValidPlanLimits(configState, 0, leastSwapCostBps(true, amountIn, amountOut));
        configState.maxShortfallBps = uint16(
            bound(configState.maxShortfallBps, 0, mostShortfallBps(token0ToToken1(sqrtPrice, amountIn) - amountOut))
        );
        setPlanLimits(configState);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // When: The keeper swaps, which pays the pool's own fee out of the buffer.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(PlanCacheLib.MaxShortfallExceeded.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_execute_MaxShortfallExceeded_UndoesTheEarlierSteps(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 amountIn,
        ConfigState memory configState
    ) public {
        // Given: A pool at a fuzzed price and a seeded vault.
        givenValidPoolState(poolState);
        givenSpacingRoom(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: A buffer for a range and a swap in the spacing, its fee a wei or more.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        uint256 sqrtPrice = sqrtPriceX96(pool);
        {
            uint256 least = uint256(1).fullMulDivUp(1 << 192, sqrtPrice * sqrtPrice).fullMulDivUp(MAX_PIPS, pool.fee());
            amountIn = FixedPointMathLib.max(spacingSwapIn(amountIn, true), least);
        }
        fundBuffer(amount0 + amountIn, amount1);
        (uint256 buffer0Before, uint256 buffer1Before) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        Plan.Steps memory plan = Plan.init().openRange(range.tickLower, range.tickUpper, amount0, amount1, 0, 0);
        plan = plan.swapViaPool(true, amountIn, priceLimit(true), 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: A max swap cost the swap fits, a max shortfall its loss exceeds.
        {
            uint256 snapshot = vm.snapshotState();
            runStagingPlan(Plan.init().openRange(range.tickLower, range.tickUpper, amount0, amount1, 0, 0));
            uint256 amountOut = poolSwapOut(true, amountIn);
            vm.revertToState(snapshot);
            givenValidPlanLimits(configState, 0, leastSwapCostBps(true, amountIn, amountOut));
            uint256 mostBps = mostShortfallBps(token0ToToken1(sqrtPrice, amountIn) - amountOut);
            configState.maxShortfallBps = uint16(bound(configState.maxShortfallBps, 0, mostBps));
            setPlanLimits(configState);
        }

        // When: The keeper opens the range and then swaps.
        // Then: It reverts, and the range the first step opened is gone.
        vm.prank(users.keeper);
        vm.expectRevert(PlanCacheLib.MaxShortfallExceeded.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
        assertEq(almCore.getRangesLength(), 0);
        assertEq(almCore.bufferAmount0(), buffer0Before);
        assertEq(almCore.bufferAmount1(), buffer1Before);
    }

    function testFuzz_Success_execute_TrustedPriceAboveUint128(
        PoolState memory poolState,
        uint160 trustedSqrtPriceX96,
        uint256 buffer0,
        uint256 buffer1,
        ConfigState memory configState
    ) public {
        // Given: A pool at a fuzzed price above uint128.
        givenValidPoolState(poolState);
        int24 tickMax = TickMath.MAX_TICK / poolState.tickSpacing * poolState.tickSpacing;
        poolState.sqrtPrice = bound(
            poolState.sqrtPrice,
            uint256(type(uint128).max) + 1,
            TickMath.getSqrtPriceAtTick(tickMax - poolState.tickSpacing)
        );

        // And: Depth whose token1 up to the highest price stays within an amount.
        uint128 depth = uint128(
            bound(poolState.liquidityPool, 1, Constants.MAX_FUZZED_AMOUNT.fullMulDiv(1 << 96, TickMath.MAX_SQRT_PRICE))
        );
        poolState.liquidityPool = depth;
        setPoolState(poolState, false);
        (uint256 amount0, uint256 amount1) = amountsRoundedUp(sqrtPriceX96(pool), -tickMax, tickMax, depth);
        mintPosition(pool, users.liquidityProvider, -tickMax, tickMax, amount0, amount1);
        assertGt(pool.liquidity(), 0);

        // And: A buffer the plan values at its trusted price.
        buffer0 = bound(buffer0, 1, Constants.MAX_FUZZED_AMOUNT);
        buffer1 = bound(buffer1, 1, Constants.MAX_FUZZED_AMOUNT);
        fundBuffer(buffer0, buffer1);

        // And: A trusted price above uint128, inside the bands around spot and the TWAP.
        uint256 spot = sqrtPriceX96(pool);
        uint256 mean = almCore.meanSqrtPriceX96_();
        trustedSqrtPriceX96 = uint160(
            bound(
                trustedSqrtPriceX96,
                FixedPointMathLib.max(spot, mean),
                FixedPointMathLib.min(FixedPointMathLib.min(spot, mean) * 3 / 2, TickMath.MAX_SQRT_PRICE - 1)
            )
        );
        Plan.Steps memory plan = Plan.init();

        // And: Plan limits storage holds, the empty plan losing nothing.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute().
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The plan runs and leaves the buffer as it was.
        assertEq(almCore.bufferAmount0(), buffer0);
        assertEq(almCore.bufferAmount1(), buffer1);
    }

    function testFuzz_Success_execute_AfterThePlanInterval(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint32 interval,
        uint256 elapsed,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A clock past a plan interval, and a plan that ran at least that long ago.
        interval = uint32(bound(interval, 0, (type(uint32).max - vm.getBlockTimestamp()) / 2));
        elapsed = bound(elapsed, interval, (type(uint32).max - vm.getBlockTimestamp()) - interval);
        vm.warp(vm.getBlockTimestamp() + interval);
        givenValidPlanLimits(configState, 0, 0);
        vm.prank(factory);
        almCore.setPlanLimits(configState.maxShortfallBps, configState.maxSwapCostBps, interval);
        runPlan(Plan.init());
        vm.warp(vm.getBlockTimestamp() + elapsed);

        // When: The keeper runs the next plan.
        runPlan(Plan.init());

        // Then: The plan ran and its time is stored.
        assertEq(almCore.lastPlanAt_(), vm.getBlockTimestamp());
    }

    function testFuzz_Success_execute_AtThePlanInterval(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint32 interval,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A clock past a plan interval, and a plan that ran exactly that long ago.
        interval = uint32(bound(interval, 1, (type(uint32).max - vm.getBlockTimestamp()) / 2));
        vm.warp(vm.getBlockTimestamp() + interval);
        givenValidPlanLimits(configState, 0, 0);
        vm.prank(factory);
        almCore.setPlanLimits(configState.maxShortfallBps, configState.maxSwapCostBps, interval);
        runPlan(Plan.init());
        vm.warp(vm.getBlockTimestamp() + interval);

        // When: The keeper runs the next plan.
        runPlan(Plan.init());

        // Then: The plan ran and its time is stored.
        assertEq(almCore.lastPlanAt_(), vm.getBlockTimestamp());
    }

    function testFuzz_Success_execute_PausedRunsAStepItDoesNotRefuse(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, and a paused core.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        vm.prank(factory);
        almCore.pause();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper collects the range's fees.
        runPlan(Plan.init().collect(almCore.getRange(range.index).unstakedTokenId));

        // Then: The plan ran.
        assertEq(almCore.lastPlanAt_(), vm.getBlockTimestamp());
    }

    function testFuzz_Success_execute_NoCheckpointWithoutRewardsOrSupply(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false, false);

        // And: No staked leg.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Plan.Steps memory plan = Plan.init()
            .collect(almCore.getRange(range.index).unstakedTokenId)
            .collect(almCore.getRange(range.index).unstakedTokenId);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        vm.expectCall(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.earned.selector, address(almCore)), 0);
        runPlan(plan);

        // Then: The gauge was never asked, the accumulator and high water stay zero.
        assertEq(almCore.rewardPerShare_(), 0);
        assertEq(almCore.getRewardHighWater(), 0);
    }

    function testFuzz_Success_execute_RunsEveryStepInOrder(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault funding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: A plan that opens the range and then closes it again.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper runs both steps in one call.
        runPlan(
            Plan.init()
                .openRange(range.tickLower, range.tickUpper, amount0, amount1, 0, 0)
                .closeRange(0, Sentinels.OPENED)
        );

        // Then: The teardown step saw what the buildup step left behind.
        assertEq(almCore.getRangesLength(), 0);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0() + almCore.getProtocolFees0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1() + almCore.getProtocolFees1());
    }

    function testFuzz_Success_execute_SurvivesADonation(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 donation0,
        uint256 donation1,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, and a donation of each token.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        donation0 = bound(donation0, 1, Constants.MAX_FUZZED_AMOUNT);
        donation1 = bound(donation1, 1, Constants.MAX_FUZZED_AMOUNT);
        ERC20Mock(address(token0)).mint(address(almCore), donation0);
        ERC20Mock(address(token1)).mint(address(almCore), donation1);
        (uint256 buffer0, uint256 buffer1) = (almCore.bufferAmount0(), almCore.bufferAmount1());

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper runs a plan.
        runPlan(Plan.init().collect(almCore.getRange(range.index).unstakedTokenId));

        // Then: The buffer is unchanged, and the donation is stranded outside it.
        assertEq(almCore.bufferAmount0(), buffer0);
        assertEq(almCore.bufferAmount1(), buffer1);
        assertEq(token0.balanceOf(address(almCore)), buffer0 + almCore.getProtocolFees0() + donation0);
        assertEq(token1.balanceOf(address(almCore)), buffer1 + almCore.getProtocolFees1() + donation1);
    }

    function testFuzz_Success_execute_SentinelTakesTheWholeBuffer(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, its buffer topped up with the leg's amounts.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        fundBuffer(amount0, amount1);

        // And: The liquidity the whole buffer buys, and the amounts the pool takes.
        uint256 buffer0 = almCore.bufferAmount0();
        uint256 buffer1 = almCore.bufferAmount1();
        uint128 liquidityBefore = positionLiquidity(almCore.getRange(range.index).unstakedTokenId);
        uint128 liquidity = liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, buffer0, buffer1);
        (uint256 used0, uint256 used1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper passes the whole of both sides as both desired amounts.
        runPlan(
            Plan.init()
                .increaseLiquidity(
                    range.index,
                    almCore.getRange(range.index).unstakedTokenId,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    0,
                    0
                )
        );

        // Then: The range took that liquidity, and the buffer paid exactly its amounts.
        assertEq(positionLiquidity(almCore.getRange(range.index).unstakedTokenId), liquidityBefore + liquidity);
        assertEq(almCore.bufferAmount0(), buffer0 - used0);
        assertEq(almCore.bufferAmount1(), buffer1 - used1);
    }

    function testFuzz_Success_execute_SentinelTakesTheWholeSide(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper removes the whole unstaked side without naming the amount.
        runPlan(
            Plan.init()
                .decreaseLiquidity(
                    range.index, almCore.getRange(range.index).unstakedTokenId, Sentinels.RANGE_LIQUIDITY, 0, 0
                )
        );

        // Then: The side is empty.
        assertEq(positionLiquidity(almCore.getRange(range.index).unstakedTokenId), 0);
    }

    function testFuzz_Success_execute_OpenRangeSentinelTakesTheWholeBuffer(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range not open yet, and a seeded vault whose buffer holds more.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: The liquidity the whole buffer buys, and the amounts the pool takes.
        uint256 buffer0 = almCore.bufferAmount0();
        uint256 buffer1 = almCore.bufferAmount1();
        uint128 liquidity = liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, buffer0, buffer1);
        (uint256 used0, uint256 used1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);
        uint256 index = almCore.getRangesLength();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper opens the range with the whole buffer as both desired amounts.
        runPlan(
            Plan.init()
                .openRange(
                    range.tickLower,
                    range.tickUpper,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    0,
                    0
                )
        );

        // Then: The range holds that liquidity, and the buffer paid exactly its amounts.
        assertEq(positionLiquidity(almCore.getRange(index).unstakedTokenId), liquidity);
        assertEq(almCore.bufferAmount0(), buffer0 - used0);
        assertEq(almCore.bufferAmount1(), buffer1 - used1);
    }

    function testFuzz_Success_execute_StakeSentinelTakesTheWholeBuffer(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 surplus0,
        uint256 surplus1,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false, false);

        // And: No staked leg.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: The buffer topped up with the leg's amounts and a surplus within the room.
        {
            (uint256 amount0, uint256 amount1) =
                amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
            (uint256 max0, uint256 max1) = amountsRoundedUp(
                sqrtPriceX96(pool),
                range.tickLower,
                range.tickUpper,
                liquidityCeiling(range.tickLower, range.tickUpper, 0)
            );
            surplus0 = bound(surplus0, 0, max0.zeroFloorSub(amount0));
            surplus1 = bound(surplus1, 0, max1.zeroFloorSub(amount1));
            fundBuffer(amount0 + surplus0, amount1 + surplus1);
        }

        // And: The liquidity the whole buffer buys, and the amounts the pool takes.
        uint256 buffer0 = almCore.bufferAmount0();
        uint256 buffer1 = almCore.bufferAmount1();
        uint128 liquidity = liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, buffer0, buffer1);
        (uint256 used0, uint256 used1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper stakes with the whole buffer as both desired amounts.
        runPlan(
            Plan.init()
                .stake(
                    range.index,
                    almCore.getRange(range.index).unstakedTokenId,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    0,
                    0
                )
        );

        // Then: The staked leg holds that liquidity, the buffer paying its amounts.
        assertEq(almCore.getRange(range.index).stakedLiquidity, liquidity);
        assertEq(almCore.bufferAmount0(), buffer0 - used0);
        assertEq(almCore.bufferAmount1(), buffer1 - used1);
    }

    function testFuzz_Success_execute_SwapViaPoolSentinelOneForZero(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 amountIn,
        uint256 surplus0,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);

        // And: Token1 past the range's within the least input, so the input fills whole.
        (, uint256 amount1) = amountsRoundedUp(
            sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        coreState.buffer1 = bound(coreState.buffer1, amount1 > 0 ? amount1 : 1, amount1 + leastSwapIn(false));
        coreState.supply = bound(
            coreState.supply,
            almCore.DEAD_SHARES_(),
            FixedPointMathLib.max(
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.min(
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                    Constants.MAX_FUZZED_AMOUNT
                )
            )
        );
        setCoreState(coreState);
        setRangeState(range);

        // And: An input past the least that the other depth fills below twice the price.
        amountIn = FixedPointMathLib.max(
            FixedPointMathLib.min(
                feeEarningTrade(pool, range.liquidity, amountIn, false),
                uint256(poolState.liquidityPool).fullMulDiv(sqrtPriceX96(pool), 1 << 96)
            ),
            leastSwapIn(false)
        );

        // And: The buffer holds the input and some token0 already.
        surplus0 = bound(surplus0, 0, Constants.MAX_FUZZED_AMOUNT - almCore.bufferAmount0());
        fundBuffer(surplus0, amountIn.zeroFloorSub(almCore.bufferAmount1()));
        uint256 buffer0 = almCore.bufferAmount0();
        uint256 buffer1 = almCore.bufferAmount1();
        uint256 poolBalance0 = token0.balanceOf(address(pool));
        uint256 poolBalance1 = token1.balanceOf(address(pool));

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 1, false, buffer1, poolSwapOut(false, buffer1));
        setPlanLimits(configState);

        // When: The keeper swaps the buffer's balance of token1.
        runPlan(
            Plan.init().swapViaPool(false, Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR, priceLimit(false), 0)
        );

        // Then: The token1 buffer went to the pool, and its output arrived in the buffer.
        assertEq(token1.balanceOf(address(pool)), poolBalance1 + buffer1);
        assertEq(almCore.bufferAmount1(), 0);
        assertEq(almCore.bufferAmount0(), buffer0 + poolBalance0 - token0.balanceOf(address(pool)));
    }

    function testFuzz_Success_execute_ClearsSwapsToARatioMintsTheOpenBalanceAndSettles(
        uint256 topUp,
        uint256 fee,
        uint256 bps,
        RangeState memory range,
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range above the price, taking only token0.
        {
            int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
            int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
            range.tickLower = int24(bound(range.tickLower, compressed + 1, band - 2)) * poolState.tickSpacing;
        }
        givenValidRangeState(range, poolState, false);
        uint256 owed1;
        uint256 target0;
        {
            uint256 quarter0;
            (quarter0,) = amountsRoundedDown(
                uint160(poolState.sqrtPrice),
                range.tickLower,
                range.tickUpper,
                liquidityCeiling(range.tickLower, range.tickUpper, 0) / 4
            );
            quarter0 =
                FixedPointMathLib.min(quarter0, token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 4));
            givenValidCoreState(coreState, poolState, range, 0, 0, 0);

            // And: At most that token0 past the range, and token1 worth that at most.
            {
                (uint256 amount0,) = amountsRoundedUp(
                    uint160(poolState.sqrtPrice),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                coreState.buffer0 =
                    amount0 + bound(coreState.buffer0 - amount0, 0, FixedPointMathLib.min(amount0, quarter0));
                coreState.buffer1 = bound(
                    coreState.buffer1,
                    1,
                    FixedPointMathLib.max(token0ToToken1(poolState.sqrtPrice, coreState.buffer0 - amount0), 1)
                );
            }

            // And: A seed holding past 64 wei of token0's worth more, within the room.
            coreState.buffer0 += bound(
                topUp,
                (64 * (uint256(1).fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192) + 2))
                .fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice),
                quarter0
            );

            // And: A supply to redeem from, each aLP a 512th of that token0 at most.
            coreState.supply = bound(
                coreState.supply,
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.max(
                    almCore.DEAD_SHARES_(),
                    FixedPointMathLib.min(
                        coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                        Constants.MAX_FUZZED_AMOUNT
                    )
                )
            );
            {
                uint256 supplyFloor = FixedPointMathLib.max(
                    2 * almCore.DEAD_SHARES_() + 4,
                    (512 * (coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0 + 1) + 3))
                    .divUp(token0ToToken1(poolState.sqrtPrice, quarter0)) + 8
                );
                coreState.supply = bound(
                    coreState.supply,
                    supplyFloor,
                    FixedPointMathLib.max(
                        supplyFloor,
                        FixedPointMathLib.min(
                            coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                            Constants.MAX_FUZZED_AMOUNT
                        )
                    )
                );
            }
            setCoreState(coreState);
            setRangeState(range);

            uint256 worth;
            {
                // And: A token0 deposit worth 72 aLP and more, and no token0 redeem.
                (uint256 holdings0,) = amountsRoundedDown(
                    uint160(poolState.sqrtPrice),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                holdings0 += almCore.bufferAmount0();
                uint256 value = almCore.bufferAmount1() + token0ToToken1(poolState.sqrtPrice, holdings0);
                {
                    uint256 least0 = (72 * value.divUp(coreState.supply) + 8)
                    .fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice);
                    givenValidQueueState(
                        queueState,
                        least0,
                        0,
                        Constants.QUEUE_DEPOSIT0 | Constants.QUEUE_DEPOSIT1 | Constants.QUEUE_REDEEM1
                    );
                    uint256 most0 = FixedPointMathLib.min(quarter0, token1ToToken0(poolState.sqrtPrice, value));
                    queueState.deposit0 = bound(queueState.deposit0, FixedPointMathLib.min(least0, most0), most0);
                }
                worth = token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() + queueState.deposit0)
                    + almCore.bufferAmount1();

                // And: A token1 redeem the sale pays, large enough to need it.
                queueState.redeem1 = bound(
                    queueState.redeem1,
                    (34 * coreState.supply).divUp(value),
                    FixedPointMathLib.min(
                        almCore.balanceOf(users.steward) / 2, (worth / 2).fullMulDiv(coreState.supply, value)
                    )
                );
                owed1 = queueState.redeem1.fullMulDiv(value, coreState.supply);
            }
            setQueueState(queueState);

            // And: A token0 share of a quarter to a half the buffer's, past a unit.
            (uint256 least,) = amountsRoundedUp(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, 1);
            least = (least + 2).fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192);
            least = FixedPointMathLib.max(
                ConfigLib.BPS_DENOMINATOR / 4, (least * ConfigLib.BPS_DENOMINATOR).divUp(worth - owed1)
            );
            bps = bound(bps, least, (worth - 1).fullMulDiv(ConfigLib.BPS_DENOMINATOR, 2 * worth));
            target0 = ((worth - owed1) * bps / ConfigLib.BPS_DENOMINATOR)
            .fullMulDiv(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice);
        }

        // And: A max swap cost up to the top pool fee, a router fee within it.
        givenValidPlanLimits(configState, 0, 0);
        configState.maxSwapCostBps = uint16(bound(configState.maxSwapCostBps, 0, Constants.MAX_POOL_FEE / 100));
        fee = bound(fee, 0, uint256(configState.maxSwapCostBps) * 100);

        // And: The token0 the ratio leaves to sell.
        uint256 sold = almCore.bufferAmount0() + queueState.deposit0 - target0;

        // And: A max shortfall above the sale's fee and the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(4, token0ToToken1(poolState.sqrtPrice, sold).fullMulDivUp(fee, MAX_PIPS) + 2),
            configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The keeper clears, swaps to the ratio and mints the open buffer.
        {
            uint256 routerFee = fee;
            uint256 ratio = Sentinels.TO_TARGET_RATIO | bps;
            uint256 sqrtPrice = poolState.sqrtPrice;
            Plan.Steps memory plan = Plan.init().clearAllRequests(true, true).clearAllRequests(false, false);
            plan = plan.swapBalance(
                    address(new BalanceRouterMock()),
                    address(token0),
                    address(token1),
                    address(routerTrampoline),
                    true,
                    ratio,
                    sqrtPrice,
                    routerFee
                )
                .settleRequests();
            runPlan(
                plan.openRange(
                    range.tickLower,
                    range.tickUpper,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    0,
                    0
                )
            );
        }

        // Then: The range took the liquidity the token0 target buys, paid by the buffer.
        {
            uint128 liquidity =
                liquidityForAmounts(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, target0, 0);
            (uint256 used0,) =
                amountsRoundedUp(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, liquidity);
            assertEq(positionLiquidity(almCore.getRange(1).unstakedTokenId), liquidity);
            assertEq(almCore.bufferAmount0(), target0 - used0);
        }

        // And: The epochs settle at the swap, the redeem within its payout owed.
        {
            (uint256 held0,) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            held0 += target0;
            uint256 swapped = token0ToToken1(poolState.sqrtPrice, sold);
            uint256 held1 = coreState.buffer1 + swapped - swapped * fee / MAX_PIPS;
            uint256 valueBefore =
                coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, held0 + sold - queueState.deposit0);
            uint256 valueUp =
                CLMath.convert(poolState.sqrtPrice, true, held0 + sold - queueState.deposit0, true) + held1 - swapped;
            uint256 levy = CLMath.convert(poolState.sqrtPrice, true, sold, true) - (held1 - coreState.buffer1);
            uint256 depositValue = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
            held0 = token0ToToken1(poolState.sqrtPrice, held0);
            uint256 supply = coreState.supply;
            uint256 redeemLevy;
            {
                uint256 redeemValue = queueState.redeem1;
                redeemValue = redeemValue.fullMulDiv(valueBefore.zeroFloorSub(levy), supply);
                uint256 value = valueBefore.zeroFloorSub(levy);
                held1 = held1.zeroFloorSub(redeemValue);
                uint256 depositSwap = depositValue.fullMulDiv(held1, held0 + held1);
                uint256 redeemSwap = redeemValue.fullMulDiv(held0, held0 + held1);
                if (swapped != 0 && depositSwap + redeemSwap != 0) {
                    levy = levy.fullMulDivUp(FixedPointMathLib.min(depositSwap + redeemSwap, swapped), swapped);
                    redeemLevy =
                        FixedPointMathLib.min(levy.fullMulDivUp(redeemSwap, depositSwap + redeemSwap), redeemValue);
                    levy = FixedPointMathLib.min(levy.fullMulDivUp(depositSwap, depositSwap + redeemSwap), depositValue);
                    value += levy;
                    valueUp += levy;
                    depositValue -= levy;
                }
                value += redeemLevy;
                valueUp += redeemLevy;
                valueBefore = FixedPointMathLib.min(value, valueBefore);
            }
            uint256 payout1 = queueState.redeem1;
            payout1 = payout1.fullMulDiv(valueBefore, supply) - redeemLevy;
            assertEq(almCore.redeemEpoch(asyncVault1, 0).amountOut, payout1);
            payout1 += queueState.deposit1;
            assertEq(almCore.getEscrowed1(), payout1);
            assertEq(almCore.depositEpoch(asyncVault0, 0).amountOut, depositValue.fullMulDiv(supply, valueUp));
        }
        assertLe(almCore.redeemEpoch(asyncVault1, 0).amountOut, owed1);

        // And: The deposit minted aLP.
        assertGt(almCore.depositEpoch(asyncVault0, 0).amountOut, 0);
    }

    function testFuzz_Success_execute_CollectBeforeAnOpenBalanceMintSettles(
        uint256 tokenId,
        uint256 fees,
        RangeState memory range,
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range above the price, taking only token0.
        {
            int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
            int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
            range.tickLower = int24(bound(range.tickLower, compressed + 1, band - 2)) * poolState.tickSpacing;
        }
        givenValidRangeState(range, poolState, false);
        (uint256 quarter0,) = amountsRoundedDown(
            uint160(poolState.sqrtPrice),
            range.tickLower,
            range.tickUpper,
            liquidityCeiling(range.tickLower, range.tickUpper, 0) / 4
        );
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);

        // And: A supply with aLP to redeem, each worth half a quarter room's token0.
        {
            uint256 supplyFloor = FixedPointMathLib.max(
                almCore.DEAD_SHARES_() + 2,
                (2 * (coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0 + 1) + 4))
                .divUp(token0ToToken1(poolState.sqrtPrice, quarter0))
            );
            coreState.supply = bound(
                coreState.supply,
                supplyFloor,
                FixedPointMathLib.max(
                    supplyFloor,
                    FixedPointMathLib.min(
                        coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                        Constants.MAX_FUZZED_AMOUNT
                    )
                )
            );
        }
        setCoreState(coreState);
        setRangeState(range);

        // And: Deposits, the token0 one in the room, a token0 redeem, no token1 redeem.
        givenValidQueueState(
            queueState, 0, 0, Constants.QUEUE_DEPOSIT0 | Constants.QUEUE_DEPOSIT1 | Constants.QUEUE_REDEEM0
        );
        queueState.deposit0 = bound(queueState.deposit0, 0, quarter0);
        uint256 value;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = amount1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
        }
        queueState.redeem0 = bound(
            queueState.redeem0,
            1,
            FixedPointMathLib.min(
                almCore.balanceOf(users.steward) / 2,
                token0ToToken1(poolState.sqrtPrice, quarter0).fullMulDiv(coreState.supply, 2 * value + 2)
            )
        );

        // And: A position paying token1 fees worth at most the vault on collection.
        tokenId = bound(tokenId, POSITION_MANAGER.totalSupply() + 2, type(uint96).max);
        fees = bound(fees, 0, value);
        token1.mint(address(almCore), fees);
        vm.mockCall(
            address(POSITION_MANAGER),
            abi.encodeCall(
                IMetadexCLPositionManager.collect,
                (IMetadexCLPositionManager.CollectParams({
                        tokenId: tokenId,
                        recipient: address(almCore),
                        amount0Max: type(uint128).max,
                        amount1Max: type(uint128).max
                    }))
            ),
            abi.encode(uint256(0), fees)
        );

        // And: A token0 buffer paying the redeem, its open balance a unit's.
        {
            (uint256 amount0,) = amountsRoundedUp(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, 1);
            amount0 += (value + fees + 2)
                .fullMulDivUp(queueState.redeem0, coreState.supply)
                .fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice) + 3;
            fundBuffer(amount0.fullMulDivUp(coreState.supply, coreState.supply - queueState.redeem0), 0);
        }
        setQueueState(queueState);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(6, 0), 0);
        setPlanLimits(configState);

        // When: The keeper collects, then mints the open buffer of token0.
        Plan.Steps memory plan = Plan.init()
            .clearAllRequests(true, true)
            .clearAllRequests(false, true)
            .clearAllRequests(true, false)
            .clearAllRequests(false, false)
            .collect(tokenId);
        runPlan(
            plan.settleRequests()
                .openRange(
                    range.tickLower,
                    range.tickUpper,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    0,
                    0
                )
        );

        // Then: The redeem settles with its payout in escrow.
        assertEq(almCore.getEscrowed0(), almCore.redeemEpoch(asyncVault0, 0).amountOut);

        // And: The range is open.
        assertGt(positionLiquidity(almCore.getRange(1).unstakedTokenId), 0);
    }

    function testFuzz_Success_execute_DecreaseAfterAnOpenBalanceMintSettlesWithinThePayoutOwed(
        RangeState memory range,
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range above the price, taking only token0.
        {
            int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
            int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
            range.tickLower = int24(bound(range.tickLower, compressed + 1, band - 2)) * poolState.tickSpacing;
        }
        givenValidRangeState(range, poolState, false);
        (uint256 quarter0,) = amountsRoundedDown(
            uint160(poolState.sqrtPrice),
            range.tickLower,
            range.tickUpper,
            liquidityCeiling(range.tickLower, range.tickUpper, 0) / 4
        );
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);

        // And: A supply with aLP to redeem, each worth a quarter room's token0 at most.
        {
            uint256 supplyFloor = FixedPointMathLib.max(
                almCore.DEAD_SHARES_() + 2,
                (coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0 + 1) + 4)
                .divUp(token0ToToken1(poolState.sqrtPrice, quarter0))
            );
            coreState.supply = bound(
                coreState.supply,
                supplyFloor,
                FixedPointMathLib.max(
                    supplyFloor,
                    FixedPointMathLib.min(
                        coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                        Constants.MAX_FUZZED_AMOUNT
                    )
                )
            );
        }
        setCoreState(coreState);
        setRangeState(range);

        // And: Deposits, the token0 one in the room, a token0 redeem, no token1 redeem.
        givenValidQueueState(
            queueState, 0, 0, Constants.QUEUE_DEPOSIT0 | Constants.QUEUE_DEPOSIT1 | Constants.QUEUE_REDEEM0
        );
        queueState.deposit0 = bound(queueState.deposit0, 0, quarter0);
        (uint256 holdings0, uint256 holdings1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        {
            uint256 value = holdings1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, holdings0 + almCore.bufferAmount0());
            uint256 ceiling = token0ToToken1(poolState.sqrtPrice, quarter0).fullMulDiv(coreState.supply, value + 2);
            ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
            queueState.redeem0 = bound(queueState.redeem0, 1, ceiling);

            // And: A token0 buffer paying the redeem, its open balance a unit's.
            (uint256 amount0,) = amountsRoundedUp(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, 1);
            amount0 += (value + 2)
                .fullMulDivUp(queueState.redeem0, coreState.supply)
                .fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice) + 3;
            fundBuffer(amount0.fullMulDivUp(coreState.supply, coreState.supply - queueState.redeem0), 0);
        }
        setQueueState(queueState);

        // And: The payout owed at the plan's value once the deposits clear.
        holdings0 += almCore.bufferAmount0();
        holdings1 += almCore.bufferAmount1();
        uint256 owed = (holdings1 + token0ToToken1(poolState.sqrtPrice, holdings0))
            .fullMulDiv(queueState.redeem0, coreState.supply)
            .fullMulDiv(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(6, 0), 0);
        setPlanLimits(configState);

        // When: The keeper mints the open buffer of token0, then removes the whole range.
        (int24 tickLower, int24 tickUpper) = (range.tickLower, range.tickUpper);
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .clearAllRequests(false, true)
                .clearAllRequests(true, false)
                .clearAllRequests(false, false)
                .settleRequests()
                .openRange(
                    tickLower,
                    tickUpper,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    0,
                    0
                )
                .decreaseLiquidity(1, Sentinels.OPENED, Sentinels.RANGE_LIQUIDITY, 0, 0)
        );

        // Then: The redeem settles with its payout in escrow, within the payout owed.
        uint256 payout0 = almCore.redeemEpoch(asyncVault0, 0).amountOut;
        assertEq(almCore.getEscrowed0(), payout0);
        assertLe(payout0, owed);
    }

    function testFuzz_Success_execute_OpenBalanceSlackMintCoversTheLevy(
        RangeState memory range,
        uint256 sold,
        uint256 fee,
        uint256 slack,
        CoreState memory coreState,
        QueueState memory queueState,
        ConfigState memory configState,
        PoolState memory poolState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range above the price, taking only token0.
        {
            int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
            int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
            range.tickLower = int24(bound(range.tickLower, compressed + 1, band - 2)) * poolState.tickSpacing;
        }
        givenValidRangeState(range, poolState, false);
        uint256 room0;
        {
            uint128 roomLiquidity = liquidityCeiling(range.tickLower, range.tickUpper, 0) / 16;
            (room0,) = amountsRoundedDown(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, roomLiquidity);
        }
        room0 = FixedPointMathLib.min(room0, token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 16));
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);

        // And: A seed holding at most that token0 past the range.
        {
            (uint256 amount0,) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            coreState.buffer0 = amount0 + bound(coreState.buffer0 - amount0, 0, FixedPointMathLib.min(amount0, room0));
        }

        // And: A supply with aLP to redeem, each an eighth of that token0 at most.
        coreState.supply = bound(
            coreState.supply,
            almCore.DEAD_SHARES_(),
            FixedPointMathLib.max(
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.min(
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                    Constants.MAX_FUZZED_AMOUNT
                )
            )
        );
        {
            uint256 supplyFloor = FixedPointMathLib.max(
                2 * almCore.DEAD_SHARES_() + 4,
                (8 * (coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0 + 1) + 3))
                .divUp(token0ToToken1(poolState.sqrtPrice, room0)) + 8
            );
            coreState.supply = bound(
                coreState.supply,
                supplyFloor,
                FixedPointMathLib.max(
                    supplyFloor,
                    FixedPointMathLib.min(
                        coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                        Constants.MAX_FUZZED_AMOUNT
                    )
                )
            );
        }
        setCoreState(coreState);
        setRangeState(range);
        uint256 value;
        {
            (uint256 holdings0,) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = almCore.bufferAmount1() + token0ToToken1(poolState.sqrtPrice, holdings0 + almCore.bufferAmount0());

            // And: A token0 redeem of a sixteenth of the supply at most, and no deposit.
            givenValidQueueState(queueState, 0, 0, Constants.QUEUE_REDEEM0 | Constants.QUEUE_REDEEM1);
            queueState.redeem0 = bound(
                queueState.redeem0,
                1,
                FixedPointMathLib.min(
                    FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, coreState.supply / 16),
                    token0ToToken1(poolState.sqrtPrice, room0).fullMulDiv(coreState.supply, value + 2)
                )
            );

            // And: A token0 buffer paying the redeem, its open balance twice the sale.
            (uint256 amount0,) = amountsRoundedUp(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, 1);
            amount0 += (value + 2)
                .fullMulDivUp(queueState.redeem0, coreState.supply)
                .fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice) + 2 * room0 + 3;
            fundBuffer(amount0.fullMulDivUp(coreState.supply, coreState.supply - queueState.redeem0), 0);
            value = almCore.bufferAmount1() + token0ToToken1(poolState.sqrtPrice, holdings0 + almCore.bufferAmount0());
        }

        // And: A token1 redeem a sale of that token0 at most pays.
        queueState.redeem1 = bound(
            queueState.redeem1,
            1,
            FixedPointMathLib.min(
                almCore.balanceOf(users.steward) / 2,
                ((9 * token0ToToken1(poolState.sqrtPrice, room0)) / 10 - 4).fullMulDiv(coreState.supply, value + 2)
            )
        );
        setQueueState(queueState);

        // And: A token0 sale covering the token1 redeem, filled less a pool fee.
        sold = bound(
            sold,
            FixedPointMathLib.max(
                ConfigLib.BPS_DENOMINATOR
                    * (uint256(1).fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice) + 4),
                ((10 * (value + 2)).fullMulDivUp(queueState.redeem1, 9 * coreState.supply) + 2)
                .fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice)
            ),
            room0
        );
        givenValidPlanLimits(configState, 0, 0);
        fee = bound(fee, 0, FixedPointMathLib.min(uint256(configState.maxSwapCostBps) * 100, Constants.MAX_POOL_FEE));

        // And: A slack covering the fee on the sale for a sixteenth of the supply.
        slack = bound(slack, fee / (16 * (MAX_PIPS / ConfigLib.BPS_DENOMINATOR)) + 1, ConfigLib.BPS_DENOMINATOR - 1);

        // And: A max shortfall above the fill's fee and the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(4, vaultValue(sqrtPriceX96(pool), true).fullMulDivUp(fee, MAX_PIPS)),
            configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The keeper clears, sells token0 and mints its open buffer less the slack.
        {
            (int24 tickLower, int24 tickUpper) = (range.tickLower, range.tickUpper);
            uint256 amount0 = Sentinels.OPEN_BALANCE | (ConfigLib.BPS_DENOMINATOR - slack);
            uint256 amountIn = sold;
            uint256 routerFee = fee;
            uint256 sqrtPrice = poolState.sqrtPrice;
            Plan.Steps memory plan = Plan.init().clearAllRequests(true, false).clearAllRequests(false, false);
            plan = plan.swapBalance(
                    address(new BalanceRouterMock()),
                    address(token0),
                    address(token1),
                    address(routerTrampoline),
                    true,
                    amountIn,
                    sqrtPrice,
                    routerFee
                )
                .settleRequests();
            runPlan(
                plan.openRange(tickLower, tickUpper, amount0, Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR, 0, 0)
            );
        }

        // Then: Both redeems settle with their payouts in escrow.
        assertEq(almCore.getEscrowed0(), almCore.redeemEpoch(asyncVault0, 0).amountOut);
        assertEq(almCore.getEscrowed1(), almCore.redeemEpoch(asyncVault1, 0).amountOut);
    }

    function testFuzz_Success_execute_OpenBalanceMintAfterASwapAboveTheTrustedPriceSettles(
        uint256 trustedSqrtPriceX96,
        uint256 sold,
        uint256 fee,
        RangeState memory range,
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A trusted price below spot, a router filling at spot less a fee.
        trustedSqrtPriceX96 = bound(
            trustedSqrtPriceX96,
            FixedPointMathLib.fullMulDivUp(poolState.sqrtPrice, 1e18, 1e18 + Constants.WIDE_DEVIATION),
            poolState.sqrtPrice - 1
        );
        givenValidPlanLimits(configState, 0, 0);
        fee = bound(fee, 0, FixedPointMathLib.min(uint256(configState.maxSwapCostBps) * 100, Constants.MAX_POOL_FEE));

        // And: Ticks a spacing or more around the price, for a range the seed funds.
        givenValidRangeState(range, poolState, true, false);
        if (range.tickUpper - poolState.tickCurrent <= poolState.tickSpacing) range.tickUpper += poolState.tickSpacing;
        if (poolState.tickCurrent - range.tickLower < poolState.tickSpacing) range.tickLower -= poolState.tickSpacing;
        {
            uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
            range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));
        }

        // And: A seeded vault, its holder with shares.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 2, 0, 0);
        setCoreState(coreState);

        // And: A token0 redeem the token0 buffer pays twice over, and no deposit.
        givenValidQueueState(queueState, 0, 0, Constants.QUEUE_REDEEM0);
        {
            uint256 value0 = token0ToToken1(trustedSqrtPriceX96, almCore.bufferAmount0());
            uint256 ceiling = value0.fullMulDiv(almCore.totalSupply(), 2 * (almCore.bufferAmount1() + value0));
            queueState.redeem0 = bound(
                queueState.redeem0, 1, FixedPointMathLib.max(FixedPointMathLib.min(queueState.redeem0, ceiling), 1)
            );
        }
        setQueueState(queueState);

        // And: A token0 purchase with half the token1 buffer at most.
        sold = bound(sold, 0, almCore.bufferAmount1() / 2);

        // And: A max shortfall above the plan's loss at the trusted price.
        {
            uint256 buffer1 = almCore.bufferAmount1();
            uint256 loss = buffer1 - token0ToToken1(trustedSqrtPriceX96, token1ToToken0(poolState.sqrtPrice, buffer1))
                + sold.fullMulDivUp(fee, MAX_PIPS) + 3 * (token0ToToken1(trustedSqrtPriceX96, 1) + 2) + 1;
            givenValidPlanLimits(
                configState,
                FixedPointMathLib.min(
                    loss.fullMulDivUp(ConfigLib.BPS_DENOMINATOR, vaultValue(uint160(trustedSqrtPriceX96), false)),
                    ConfigLib.BPS_DENOMINATOR
                ),
                configState.maxSwapCostBps
            );
        }
        setPlanLimits(configState);

        // When: The keeper clears the redeem, buys token0 and mints the open buffer.
        Plan.Steps memory plan = Plan.init().clearAllRequests(true, false);
        plan = plan.swapBalance(
                address(new BalanceRouterMock()),
                address(token0),
                address(token1),
                address(routerTrampoline),
                false,
                sold,
                poolState.sqrtPrice,
                fee
            )
            .settleRequests();
        plan = plan.openRange(
            range.tickLower,
            range.tickUpper,
            Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
            Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
            0,
            0
        );
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, uint160(trustedSqrtPriceX96));

        // Then: The redeem settles with its payout in escrow.
        assertEq(almCore.getEscrowed0(), almCore.redeemEpoch(asyncVault0, 0).amountOut);

        // And: The range is open.
        assertGt(positionLiquidity(almCore.getRange(0).unstakedTokenId), 0);
    }

    function testFuzz_Success_execute_OpenBalanceMintSettlesARedeemTheDepositLevyRaises_ZeroForOne(
        uint256 fee,
        RangeState memory range,
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range below the price, taking only token1.
        {
            int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
            int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
            range.tickUpper = int24(bound(range.tickUpper, -band + 2, compressed)) * poolState.tickSpacing;
            range.tickLower = int24(bound(range.tickLower, -band + 1, range.tickUpper / poolState.tickSpacing - 1))
                * poolState.tickSpacing;
        }
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);

        // And: Over twice the range's token1, and token0 worth that at most.
        {
            (, uint256 amount1) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            coreState.buffer1 += amount1 + 1;
            coreState.buffer0 =
                bound(coreState.buffer0, 1, FixedPointMathLib.max(token1ToToken0(poolState.sqrtPrice, amount1), 1));
        }

        // And: A supply past four times the dead shares, up to the vault's value.
        {
            uint256 supplyFloor = 4 * almCore.DEAD_SHARES_();
            coreState.supply = bound(
                coreState.supply,
                supplyFloor,
                FixedPointMathLib.max(
                    supplyFloor,
                    FixedPointMathLib.min(
                        coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                        Constants.MAX_FUZZED_AMOUNT
                    )
                )
            );
        }
        setCoreState(coreState);
        setRangeState(range);

        // And: A router filling at the price, less a fee up to the highest pool fee.
        givenValidPlanLimits(configState, 0, 1);
        fee = bound(fee, 1, FixedPointMathLib.min(uint256(configState.maxSwapCostBps) * 100, Constants.MAX_POOL_FEE));

        // And: A token0 deposit levied eight unit's token1 and more at that fee.
        uint256 least0;
        {
            (, uint256 unit1) = amountsRoundedUp(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, 1);
            least0 = (8 * (unit1 + 8))
                .fullMulDivUp(MAX_PIPS, fee)
                .fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice) + 1;
        }
        givenValidQueueState(queueState, least0, 0, Constants.QUEUE_DEPOSIT0 | Constants.QUEUE_REDEEM1);
        {
            (, uint256 most1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, pool.maxLiquidityPerTick() / 4
            );
            queueState.deposit0 = FixedPointMathLib.min(
                queueState.deposit0,
                FixedPointMathLib.max(
                    least0,
                    token1ToToken0(poolState.sqrtPrice, FixedPointMathLib.min(most1, Constants.MAX_FUZZED_AMOUNT / 8))
                )
            );
        }

        // And: A token1 buffer past twice the sale's fee, so the vault keeps a value.
        fundBuffer(
            0,
            2
                * token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() + queueState.deposit0)
                    .fullMulDivUp(fee, MAX_PIPS) + 2
        );

        // And: A token1 redeem of a quarter of the supply and more, and no token0 redeem.
        queueState.redeem1 = bound(queueState.redeem1, coreState.supply.divUp(4), almCore.balanceOf(users.steward) / 2);
        setQueueState(queueState);

        // And: A max shortfall above the fill's fee and the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(4, vaultValue(sqrtPriceX96(pool), true).fullMulDivUp(fee, MAX_PIPS)),
            configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The keeper clears, sells the open token0 and mints the open buffer.
        {
            uint256 routerFee = fee;
            uint256 sqrtPrice = poolState.sqrtPrice;
            Plan.Steps memory plan = Plan.init().clearAllRequests(true, true).clearAllRequests(false, false);
            plan = plan.swapBalance(
                    address(new BalanceRouterMock()),
                    address(token0),
                    address(token1),
                    address(routerTrampoline),
                    true,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    sqrtPrice,
                    routerFee
                )
                .settleRequests();
            runPlan(
                plan.openRange(
                    range.tickLower,
                    range.tickUpper,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    0,
                    0
                )
            );
        }

        // Then: The redeem settles with its payout in escrow.
        assertGt(almCore.redeemEpoch(asyncVault1, 0).amountOut, 0);
        assertEq(almCore.getEscrowed1(), almCore.redeemEpoch(asyncVault1, 0).amountOut);

        // And: The range is open.
        assertGt(positionLiquidity(almCore.getRange(1).unstakedTokenId), 0);
    }

    function testFuzz_Success_execute_OpenBalanceMintSettlesARedeemTheDepositLevyRaises_OneForZero(
        uint256 fee,
        RangeState memory range,
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range above the price, taking only token0.
        {
            int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
            int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
            range.tickLower = int24(bound(range.tickLower, compressed + 1, band - 2)) * poolState.tickSpacing;
        }
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);

        // And: Over twice the range's token0, and token1 worth that at most.
        {
            (uint256 amount0,) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            coreState.buffer0 += amount0 + 1;
            coreState.buffer1 =
                bound(coreState.buffer1, 1, FixedPointMathLib.max(token0ToToken1(poolState.sqrtPrice, amount0), 1));
        }

        // And: A supply past four times the dead shares, up to the vault's value.
        {
            uint256 supplyFloor = 4 * almCore.DEAD_SHARES_();
            coreState.supply = bound(
                coreState.supply,
                supplyFloor,
                FixedPointMathLib.max(
                    supplyFloor,
                    FixedPointMathLib.min(
                        coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                        Constants.MAX_FUZZED_AMOUNT
                    )
                )
            );
        }
        setCoreState(coreState);
        setRangeState(range);

        // And: A router filling at the price, less a fee up to the highest pool fee.
        givenValidPlanLimits(configState, 0, 1);
        fee = bound(fee, 1, FixedPointMathLib.min(uint256(configState.maxSwapCostBps) * 100, Constants.MAX_POOL_FEE));

        // And: A token1 deposit levied eight unit's token0 value and more at that fee.
        uint256 least1;
        {
            (uint256 unit0,) = amountsRoundedUp(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, 1);
            least1 = (8 * ((unit0 + 8).fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192) + 8))
            .fullMulDivUp(MAX_PIPS, fee) + 1;
        }
        givenValidQueueState(queueState, 0, least1, Constants.QUEUE_DEPOSIT1 | Constants.QUEUE_REDEEM0);
        {
            (uint256 most0,) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, pool.maxLiquidityPerTick() / 4
            );
            queueState.deposit1 = FixedPointMathLib.min(
                queueState.deposit1,
                FixedPointMathLib.max(
                    least1,
                    token0ToToken1(poolState.sqrtPrice, FixedPointMathLib.min(most0, Constants.MAX_FUZZED_AMOUNT / 8))
                )
            );
        }

        // And: A token0 buffer past twice the sale's fee, so the vault keeps a value.
        fundBuffer(
            token1ToToken0(
                poolState.sqrtPrice, 2 * (almCore.bufferAmount1() + queueState.deposit1).fullMulDivUp(fee, MAX_PIPS) + 2
            ) + 2,
            0
        );

        // And: A token0 redeem of a quarter of the supply and more, and no token1 redeem.
        queueState.redeem0 = bound(queueState.redeem0, coreState.supply.divUp(4), almCore.balanceOf(users.steward) / 2);
        setQueueState(queueState);

        // And: A max shortfall above the fill's fee and the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(4, vaultValue(sqrtPriceX96(pool), true).fullMulDivUp(fee, MAX_PIPS)),
            configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The keeper clears, sells the open token1 and mints the open buffer.
        {
            uint256 routerFee = fee;
            uint256 sqrtPrice = poolState.sqrtPrice;
            Plan.Steps memory plan = Plan.init().clearAllRequests(false, true).clearAllRequests(true, false);
            plan = plan.swapBalance(
                    address(new BalanceRouterMock()),
                    address(token0),
                    address(token1),
                    address(routerTrampoline),
                    false,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    sqrtPrice,
                    routerFee
                )
                .settleRequests();
            runPlan(
                plan.openRange(
                    range.tickLower,
                    range.tickUpper,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    0,
                    0
                )
            );
        }

        // Then: The redeem settles with its payout in escrow.
        assertGt(almCore.redeemEpoch(asyncVault0, 0).amountOut, 0);
        assertEq(almCore.getEscrowed0(), almCore.redeemEpoch(asyncVault0, 0).amountOut);

        // And: The range is open.
        assertGt(positionLiquidity(almCore.getRange(1).unstakedTokenId), 0);
    }

    function testFuzz_Success_execute_TargetRatioMintSettlesARedeemTheDepositLevyRaises(
        uint256 fee,
        RangeState memory range,
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range below the price, taking only token1.
        {
            int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
            int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
            range.tickUpper = int24(bound(range.tickUpper, -band + 2, compressed)) * poolState.tickSpacing;
            range.tickLower = int24(bound(range.tickLower, -band + 1, range.tickUpper / poolState.tickSpacing - 1))
                * poolState.tickSpacing;
        }
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);

        // And: Over twice the range's token1, and token0 worth that at most.
        {
            (, uint256 amount1) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            coreState.buffer1 += amount1 + 1;
            coreState.buffer0 =
                bound(coreState.buffer0, 1, FixedPointMathLib.max(token1ToToken0(poolState.sqrtPrice, amount1), 1));
        }

        // And: A supply past four times the dead shares, up to the vault's value.
        {
            uint256 supplyFloor = 4 * almCore.DEAD_SHARES_();
            coreState.supply = bound(
                coreState.supply,
                supplyFloor,
                FixedPointMathLib.max(
                    supplyFloor,
                    FixedPointMathLib.min(
                        coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                        Constants.MAX_FUZZED_AMOUNT
                    )
                )
            );
        }
        setCoreState(coreState);
        setRangeState(range);

        // And: A router filling at the price, less a fee up to the highest pool fee.
        givenValidPlanLimits(configState, 0, 1);
        fee = bound(fee, 1, FixedPointMathLib.min(uint256(configState.maxSwapCostBps) * 100, Constants.MAX_POOL_FEE));

        // And: A token0 deposit levied eight unit's token1 and more at that fee.
        {
            uint256 least0;
            {
                (, uint256 unit1) = amountsRoundedUp(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, 1);
                least0 = (8 * (unit1 + 8))
                    .fullMulDivUp(MAX_PIPS, fee)
                    .fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice) + 1;
            }
            givenValidQueueState(queueState, least0, 0, Constants.QUEUE_DEPOSIT0 | Constants.QUEUE_REDEEM1);
            (, uint256 most1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, pool.maxLiquidityPerTick() / 4
            );
            queueState.deposit0 = FixedPointMathLib.min(
                queueState.deposit0,
                FixedPointMathLib.max(
                    least0,
                    token1ToToken0(poolState.sqrtPrice, FixedPointMathLib.min(most1, Constants.MAX_FUZZED_AMOUNT / 8))
                )
            );
        }

        // And: A token1 buffer past twice the sale's fee, so the vault keeps a value.
        fundBuffer(
            0,
            2
                * token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() + queueState.deposit0)
                    .fullMulDivUp(fee, MAX_PIPS) + 2
        );

        // And: A token1 redeem of a quarter of the supply and more, and no token0 redeem.
        queueState.redeem1 = bound(queueState.redeem1, coreState.supply.divUp(4), almCore.balanceOf(users.steward) / 2);
        setQueueState(queueState);

        // And: A max shortfall above the fill's fee and the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(4, vaultValue(sqrtPriceX96(pool), true).fullMulDivUp(fee, MAX_PIPS)),
            configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The keeper clears, swaps to all token1 and mints the open buffer.
        Plan.Steps memory plan = Plan.init().clearAllRequests(true, true).clearAllRequests(false, false);
        plan = plan.swapBalance(
                address(new BalanceRouterMock()),
                address(token0),
                address(token1),
                address(routerTrampoline),
                true,
                Sentinels.TO_TARGET_RATIO,
                poolState.sqrtPrice,
                fee
            )
            .settleRequests();
        runPlan(
            plan.openRange(
                range.tickLower,
                range.tickUpper,
                Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                0,
                0
            )
        );

        // Then: The redeem settles with its payout in escrow.
        assertGt(almCore.redeemEpoch(asyncVault1, 0).amountOut, 0);
        assertEq(almCore.getEscrowed1(), almCore.redeemEpoch(asyncVault1, 0).amountOut);

        // And: The range is open.
        assertGt(positionLiquidity(almCore.getRange(1).unstakedTokenId), 0);
    }

    function testFuzz_Success_execute_EmitsPlanExecuted(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Plan.Steps memory plan = Plan.init().collect(almCore.getRange(range.index).unstakedTokenId);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: The value at the plan price and the supply, which a collect keeps.
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            trustedSqrtPriceX96, range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        uint256 value =
            amount1 + almCore.bufferAmount1() + token0ToToken1(trustedSqrtPriceX96, amount0 + almCore.bufferAmount0());
        uint256 supply = almCore.totalSupply();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        vm.prank(users.keeper);
        vm.expectEmit(true, true, true, true, address(almCore));
        emit IALMCoreEvents.PlanExecuted(1, trustedSqrtPriceX96, value, value, supply, 0, 0);
        // Then: It reports its steps, price, value before and after, supply and no swap.
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_execute_EmitsPlanExecuted_WithTheSwapDeltas(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 sold,
        bool zeroForOne,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A buffer holding a sale whose fill at the price stays within an amount.
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        sold = bound(
            sold,
            1,
            FixedPointMathLib.min(
                Constants.MAX_FUZZED_AMOUNT,
                zeroForOne
                    ? token1ToToken0(trustedSqrtPriceX96, Constants.MAX_FUZZED_AMOUNT)
                    : token0ToToken1(trustedSqrtPriceX96, Constants.MAX_FUZZED_AMOUNT)
            )
        );
        fundBuffer(zeroForOne ? sold : 0, zeroForOne ? 0 : sold);

        // And: The vault's holdings at the plan price, its value and its supply.
        uint256 held0;
        uint256 held1;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                trustedSqrtPriceX96, range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            (held0, held1) = (amount0 + almCore.bufferAmount0(), amount1 + almCore.bufferAmount1());
        }
        uint256 value = held1 + token0ToToken1(trustedSqrtPriceX96, held0);
        uint256 supply = almCore.totalSupply();

        // And: A plan selling it through a router filling at the price.
        uint256 bought =
            zeroForOne ? token0ToToken1(trustedSqrtPriceX96, sold) : token1ToToken0(trustedSqrtPriceX96, sold);
        Plan.Steps memory plan = Plan.init()
            .swapAtRate(address(token0), address(token1), address(routerTrampoline), zeroForOne, sold, bought);

        // And: The swap's buffer deltas, the input leaving it and the output arriving.
        (int256 delta0, int256 delta1) = zeroForOne ? (-int256(sold), int256(bought)) : (int256(bought), -int256(sold));
        uint256 valueAfter =
            uint256(int256(held1) + delta1) + token0ToToken1(trustedSqrtPriceX96, uint256(int256(held0) + delta0));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: It reports the swap's deltas, the value after them and the same supply.
        vm.prank(users.keeper);
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.PlanExecuted(1, trustedSqrtPriceX96, value, valueAfter, supply, delta0, delta1);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_execute_ChecksTheEmissionsOncePerPlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);

        // And: A supply to redeem from, each aLP a quarter amount of token0 at most.
        uint256 supplyFloor = FixedPointMathLib.max(
            almCore.DEAD_SHARES_() + 2,
            (coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0))
            .divUp(token0ToToken1(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 4))
        );
        coreState.supply = bound(
            coreState.supply,
            supplyFloor,
            FixedPointMathLib.max(
                supplyFloor,
                FixedPointMathLib.min(
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                    Constants.MAX_FUZZED_AMOUNT
                )
            )
        );
        setCoreState(coreState);
        setRangeState(range);

        // And: A token0 deposit of an aLP or more, a token0 redeem, no token1 request.
        uint256 sqrtPrice = sqrtPriceX96(pool);
        uint256 value;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = amount1 + almCore.bufferAmount1() + token0ToToken1(sqrtPrice, amount0 + almCore.bufferAmount0()) + 1;
        }
        givenValidQueueState(
            queueState,
            value.divUp(coreState.supply).fullMulDivUp(1 << 192, sqrtPrice * sqrtPrice),
            0,
            Constants.QUEUE_DEPOSIT0 | Constants.QUEUE_REDEEM0
        );
        queueState.redeem0 = bound(
            queueState.redeem0,
            1,
            FixedPointMathLib.min(
                almCore.balanceOf(users.steward) / 2,
                token0ToToken1(sqrtPrice, almCore.bufferAmount0() + queueState.deposit0)
                    .fullMulDiv(coreState.supply, value)
            )
        );
        setQueueState(queueState);
        Plan.Steps memory plan = Plan.init().clearAllRequests(true, true).clearAllRequests(true, false).settleRequests();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        vm.expectCall(almCore.REWARD_TOKEN_(), abi.encodeCall(ERC20.balanceOf, (address(almCore))), 1);
        runPlan(plan);

        // Then: One checkpoint read the reward balance once, both epochs settled.
        (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = almCore.pendingEpochs(asyncVault0);
        assertEq(pendingDepositEpoch, 1);
        assertEq(pendingRedeemEpoch, 1);
    }

    function testFuzz_Success_execute_ChecksTheEmissionsInEveryPlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, without a plan interval.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A pending token0 deposit and no other request.
        givenValidQueueState(queueState, 1, 0, Constants.QUEUE_DEPOSIT0);
        setQueueState(queueState);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles it, then a second token0 deposit in a second plan.
        vm.expectCall(almCore.REWARD_TOKEN_(), abi.encodeCall(ERC20.balanceOf, (address(almCore))), 2);
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());
        givenValidQueueState(queueState, 0, 0);
        recordDepositAt(asyncVault0, controller, FixedPointMathLib.max(queueState.deposit0, 1));
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());

        // Then: Each plan read the reward balance in its checkpoint, both epochs settled.
        (uint32 pendingDepositEpoch,) = almCore.pendingEpochs(asyncVault0);
        assertEq(pendingDepositEpoch, 2);
    }

    function testFuzz_Success_execute_StoresTheExchangeRate(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        int256 tickOffset,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A pending token0 deposit and no other request.
        givenValidQueueState(queueState, 1, 0, Constants.QUEUE_DEPOSIT0);
        setQueueState(queueState);
        uint256 assets = queueState.deposit0;

        // And: A trusted price in the band off spot, the supply and its value there.
        int256 tick = currentTick(pool);
        tickOffset = bound(
            tickOffset,
            TickMath.getTickAtSqrtPrice(
                    uint160(uint256(sqrtPriceX96(pool)).fullMulDivUp(1e18, 1e18 + Constants.WIDE_DEVIATION))
                ) + 1 - tick,
            TickMath.getTickAtSqrtPrice(
                    uint160(uint256(sqrtPriceX96(pool)).fullMulDiv(1e18 + Constants.WIDE_DEVIATION, 1e18))
                ) - tick - 1
        );
        if (tickOffset >= 0) ++tickOffset;
        uint160 trustedPrice = TickMath.getSqrtPriceAtTick(int24(tick + tickOffset));
        uint256 supplyBefore = almCore.totalSupply();
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            trustedPrice, range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        uint256 valueBefore =
            amount1 + almCore.bufferAmount1() + token0ToToken1(trustedPrice, amount0 + almCore.bufferAmount0());

        // And: The deposit's value there, and the value and supply once settled.
        uint256 priceX192 = uint256(trustedPrice) * trustedPrice;
        uint256 depositValue = FullMath.mulDiv(assets, priceX192, 1 << 192);
        uint256 valueAfter = amount1 + almCore.bufferAmount1()
            + FullMath.mulDiv(amount0 + almCore.bufferAmount0() + assets, priceX192, 1 << 192);
        uint256 supplyAfter = supplyBefore
            + FixedPointMathLib.fullMulDiv(
                depositValue,
                supplyBefore,
                amount1 + almCore.bufferAmount1()
                    + FullMath.mulDivRoundingUp(amount0 + almCore.bufferAmount0(), priceX192, 1 << 192)
            );

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch at the trusted price.
        Plan.Steps memory plan = Plan.init().clearAllRequests(true, true).settleRequests();
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.PlanExecuted(2, trustedPrice, valueBefore, valueAfter, supplyAfter, 0, 0);
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, trustedPrice);

        // Then: The supply grew by the settled shares.
        assertEq(almCore.totalSupply(), supplyAfter);

        // And: The supply per value after the plan, rounded up, at the trusted price.
        (uint256 supplyPerValueX128, uint160 lastSqrtPriceX96) = almCore.lastExchangeRate_();
        assertEq(supplyPerValueX128, FixedPointMathLib.fullMulDivUp(supplyAfter, 1 << 128, valueAfter));
        assertEq(lastSqrtPriceX96, trustedPrice);
    }

    function testFuzz_Success_execute_SettleThenStakeAfterAnUnfoldedCloseFoldsThePreCredit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        RangeState memory neighbour,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 feeBps,
        uint256 blocks,
        uint256 emissions,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge penalising an early unstake, and an emission fee.
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 1, MAX_PIPS));
        feeBps = bound(feeBps, 0, almCore.MAX_FEE_BPS_());
        vm.prank(factory);
        almCore.setProtocolFees(uint16(feeBps), 0, users.feeRecipient);

        // And: A vault, a range staked inside its window, an unstaked neighbour.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        givenValidRangeState(neighbour, poolState, false, false);
        setRangeState(neighbour);

        // And: A pending token0 deposit and no other request.
        givenValidQueueState(queueState, 1, 0, Constants.QUEUE_DEPOSIT0);
        setQueueState(queueState);

        // And: Emissions accrued inside the window, pre-credited by a checkpoint.
        blocks = bound(blocks, 1, minStakeBlocks - 1);
        accrueForBlocks(pool, gauge, blocks, bound(emissions, MAX_PIPS + 1, Constants.MAX_EMISSIONS));
        uint256 preCredited = hiddenEmissions(gauge, address(almCore), gauge.stakedValues(address(almCore)));
        preCredited -= preCredited * feeBps / ConfigLib.BPS_DENOMINATOR;
        almCore.checkpoint_();

        // And: The window closed without a checkpoint.
        vm.roll(almCore.getRange(range.index).stakedBlock + minStakeBlocks);

        // And: A plan that settles the deposit, then stakes the neighbour.
        Plan.Steps memory plan;
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), neighbour.tickLower, neighbour.tickUpper, neighbour.liquidity);
        fundShortfall(amount0, amount1);
        plan = Plan.init()
            .clearAllRequests(true, true)
            .settleRequests()
            .stake(neighbour.index, neighbour.unstakedTokenId, amount0, amount1, 0, 0);
        uint256 highWater = almCore.getRewardHighWater();
        uint256 rewardPerShare = almCore.rewardPerShare_();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        runPlan(plan);

        // Then: The pre-credit folded into the high water, nothing credited twice.
        assertEq(almCore.getPreCredited(), 0);
        assertEq(almCore.getRewardHighWater(), highWater + preCredited);
        assertEq(almCore.rewardPerShare_(), rewardPerShare);

        // And: The window end is the neighbour's.
        assertEq(almCore.getWindowEnd(), vm.getBlockNumber() + minStakeBlocks);
    }

    function testFuzz_Success_execute_SettleThenStakeSameRps(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        RangeState memory neighbour,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 feeBps,
        uint256 blocks,
        uint256 emissions,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge penalising an early unstake, and an emission fee.
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 1, MAX_PIPS));
        feeBps = bound(feeBps, 0, almCore.MAX_FEE_BPS_());
        vm.prank(factory);
        almCore.setProtocolFees(uint16(feeBps), 0, users.feeRecipient);

        // And: A vault, a range staked inside its window, an unstaked neighbour.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        givenValidRangeState(neighbour, poolState, false, false);
        setRangeState(neighbour);

        // And: A pending token0 deposit and no other request.
        givenValidQueueState(queueState, 1, 0, Constants.QUEUE_DEPOSIT0);
        setQueueState(queueState);

        // And: Emissions accrued inside the window.
        blocks = bound(blocks, 1, minStakeBlocks - 1);
        accrueForBlocks(pool, gauge, blocks, bound(emissions, MAX_PIPS + 1, Constants.MAX_EMISSIONS));

        // And: A plan that settles, then stakes the neighbour.
        Plan.Steps memory plan;
        {
            (uint256 amount0, uint256 amount1) =
                amountsRoundedUp(sqrtPriceX96(pool), neighbour.tickLower, neighbour.tickUpper, neighbour.liquidity);
            fundShortfall(amount0, amount1);
            plan = Plan.init()
                .clearAllRequests(true, true)
                .settleRequests()
                .stake(neighbour.index, neighbour.unstakedTokenId, amount0, amount1, 0, 0);
        }

        // And: The reward state before a plan that settles, then stakes the neighbour.
        uint256 rewardPerShare = almCore.rewardPerShare_();
        uint256 highWater = almCore.getRewardHighWater();
        uint256 preCredited = almCore.getPreCredited();
        uint256 total = almCore.getClaimedCumulative();
        uint256 lastRewardBalance = almCore.getLastRewardBalance();
        uint256 supply = almCore.totalSupply();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        runPlan(plan);

        // Then: The pre-credit is the hidden emissions after the stake, net of the fee.
        uint256 hidden = hiddenEmissions(gauge, address(almCore), gauge.stakedValues(address(almCore)));
        hidden -= hidden * feeBps / ConfigLib.BPS_DENOMINATOR;
        assertEq(almCore.getPreCredited(), hidden);

        // And: The settle credits the reward per share of the gauge after the stake.
        uint256 received = ERC20(almCore.REWARD_TOKEN_()).balanceOf(address(almCore)) - lastRewardBalance;
        uint256 earned = gauge.earned(address(almCore), gauge.stakedValues(address(almCore)));
        total += received - received * feeBps / ConfigLib.BPS_DENOMINATOR;
        total += earned - earned * feeBps / ConfigLib.BPS_DENOMINATOR;
        uint256 credit;
        if (hidden < preCredited) highWater += preCredited - hidden;
        else credit = hidden - preCredited;
        if (total > highWater) credit += total - highWater;
        assertEq(
            almCore.rewardPerShare_(),
            FixedPointMathLib.min(rewardPerShare + credit.fullMulDiv(1e18, supply), type(uint128).max)
        );
    }

    function testFuzz_Success_execute_SeveralStakesOneWindowEnd(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory neighbour,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 elapsed,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge penalising an early unstake.
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 1, MAX_PIPS));

        // And: A vault, a staked range whose window ends earlier, an unstaked neighbour.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        givenValidRangeState(neighbour, poolState, false, false);
        setRangeState(neighbour);
        vm.roll(vm.getBlockNumber() + bound(elapsed, 1, type(uint32).max));

        // And: A plan staking the neighbour and restaking the range, taking its penalty.
        Plan.Steps memory plan;
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), neighbour.tickLower, neighbour.tickUpper, neighbour.liquidity);
        fundShortfall(amount0, amount1);
        plan = Plan.init().stake(neighbour.index, neighbour.unstakedTokenId, amount0, amount1, 0, 0);
        (amount0, amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked / 2);
        fundBuffer(amount0, amount1);
        plan = plan.increaseStakedLiquidity(range.index, range.stakedTokenId, amount0, amount1, 0, 0, true);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        runPlan(plan);

        // Then: Both staked sides start their window in this block.
        assertEq(almCore.getRange(range.index).stakedBlock, vm.getBlockNumber());
        assertEq(almCore.getRange(neighbour.index).stakedBlock, vm.getBlockNumber());

        // And: The one window end is this block's.
        assertEq(almCore.getWindowEnd(), vm.getBlockNumber() + minStakeBlocks);
    }

    function testFuzz_Success_execute_ForfeitBeforeTheCheckpointFolds(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 feeBps,
        uint256 blocks,
        uint256 emissions,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge penalising an early unstake, and an emission fee.
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 1, MAX_PIPS));
        feeBps = bound(feeBps, 0, almCore.MAX_FEE_BPS_());
        vm.prank(factory);
        almCore.setProtocolFees(uint16(feeBps), 0, users.feeRecipient);

        // And: A seeded vault with a range staked inside its window.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A deposit, and a plan unstaking at a penalty, then settling it.
        givenValidQueueState(queueState, 1, 0, Constants.QUEUE_DEPOSIT0);
        setQueueState(queueState);
        Plan.Steps memory plan = Plan.init()
            .clearAllRequests(true, true)
            .unstake(range.index, range.stakedTokenId, range.liquidityStaked / 2, 0, 0, true)
            .settleRequests();

        // And: Emissions accrued inside the window, pre-credited by a checkpoint.
        blocks = bound(blocks, 1, minStakeBlocks - 1);
        accrueForBlocks(pool, gauge, blocks, bound(emissions, MAX_PIPS + 1, Constants.MAX_EMISSIONS));
        uint256 preCredited = hiddenEmissions(gauge, address(almCore), gauge.stakedValues(address(almCore)));
        preCredited -= preCredited * feeBps / ConfigLib.BPS_DENOMINATOR;
        almCore.checkpoint_();
        uint256 highWater = almCore.getRewardHighWater();
        uint256 rewardPerShare = almCore.rewardPerShare_();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        runPlan(plan);

        // Then: The forfeited pre-credit folded into the high water, nothing credited.
        assertEq(almCore.getPreCredited(), 0);
        assertEq(almCore.getRewardHighWater(), highWater + preCredited);
        assertEq(almCore.rewardPerShare_(), rewardPerShare);

        // And: The window end is the restake's.
        assertEq(almCore.getWindowEnd(), vm.getBlockNumber() + minStakeBlocks);
    }

    function testFuzz_Success_execute_CheckpointsOnceWithAWindowOpen(
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 feeBps,
        uint256 blocks,
        uint256 emissions,
        RangeState memory range,
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge penalising an early unstake, and an emission fee.
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 1, MAX_PIPS));
        feeBps = bound(feeBps, 0, almCore.MAX_FEE_BPS_());
        vm.prank(factory);
        almCore.setProtocolFees(uint16(feeBps), 0, users.feeRecipient);

        // And: A seeded vault with a range staked inside its window.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);

        // And: A supply to redeem from, each aLP a quarter amount of token0 at most.
        {
            uint256 supplyFloor = FixedPointMathLib.max(
                almCore.DEAD_SHARES_() + 2,
                (coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0))
                .divUp(token0ToToken1(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 4))
            );
            coreState.supply = bound(
                coreState.supply,
                supplyFloor,
                FixedPointMathLib.max(
                    supplyFloor,
                    FixedPointMathLib.min(
                        coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                        Constants.MAX_FUZZED_AMOUNT
                    )
                )
            );
        }
        setCoreState(coreState);
        setRangeState(range);

        // And: A token0 deposit of an aLP or more, a token0 redeem, no token1 request.
        {
            uint256 sqrtPrice = sqrtPriceX96(pool);
            uint256 value;
            {
                (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                    uint160(sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
                );
                value = amount1 + almCore.bufferAmount1() + token0ToToken1(sqrtPrice, amount0 + almCore.bufferAmount0())
                    + 1;
            }
            givenValidQueueState(
                queueState,
                value.divUp(coreState.supply).fullMulDivUp(1 << 192, sqrtPrice * sqrtPrice),
                0,
                Constants.QUEUE_DEPOSIT0 | Constants.QUEUE_REDEEM0
            );
            queueState.redeem0 = bound(
                queueState.redeem0,
                1,
                FixedPointMathLib.min(
                    almCore.balanceOf(users.steward) / 2,
                    token0ToToken1(sqrtPrice, almCore.bufferAmount0() + queueState.deposit0)
                        .fullMulDiv(coreState.supply, value)
                )
            );
        }
        setQueueState(queueState);

        // And: Emissions accrued inside the window.
        blocks = bound(blocks, 1, minStakeBlocks - 1);
        accrueForBlocks(pool, gauge, blocks, bound(emissions, MAX_PIPS + 1, Constants.MAX_EMISSIONS));
        uint256 hidden = hiddenEmissions(gauge, address(almCore), gauge.stakedValues(address(almCore)));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles both epochs in one plan.
        vm.expectCall(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.pool.selector), 1);
        runPlan(Plan.init().clearAllRequests(true, true).clearAllRequests(true, false).settleRequests());

        // Then: One checkpoint read the hidden emissions, pre-credited net of the fee.
        assertEq(almCore.getPreCredited(), hidden - hidden * feeBps / ConfigLib.BPS_DENOMINATOR);
    }

    function testFuzz_Success_execute_StakeAfterTheCheckpointOnlyWritesWindowEnd(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        RangeState memory neighbour,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 feeBps,
        uint256 blocks,
        uint256 emissions,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge penalising an early unstake, and an emission fee.
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 1, MAX_PIPS));
        feeBps = bound(feeBps, 0, almCore.MAX_FEE_BPS_());
        vm.prank(factory);
        almCore.setProtocolFees(uint16(feeBps), 0, users.feeRecipient);

        // And: A vault, a range staked inside its window, an unstaked neighbour.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        givenValidRangeState(neighbour, poolState, false, false);
        setRangeState(neighbour);

        // And: A pending token0 deposit and no other request.
        givenValidQueueState(queueState, 1, 0, Constants.QUEUE_DEPOSIT0);
        setQueueState(queueState);

        // And: Emissions accrued inside the window.
        blocks = bound(blocks, 1, minStakeBlocks - 1);
        accrueForBlocks(pool, gauge, blocks, bound(emissions, MAX_PIPS + 1, Constants.MAX_EMISSIONS));
        uint256 preCredited = hiddenEmissions(gauge, address(almCore), gauge.stakedValues(address(almCore)));
        preCredited -= preCredited * feeBps / ConfigLib.BPS_DENOMINATOR;

        // And: A plan that settles the deposit, then stakes the neighbour.
        Plan.Steps memory plan;
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), neighbour.tickLower, neighbour.tickUpper, neighbour.liquidity);
        fundShortfall(amount0, amount1);
        plan = Plan.init()
            .clearAllRequests(true, true)
            .settleRequests()
            .stake(neighbour.index, neighbour.unstakedTokenId, amount0, amount1, 0, 0);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        runPlan(plan);

        // Then: Pre-credit is the range's hidden emissions, window end the neighbour's.
        assertEq(almCore.getPreCredited(), preCredited);
        assertEq(almCore.getWindowEnd(), vm.getBlockNumber() + minStakeBlocks);

        // And: The next checkpoint has nothing left to fold or credit.
        uint256 highWater = almCore.getRewardHighWater();
        uint256 rewardPerShare = almCore.rewardPerShare_();
        almCore.checkpoint_();
        assertEq(almCore.getPreCredited(), preCredited);
        assertEq(almCore.getRewardHighWater(), highWater);
        assertEq(almCore.rewardPerShare_(), rewardPerShare);
        assertEq(almCore.getWindowEnd(), vm.getBlockNumber() + minStakeBlocks);
    }

    function testFuzz_Success_execute_NoSettleStepNeverCheckpoints(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        RangeState memory neighbour,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocks,
        uint256 emissions,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge penalising an early unstake.
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 1, MAX_PIPS));

        // And: A vault, a range staked inside its window, an unstaked neighbour.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        givenValidRangeState(neighbour, poolState, false, false);
        setRangeState(neighbour);

        // And: A pending token0 deposit and no other request.
        givenValidQueueState(queueState, 1, 0, Constants.QUEUE_DEPOSIT0);
        setQueueState(queueState);

        // And: Emissions accrued inside the window.
        blocks = bound(blocks, 1, minStakeBlocks - 1);
        accrueForBlocks(pool, gauge, blocks, bound(emissions, MAX_PIPS + 1, Constants.MAX_EMISSIONS));

        // And: A plan that cancels the deposit, stakes the neighbour, collects the range.
        Plan.Steps memory plan = Plan.init().cancelRequests(true, true, Plan.one(accountB));
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), neighbour.tickLower, neighbour.tickUpper, neighbour.liquidity);
        fundShortfall(amount0, amount1);
        plan = plan.stake(neighbour.index, neighbour.unstakedTokenId, amount0, amount1, 0, 0)
            .collect(range.unstakedTokenId);
        uint256 preCredited = almCore.getPreCredited();
        uint256 highWater = almCore.getRewardHighWater();
        uint256 rewardPerShare = almCore.rewardPerShare_();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(3, 0), 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        vm.expectCall(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.pool.selector), 0);
        vm.expectCall(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.earned.selector, address(almCore)), 0);
        runPlan(plan);

        // Then: No checkpoint ran, the reward accounting is untouched.
        assertEq(almCore.getPreCredited(), preCredited);
        assertEq(almCore.getRewardHighWater(), highWater);
        assertEq(almCore.rewardPerShare_(), rewardPerShare);

        // And: The stake still wrote its window end.
        assertEq(almCore.getWindowEnd(), vm.getBlockNumber() + minStakeBlocks);
    }

    function testFuzz_Success_execute_EmergencyUnstakeTakesTheWholeSide(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range on both sides, emergency withdraw enabled.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        clGaugeFactory.setEmergencyWithdrawEnabled(true);

        // And: The staked principal, the buffer, the positions and the vault value.
        (uint256 principal0, uint256 principal1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked);
        uint256 buffer0 = almCore.bufferAmount0();
        uint256 buffer1 = almCore.bufferAmount1();
        uint256 positions = POSITION_MANAGER.totalSupply();
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 value = amount1 + buffer1 + token0ToToken1(sqrtPriceX96(pool), amount0 + buffer0);
            Plan.Steps memory plan = Plan.init().emergencyUnstake(range.index, range.stakedTokenId);
            uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

            // And: Plan limits above the plan's rounding loss.
            givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
            setPlanLimits(configState);

            // When: The keeper takes the staked side out through the emergency withdraw.
            vm.expectEmit(address(almCore));
            emit IALMCoreEvents.Unstaked(range.index, range.stakedTokenId);
            vm.expectEmit(address(almCore));
            emit IALMCoreEvents.PlanExecuted(1, trustedSqrtPriceX96, value, value, almCore.totalSupply(), 0, 0);
            vm.prank(users.keeper);
            almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
        }

        // Then: The staked side left the gauge and is burned, the unstaked one untouched.
        Range memory staged = almCore.getRange(range.index);
        assertEq(staged.stakedTokenId, 0);
        assertEq(staged.stakedLiquidity, 0);
        assertEq(staged.unstakedTokenId, range.unstakedTokenId);
        assertEq(positionLiquidity(staged.unstakedTokenId), range.liquidity);
        assertFalse(gauge.stakedContains(address(almCore), range.stakedTokenId));
        assertEq(POSITION_MANAGER.totalSupply(), positions - 1);

        // And: The buffer holds the side's principal, moved out of the range.
        assertEq(almCore.bufferAmount0(), buffer0 + principal0);
        assertEq(almCore.bufferAmount1(), buffer1 + principal1);
    }

    function testFuzz_Success_execute_EmergencyUnstakeInsideTheWindow(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocks,
        uint256 emissions,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge penalising an early unstake, and its emergency withdraw enabled.
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 1, MAX_PIPS));
        clGaugeFactory.setEmergencyWithdrawEnabled(true);

        // And: A seeded vault with a range staked inside its window, and emissions.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        accrueForBlocks(pool, gauge, bound(blocks, 1, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 rewardBalance = ERC20(almCore.REWARD_TOKEN_()).balanceOf(address(almCore));

        // And: The staked side's principal rounded down, and the buffer.
        (uint256 principal0, uint256 principal1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked);
        uint256 buffer0 = almCore.bufferAmount0();
        uint256 buffer1 = almCore.bufferAmount1();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper takes the staked side out through the emergency withdraw.
        runPlan(Plan.init().emergencyUnstake(range.index, range.stakedTokenId));

        // Then: The staked side is gone, with nothing claimed or deferred.
        assertEq(almCore.getRange(range.index).stakedTokenId, 0);
        assertEq(gauge.deferredEmissions(address(almCore)), 0);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(address(almCore)), rewardBalance);

        // And: The buffer holds the side's principal.
        assertEq(almCore.bufferAmount0() - buffer0, principal0);
        assertEq(almCore.bufferAmount1() - buffer1, principal1);
    }

    function testFuzz_Success_execute_EmergencyUnstakeWhilePaused(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a staked range, emergency withdraw on, a paused core.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        clGaugeFactory.setEmergencyWithdrawEnabled(true);
        vm.prank(factory);
        almCore.pause();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper takes the staked side out through the emergency withdraw.
        runPlan(Plan.init().emergencyUnstake(range.index, range.stakedTokenId));

        // Then: The staked side is gone.
        assertEq(almCore.getRange(range.index).stakedTokenId, 0);
        assertEq(almCore.getRange(range.index).stakedLiquidity, 0);
    }

    function testFuzz_Success_execute_EmergencyUnstakeThenCloseRange(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a staked range, and the gauge's emergency withdraw on.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        clGaugeFactory.setEmergencyWithdrawEnabled(true);
        uint256 positions = POSITION_MANAGER.totalSupply();

        // And: Each side's principal rounded down, and the buffer.
        (uint256 staked0, uint256 staked1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked);
        (uint256 unstaked0, uint256 unstaked1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        uint256 buffer0 = almCore.bufferAmount0();
        uint256 buffer1 = almCore.bufferAmount1();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: One plan emergency unstakes the staked side, then closes the range.
        runPlan(
            Plan.init()
                .emergencyUnstake(range.index, range.stakedTokenId)
                .closeRange(range.index, range.unstakedTokenId)
        );

        // Then: The range and both its positions are gone, and the core holds its buffer.
        assertEq(almCore.getRangesLength(), 0);
        assertEq(POSITION_MANAGER.totalSupply(), positions - 2);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0() + almCore.getProtocolFees0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1() + almCore.getProtocolFees1());

        // And: The buffer holds both sides' principal.
        assertEq(almCore.bufferAmount0() - buffer0, staked0 + unstaked0);
        assertEq(almCore.bufferAmount1() - buffer1, staked1 + unstaked1);
    }

    function testFuzz_Success_execute_EmergencyUnstakeWhileTheVoterReverts(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 elapsed,
        bytes4 reason,
        uint256 shares,
        uint256 reward,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault with a range staked outside its window, emergency withdraw on.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);

        // And: A seed holder with aLP.
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        clGaugeFactory.setEmergencyWithdrawEnabled(true);

        // And: Time past the pool's last settle, and a voter whose settle reverts.
        vm.warp(vm.getBlockTimestamp() + bound(elapsed, 1, (type(uint32).max - vm.getBlockTimestamp())));
        vm.mockCallRevert(
            address(leafVoter),
            abi.encodeWithSelector(leafVoter.settleGauge.selector, address(gauge)),
            abi.encode(reason)
        );

        // And: A normal unstake of the staked side reverts on the voter.
        Plan.Steps memory plan =
            Plan.init().unstake(range.index, range.stakedTokenId, Sentinels.RANGE_LIQUIDITY, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectRevert(abi.encode(reason));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper takes the staked side out through the emergency withdraw.
        runPlan(Plan.init().emergencyUnstake(range.index, range.stakedTokenId));

        // Then: The staked side is gone.
        assertEq(almCore.getRange(range.index).stakedTokenId, 0);

        // And: Reward the core already holds, a wei and more of it the holder's.
        uint256 supply = almCore.totalSupply();
        uint256 balance = almCore.balanceOf(users.steward);
        reward = bound(reward, supply.divUp(balance) + supply.divUp(1e18), Constants.MAX_EMISSIONS);
        deal(almCore.REWARD_TOKEN_(), address(almCore), reward);

        // And: The holder burns part of its aLP and claims its reward.
        shares = bound(shares, 1, balance);
        vm.startPrank(users.steward);
        almCore.burn(shares, users.steward, users.steward);
        uint256 amount = almCore.claimEmissions(users.steward);
        vm.stopPrank();
        assertEq(almCore.balanceOf(users.steward), balance - shares);
        assertEq(amount, balance.fullMulDiv(reward.fullMulDiv(1e18, supply), 1e18));
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(users.steward), amount);
    }

    function testFuzz_Success_execute_EmergencyUnstakeKeepsTheRewardPerShare(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 feeBps,
        uint256 emissions,
        uint256 laterEmissions,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee.
        feeBps = bound(feeBps, 0, almCore.MAX_FEE_BPS_());
        vm.prank(factory);
        almCore.setProtocolFees(uint16(feeBps), 0, users.feeRecipient);

        // And: A vault with a range staked outside its window, emergency withdraw on.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        clGaugeFactory.setEmergencyWithdrawEnabled(true);

        // And: Emissions accrued and credited by a checkpoint, then more accrued.
        accrueForBlocks(pool, gauge, 1, bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 accrued = gauge.earned(address(almCore));
        accrued -= accrued * feeBps / ConfigLib.BPS_DENOMINATOR;
        almCore.checkpoint_();
        uint256 rewardPerShare = almCore.rewardPerShare_();
        accrueForBlocks(pool, gauge, 1, bound(laterEmissions, 1, Constants.MAX_EMISSIONS));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper emergency unstakes the staked side, then a checkpoint runs.
        runPlan(Plan.init().emergencyUnstake(range.index, range.stakedTokenId));
        almCore.checkpoint_();

        // Then: Reward per share unchanged, deficit the first checkpoint's net accrual.
        (,, uint256 total) = almCore.getRewardTotals();
        assertEq(almCore.rewardPerShare_(), rewardPerShare);
        assertEq(total, 0);
        assertEq(almCore.getRewardHighWater() - total, accrued);
    }

    function testFuzz_Success_execute_EmergencyUnstakeAfterACloseStepCreditsNothingNew(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 feeBps,
        uint256 emissions,
        uint256 laterEmissions,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee.
        feeBps = bound(feeBps, 0, almCore.MAX_FEE_BPS_());
        vm.prank(factory);
        almCore.setProtocolFees(uint16(feeBps), 0, users.feeRecipient);

        // And: A vault with a range staked outside its window, emergency withdraw on.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        clGaugeFactory.setEmergencyWithdrawEnabled(true);

        // And: A pending token0 deposit and no other request.
        givenValidQueueState(queueState, 1, 0, Constants.QUEUE_DEPOSIT0);
        setQueueState(queueState);

        // And: Emissions accrued and credited by a checkpoint, then more accrued.
        accrueForBlocks(pool, gauge, 1, bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 accrued = gauge.earned(address(almCore));
        accrued -= accrued * feeBps / ConfigLib.BPS_DENOMINATOR;
        almCore.checkpoint_();
        uint256 rewardPerShare = almCore.rewardPerShare_();
        accrueForBlocks(pool, gauge, 1, bound(laterEmissions, 1, Constants.MAX_EMISSIONS));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the deposit, then emergency unstakes the staked side.
        runPlan(
            Plan.init().clearAllRequests(true, true).emergencyUnstake(range.index, range.stakedTokenId).settleRequests()
        );

        // Then: The clear step does not checkpoint, the plan's credits nothing.
        (,, uint256 total) = almCore.getRewardTotals();
        assertEq(almCore.rewardPerShare_(), rewardPerShare);
        assertEq(almCore.getRewardHighWater() - total, accrued);
    }

    function testFuzz_Success_execute_EmergencyUnstakeCheckpointAfterTheStepCreditsNothingNew(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 feeBps,
        uint256 emissions,
        uint256 laterEmissions,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee.
        feeBps = bound(feeBps, 0, almCore.MAX_FEE_BPS_());
        vm.prank(factory);
        almCore.setProtocolFees(uint16(feeBps), 0, users.feeRecipient);

        // And: A vault with a range staked outside its window, emergency withdraw on.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        clGaugeFactory.setEmergencyWithdrawEnabled(true);

        // And: A pending token0 deposit and no other request.
        givenValidQueueState(queueState, 1, 0, Constants.QUEUE_DEPOSIT0);
        setQueueState(queueState);

        // And: Emissions accrued and credited by a checkpoint, then more accrued.
        accrueForBlocks(pool, gauge, 1, bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 accrued = gauge.earned(address(almCore));
        accrued -= accrued * feeBps / ConfigLib.BPS_DENOMINATOR;
        almCore.checkpoint_();
        uint256 rewardPerShare = almCore.rewardPerShare_();
        accrueForBlocks(pool, gauge, 1, bound(laterEmissions, 1, Constants.MAX_EMISSIONS));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper emergency unstakes the staked side, then settles the deposit.
        runPlan(
            Plan.init().clearAllRequests(true, true).emergencyUnstake(range.index, range.stakedTokenId).settleRequests()
        );

        // Then: Nothing new credited, the deficit the earlier checkpoint's accrual.
        (,, uint256 total) = almCore.getRewardTotals();
        assertEq(almCore.rewardPerShare_(), rewardPerShare);
        assertEq(almCore.getRewardHighWater() - total, accrued);
    }

    function testFuzz_Success_execute_EmergencyUnstakeEmissionsRefillTheDeficitFirst(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 feeBps,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee.
        feeBps = bound(feeBps, 0, almCore.MAX_FEE_BPS_());
        vm.prank(factory);
        almCore.setProtocolFees(uint16(feeBps), 0, users.feeRecipient);

        // And: A seeded vault with a range around the price, staked outside its window.
        {
            int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
            int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
            range.tickLower = int24(bound(range.tickLower, -band + 1, compressed)) * poolState.tickSpacing;
            range.tickUpper = int24(bound(range.tickUpper, compressed + 1, band - 1)) * poolState.tickSpacing;
        }
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: The gauge's emergency withdraw enabled.
        clGaugeFactory.setEmergencyWithdrawEnabled(true);

        // And: Emissions credited by a checkpoint, forfeited by an emergency unstake.
        emissions = bound(emissions, MAX_PIPS + 1, Constants.MAX_EMISSIONS);
        accrueForBlocks(pool, gauge, 1, emissions);
        almCore.checkpoint_();
        runStagingPlan(Plan.init().emergencyUnstake(range.index, range.stakedTokenId));
        uint256 highWater = almCore.getRewardHighWater();
        uint256 rewardPerShare = almCore.rewardPerShare_();

        // And: The keeper stakes the range again, outside its window.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked);
        fundShortfall(amount0, amount1);
        runStagingPlan(Plan.init().stake(range.index, range.unstakedTokenId, amount0, amount1, 0, 0));
        closePenaltyWindow(gauge);

        // When: Half the forfeited emissions accrue again, then a checkpoint runs.
        accrueForBlocks(pool, gauge, 1, emissions / 2);
        uint256 refill = gauge.earned(address(almCore));
        refill -= refill * feeBps / ConfigLib.BPS_DENOMINATOR;
        almCore.checkpoint_();

        // Then: The lifetime reward stays under the high water, and nothing is credited.
        assertLt(refill, highWater);
        assertEq(almCore.getRewardHighWater(), highWater);
        assertEq(almCore.rewardPerShare_(), rewardPerShare);

        // When: The forfeited emissions accrue once more, then a checkpoint runs.
        accrueForBlocks(pool, gauge, 1, emissions);
        refill = gauge.earned(address(almCore));
        refill -= refill * feeBps / ConfigLib.BPS_DENOMINATOR;
        almCore.checkpoint_();

        // Then: Only the lifetime reward above the high water is credited.
        assertEq(almCore.getRewardHighWater(), refill);
        assertEq(
            almCore.rewardPerShare_(),
            rewardPerShare + FixedPointMathLib.fullMulDiv(refill - highWater, 1e18, almCore.totalSupply())
        );
    }

    function testFuzz_Success_execute_EmergencyUnstakeInsideTheWindowFoldsThePreCredit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 feeBps,
        uint256 blocks,
        uint256 emissions,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge penalising early unstakes, emergency withdraw on, an emission fee.
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 1, MAX_PIPS));
        clGaugeFactory.setEmergencyWithdrawEnabled(true);
        feeBps = bound(feeBps, 0, almCore.MAX_FEE_BPS_());
        vm.prank(factory);
        almCore.setProtocolFees(uint16(feeBps), 0, users.feeRecipient);

        // And: A seeded vault with a range staked inside its window.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Emissions accrued inside the window, pre-credited by a checkpoint.
        accrueForBlocks(pool, gauge, bound(blocks, 1, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 preCredited = hiddenEmissions(gauge, address(almCore), almCore.stakedTokenIds());
        preCredited -= preCredited * feeBps / ConfigLib.BPS_DENOMINATOR;
        almCore.checkpoint_();
        uint256 highWater = almCore.getRewardHighWater();
        uint256 rewardPerShare = almCore.rewardPerShare_();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper unstakes inside the window, then a checkpoint runs.
        runPlan(Plan.init().emergencyUnstake(range.index, range.stakedTokenId));
        almCore.checkpoint_();

        // Then: Pre-credit folded into the high water, window end cleared, no credit.
        assertEq(almCore.getPreCredited(), 0);
        assertEq(almCore.getRewardHighWater(), highWater + preCredited);
        assertEq(almCore.getWindowEnd(), 0);
        assertEq(almCore.rewardPerShare_(), rewardPerShare);
    }

    function testFuzz_Success_execute_EmergencyUnstakePayRewardIsFirstCome(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault with a range staked outside its window, emergency withdraw on.
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);

        // And: A seed holder with aLP.
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        clGaugeFactory.setEmergencyWithdrawEnabled(true);

        // And: Two holders splitting the seed holder's aLP, a quarter and the rest.
        uint256 balance = almCore.balanceOf(users.steward);
        vm.startPrank(users.steward);
        almCore.transfer(accountA, balance / 4);
        almCore.transfer(accountB, balance - balance / 4);
        vm.stopPrank();

        // And: Emissions owing holder B a credit, claimed, then twice as many forfeited.
        emissions = bound(
            emissions,
            almCore.totalSupply().divUp(balance - balance / 4) + almCore.totalSupply().divUp(1e18) + 1,
            Constants.MAX_EMISSIONS / 4
        );
        accrueForBlocks(pool, gauge, 1, emissions);
        almCore.claimEmissions(accountC);
        accrueForBlocks(pool, gauge, 1, 2 * emissions);
        almCore.checkpoint_();
        runStagingPlan(Plan.init().emergencyUnstake(range.index, range.stakedTokenId));

        // When: The first holder claims.
        uint256 amountA = almCore.claimEmissions(accountA);

        // Then: It is paid its whole credit.
        assertEq(amountA, FixedPointMathLib.fullMulDiv(balance / 4, almCore.rewardPerShare_(), 1e18));
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(accountA), amountA);

        // And: The second holder is paid what is left of the reward balance.
        uint256 rewardPerShare = almCore.rewardPerShare_();
        uint256 creditB = FixedPointMathLib.fullMulDiv(balance - balance / 4, rewardPerShare, 1e18);
        uint256 left = almCore.getLastRewardBalance();
        uint256 partB = almCore.claimEmissions(accountB);
        assertEq(partB, FixedPointMathLib.min(creditB, left));

        // When: The range restakes, emissions refill the deficit, holder B claims.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked);
        fundShortfall(amount0, amount1);
        runStagingPlan(Plan.init().stake(range.index, range.unstakedTokenId, amount0, amount1, 0, 0));
        closePenaltyWindow(gauge);
        accrueForBlocks(pool, gauge, 1, 4 * emissions);
        uint256 amountB = almCore.claimEmissions(accountB);

        // Then: It is paid the rest of its credit, accrued in two steps.
        creditB += FixedPointMathLib.fullMulDiv(balance - balance / 4, almCore.rewardPerShare_() - rewardPerShare, 1e18);
        assertEq(partB + amountB, creditB);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(accountB), partB + amountB);
    }

    function testFuzz_Success_execute_EmergencyUnstakeOwedOutlivesAFullBurn(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 emissions,
        uint256 shares,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range around the price, staked outside its window.
        {
            int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
            int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
            range.tickLower = int24(bound(range.tickLower, -band + 1, compressed)) * poolState.tickSpacing;
            range.tickUpper = int24(bound(range.tickUpper, compressed + 1, band - 1)) * poolState.tickSpacing;
        }
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);

        // And: A seed holder with aLP.
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: The gauge's emergency withdraw enabled.
        clGaugeFactory.setEmergencyWithdrawEnabled(true);

        // And: Emissions owing the holder a credit, credited, then forfeited.
        uint256 supply = almCore.totalSupply();
        emissions = bound(
            emissions,
            supply.divUp(almCore.balanceOf(users.steward)) + supply.divUp(1e18) + 1,
            Constants.MAX_EMISSIONS / 2
        );
        accrueForBlocks(pool, gauge, 1, emissions);
        almCore.checkpoint_();
        runPlan(Plan.init().emergencyUnstake(range.index, range.stakedTokenId));

        // When: The seed holder burns all its aLP.
        uint256 balance = almCore.balanceOf(users.steward);
        vm.prank(users.steward);
        almCore.burn(balance, users.steward, users.steward);

        // Then: Its credit outlives the shares.
        uint256 owed = FixedPointMathLib.fullMulDiv(balance, almCore.rewardPerShare_(), 1e18);
        assertGt(owed, 0);
        assertEq(almCore.balanceOf(users.steward), 0);
        assertEq(almCore.getPendingReward(users.steward), owed);

        // When: A holder mints, the range restakes, emissions refill, the burner claims.
        token0.mint(accountA, type(uint128).max);
        token1.mint(accountA, type(uint128).max);
        vm.startPrank(accountA);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(bound(shares, 1, balance), accountA);
        vm.stopPrank();
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked);
        fundShortfall(amount0, amount1);
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);
        runPlan(Plan.init().stake(range.index, range.unstakedTokenId, amount0, amount1, 0, 0));
        closePenaltyWindow(gauge);
        accrueForBlocks(pool, gauge, 1, 2 * emissions);
        uint256 amount = almCore.claimEmissions(users.steward);

        // Then: It is paid its whole credit.
        assertEq(amount, owed);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(users.steward), owed);
        assertEq(almCore.getPendingReward(users.steward), 0);
    }

    function testFuzz_Success_execute_EmergencyUnstakeWhileNotMintable(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 pick,
        uint256 blocks,
        uint256 emissions,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range around the price, staked outside its window.
        {
            int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
            int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
            range.tickLower = int24(bound(range.tickLower, -band + 1, compressed)) * poolState.tickSpacing;
            range.tickUpper = int24(bound(range.tickUpper, compressed + 1, band - 1)) * poolState.tickSpacing;
        }
        givenValidRangeState(range, poolState, false, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: The gauge's emergency withdraw enabled.
        clGaugeFactory.setEmergencyWithdrawEnabled(true);

        // And: Emissions accrued on the staked side, then a chain that cannot mint them.
        accrueForBlocks(
            pool, gauge, bound(blocks, 1, type(uint32).max), bound(emissions, MAX_PIPS + 1, Constants.MAX_EMISSIONS)
        );
        setNotMintableStatus(pick);
        uint256 earned = gauge.earned(address(almCore), almCore.stakedTokenIds());
        assertGt(earned, 0);
        uint256 net = earned - earned * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        (,, uint256 total) = almCore.getRewardTotals();
        uint256 highWater = almCore.getRewardHighWater();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper takes the staked side out through the emergency withdraw.
        runPlan(Plan.init().emergencyUnstake(range.index, range.stakedTokenId));

        // Then: The staked side is gone.
        assertEq(almCore.getRange(range.index).stakedTokenId, 0);

        // And: The forfeit leaves the lifetime reward, the high water keeps it.
        (,, uint256 totalAfter) = almCore.getRewardTotals();
        assertEq(totalAfter, total - net);
        assertEq(almCore.getRewardHighWater(), highWater);
    }

    function testFuzz_Success_execute_RunsEveryStepInOrder_EpochEventsLast(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 sold,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A core worth a wei of token1, the core worth zero (audit doc 6.1) excluded.
        vm.assume(vaultValue(sqrtPriceX96(pool), false) > 0);

        // And: Pending requests, a token0 deposit among them.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);

        // And: A sale of the cleared buffer's token0, filled at the price in an amount.
        uint160 sqrtPrice = sqrtPriceX96(pool);
        sold = bound(
            sold,
            1,
            FixedPointMathLib.min(
                almCore.bufferAmount0() + queueState.deposit0, token1ToToken0(sqrtPrice, Constants.MAX_FUZZED_AMOUNT)
            )
        );
        Plan.Steps memory plan = Plan.init()
            .clearAllRequests(true, true)
            .swapAtRate(
                address(token0), address(token1), address(routerTrampoline), true, sold, token0ToToken1(sqrtPrice, sold)
            )
            .settleRequests();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the deposit and then swaps.
        // Then: The swap's token0 transfer, then the epoch's event, then the plan's.
        vm.prank(users.keeper);
        vm.expectEmit(false, false, false, false, address(token0));
        emit ERC20.Transfer(address(almCore), address(routerTrampoline), sold);
        vm.expectEmit(true, false, false, false, address(almCore));
        emit IALMCoreEvents.DepositEpochSettled(asyncVault0, 0, 0, 0);
        vm.expectEmit(false, false, false, false, address(almCore));
        emit IALMCoreEvents.PlanExecuted(0, 0, 0, 0, 0, 0, 0);
        almCore.execute(plan.commands, plan.inputs, sqrtPrice);
    }

    function testFuzz_Success_execute_FinalisationBeforeSolvencyAndShortfall(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint16 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);

        // And: A supply to redeem from, each aLP a quarter amount of token0 at most.
        {
            uint256 supplyFloor = FixedPointMathLib.max(
                almCore.DEAD_SHARES_() + 2,
                (coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0 + 1) + 4)
                .divUp(token0ToToken1(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 4)) + 1
            );
            coreState.supply = bound(
                coreState.supply,
                supplyFloor,
                FixedPointMathLib.max(
                    supplyFloor,
                    FixedPointMathLib.min(
                        coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                        Constants.MAX_FUZZED_AMOUNT
                    )
                )
            );
        }
        setCoreState(coreState);
        setRangeState(range);

        // And: A plan that may lose nothing, and any max swap cost.
        {
            ConfigState memory configState;
            configState.maxSwapCostBps = maxSwapCostBps;
            givenValidPlanLimits(configState, 0, 0);
            setPlanLimits(configState);
            maxSwapCostBps = configState.maxSwapCostBps;
        }

        // And: A token0 buffer worth an aLP and more, and the vault's holdings and value.
        uint160 sqrtPrice = sqrtPriceX96(pool);
        uint256 value;
        uint256 paid;
        uint256 valueAfter;
        {
            (uint256 amount0, uint256 amount1) =
                amountsRoundedDown(sqrtPrice, range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked);
            fundBuffer(
                (amount1 + almCore.bufferAmount1() + token0ToToken1(sqrtPrice, amount0 + almCore.bufferAmount0()) + 1)
                    .divUp(coreState.supply - 1)
                    .fullMulDivUp(1 << 192, uint256(sqrtPrice) * sqrtPrice),
                0
            );
            amount0 += almCore.bufferAmount0();
            amount1 += almCore.bufferAmount1();
            value = amount1 + token0ToToken1(sqrtPrice, amount0);

            // And: A token0 redeem the buffer pays, and no other request.
            givenValidQueueState(queueState, 0, 0, Constants.QUEUE_REDEEM0);
            queueState.redeem0 = bound(
                queueState.redeem0,
                1,
                FixedPointMathLib.min(
                    almCore.balanceOf(users.steward) / 2,
                    token0ToToken1(sqrtPrice, almCore.bufferAmount0()).fullMulDiv(coreState.supply, value)
                )
            );
            setQueueState(queueState);

            // And: The payout at the plan's value, and the value after paying it.
            paid = value.fullMulDiv(queueState.redeem0, coreState.supply)
                .fullMulDiv(1 << 192, uint256(sqrtPrice) * sqrtPrice);
            valueAfter = amount1 + token0ToToken1(sqrtPrice, amount0 - paid);
        }

        // When: The keeper settles the redeem.
        {
            Plan.Steps memory plan = Plan.init().clearAllRequests(true, false).settleRequests();
            vm.prank(users.keeper);
            vm.expectEmit(address(almCore));
            emit IALMCoreEvents.PlanExecuted(
                2, sqrtPrice, value, valueAfter, coreState.supply - queueState.redeem0, 0, 0
            );
            almCore.execute(plan.commands, plan.inputs, sqrtPrice);
        }

        // Then: The solvency and shortfall checks saw the value after net of the payout.
        assertEq(almCore.getEscrowed0(), paid);

        // And: The rate is the supply after the burn over the value after the payout.
        (uint256 supplyPerValueX128,) = almCore.lastExchangeRate_();
        assertEq(supplyPerValueX128, (coreState.supply - queueState.redeem0).fullMulDivUp(1 << 128, valueAfter));
    }

    function testFuzz_Success_execute_SettleOnlyPlanNeverFailsShortfall(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint16 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);

        // And: A supply with aLP to redeem, each worth a quarter amount at most.
        uint256 supplyFloor = FixedPointMathLib.max(
            almCore.DEAD_SHARES_() + 2,
            (coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0 + 2) + 4)
            .divUp(
                FixedPointMathLib.min(
                    token0ToToken1(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 4),
                    Constants.MAX_FUZZED_AMOUNT / 4
                )
            ) + 2
        );
        coreState.supply = bound(
            coreState.supply,
            supplyFloor,
            FixedPointMathLib.max(
                supplyFloor,
                FixedPointMathLib.min(
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                    Constants.MAX_FUZZED_AMOUNT
                )
            )
        );
        setCoreState(coreState);
        setRangeState(range);

        // And: A plan that may lose nothing, and any max swap cost.
        {
            ConfigState memory configState;
            configState.maxSwapCostBps = maxSwapCostBps;
            givenValidPlanLimits(configState, 0, 0);
            setPlanLimits(configState);
            maxSwapCostBps = configState.maxSwapCostBps;
        }

        // And: A buffer holding at least an aLP's worth of each token.
        uint160 sqrtPrice = sqrtPriceX96(pool);
        uint256 priceX192 = uint256(sqrtPrice) * sqrtPrice;
        (uint256 amount0, uint256 amount1) =
            amountsRoundedDown(sqrtPrice, range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked);
        uint256 worth = (amount1 + almCore.bufferAmount1()
                + token0ToToken1(sqrtPrice, amount0 + almCore.bufferAmount0())
                + uint256(1).fullMulDivUp(priceX192, 1 << 192) + 2)
        .divUp(coreState.supply - 2);
        fundBuffer(worth.fullMulDivUp(1 << 192, priceX192), worth);
        uint256 value = amount1 + almCore.bufferAmount1() + token0ToToken1(sqrtPrice, amount0 + almCore.bufferAmount0());

        // And: A deposit in each vault, and a redeem in each vault its buffer pays.
        givenValidQueueState(queueState, 1, 1);
        {
            uint256 ceiling = token0ToToken1(sqrtPrice, almCore.bufferAmount0()).fullMulDiv(coreState.supply, value + 1);
            ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
            queueState.redeem0 = bound(queueState.redeem0, 1, ceiling);
            ceiling = almCore.bufferAmount1().fullMulDiv(coreState.supply, value + 1);
            ceiling = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, ceiling);
            queueState.redeem1 = bound(queueState.redeem1, 1, ceiling);
        }
        setQueueState(queueState);

        // When: The keeper settles all four without a swap.
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .clearAllRequests(true, false)
                .clearAllRequests(false, true)
                .clearAllRequests(false, false)
                .settleRequests()
        );

        // Then: The plan ran, every epoch settled.
        (uint32 pendingDeposit0, uint32 pendingRedeem0) = almCore.pendingEpochs(asyncVault0);
        (uint32 pendingDeposit1, uint32 pendingRedeem1) = almCore.pendingEpochs(asyncVault1);
        assertEq(pendingDeposit0 + pendingRedeem0 + pendingDeposit1 + pendingRedeem1, 4);
    }

    function testFuzz_Success_execute_SettleOnlyPlanChargesTheFullRealisedCost(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 sold,
        uint256 amountOut,
        uint16 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range below the price, so it holds only token1.
        {
            int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
            int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
            range.tickLower = int24(bound(range.tickLower, -band + 1, compressed - 1)) * poolState.tickSpacing;
            range.tickUpper = int24(bound(range.tickUpper, range.tickLower / poolState.tickSpacing + 1, compressed))
                * poolState.tickSpacing;
        }
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 3);

        // And: The least token0, three wei of token1 past the range's, a supply.
        coreState.buffer0 = 1;
        coreState.supply = bound(
            coreState.supply,
            almCore.DEAD_SHARES_(),
            FixedPointMathLib.max(
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.min(
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                    Constants.MAX_FUZZED_AMOUNT
                )
            )
        );
        setCoreState(coreState);
        setRangeState(range);

        // And: A plan that may lose nothing, and a max swap cost.
        {
            ConfigState memory configState;
            configState.maxSwapCostBps = maxSwapCostBps;
            givenValidPlanLimits(configState, 0, 0);
            setPlanLimits(configState);
            maxSwapCostBps = configState.maxSwapCostBps;
        }

        // And: A token0 deposit worth four wei of token0 and more, no other request.
        uint160 sqrtPrice = sqrtPriceX96(pool);
        {
            uint256 depositFloor = (4 * uint256(1).fullMulDivUp(uint256(sqrtPrice) * sqrtPrice, 1 << 192) + 6)
            .fullMulDivUp(1 << 192, uint256(sqrtPrice) * sqrtPrice);
            givenValidQueueState(queueState, depositFloor, 0, Constants.QUEUE_DEPOSIT0);
            queueState.deposit0 = bound(
                queueState.deposit0,
                depositFloor,
                FixedPointMathLib.max(depositFloor, token1ToToken0(sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 4))
            );
        }
        setQueueState(queueState);
        uint256 depositValue = token0ToToken1(sqrtPrice, queueState.deposit0);

        // And: A token1 buffer worth at least the token0 held and the deposit.
        (, uint256 holdings1) =
            amountsRoundedDown(sqrtPrice, range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked);
        uint256 holdings0 = almCore.bufferAmount0();
        fundBuffer(
            0,
            (token0ToToken1(sqrtPrice, holdings0) + depositValue + 2).zeroFloorSub(holdings1 + almCore.bufferAmount1())
        );
        holdings1 += almCore.bufferAmount1();
        uint256 value = holdings1 + token0ToToken1(sqrtPrice, holdings0);

        // And: A sale within its net trade and the deposit, filled to the floor.
        sold = bound(
            sold,
            uint256(1).fullMulDivUp(1 << 192, uint256(sqrtPrice) * sqrtPrice),
            token1ToToken0(
                sqrtPrice,
                FixedPointMathLib.min(
                    depositValue.fullMulDiv(
                        holdings1, token0ToToken1(sqrtPrice, holdings0) + depositValue + holdings1 + 2
                    ),
                    depositValue - 3
                )
            )
        );
        amountOut = bound(
            amountOut,
            token0ToToken1(sqrtPrice, sold)
                .fullMulDivUp(ConfigLib.BPS_DENOMINATOR - maxSwapCostBps, ConfigLib.BPS_DENOMINATOR),
            token0ToToken1(sqrtPrice, sold)
        );

        // When: The keeper settles the deposit and swaps.
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .swapAtRate(address(token0), address(token1), address(routerTrampoline), true, sold, amountOut)
                .settleRequests()
        );

        // Then: The deposit pays the swap's whole cost at the trusted price.
        uint256 supply = coreState.supply;
        uint256 valueAfter = holdings1 + amountOut + token0ToToken1(sqrtPrice, holdings0 + queueState.deposit0 - sold);
        uint256 shares = almCore.depositEpoch(asyncVault0, 0).amountOut;
        uint256 cost = CLMath.convert(sqrtPrice, true, sold, true) - amountOut;
        uint256 valueUp =
            holdings1 + CLMath.convert(sqrtPrice, true, holdings0, true) + amountOut - token0ToToken1(sqrtPrice, sold);
        uint256 expected = (depositValue - cost).fullMulDiv(supply, valueUp + cost);
        assertEq(shares, expected);

        // And: The stayers keep their value per share.
        assertGe(valueAfter.fullMulDiv(supply, supply + shares), value);
    }

    function testFuzz_Success_execute_FlowsSwapAloneLeavesTheStartSetWhole(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 amountOut,
        uint16 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range above the price, so it holds only token0.
        {
            int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
            int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
            range.tickLower = int24(bound(range.tickLower, compressed + 1, band - 2)) * poolState.tickSpacing;
        }
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);

        // And: A seed holding the least token1, and a supply up to its value.
        coreState.buffer1 = 1;
        coreState.supply = bound(
            coreState.supply,
            almCore.DEAD_SHARES_(),
            FixedPointMathLib.max(
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.min(
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                    Constants.MAX_FUZZED_AMOUNT
                )
            )
        );
        setCoreState(coreState);
        setRangeState(range);

        // And: A plan that may lose nothing, and a max swap cost.
        {
            ConfigState memory configState;
            configState.maxSwapCostBps = maxSwapCostBps;
            givenValidPlanLimits(configState, 0, 1);
            setPlanLimits(configState);
            maxSwapCostBps = configState.maxSwapCostBps;
        }

        // And: A token1 deposit buying a token0 wei within the floor, alone.
        uint160 sqrtPrice = sqrtPriceX96(pool);
        {
            uint256 depositFloor = (uint256(1).fullMulDivUp(1 << 192, uint256(sqrtPrice) * sqrtPrice)
                    * ConfigLib.BPS_DENOMINATOR)
            .fullMulDivUp(uint256(sqrtPrice) * sqrtPrice, 1 << 192);
            givenValidQueueState(queueState, 0, depositFloor, Constants.QUEUE_DEPOSIT1);
            queueState.deposit1 = bound(
                queueState.deposit1,
                depositFloor,
                FixedPointMathLib.max(depositFloor, token0ToToken1(sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 4))
            );
        }
        setQueueState(queueState);

        // And: A token0 buffer worth at least the deposit.
        (uint256 holdings0,) =
            amountsRoundedDown(sqrtPrice, range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked);
        fundBuffer(
            queueState.deposit1
                .fullMulDivUp(1 << 192, uint256(sqrtPrice) * sqrtPrice)
                .zeroFloorSub(holdings0 + almCore.bufferAmount0()),
            0
        );
        holdings0 += almCore.bufferAmount0();
        uint256 holdings1 = almCore.bufferAmount1();

        // And: The whole deposit spent on token0, filled at the price within the floor.
        amountOut = bound(
            amountOut,
            FixedPointMathLib.max(
                token1ToToken0(sqrtPrice, queueState.deposit1)
                    .fullMulDivUp(ConfigLib.BPS_DENOMINATOR - maxSwapCostBps, ConfigLib.BPS_DENOMINATOR),
                uint256(1).fullMulDivUp(1 << 192, uint256(sqrtPrice) * sqrtPrice)
            ),
            token1ToToken0(sqrtPrice, queueState.deposit1)
        );

        // When: The keeper settles the deposit and buys token0 with it.
        runPlan(
            Plan.init()
                .clearAllRequests(false, true)
                .swapAtRate(
                    address(token0), address(token1), address(routerTrampoline), false, queueState.deposit1, amountOut
                )
                .settleRequests()
        );

        // Then: The plan passed the shortfall check, the deposit paying the whole swap.
        uint256 swapped = token0ToToken1(sqrtPrice, amountOut);
        uint256 cost = swapped != 0 ? queueState.deposit1.zeroFloorSub(swapped) : 0;
        uint256 valueUp = holdings1 + CLMath.convert(sqrtPrice, true, holdings0, true)
            + CLMath.convert(sqrtPrice, true, amountOut, true) - queueState.deposit1;
        assertEq(
            almCore.depositEpoch(asyncVault1, 0).amountOut,
            (queueState.deposit1 - cost).fullMulDiv(coreState.supply, valueUp + cost)
        );
    }

    function testFuzz_Success_execute_FlowCostNotNettedAgainstAGain(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 sold,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range around the price, a spacing below it at least.
        {
            int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
            int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
            range.tickLower = int24(bound(range.tickLower, -band + 1, compressed - 1)) * poolState.tickSpacing;
            range.tickUpper = int24(bound(range.tickUpper, compressed + 1, band - 1)) * poolState.tickSpacing;
        }
        givenValidRangeState(range, poolState, false, false);

        // And: No staked leg, an unstaked leg a fee-paying sale worth a 16th reaches.
        {
            uint256 priceUp = uint256(1).fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192);
            uint256 perLiquidity = (uint256(1) << 192) / TickMath.getSqrtPriceAtTick(range.tickLower)
                - (uint256(1) << 192) / poolState.sqrtPrice;
            range.liquidity = uint128(
                bound(
                    range.liquidity,
                    FixedPointMathLib.max(
                        FixedPointMathLib.max(
                            Constants.MIN_FUZZED_LIQUIDITY,
                            uint256(poolState.liquidityPool)
                                .fullMulDivUp(
                                    48e6 * priceUp, Constants.MAX_FUZZED_AMOUNT * poolState.fee - 48e6 * priceUp
                                )
                        ),
                        (uint256(4e6) << 96).divUp(poolState.fee * perLiquidity)
                    ),
                    liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
                )
            );
        }
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: The token0 a sale needs to pay the range a fee, and that the range takes.
        uint160 sqrtPrice = sqrtPriceX96(pool);
        {
            uint256 least = FixedPointMathLib.max(
                (3 * uint256(pool.liquidity())).divUp(range.liquidity).fullMulDivUp(MAX_PIPS, pool.fee()),
                leastSwapIn(true)
            );
            uint256 inside = FixedPointMathLib.min(
                uint256(pool.liquidity()).fullMulDiv(1 << 96, TickMath.getSqrtPriceAtTick(range.tickLower))
                    - uint256(pool.liquidity()).fullMulDiv(1 << 96, sqrtPrice),
                FixedPointMathLib.max(least, uint256(pool.liquidity()).fullMulDiv(1 << 96, sqrtPrice))
            );

            // And: A buffer holding that sale's token0, and token1 worth twice it.
            fundBuffer(least.zeroFloorSub(almCore.bufferAmount0()), 0);
            (uint256 amount0, uint256 amount1) =
                amountsRoundedDown(sqrtPrice, range.tickLower, range.tickUpper, range.liquidity);
            fundBuffer(
                0,
                (2 * least.fullMulDivUp(uint256(sqrtPrice) * sqrtPrice, 1 << 192) + 4)
                .zeroFloorSub(
                    amount1 + almCore.bufferAmount1() + token0ToToken1(sqrtPrice, amount0 + almCore.bufferAmount0())
                )
            );

            // And: A pending token0 deposit and no other request.
            givenValidQueueState(queueState, 1, 0, Constants.QUEUE_DEPOSIT0);
            setQueueState(queueState);

            // And: A token0 sale paying the range a fee, above half the price.
            (amount0, amount1) = amountsRoundedDown(sqrtPrice, range.tickLower, range.tickUpper, range.liquidity);
            sold = bound(
                sold,
                least,
                FixedPointMathLib.min(
                    FixedPointMathLib.min(almCore.bufferAmount0() + queueState.deposit0, inside),
                    token1ToToken0(
                        sqrtPrice,
                        (amount1
                                + almCore.bufferAmount1()
                                + token0ToToken1(sqrtPrice, amount0 + almCore.bufferAmount0())) / 2
                    )
                )
            );
        }
        uint256 buffer0 = almCore.bufferAmount0();
        uint256 buffer1 = almCore.bufferAmount1();
        {
            Plan.Steps memory plan;
            {
                bytes memory path = abi.encodePacked(address(token0), poolState.tickSpacing, address(token1));
                uint256 amountIn = sold;
                plan = Plan.init()
                    .clearAllRequests(true, true)
                    .swapViaRouter(
                        address(SWAP_ROUTER),
                        amountIn,
                        true,
                        0,
                        abi.encodeCall(
                            IMetadexSwapRouter.exactInput,
                            IMetadexSwapRouter.ExactInputParams({
                                path: path,
                                recipient: address(routerTrampoline),
                                deadline: type(uint256).max,
                                amountIn: amountIn,
                                amountOutMinimum: 0
                            })
                        )
                    )
                    .settleRequests()
                    .collect(range.unstakedTokenId);
            }

            // And: Plan limits above the swap's cost and the plan's loss.
            givenValidPlanLimits(configState, 3, true, sold, poolSwapOut(true, sold));
            setPlanLimits(configState);

            // When: The keeper settles, swaps and collects the range's fees in one plan.
            runPlan(plan);
        }

        // Then: The plan gained the range's fees.
        assertGt(almCore.bufferAmount0(), buffer0 + queueState.deposit0 - sold);

        // And: The deposit's levy is the swap's whole cost, later fees left out.
        uint256 shares;
        {
            (uint256 amount0, uint256 amount1) =
                amountsRoundedDown(sqrtPrice, range.tickLower, range.tickUpper, range.liquidity);
            uint256 bought = almCore.bufferAmount1() - buffer1;
            uint256 cost = CLMath.convert(sqrtPrice, true, sold, true).zeroFloorSub(bought);
            uint256 depositValue = token0ToToken1(sqrtPrice, queueState.deposit0);
            uint256 supply = coreState.supply;
            uint256 swapped = token0ToToken1(sqrtPrice, sold);
            uint256 value =
                amount1 + buffer1 + bought + CLMath.convert(sqrtPrice, true, amount0 + buffer0, true) - swapped;
            amount0 = amount0 + buffer0 + queueState.deposit0 - sold;
            amount0 = token0ToToken1(sqrtPrice, amount0);
            amount1 += buffer1 + bought;
            uint256 levy;
            if (cost != 0 && swapped != 0) {
                uint256 depositSwap = depositValue.fullMulDiv(amount1, amount0 + amount1);
                if (depositSwap != 0) {
                    levy = cost.fullMulDivUp(FixedPointMathLib.min(depositSwap, swapped), swapped);
                    levy = FixedPointMathLib.min(levy, depositValue);
                }
            }
            if (depositValue != levy) shares = (depositValue - levy).fullMulDiv(supply, value + levy);
        }
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountOut, shares);
    }

    function testFuzz_Success_execute_FourSettlesInEveryOrderAgree(
        RangeState memory range,
        ConfigState memory configState,
        uint256 order,
        uint256 sold,
        uint256 amountOut,
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);

        // And: A supply with aLP to redeem, each worth a quarter amount at most.
        {
            uint256 supplyFloor = FixedPointMathLib.max(
                almCore.DEAD_SHARES_() + 2,
                (coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0 + 3) + 16)
                .divUp(
                    FixedPointMathLib.min(
                        token0ToToken1(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 4),
                        Constants.MAX_FUZZED_AMOUNT / 4
                    )
                ) + 2
            );
            coreState.supply = bound(
                coreState.supply,
                supplyFloor,
                FixedPointMathLib.max(
                    supplyFloor,
                    FixedPointMathLib.min(
                        coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0),
                        Constants.MAX_FUZZED_AMOUNT
                    )
                )
            );
        }
        setCoreState(coreState);
        setRangeState(range);

        // And: A buffer holding an aLP's worth of each token and more, and the holdings.
        (uint256 held0, uint256 held1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        {
            uint256 worth = (held1 + almCore.bufferAmount1()
                    + token0ToToken1(poolState.sqrtPrice, held0 + almCore.bufferAmount0())
                    + uint256(2).fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192) + 8)
            .divUp(coreState.supply - 2);
            fundBuffer(worth.fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice) + 1, worth);
        }
        held0 += almCore.bufferAmount0();
        held1 += almCore.bufferAmount1();
        {
            uint256 holdingsValue = held1 + token0ToToken1(poolState.sqrtPrice, held0);

            // And: A deposit in each vault, a redeem in each its buffer pays past a sale.
            givenValidQueueState(queueState, 1, 1);
            queueState.redeem0 = bound(
                queueState.redeem0,
                1,
                FixedPointMathLib.min(
                    almCore.balanceOf(users.steward) / 2,
                    token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() - 1)
                        .fullMulDiv(coreState.supply, holdingsValue + 5)
                )
            );
            queueState.redeem1 = bound(
                queueState.redeem1,
                1,
                FixedPointMathLib.min(
                    almCore.balanceOf(users.steward) / 2,
                    almCore.bufferAmount1().fullMulDiv(coreState.supply, holdingsValue + 5)
                )
            );
            setQueueState(queueState);

            // And: Plan limits storage holds.
            givenValidPlanLimits(configState, 0, 0);

            // And: A sale of the token0 the redeem leaves, its fee within the bounds.
            sold = bound(
                sold,
                1,
                FixedPointMathLib.min(
                    almCore.bufferAmount0()
                        - (holdingsValue + 5)
                            .fullMulDivUp(queueState.redeem0, coreState.supply)
                            .fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice),
                    token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT)
                )
            );
            amountOut = token0ToToken1(poolState.sqrtPrice, sold);
            amountOut = bound(
                amountOut,
                amountOut
                    - FixedPointMathLib.min(holdingsValue - 3, maxSwapLoss(amountOut, configState.maxSwapCostBps)),
                amountOut
            );
        }

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(7, token0ToToken1(poolState.sqrtPrice, sold) - amountOut),
            leastSwapCostBps(true, sold, amountOut)
        );
        setPlanLimits(configState);

        // When: The four settles run in a fuzzed permutation, the sale after them.
        {
            Plan.Steps memory permuted = Plan.init();
            {
                Plan.Steps memory settles = Plan.init()
                    .clearAllRequests(true, true)
                    .clearAllRequests(true, false)
                    .clearAllRequests(false, true)
                    .clearAllRequests(false, false);
                order = bound(order, 0, 23);
                uint256[4] memory steps = [uint256(0), 1, 2, 3];
                for (uint256 i = 4; i > 0; --i) {
                    uint256 pick = order % i;
                    order /= i;
                    permuted = permuted.add(uint8(settles.commands[steps[pick]]), settles.inputs[steps[pick]]);
                    steps[pick] = steps[i - 1];
                }
            }
            permuted = permuted.swapAtRate(
                address(token0), address(token1), address(routerTrampoline), true, sold, amountOut
            );
            runPlan(permuted.settleRequests());
        }

        // Then: Every epoch settles at the definition, whatever the order.
        uint256 valueBefore = held1 + token0ToToken1(poolState.sqrtPrice, held0);
        uint256 supply = coreState.supply;
        uint256 sqrtPrice = poolState.sqrtPrice;
        uint256 swapped = token0ToToken1(sqrtPrice, sold);
        uint256 cost = CLMath.convert(sqrtPrice, true, sold, true) - amountOut;
        uint256 depositValue = token0ToToken1(sqrtPrice, queueState.deposit0);
        uint256 valueUp = held1 + CLMath.convert(sqrtPrice, true, held0, true) - (swapped - amountOut);
        held0 = token0ToToken1(sqrtPrice, held0 + queueState.deposit0 - sold);
        held1 += queueState.deposit1 + amountOut;
        uint256 value = valueBefore.zeroFloorSub(cost);
        uint256 redeemLevy;
        {
            uint256 offset = queueState.deposit1;
            uint256 redeemValue0 = queueState.redeem0;
            redeemValue0 = redeemValue0.fullMulDiv(value, supply);
            held0 = held0.zeroFloorSub(redeemValue0);
            uint256 redeemValue1 = queueState.redeem1;
            redeemValue1 = redeemValue1.fullMulDiv(value, supply);
            held1 = held1.zeroFloorSub(redeemValue1);
            uint256 holdings0 = held0;
            uint256 holdings1 = held1;
            if (swapped != 0 && holdings0 + holdings1 != 0) {
                offset = offset.fullMulDiv(holdings0, holdings0 + holdings1);
                offset += redeemValue0.fullMulDiv(holdings1, holdings0 + holdings1);
                uint256 depositSwap = depositValue.fullMulDiv(holdings1, holdings0 + holdings1);
                uint256 redeemSwap = redeemValue1.fullMulDiv(holdings0, holdings0 + holdings1);
                if (depositSwap + redeemSwap > offset) {
                    cost = cost.fullMulDivUp(FixedPointMathLib.min(swapped, depositSwap + redeemSwap - offset), swapped);
                    redeemLevy =
                        FixedPointMathLib.min(cost.fullMulDivUp(redeemSwap, depositSwap + redeemSwap), redeemValue1);
                    cost = FixedPointMathLib.min(cost.fullMulDivUp(depositSwap, depositSwap + redeemSwap), depositValue);
                    value += cost;
                    valueUp += cost;
                    depositValue -= cost;
                }
            }
        }
        value += redeemLevy;
        valueUp += redeemLevy;
        valueBefore = FixedPointMathLib.min(value, valueBefore);
        uint256 payout0 = queueState.redeem0;
        payout0 = payout0.fullMulDiv(valueBefore, supply).fullMulDiv(1 << 192, sqrtPrice * sqrtPrice);
        uint256 payout1 = queueState.redeem1;
        payout1 = payout1.fullMulDiv(valueBefore, supply) - redeemLevy;
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountOut, payout0);
        assertEq(almCore.redeemEpoch(asyncVault1, 0).amountOut, payout1);
        uint256 shares0 = depositValue == 0 ? 0 : depositValue.fullMulDiv(supply, valueUp);
        uint256 shares1 = queueState.deposit1;
        shares1 = shares1.fullMulDiv(supply, valueUp);
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountOut, shares0);
        assertEq(almCore.depositEpoch(asyncVault1, 0).amountOut, shares1);

        // And: The payouts sit in token escrow and the minted shares in aLP escrow.
        assertEq(almCore.getEscrowed0(), payout0);
        assertEq(almCore.getEscrowed1(), payout1);
        assertEq(almCore.balanceOf(address(almCore)), shares0 + shares1);
    }
}
