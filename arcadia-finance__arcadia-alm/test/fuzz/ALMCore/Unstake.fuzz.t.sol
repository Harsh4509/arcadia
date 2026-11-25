/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { CalldataLogic } from "../../../src/core/libraries/logic/CalldataLogic.sol";
import { CommandLogic } from "../../../src/core/libraries/logic/CommandLogic.sol";
import { Config } from "../../../src/core/types/State.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { IArbSys } from "../../../src/interfaces/IArbSys.sol";
import { Plan } from "../../utils/Plan.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { RangesLib } from "../../../src/core/libraries/state/RangesLib.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";

/**
 * @notice Fuzz tests for the function "unstake" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events, unsafe-typecast, unused-return)
contract Unstake_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_unstake_OnlyKeeper(
        address caller,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: A caller that is not the keeper.
        vm.assume(caller != users.keeper);
        Plan.Steps memory plan = Plan.init()
            .unstake(
                range.index,
                almCore.getRange(range.index).stakedTokenId,
                almCore.getRange(range.index).stakedLiquidity,
                0,
                0,
                false
            );
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling unstake().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ALMKeeperExtension.OnlyKeeper.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_unstake_InvalidPayload(
        PoolState memory poolState,
        uint256 length,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An unstake payload up to twice its length, of any length but its own.
        length = bound(length, 0, 2 * CalldataLogic.UNSTAKE_LENGTH);
        vm.assume(length != CalldataLogic.UNSTAKE_LENGTH);
        Plan.Steps memory plan = Plan.init().add(CommandLogic.UNSTAKE, new bytes(length));
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

    function testFuzz_Revert_unstake_RangeMismatch_OutOfBounds(
        PoolState memory poolState,
        uint256 index,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No ranges at all, and a step naming one.
        index = bound(index, 0, type(uint8).max);
        Plan.Steps memory plan = Plan.init().unstake(index, Sentinels.OPENED, Sentinels.RANGE_LIQUIDITY, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: It reverts instead of panicking on the array read.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_unstake_RangeMismatch_UnstakedTokenId(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg, and a step naming it by its unstaked token id.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        Plan.Steps memory plan = Plan.init()
            .unstake(
                range.index,
                almCore.getRange(range.index).unstakedTokenId,
                almCore.getRange(range.index).stakedLiquidity,
                0,
                0,
                false
            );
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls unstake().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, range.index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_unstake_RangeMismatch_NotOpenedInThePlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A staked range from an earlier plan, named by the opened sentinel.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        Plan.Steps memory plan = Plan.init().unstake(range.index, Sentinels.OPENED, range.liquidityStaked, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls unstake().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, range.index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_unstake_RangeMismatch_StaleTokenIdAfterDrain(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range whose staked leg an earlier plan drained.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        runPlan(Plan.init().unstake(range.index, range.stakedTokenId, Sentinels.RANGE_LIQUIDITY, 0, 0, false));

        // And: A step naming the drained leg by its old token id.
        Plan.Steps memory plan =
            Plan.init().unstake(range.index, range.stakedTokenId, Sentinels.RANGE_LIQUIDITY, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, range.index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_unstake_RangeNotStaked(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range without a staked leg.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Plan.Steps memory plan = Plan.init()
            .unstake(
                range.index,
                almCore.getRange(range.index).stakedTokenId,
                almCore.getRange(range.index).stakedLiquidity,
                0,
                0,
                false
            );
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls unstake().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(RangesLib.RangeNotStaked.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_unstake_PenaltyWindowOpen(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 blocksPassed,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        vm.roll(vm.getBlockNumber() + bound(blocksPassed, 0, clGaugeFactory.minStakeBlocks(address(gauge)) - 1));
        Plan.Steps memory plan = Plan.init()
            .unstake(
                range.index,
                almCore.getRange(range.index).stakedTokenId,
                almCore.getRange(range.index).stakedLiquidity,
                0,
                0,
                false
            );
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls unstake().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(RangesLib.PenaltyWindowOpen.selector, range.stakedTokenId));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_unstake_PenaltyWindowOpen_ArbBlock(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 stakedBlock,
        uint256 blocksPassed,
        uint256 arbBlocksPassed,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core whose gauge counts blocks with ArbSys.arbBlockNumber.
        Config memory config = coreViewLogic.getConfig(address(almCore));
        config.arbBlockNumber = true;
        almCore.setConfig(config);
        vm.etch(Constants.ARB_SYS, hex"00");

        // And: A range with a staked leg, staked at a fuzzed arb block.
        stakedBlock = bound(stakedBlock, 0, type(uint32).max);
        vm.mockCall(Constants.ARB_SYS, abi.encodeCall(IArbSys.arbBlockNumber, ()), abi.encode(stakedBlock));
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: The block number far past the window, the arb block still inside it.
        uint256 minStakeBlocks = clGaugeFactory.minStakeBlocks(address(gauge));
        vm.roll(vm.getBlockNumber() + minStakeBlocks + bound(blocksPassed, 0, type(uint32).max));
        vm.mockCall(
            Constants.ARB_SYS,
            abi.encodeCall(IArbSys.arbBlockNumber, ()),
            abi.encode(stakedBlock + bound(arbBlocksPassed, 0, minStakeBlocks - 1))
        );
        Plan.Steps memory plan = Plan.init()
            .unstake(
                range.index,
                almCore.getRange(range.index).stakedTokenId,
                almCore.getRange(range.index).stakedLiquidity,
                0,
                0,
                false
            );
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls unstake().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(RangesLib.PenaltyWindowOpen.selector, range.stakedTokenId));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_unstake_PenaltyWindowOpen_PartialDecrease(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 blocksPassed,
        uint128 liquidityRemoved,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg, inside its penalty window.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        vm.roll(vm.getBlockNumber() + bound(blocksPassed, 0, clGaugeFactory.minStakeBlocks(address(gauge)) - 1));

        // And: A step removing part of the leg without accepting the penalty.
        liquidityRemoved = uint128(bound(liquidityRemoved, 1, range.liquidityStaked - 1));
        Plan.Steps memory plan = Plan.init().unstake(range.index, range.stakedTokenId, liquidityRemoved, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(RangesLib.PenaltyWindowOpen.selector, range.stakedTokenId));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_unstake_PenaltyWindowOpen_SecondUnstakeInThePlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityRemoved,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg, outside its penalty window.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: A plan removing part of the leg, then the rest, not accepting the penalty.
        liquidityRemoved = uint128(bound(liquidityRemoved, 1, range.liquidityStaked - 1));
        Plan.Steps memory plan = Plan.init()
            .unstake(range.index, range.stakedTokenId, liquidityRemoved, 0, 0, false)
            .unstake(range.index, range.stakedTokenId, Sentinels.RANGE_LIQUIDITY, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: It reverts, the first step's restake having opened a new window.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(RangesLib.PenaltyWindowOpen.selector, range.stakedTokenId));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_unstake_PriceSlippageCheck(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityRemoved,
        uint256 amountMin,
        bool minOnToken0,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        liquidityRemoved = uint128(bound(liquidityRemoved, 1, range.liquidityStaked));

        // And: A minimum above what the removed liquidity releases of one token.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityRemoved);
        amountMin = bound(amountMin, (minOnToken0 ? amount0 : amount1) + 1, type(uint256).max);
        Plan.Steps memory plan = Plan.init()
            .unstake(
                range.index,
                range.stakedTokenId,
                liquidityRemoved,
                minOnToken0 ? amountMin : 0,
                minOnToken0 ? 0 : amountMin,
                false
            );
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls unstake().
        // Then: It reverts with the position manager's slippage check.
        vm.prank(users.keeper);
        vm.expectRevert(bytes("PS"));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_unstake_RemovesMoreThanTheSide(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 extra,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg, outside its penalty window.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: A step removing more than the leg holds, short of the whole-side sentinel.
        uint128 liquidity =
            range.liquidityStaked + uint128(bound(extra, 1, Sentinels.RANGE_LIQUIDITY - 1 - range.liquidityStaked));
        Plan.Steps memory plan = Plan.init().unstake(range.index, range.stakedTokenId, liquidity, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: It reverts with the position manager's bare liquidity check.
        vm.prank(users.keeper);
        vm.expectRevert(bytes(""));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_unstake_ZeroLiquidity(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg, outside its penalty window.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: A step removing no liquidity.
        Plan.Steps memory plan = Plan.init().unstake(range.index, range.stakedTokenId, 0, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: It reverts with the position manager's bare liquidity check.
        vm.prank(users.keeper);
        vm.expectRevert(bytes(""));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_unstake(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool acceptPenalty,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Range memory before = almCore.getRange(range.index);
        uint256 positionsBefore = POSITION_MANAGER.totalSupply();
        closePenaltyWindow(gauge);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls unstake(), accepting the penalty or not.
        Plan.Steps memory plan = Plan.init()
            .unstake(
                range.index,
                almCore.getRange(range.index).stakedTokenId,
                almCore.getRange(range.index).stakedLiquidity,
                0,
                0,
                acceptPenalty
            );
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.Unstaked(range.index, range.stakedTokenId);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The staked leg is burned and the unstaked one is untouched.
        Range memory staged = almCore.getRange(range.index);
        assertEq(staged.stakedTokenId, 0);
        assertEq(staged.stakedLiquidity, 0);
        assertEq(staged.unstakedTokenId, before.unstakedTokenId);
        assertEq(positionLiquidity(staged.unstakedTokenId), positionLiquidity(before.unstakedTokenId));
        assertFalse(gauge.stakedContains(address(almCore), range.stakedTokenId));
        assertEq(POSITION_MANAGER.totalSupply(), positionsBefore - 1);
    }

    function testFuzz_Success_unstake_PartialLeavesTheLegStaked(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 removedBps,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Range memory before = almCore.getRange(range.index);
        closePenaltyWindow(gauge);
        uint128 liquidity = uint128(bound(removedBps, 1, before.stakedLiquidity - 1));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager removes part of the staked leg.
        runPlan(Plan.init().unstake(range.index, almCore.getRange(range.index).stakedTokenId, liquidity, 0, 0, false));

        // Then: The same leg is back in the gauge, shrunk by what was removed.
        Range memory staged = almCore.getRange(range.index);
        assertEq(staged.stakedTokenId, range.stakedTokenId);
        assertEq(staged.stakedLiquidity, before.stakedLiquidity - liquidity);
        assertEq(staged.stakedLiquidity, positionLiquidity(range.stakedTokenId));
        assertTrue(gauge.stakedContains(address(almCore), range.stakedTokenId));
        assertEq(positionLiquidity(staged.unstakedTokenId), positionLiquidity(before.unstakedTokenId));

        // And: The leg was restaked now, the window end moved to its new window's end.
        assertEq(staged.stakedBlock, vm.getBlockNumber());
        assertEq(almCore.getWindowEnd(), vm.getBlockNumber() + clGaugeFactory.minStakeBlocks(address(gauge)));
    }

    function testFuzz_Success_unstake_PartialReturnsPrincipalToBuffer(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityRemoved,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg, outside its penalty window.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: Part of the leg to remove, and its principal rounded down by the pool.
        liquidityRemoved = uint128(bound(liquidityRemoved, 1, range.liquidityStaked - 1));
        (uint256 amount0, uint256 amount1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityRemoved);
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager removes part of the staked leg.
        runPlan(Plan.init().unstake(range.index, range.stakedTokenId, liquidityRemoved, 0, 0, false));

        // Then: The released principal is back in the buffer.
        assertEq(almCore.bufferAmount0() - buffer0Before, amount0);
        assertEq(almCore.bufferAmount1() - buffer1Before, amount1);
    }

    function testFuzz_Success_unstake_AcceptPenaltyPartialInsideTheWindow(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 blocksPassed,
        uint128 liquidityRemoved,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg, inside its penalty window.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        vm.roll(vm.getBlockNumber() + bound(blocksPassed, 0, clGaugeFactory.minStakeBlocks(address(gauge)) - 1));
        liquidityRemoved = uint128(bound(liquidityRemoved, 1, range.liquidityStaked - 1));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager removes part of the staked leg, accepting the penalty.
        runPlan(Plan.init().unstake(range.index, range.stakedTokenId, liquidityRemoved, 0, 0, true));

        // Then: The same leg is back in the gauge, shrunk by what was removed.
        Range memory staged = almCore.getRange(range.index);
        assertEq(staged.stakedTokenId, range.stakedTokenId);
        assertEq(staged.stakedLiquidity, range.liquidityStaked - liquidityRemoved);
        assertTrue(gauge.stakedContains(address(almCore), range.stakedTokenId));

        // And: The leg was restaked in this block.
        assertEq(staged.stakedBlock, vm.getBlockNumber());
    }

    function testFuzz_Success_unstake_MinAtTheRelease(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityRemoved,
        bool minOnToken0,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg, outside its penalty window.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: A minimum equal to what the removed liquidity releases of one token.
        liquidityRemoved = uint128(bound(liquidityRemoved, 1, range.liquidityStaked));
        (uint256 amount0, uint256 amount1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityRemoved);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager removes it with that minimum.
        runPlan(
            Plan.init()
                .unstake(
                    range.index,
                    range.stakedTokenId,
                    liquidityRemoved,
                    minOnToken0 ? amount0 : 0,
                    minOnToken0 ? 0 : amount1,
                    false
                )
        );

        // Then: The leg shrank by what was removed.
        assertEq(almCore.getRange(range.index).stakedLiquidity, range.liquidityStaked - liquidityRemoved);
    }

    function testFuzz_Success_unstake_ClaimsOrDefersTheEmissionsByChainStatus(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 blocks,
        uint256 emissions,
        bool mintable,
        uint256 pick,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price, staked past its window, with emissions accrued.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        accrueForBlocks(pool, gauge, bound(blocks, 1, type(uint32).max), bound(emissions, 2, Constants.MAX_EMISSIONS));

        // And: A fuzzed chain status, what the leg earned and the core's reward balance.
        if (mintable) setMintableStatus(pick);
        else setNotMintableStatus(pick);
        uint256 earned = gauge.earned(address(almCore), almCore.stakedTokenIds());
        assertGt(earned, 0);
        uint256 rewardBalance = ERC20(almCore.REWARD_TOKEN_()).balanceOf(address(almCore));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager removes the whole staked leg.
        runPlan(
            Plan.init()
                .unstake(range.index, range.stakedTokenId, almCore.getRange(range.index).stakedLiquidity, 0, 0, false)
        );

        // Then: A minting chain paid the core the emissions, else the gauge deferred.
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(address(almCore)), rewardBalance + (mintable ? earned : 0));
        assertEq(gauge.deferredEmissions(address(almCore)), mintable ? 0 : earned);
    }

    function testFuzz_Success_unstake_PartialClaimsOrDefersTheEmissions(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 blocks,
        uint256 emissions,
        bool mintable,
        uint256 pick,
        uint128 liquidityRemoved,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price, staked past its window, with emissions accrued.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        accrueForBlocks(pool, gauge, bound(blocks, 1, type(uint32).max), bound(emissions, 2, Constants.MAX_EMISSIONS));

        // And: A fuzzed chain status, what the leg earned and the core's reward balance.
        if (mintable) setMintableStatus(pick);
        else setNotMintableStatus(pick);
        uint256 earned = gauge.earned(address(almCore), almCore.stakedTokenIds());
        assertGt(earned, 0);
        uint256 rewardBalance = ERC20(almCore.REWARD_TOKEN_()).balanceOf(address(almCore));
        liquidityRemoved = uint128(bound(liquidityRemoved, 1, range.liquidityStaked - 1));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager removes part of the staked leg.
        runPlan(Plan.init().unstake(range.index, range.stakedTokenId, liquidityRemoved, 0, 0, false));

        // Then: A minting chain paid the emissions, else the gauge deferred them.
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(address(almCore)), rewardBalance + (mintable ? earned : 0));
        assertEq(gauge.deferredEmissions(address(almCore)), mintable ? 0 : earned);
    }

    function testFuzz_Success_unstake_AcceptPenaltyInsideTheWindow(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 blocksPassed,
        uint256 emissions,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price, staked inside its window, emissions accrued.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        accrueForBlocks(
            pool,
            gauge,
            bound(blocksPassed, 0, clGaugeFactory.minStakeBlocks(address(gauge)) - 1),
            bound(emissions, 1, Constants.MAX_EMISSIONS)
        );

        // And: The buffer after the leg's principal rounded down, and the reward balance.
        (uint256 expected0, uint256 expected1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked);
        (expected0, expected1) = (expected0 + almCore.bufferAmount0(), expected1 + almCore.bufferAmount1());
        uint256 rewardBalance = ERC20(almCore.REWARD_TOKEN_()).balanceOf(address(almCore));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager removes the whole staked leg, accepting the penalty.
        runPlan(
            Plan.init()
                .unstake(
                    range.index,
                    almCore.getRange(range.index).stakedTokenId,
                    almCore.getRange(range.index).stakedLiquidity,
                    0,
                    0,
                    true
                )
        );

        // Then: The leg is gone.
        Range memory staged = almCore.getRange(range.index);
        assertEq(staged.stakedTokenId, 0);
        assertEq(staged.stakedLiquidity, 0);
        assertFalse(gauge.stakedContains(address(almCore), range.stakedTokenId));

        // And: The pending emissions are forfeited, neither claimed nor deferred.
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(address(almCore)), rewardBalance);
        assertEq(gauge.deferredEmissions(address(almCore)), 0);

        // And: The released principal is back in the buffer.
        assertEq(almCore.bufferAmount0(), expected0);
        assertEq(almCore.bufferAmount1(), expected1);
    }

    function testFuzz_Success_unstake_ZeroPenaltyRateNeverOpens(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 minStakeBlocks,
        uint256 blocksPassed,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge with a fuzzed window and no penalty for an early unstake.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, 0);

        // And: A range with a staked leg, still inside the window.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        vm.roll(vm.getBlockNumber() + bound(blocksPassed, 0, minStakeBlocks - 1));
        Plan.Steps memory plan =
            Plan.init().unstake(range.index, range.stakedTokenId, Sentinels.RANGE_LIQUIDITY, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager removes the whole staked leg without accepting the penalty.
        vm.prank(users.keeper);
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.Unstaked(range.index, range.stakedTokenId);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The leg is gone.
        assertEq(almCore.getRange(range.index).stakedTokenId, 0);
        assertEq(almCore.getRange(range.index).stakedLiquidity, 0);
    }

    function testFuzz_Success_unstake_WindowClosedAtTheArbBlock(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 stakedBlock,
        uint256 blocksPassed,
        uint256 arbBlocksPassed,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core whose gauge counts blocks with ArbSys.arbBlockNumber.
        Config memory config = coreViewLogic.getConfig(address(almCore));
        config.arbBlockNumber = true;
        almCore.setConfig(config);
        vm.etch(Constants.ARB_SYS, hex"00");

        // And: A range with a staked leg, staked at a fuzzed arb block.
        stakedBlock = bound(stakedBlock, 0, type(uint32).max);
        vm.mockCall(Constants.ARB_SYS, abi.encodeCall(IArbSys.arbBlockNumber, ()), abi.encode(stakedBlock));
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: The arb block past the window, the block number still inside it.
        uint256 minStakeBlocks = clGaugeFactory.minStakeBlocks(address(gauge));
        vm.roll(vm.getBlockNumber() + bound(blocksPassed, 0, minStakeBlocks - 1));
        vm.mockCall(
            Constants.ARB_SYS,
            abi.encodeCall(IArbSys.arbBlockNumber, ()),
            abi.encode(stakedBlock + minStakeBlocks + bound(arbBlocksPassed, 0, type(uint32).max))
        );

        // And: The buffer after the leg's principal, rounded down by the pool.
        (uint256 expected0, uint256 expected1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked);
        (expected0, expected1) = (expected0 + almCore.bufferAmount0(), expected1 + almCore.bufferAmount1());

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager removes the whole staked leg without accepting the penalty.
        runPlan(
            Plan.init()
                .unstake(
                    range.index,
                    almCore.getRange(range.index).stakedTokenId,
                    almCore.getRange(range.index).stakedLiquidity,
                    0,
                    0,
                    false
                )
        );

        // Then: The leg is gone.
        Range memory staged = almCore.getRange(range.index);
        assertEq(staged.stakedTokenId, 0);
        assertEq(staged.stakedLiquidity, 0);
        assertFalse(gauge.stakedContains(address(almCore), range.stakedTokenId));

        // And: The released principal is back in the buffer.
        assertEq(almCore.bufferAmount0(), expected0);
        assertEq(almCore.bufferAmount1(), expected1);
    }

    function testFuzz_Success_unstake_ReturnsPrincipalToBuffer(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        (uint256 amount0, uint256 amount1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked);
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();
        closePenaltyWindow(gauge);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls unstake().
        runPlan(
            Plan.init()
                .unstake(
                    range.index,
                    almCore.getRange(range.index).stakedTokenId,
                    almCore.getRange(range.index).stakedLiquidity,
                    0,
                    0,
                    false
                )
        );

        // Then: The released principal, rounded down by the pool, is back in the buffer.
        assertEq(almCore.bufferAmount0() - buffer0Before, amount0);
        assertEq(almCore.bufferAmount1() - buffer1Before, amount1);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1());
    }

    function testFuzz_Success_unstake_LeavesPrincipalUntaxed(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 amountIn,
        uint16 feeBps,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A protocol share of every collection.
        feeBps = uint16(bound(feeBps, 1, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(0, feeBps, users.feeRecipient);

        // And: A range around the price with a staked leg, a real share of the room.
        givenValidRangeState(range, poolState, true);
        {
            uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
            range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));
            range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        }

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            feeEarningTrade(pool, range.liquidity, amountIn, true)
        );
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        // And: The buffer after the staked principal, and the net unstaked fees.
        uint256 expected0;
        uint256 expected1;
        uint256 protocol0;
        uint256 protocol1;
        {
            (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                sqrtPriceX96(pool), range.tickLower, range.tickUpper, almCore.getRange(range.index).stakedLiquidity
            );
            (uint256 fees0, uint256 fees1) = positionFees(pool, range.unstakedTokenId);
            (protocol0, protocol1) =
            (fees0 * feeBps / almCore.BPS_DENOMINATOR_(), fees1 * feeBps / almCore.BPS_DENOMINATOR_());
            expected0 = almCore.bufferAmount0() + principal0 + fees0 - protocol0;
            expected1 = almCore.bufferAmount1() + principal1 + fees1 - protocol1;
        }

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls unstake().
        runPlan(
            Plan.init()
                .unstake(
                    range.index,
                    almCore.getRange(range.index).stakedTokenId,
                    almCore.getRange(range.index).stakedLiquidity,
                    0,
                    0,
                    false
                )
        );

        // Then: The staked leg's principal reaches the buffer untaxed.
        assertEq(almCore.bufferAmount0(), expected0);
        assertEq(almCore.bufferAmount1(), expected1);

        // And: Only the unstaked leg's fees were taxed.
        assertEq(almCore.getProtocolFees0(), protocol0);
        assertEq(almCore.getProtocolFees1(), protocol1);
    }

    function testFuzz_Success_unstake_Paused(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        vm.prank(factory);
        almCore.pause();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls unstake().
        runPlan(
            Plan.init()
                .unstake(
                    range.index,
                    almCore.getRange(range.index).stakedTokenId,
                    almCore.getRange(range.index).stakedLiquidity,
                    0,
                    0,
                    false
                )
        );

        // Then: The staked leg is gone.
        assertEq(almCore.getRange(range.index).stakedTokenId, 0);
    }

    function testFuzz_Success_unstake_RangeOpenedEarlierInThePlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault whose buffer holds what the range and its staked leg need.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        (uint256 staked0, uint256 staked1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked);
        fundShortfall(amount0 + staked0, amount1 + staked1);
        (uint256 buffer0, uint256 buffer1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        range.index = almCore.getRangesLength();
        uint256 positionsBefore = POSITION_MANAGER.totalSupply();
        uint128 stakedLiquidity =
            liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, staked0, staked1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(3, 0), 0);
        setPlanLimits(configState);

        // When: One plan opens, stakes and unstakes the range via the opened sentinel.
        {
            Plan.Steps memory plan = Plan.init().openRange(range.tickLower, range.tickUpper, amount0, amount1, 0, 0);
            plan = plan.stake(range.index, Sentinels.OPENED, staked0, staked1, 0, 0);
            runPlan(plan.unstake(range.index, Sentinels.OPENED, stakedLiquidity, 0, 0, true));
        }

        // Then: The staked leg is burned and the unstaked one is untouched.
        Range memory staged = almCore.getRange(range.index);
        assertEq(staged.stakedTokenId, 0);
        assertEq(staged.stakedLiquidity, 0);
        assertEq(
            positionLiquidity(staged.unstakedTokenId),
            liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1)
        );
        assertEq(POSITION_MANAGER.totalSupply(), positionsBefore + 1);

        // And: The buffer paid the open and the stake, and got the staked principal back.
        {
            (uint256 opened0, uint256 opened1) = amountsRoundedUp(
                sqrtPriceX96(pool), range.tickLower, range.tickUpper, positionLiquidity(staged.unstakedTokenId)
            );
            (buffer0, buffer1) = (buffer0 - opened0, buffer1 - opened1);
        }
        {
            (uint256 paid0, uint256 paid1) =
                amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, stakedLiquidity);
            (buffer0, buffer1) = (buffer0 - paid0, buffer1 - paid1);
        }
        {
            (uint256 principal0, uint256 principal1) =
                amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, stakedLiquidity);
            (buffer0, buffer1) = (buffer0 + principal0, buffer1 + principal1);
        }
        assertEq(almCore.bufferAmount0(), buffer0);
        assertEq(almCore.bufferAmount1(), buffer1);
    }

    function testFuzz_Success_unstake_StakeWindowAgreesWithGaugeHaircut(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 emissions,
        uint256 blocksPassed
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price with a staked leg.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Emissions accrued to the gauge.
        addEmissionsToGaugeCL(pool, gauge, bound(emissions, 2, MAX_BASE_RATE));

        // And: Any number of blocks around the window boundary have passed.
        uint256 minStakeBlocks = clGaugeFactory.minStakeBlocks(address(gauge));
        vm.roll(vm.getBlockNumber() + bound(blocksPassed, 0, 2 * minStakeBlocks));

        // When: Reading the gauge's accrual, and whether the window is still open.
        bool open = vm.getBlockNumber() < gauge.depositBlock(range.stakedTokenId) + minStakeBlocks;
        uint256 earned = gauge.earned(address(almCore));

        // Then: Inside the window the haircut takes all, outside it the accrual survives.
        if (open) assertEq(earned, 0);
        else assertGt(earned, 0);
    }
}
