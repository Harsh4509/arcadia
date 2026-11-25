/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { Constants } from "../../utils/Constants.sol";
import { Plan } from "../../utils/Plan.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { RangesLib } from "../../../src/core/libraries/state/RangesLib.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";

/**
 * @notice Fuzz tests for the function "emergencyUnstake" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract EmergencyUnstake_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_emergencyUnstake_RangeMismatch_OutOfBounds(
        PoolState memory poolState,
        uint256 index,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No ranges, the gauge's emergency withdraw on, and a step naming one.
        clGaugeFactory.setEmergencyWithdrawEnabled(true);
        index = bound(index, 0, type(uint8).max);
        Plan.Steps memory plan = Plan.init().emergencyUnstake(index, Sentinels.OPENED);
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

    function testFuzz_Revert_emergencyUnstake_RangeMismatch_OpenedNotInThePlan(
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
        clGaugeFactory.setEmergencyWithdrawEnabled(true);
        Plan.Steps memory plan = Plan.init().emergencyUnstake(range.index, Sentinels.OPENED);
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

    function testFuzz_Revert_emergencyUnstake_RangeMismatch_UnstakedTokenId(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A staked range, and a step naming it by its unstaked token id.
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
        clGaugeFactory.setEmergencyWithdrawEnabled(true);
        Plan.Steps memory plan = Plan.init().emergencyUnstake(range.index, range.unstakedTokenId);
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

    function testFuzz_Revert_emergencyUnstake_RangeMismatch_AfterEmergency(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range whose staked leg an earlier emergency unstake took out.
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
        clGaugeFactory.setEmergencyWithdrawEnabled(true);
        runPlan(Plan.init().emergencyUnstake(range.index, range.stakedTokenId));

        // And: A step naming the leg by its old token id.
        Plan.Steps memory plan = Plan.init().emergencyUnstake(range.index, range.stakedTokenId);
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

    function testFuzz_Revert_emergencyUnstake_RangeNotStaked_AfterEmergency(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range whose staked leg an earlier emergency unstake took out.
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
        clGaugeFactory.setEmergencyWithdrawEnabled(true);
        runPlan(Plan.init().emergencyUnstake(range.index, range.stakedTokenId));

        // And: A step naming the drained leg by its cleared token id.
        Plan.Steps memory plan = Plan.init().emergencyUnstake(range.index, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(RangesLib.RangeNotStaked.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_emergencyUnstake_AfterPartialUnstakeInThePlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityRemoved,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A staked leg outside its window, and the gauge's emergency withdraw on.
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
        clGaugeFactory.setEmergencyWithdrawEnabled(true);
        uint256 positionsBefore = POSITION_MANAGER.totalSupply();

        // And: The buffer plus both parts' principal, each rounded down by the pool.
        liquidityRemoved = uint128(bound(liquidityRemoved, 1, range.liquidityStaked - 1));
        (uint256 removed0, uint256 removed1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityRemoved);
        (uint256 rest0, uint256 rest1) = amountsRoundedDown(
            sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked - liquidityRemoved
        );
        uint256 expected0 = almCore.bufferAmount0() + removed0 + rest0;
        uint256 expected1 = almCore.bufferAmount1() + removed1 + rest1;

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: One plan removes part of the leg, then the rest by emergency withdraw.
        runPlan(
            Plan.init()
                .unstake(range.index, range.stakedTokenId, liquidityRemoved, 0, 0, false)
                .emergencyUnstake(range.index, range.stakedTokenId)
        );

        // Then: The staked leg is out of the gauge and burned.
        Range memory staged = almCore.getRange(range.index);
        assertEq(staged.stakedTokenId, 0);
        assertEq(staged.stakedLiquidity, 0);
        assertFalse(gauge.stakedContains(address(almCore), range.stakedTokenId));
        assertEq(POSITION_MANAGER.totalSupply(), positionsBefore - 1);

        // And: The buffer holds the principal of both parts.
        assertEq(almCore.bufferAmount0(), expected0);
        assertEq(almCore.bufferAmount1(), expected1);
    }
}
