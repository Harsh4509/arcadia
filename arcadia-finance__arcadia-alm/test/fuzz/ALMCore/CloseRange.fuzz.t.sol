/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { CalldataLogic } from "../../../src/core/libraries/logic/CalldataLogic.sol";
import { CommandLogic } from "../../../src/core/libraries/logic/CommandLogic.sol";
import { Constants } from "../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { Plan } from "../../utils/Plan.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { RangesLib } from "../../../src/core/libraries/state/RangesLib.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";

/**
 * @notice Fuzz tests for the function "closeRange" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events, unsafe-typecast, unused-return)
contract CloseRange_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_closeRange_OnlyKeeper(
        address caller,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range, and a caller that is not the manager.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        vm.assume(caller != users.keeper);
        Plan.Steps memory plan = Plan.init().closeRange(range.index, almCore.getRange(range.index).unstakedTokenId);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling closeRange().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ALMKeeperExtension.OnlyKeeper.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_closeRange_InvalidPayload(
        PoolState memory poolState,
        uint256 length,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A close payload up to twice a range key's length, of any other length.
        length = bound(length, 0, 2 * CalldataLogic.CLOSE_RANGE_LENGTH);
        vm.assume(length != CalldataLogic.CLOSE_RANGE_LENGTH);
        Plan.Steps memory plan = Plan.init().add(CommandLogic.CLOSE_RANGE, new bytes(length));
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

    function testFuzz_Revert_closeRange_RangeMismatch_OutOfBounds(
        PoolState memory poolState,
        uint256 index,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No ranges at all, and a step naming one.
        index = bound(index, 0, type(uint8).max);
        Plan.Steps memory plan = Plan.init().closeRange(index, Sentinels.OPENED);
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

    function testFuzz_Revert_closeRange_RangeMismatch_PastTheRangesWithAZeroTokenId(
        PoolState memory poolState,
        uint256 index,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No ranges, and a step naming one with the zero token id of an empty slot.
        index = bound(index, 0, type(uint8).max);
        Plan.Steps memory plan = Plan.init().closeRange(index, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_closeRange_RangeMismatch_OpenedNotInThePlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range from an earlier plan, named by the opened sentinel.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Plan.Steps memory plan = Plan.init().closeRange(range.index, Sentinels.OPENED);
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

    function testFuzz_Revert_closeRange_RangeMismatch_WildcardAfterAClose(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory neighbour,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Two ranges, a plan closing the first then naming index 0 by the sentinel.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A neighbour.
        givenValidRangeState(neighbour, poolState, false);
        setRangeState(neighbour);
        uint256 first = range.index;
        Plan.Steps memory plan =
            Plan.init().closeRange(first, almCore.getRange(first).unstakedTokenId).closeRange(first, Sentinels.OPENED);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it, the sentinel meeting the range moved into the slot.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, first));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_closeRange_RangeMismatch_ZeroTokenId(
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
        Plan.Steps memory plan = Plan.init().closeRange(range.index, 0);
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

    function testFuzz_Revert_closeRange_RangeMismatch(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory neighbour,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Two ranges, and a plan that closes the first one twice by index.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A neighbour.
        givenValidRangeState(neighbour, poolState, false);
        setRangeState(neighbour);
        uint256 first = range.index;
        Plan.Steps memory plan = Plan.init()
            .closeRange(first, almCore.getRange(first).unstakedTokenId)
            .closeRange(first, almCore.getRange(first).unstakedTokenId);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it, the second step meeting the range moved into it.
        // Then: It reverts instead of closing a range the plan never named.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, first));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_closeRange_RangeStaked(
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
        Plan.Steps memory plan = Plan.init().closeRange(range.index, almCore.getRange(range.index).unstakedTokenId);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls closeRange().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(RangesLib.RangeStaked.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_closeRange(
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
        uint256 tokenId = almCore.getRange(range.index).unstakedTokenId;
        uint256 positionsBefore = POSITION_MANAGER.totalSupply();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls closeRange().
        Plan.Steps memory plan = Plan.init().closeRange(range.index, almCore.getRange(range.index).unstakedTokenId);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.RangeClosed(range.index, tokenId);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);

        // Then: The range is gone and its position is burned.
        assertEq(almCore.getRangesLength(), 0);
        assertEq(POSITION_MANAGER.totalSupply(), positionsBefore - 1);
    }

    function testFuzz_Success_closeRange_AfterADonation(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 donation,
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
        uint256 tokenId = almCore.getRange(range.index).unstakedTokenId;

        // And: A third party added liquidity to the range's position.
        donateToRange(range, uint128(bound(donation, 1, range.liquidity)));
        uint128 liquidity = positionLiquidity(tokenId);
        assertGt(liquidity, range.liquidity);
        (uint256 principal0, uint256 principal1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();
        uint256 positionsBefore = POSITION_MANAGER.totalSupply();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls closeRange().
        runPlan(Plan.init().closeRange(range.index, almCore.getRange(range.index).unstakedTokenId));

        // Then: The position is burned, the buffer holds its principal and the donation.
        assertEq(almCore.getRangesLength(), 0);
        assertEq(POSITION_MANAGER.totalSupply(), positionsBefore - 1);
        assertEq(almCore.bufferAmount0() - buffer0Before, principal0);
        assertEq(almCore.bufferAmount1() - buffer1Before, principal1);
    }

    function testFuzz_Success_closeRange_SentinelFollowsTheMovedRange(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory opened,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A pre-existing range.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        uint256 stale = range.index;

        // And: A second range, and a buffer twice what it needs, to open it and stake it.
        givenValidRangeState(opened, poolState, false);
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), opened.tickLower, opened.tickUpper, opened.liquidity);
        fundBuffer(2 * amount0, 2 * amount1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(3, 0), 0);
        setPlanLimits(configState);

        // When: The plan opens a range, closes the older one, then stakes the new one.
        Plan.Steps memory plan = Plan.init().openRange(opened.tickLower, opened.tickUpper, amount0, amount1, 0, 0);
        plan = plan.closeRange(stale, almCore.getRange(stale).unstakedTokenId);
        plan = plan.stake(stale, Sentinels.OPENED, amount0, amount1, 0, 0);
        runPlan(plan);

        // Then: The sentinel followed the range into its new slot and staked it.
        assertEq(almCore.getRangesLength(), 1);
        assertTrue(almCore.getRange(stale).stakedTokenId != 0);
    }

    function testFuzz_Success_closeRange_TheLastOfThreeRangesTakesTheSlot(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory second,
        RangeState memory third,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding three ranges without staked legs.
        givenValidRangeState(range, poolState, false, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        givenValidRangeState(second, poolState, false, false);
        second.liquidity = uint128(
            bound(
                second.liquidity,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(second.tickLower, second.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 8
            )
        );
        setRangeState(second);
        givenValidRangeState(third, poolState, false, false);
        third.liquidity = uint128(
            bound(
                third.liquidity,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(third.tickLower, third.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 8
            )
        );
        setRangeState(third);
        uint256 secondTokenId = almCore.getRange(1).unstakedTokenId;
        uint256 thirdTokenId = almCore.getRange(2).unstakedTokenId;

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper closes the first.
        runPlan(Plan.init().closeRange(0, almCore.getRange(0).unstakedTokenId));

        // Then: The third range moved into its slot, and the second stayed.
        assertEq(almCore.getRangesLength(), 2);
        assertEq(almCore.getRange(0).unstakedTokenId, thirdTokenId);
        assertEq(almCore.getRange(1).unstakedTokenId, secondTokenId);
    }

    function testFuzz_Success_closeRange_ReturnsLiquidityToBuffer(
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
        Range memory staged = almCore.getRange(range.index);
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            sqrtPriceX96(pool), range.tickLower, range.tickUpper, positionLiquidity(staged.unstakedTokenId)
        );
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls closeRange().
        runPlan(Plan.init().closeRange(range.index, almCore.getRange(range.index).unstakedTokenId));

        // Then: The released principal, rounded down by the pool, is back in the buffer.
        assertEq(almCore.bufferAmount0() - buffer0Before, amount0);
        assertEq(almCore.bufferAmount1() - buffer1Before, amount1);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1());
    }

    function testFuzz_Success_closeRange_KeepsTheValueAtThePlanPrice(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range below the price, without a staked leg.
        givenValidRangeState(range, poolState, false, false);
        givenRangeRoom(range, poolState, true);
        int24 tickSpacing = poolState.tickSpacing;
        int24 spot = poolState.tickCurrent / tickSpacing;
        if (poolState.tickCurrent < 0 && poolState.tickCurrent % tickSpacing != 0) --spot;
        range.tickUpper =
            int24(bound(range.tickUpper / tickSpacing, range.tickLower / tickSpacing + 1, spot)) * tickSpacing;
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Plan.Steps memory plan = Plan.init().closeRange(range.index, almCore.getRange(range.index).unstakedTokenId);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: The value at the plan price and the supply.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedDown(trustedSqrtPriceX96, range.tickLower, range.tickUpper, range.liquidity);
        uint256 value =
            amount1 + almCore.bufferAmount1() + token0ToToken1(trustedSqrtPriceX96, amount0 + almCore.bufferAmount0());
        uint256 supply = almCore.totalSupply();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper closes the range at the pool price.
        vm.prank(users.keeper);
        vm.expectEmit(true, true, true, true, address(almCore));
        emit IALMCoreEvents.PlanExecuted(1, trustedSqrtPriceX96, value, value, supply, 0, 0);
        // Then: The released principal keeps the value it had in the range.
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_closeRange_LeavesPrincipalUntaxed(
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

        // And: A range around the price without a staked leg, a real share of the room.
        givenValidRangeState(range, poolState, true, false);
        {
            uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
            range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));
        }

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        uint256 index = range.index;

        // And: Swap fees the range earned.
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            feeEarningTrade(pool, range.liquidity, amountIn, true)
        );

        // And: The TWAP has caught up with the trade.
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        // And: A protocol share whose cut of the range's token0 fees is at least a wei.
        {
            (uint256 gross0,) = positionFees(pool, almCore.getRange(index).unstakedTokenId);
            // And: Fees the highest share cuts a wei from, a hole for smaller fee growth.
            vm.assume(gross0 * almCore.MAX_FEE_BPS_() >= almCore.BPS_DENOMINATOR_());
            feeBps = uint16(bound(feeBps, almCore.BPS_DENOMINATOR_().divUp(gross0), almCore.MAX_FEE_BPS_()));
        }
        vm.prank(factory);
        almCore.setProtocolFees(0, feeBps, users.feeRecipient);

        // And: Those fees are harvested, so only principal is left to collect.
        runPlan(Plan.init().collect(range.unstakedTokenId));
        uint256 protocolFees0 = almCore.getProtocolFees0();
        uint256 protocolFees1 = almCore.getProtocolFees1();
        uint256 buffer0 = almCore.bufferAmount0();
        uint256 buffer1 = almCore.bufferAmount1();
        (uint256 principal0, uint256 principal1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls closeRange().
        runPlan(Plan.init().closeRange(index, almCore.getRange(index).unstakedTokenId));

        // Then: The protocol fees do not move and the whole principal reaches the buffer.
        assertEq(almCore.getProtocolFees0(), protocolFees0);
        assertEq(almCore.getProtocolFees1(), protocolFees1);
        assertEq(almCore.bufferAmount0(), buffer0 + principal0);
        assertEq(almCore.bufferAmount1(), buffer1 + principal1);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0() + protocolFees0);
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1() + protocolFees1);
    }

    function testFuzz_Success_closeRange_CollectsFeesEarnedInThePlan(
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

        // And: A range around the price without a staked leg, a real share of the room.
        givenValidRangeState(range, poolState, true, false);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A buffer holding a fee-earning trade.
        amountIn = feeEarningTrade(pool, range.liquidity, amountIn, true);
        fundBuffer(amountIn, 0);

        // And: A protocol share of every collection.
        feeBps = uint16(bound(feeBps, 1, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(0, feeBps, users.feeRecipient);

        // And: The range's fees from the same swap made in the pool directly.
        uint256 snapshot = vm.snapshotState();
        token0.mint(users.liquidityProvider, amountIn);
        swapAsActor(pool, users.liquidityProvider, address(token0), address(token1), amountIn, priceLimit(true));
        (uint256 fees0, uint256 fees1) = positionFees(pool, range.unstakedTokenId);
        vm.revertToState(snapshot);
        uint256 protocolFees0 = fees0 * feeBps / almCore.BPS_DENOMINATOR_();
        uint256 protocolFees1 = fees1 * feeBps / almCore.BPS_DENOMINATOR_();

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 2, true, amountIn, poolSwapOut(true, amountIn));
        setPlanLimits(configState);

        // When: The manager swaps through the range and then closes it.
        runPlan(
            Plan.init().swapViaPool(true, amountIn, priceLimit(true), 0).closeRange(range.index, range.unstakedTokenId)
        );

        // Then: The protocol share of the close's fees is floored once.
        assertGt(fees0, 0);
        assertEq(almCore.getProtocolFees0(), protocolFees0);
        assertEq(almCore.getProtocolFees1(), protocolFees1);

        // And: The buffer holds every token the core holds but the protocol share.
        assertEq(almCore.bufferAmount0(), token0.balanceOf(address(almCore)) - protocolFees0);
        assertEq(almCore.bufferAmount1(), token1.balanceOf(address(almCore)) - protocolFees1);
    }

    function testFuzz_Success_closeRange_DrainedSideInThePlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range, and its principal rounded down by the pool.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        (uint256 amount0, uint256 amount1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();
        uint256 positionsBefore = POSITION_MANAGER.totalSupply();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: One plan removes the range's whole liquidity, then closes it.
        runPlan(
            Plan.init()
                .decreaseLiquidity(range.index, range.unstakedTokenId, Sentinels.RANGE_LIQUIDITY, 0, 0)
                .closeRange(range.index, range.unstakedTokenId)
        );

        // Then: The range is gone and its emptied position is burned.
        assertEq(almCore.getRangesLength(), 0);
        assertEq(POSITION_MANAGER.totalSupply(), positionsBefore - 1);

        // And: The buffer holds the principal the decrease released.
        assertEq(almCore.bufferAmount0() - buffer0Before, amount0);
        assertEq(almCore.bufferAmount1() - buffer1Before, amount1);
    }

    function testFuzz_Success_closeRange_SwapRemovesFromRanges(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory neighbour,
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

        // And: A neighbour.
        givenValidRangeState(neighbour, poolState, false);
        setRangeState(neighbour);
        Range memory last = almCore.getRange(1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager burns the first range.
        runPlan(Plan.init().closeRange(0, almCore.getRange(0).unstakedTokenId));

        // Then: The last range took its slot, with its ticks and liquidity.
        Range memory moved = almCore.getRange(0);
        assertEq(almCore.getRangesLength(), 1);
        assertEq(moved.unstakedTokenId, last.unstakedTokenId);
        assertEq(moved.tickLower, neighbour.tickLower);
        assertEq(moved.tickUpper, neighbour.tickUpper);
        assertEq(positionLiquidity(moved.unstakedTokenId), positionLiquidity(last.unstakedTokenId));
    }

    function testFuzz_Success_closeRange_OpenedFlagFollowsTheMovedRange(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory opened,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A pre-existing range.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        uint256 positionsBefore = POSITION_MANAGER.totalSupply();

        // And: A second range, and a buffer holding what it needs.
        givenValidRangeState(opened, poolState, false);
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), opened.tickLower, opened.tickUpper, opened.liquidity);
        fundBuffer(amount0, amount1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(3, 0), 0);
        setPlanLimits(configState);

        // When: A plan opens a range, closes the old one, then the new one by sentinel.
        Plan.Steps memory plan = Plan.init().openRange(opened.tickLower, opened.tickUpper, amount0, amount1, 0, 0);
        plan = plan.closeRange(range.index, range.unstakedTokenId);
        plan = plan.closeRange(range.index, Sentinels.OPENED);
        runPlan(plan);

        // Then: Both ranges are gone and both positions are burned.
        assertEq(almCore.getRangesLength(), 0);
        assertEq(POSITION_MANAGER.totalSupply(), positionsBefore - 1);
    }

    function testFuzz_Success_closeRange_Paused(
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
        vm.prank(factory);
        almCore.pause();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls closeRange().
        runPlan(Plan.init().closeRange(range.index, almCore.getRange(range.index).unstakedTokenId));

        // Then: The range is gone.
        assertEq(almCore.getRangesLength(), 0);
    }
}
