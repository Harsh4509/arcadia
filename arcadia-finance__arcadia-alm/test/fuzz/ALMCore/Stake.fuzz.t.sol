/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { CalldataLogic } from "../../../src/core/libraries/logic/CalldataLogic.sol";
import { CommandLogic } from "../../../src/core/libraries/logic/CommandLogic.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { Plan } from "../../utils/Plan.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { RangesLib } from "../../../src/core/libraries/state/RangesLib.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";
import { stdError } from "@forge-std/StdError.sol";

/**
 * @notice Fuzz tests for the function "stake" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events, unsafe-typecast, unused-return)
contract Stake_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_stake_OnlyKeeper(
        address caller,
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

        // And: A caller that is not the keeper.
        vm.assume(caller != users.keeper);
        Plan.Steps memory plan =
            Plan.init().stake(range.index, almCore.getRange(range.index).unstakedTokenId, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling stake().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ALMKeeperExtension.OnlyKeeper.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_stake_Paused(
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
        Plan.Steps memory plan =
            Plan.init().stake(range.index, almCore.getRange(range.index).unstakedTokenId, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls stake().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.Paused.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_stake_InvalidOrder_AClearedEpochIsUnsettled(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
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

        // And: A pending token0 deposit, cleared by the plan before the step.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        Plan.Steps memory plan = Plan.init()
            .clearAllRequests(true, true)
            .stake(range.index, almCore.getRange(range.index).unstakedTokenId, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper calls stake() before the settlement.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.InvalidOrder.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_stake_InvalidPayload(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 bps,
        bool onToken0,
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

        // And: An open buffer flag on a remainder above the bps denominator, one token.
        bps = bound(bps, ConfigLib.BPS_DENOMINATOR + 1, Sentinels.OPEN_BALANCE - 1);
        Plan.Steps memory plan = Plan.init()
            .stake(
                range.index,
                range.unstakedTokenId,
                onToken0 ? Sentinels.OPEN_BALANCE | bps : 0,
                onToken0 ? 0 : Sentinels.OPEN_BALANCE | bps,
                0,
                0
            );
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper adds liquidity.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_stake_RangeMismatch_StakedTokenId(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg, and a step naming it by its staked token id.
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
        Plan.Steps memory plan = Plan.init().stake(range.index, range.stakedTokenId, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls stake().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, range.index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_stake_RangeStaked(
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
        Plan.Steps memory plan = Plan.init().stake(range.index, range.unstakedTokenId, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls stake() on it again.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(RangesLib.RangeStaked.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_stake_PriceSlippageCheck(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 amountMin,
        bool minOnToken0,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range without a staked leg, and a buffer holding a staked leg its size.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        fundBuffer(amount0, amount1);

        // And: A minimum above the desired amount of one token.
        amountMin = bound(amountMin, (minOnToken0 ? amount0 : amount1) + 1, type(uint256).max);
        Plan.Steps memory plan = Plan.init()
            .stake(
                range.index,
                range.unstakedTokenId,
                amount0,
                amount1,
                minOnToken0 ? amountMin : 0,
                minOnToken0 ? 0 : amountMin
            );
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls stake().
        // Then: It reverts with the position manager's slippage check.
        vm.prank(users.keeper);
        vm.expectRevert(bytes("PSC"));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_stake_InvalidPayload_Length(
        PoolState memory poolState,
        bytes memory payload,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A stake payload of any length but its own.
        vm.assume(payload.length != CalldataLogic.STAKE_LENGTH);
        Plan.Steps memory plan = Plan.init().add(CommandLogic.STAKE, payload);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper stakes.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_stake_RangeMismatch_IndexOutOfBounds(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 index,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range, and a step naming an index past the last range.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        index = bound(index, almCore.getRangesLength(), type(uint8).max);
        Plan.Steps memory plan = Plan.init().stake(index, range.unstakedTokenId, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper stakes.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_stake_RangeMismatch_NotOpenedInThePlan(
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
        Plan.Steps memory plan = Plan.init().stake(range.index, Sentinels.OPENED, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper stakes.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, range.index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_stake_RangeMismatch_ClosedEarlierInThePlan(
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

        // And: A neighbour, and a plan closing the range, then staking its id.
        givenValidRangeState(neighbour, poolState, false);
        setRangeState(neighbour);
        Plan.Steps memory plan = Plan.init()
            .closeRange(range.index, range.unstakedTokenId)
            .stake(range.index, range.unstakedTokenId, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: The neighbour moved into the closed range's index, so it reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, range.index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_stake_ArithmeticError_StakeWithinTheEscrow(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 amount0,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range above the price without a staked leg, so it takes only token0.
        givenValidRangeState(range, poolState, false, false);
        range.tickLower = int24(
            bound(
                range.tickLower / poolState.tickSpacing,
                (poolState.tickCurrent + poolState.tickSpacing) / poolState.tickSpacing,
                (bandTick(poolState.tickSpacing) / poolState.tickSpacing) - 2
            )
        ) * poolState.tickSpacing;
        range.tickUpper = int24(
            bound(
                range.tickUpper / poolState.tickSpacing,
                range.tickLower / poolState.tickSpacing + 1,
                (bandTick(poolState.tickSpacing) / poolState.tickSpacing) - 1
            )
        ) * poolState.tickSpacing;
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A token0 deposit only, in escrow, up to the buffer, past mint rounding.
        givenValidQueueState(queueState, 0, 0);
        (uint256 unit0,) = amountsRoundedUp(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, 1);
        (uint256 used0,) = amountsRoundedUp(
            uint160(poolState.sqrtPrice),
            range.tickLower,
            range.tickUpper,
            liquidityForAmounts(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, almCore.bufferAmount0(), 0
            )
        );
        unit0 = 4 * (almCore.bufferAmount0() - used0) + 2 * unit0 + 2;
        queueState.deposit0 = bound(
            queueState.deposit0,
            unit0,
            FixedPointMathLib.max(FixedPointMathLib.min(queueState.deposit0, almCore.bufferAmount0()), unit0)
        );
        (queueState.deposit1, queueState.redeem0, queueState.redeem1) = (0, 0, 0);
        setQueueState(queueState);

        // And: A token0 amount past the buffer by half the escrow at least.
        amount0 =
            bound(amount0, almCore.bufferAmount0() + almCore.getEscrowed0() / 2, token0.balanceOf(address(almCore)));
        Plan.Steps memory plan = Plan.init().stake(range.index, range.unstakedTokenId, amount0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper stakes.
        // Then: The buffer ledger underflows.
        vm.prank(users.keeper);
        vm.expectRevert(stdError.arithmeticError);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_stake(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityStaked,
        bool mintable,
        uint256 pick,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price, on any chain status.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        if (mintable) setMintableStatus(pick);
        else setNotMintableStatus(pick);

        // And: A range without a staked leg.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Range memory before = almCore.getRange(range.index);
        liquidityStaked = uint128(
            bound(
                liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY)
            )
        );
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityStaked);
        fundBuffer(amount0, amount1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls stake().
        runPlan(Plan.init().stake(range.index, almCore.getRange(range.index).unstakedTokenId, amount0, amount1, 0, 0));

        // Then: The gauge holds a fresh leg at the range's ticks beside the unstaked one.
        Range memory staged = almCore.getRange(range.index);
        assertTrue(staged.stakedTokenId != 0);
        assertTrue(staged.stakedTokenId != staged.unstakedTokenId);
        assertEq(staged.unstakedTokenId, before.unstakedTokenId);
        assertEq(positionLiquidity(staged.unstakedTokenId), positionLiquidity(before.unstakedTokenId));
        assertEq(staged.stakedLiquidity, positionLiquidity(staged.stakedTokenId));
        assertEq(
            staged.stakedLiquidity,
            liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1)
        );
        assertTrue(gauge.stakedContains(address(almCore), staged.stakedTokenId));
        assertEq(staged.stakedBlock, gauge.depositBlock(staged.stakedTokenId));

        (int24 stakedLower, int24 stakedUpper) = positionTicks(staged.stakedTokenId);
        assertEq(stakedLower, range.tickLower);
        assertEq(stakedUpper, range.tickUpper);

        // And: The window end is the end of the new leg's penalty window.
        assertEq(almCore.getWindowEnd(), vm.getBlockNumber() + clGaugeFactory.minStakeBlocks(address(gauge)));
    }

    function testFuzz_Success_stake_DebitsBufferByAmountsUsed(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityStaked,
        uint256 surplus0,
        uint256 surplus1,
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
        liquidityStaked = uint128(
            bound(
                liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, 2 * Constants.MIN_FUZZED_LIQUIDITY) / 2
            )
        );
        {
            (uint256 amount0, uint256 amount1) =
                amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityStaked);
            (surplus0, surplus1) = (bound(surplus0, 0, amount0), bound(surplus1, 0, amount1));
            fundBuffer(amount0 + surplus0, amount1 + surplus1);
        }
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls stake() with the whole buffer as the desired amounts.
        runPlan(
            Plan.init()
                .stake(range.index, almCore.getRange(range.index).unstakedTokenId, buffer0Before, buffer1Before, 0, 0)
        );

        // Then: The buffer is debited by what the position manager consumed.
        (uint256 used0, uint256 used1) = amountsRoundedUp(
            sqrtPriceX96(pool), range.tickLower, range.tickUpper, almCore.getRange(range.index).stakedLiquidity
        );
        assertEq(almCore.bufferAmount0() + used0, buffer0Before);
        assertEq(almCore.bufferAmount1() + used1, buffer1Before);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1());
    }

    function testFuzz_Success_stake_OpenBalanceShare(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 surplus0,
        uint256 surplus1,
        uint256 bps,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with its unstaked leg open and no staked leg.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: The buffer holds up to twice a staked leg the unstaked one's size.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        fundBuffer(amount0 + bound(surplus0, 0, amount0), amount1 + bound(surplus1, 0, amount1));
        (amount0, amount1) = (almCore.bufferAmount0(), almCore.bufferAmount1());

        // And: A share buying at least the liquidity floor, and the liquidity it buys.
        (uint256 least0, uint256 least1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        bps = bound(
            bps,
            FixedPointMathLib.max(
                least0 == 0 ? 0 : FixedPointMathLib.divUp(least0 * ConfigLib.BPS_DENOMINATOR, amount0),
                least1 == 0 ? 0 : FixedPointMathLib.divUp(least1 * ConfigLib.BPS_DENOMINATOR, amount1)
            ),
            ConfigLib.BPS_DENOMINATOR
        );
        uint128 liquidity = liquidityForAmounts(
            sqrtPriceX96(pool),
            range.tickLower,
            range.tickUpper,
            amount0 * bps / ConfigLib.BPS_DENOMINATOR,
            amount1 * bps / ConfigLib.BPS_DENOMINATOR
        );

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper stakes that share of the open buffer.
        runPlan(
            Plan.init()
                .stake(
                    range.index,
                    almCore.getRange(range.index).unstakedTokenId,
                    Sentinels.OPEN_BALANCE | bps,
                    Sentinels.OPEN_BALANCE | bps,
                    0,
                    0
                )
        );

        // Then: The staked leg holds that liquidity, the buffer paying its amounts.
        (uint256 used0, uint256 used1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);
        assertEq(almCore.getRange(range.index).stakedLiquidity, liquidity);
        assertEq(almCore.bufferAmount0(), amount0 - used0);
        assertEq(almCore.bufferAmount1(), amount1 - used1);
    }

    function testFuzz_Success_stake_EmitsStaked(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityStaked,
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
        liquidityStaked = uint128(
            bound(
                liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY)
            )
        );
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityStaked);
        fundBuffer(amount0, amount1);

        // And: The token id the position manager mints next, and the liquidity bought.
        uint256 tokenId = POSITION_MANAGER.totalSupply() + 1;
        uint128 liquidity = liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls stake().
        Plan.Steps memory plan =
            Plan.init().stake(range.index, almCore.getRange(range.index).unstakedTokenId, amount0, amount1, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(address(almCore));
        // Then: It emits Staked.
        emit IALMCoreEvents.Staked(range.index, tokenId, liquidity);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_stake_RangeOpenedEarlierInThePlan(
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
        uint256 index = almCore.getRangesLength();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The plan opens a range, then stakes it by the opened sentinel.
        Plan.Steps memory plan = Plan.init().openRange(range.tickLower, range.tickUpper, amount0, amount1, 0, 0);
        runPlan(plan.stake(index, Sentinels.OPENED, staked0, staked1, 0, 0));

        // Then: The new range holds a staked leg at its ticks, held by the gauge.
        Range memory staged = almCore.getRange(index);
        assertTrue(staged.stakedTokenId != 0);
        assertTrue(staged.stakedTokenId != staged.unstakedTokenId);
        assertEq(staged.stakedLiquidity, positionLiquidity(staged.stakedTokenId));

        // And: Each leg holds the liquidity its amounts buy.
        assertEq(
            positionLiquidity(staged.unstakedTokenId),
            liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1)
        );
        assertEq(
            staged.stakedLiquidity,
            liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, staked0, staked1)
        );
        assertTrue(gauge.stakedContains(address(almCore), staged.stakedTokenId));
        (int24 stakedLower, int24 stakedUpper) = positionTicks(staged.stakedTokenId);
        assertEq(stakedLower, range.tickLower);
        assertEq(stakedUpper, range.tickUpper);
    }

    function testFuzz_Success_stake_MinimumAtTheAmountsUsed(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityStaked,
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

        // And: The buffer holds a staked leg's amounts, and what the leg uses of them.
        liquidityStaked = uint128(
            bound(
                liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY)
            )
        );
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityStaked);
        fundBuffer(amount0, amount1);
        uint128 liquidity = liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1);
        (uint256 used0, uint256 used1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);
        uint256 buffer0 = almCore.bufferAmount0();
        uint256 buffer1 = almCore.bufferAmount1();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper stakes with minimums at the amounts used.
        runPlan(Plan.init().stake(range.index, range.unstakedTokenId, amount0, amount1, used0, used1));

        // Then: The staked leg holds the liquidity, the buffer paid the amounts used.
        assertEq(almCore.getRange(range.index).stakedLiquidity, liquidity);
        assertEq(almCore.bufferAmount0(), buffer0 - used0);
        assertEq(almCore.bufferAmount1(), buffer1 - used1);
    }

    function testFuzz_Success_stake_OpenBalanceSharePastThePayout(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 bps,
        bool isToken0,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price without a staked leg, a real share of the room.
        givenValidRangeState(range, poolState, true, false);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

        // And: A vault whose holder holds shares, the range funded on top of its buffer.
        givenBufferPaysShares(coreState, poolState, range, isToken0 ? 3 : 0, isToken0 ? 0 : 3);
        setCoreState(coreState);
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            fundBuffer(amount0, amount1);
        }
        setRangeState(range);

        // And: Deposits up to the buffer, and a one token redeem it pays twice over.
        givenValidQueueState(
            queueState,
            0,
            0,
            Constants.QUEUE_DEPOSIT0 | Constants.QUEUE_DEPOSIT1
                | (isToken0 ? Constants.QUEUE_REDEEM0 : Constants.QUEUE_REDEEM1)
        );
        queueState.deposit0 =
            bound(queueState.deposit0, 0, FixedPointMathLib.min(queueState.deposit0, almCore.bufferAmount0()));
        queueState.deposit1 =
            bound(queueState.deposit1, 0, FixedPointMathLib.min(queueState.deposit1, almCore.bufferAmount1()));
        {
            uint256 worth;
            {
                Range memory staged = almCore.getRange(range.index);
                (uint256 held0, uint256 held1) = amountsRoundedDown(
                    uint160(poolState.sqrtPrice),
                    staged.tickLower,
                    staged.tickUpper,
                    positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
                );
                worth = held1 + almCore.bufferAmount1()
                    + token0ToToken1(poolState.sqrtPrice, held0 + almCore.bufferAmount0());
            }
            uint256 ceiling = (isToken0
                    ? token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0())
                    : almCore.bufferAmount1())
            .fullMulDiv(almCore.totalSupply(), 2 * (worth + 1));
            if (isToken0) {
                queueState.redeem0 = bound(
                    queueState.redeem0, 1, FixedPointMathLib.max(FixedPointMathLib.min(queueState.redeem0, ceiling), 1)
                );
            } else {
                queueState.redeem1 = bound(
                    queueState.redeem1, 1, FixedPointMathLib.max(FixedPointMathLib.min(queueState.redeem1, ceiling), 1)
                );
            }
        }
        setQueueState(queueState);

        // And: The payout settled before the step, and the liquidity an open share buys.
        bps = bound(bps, 1, ConfigLib.BPS_DENOMINATOR);
        uint128 expected;
        uint160 sqrtPrice = sqrtPriceX96(pool);
        uint256 buffer0 = almCore.bufferAmount0() + queueState.deposit0;
        uint256 buffer1 = almCore.bufferAmount1() + queueState.deposit1;
        uint256 value;
        {
            Range memory staged = almCore.getRange(range.index);
            (uint256 held0, uint256 held1) = amountsRoundedDown(
                sqrtPrice,
                staged.tickLower,
                staged.tickUpper,
                positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
            );
            value = buffer1 - queueState.deposit1 + held1
                + token0ToToken1(sqrtPrice, buffer0 - queueState.deposit0 + held0);
        }
        uint256 owed = (isToken0 ? queueState.redeem0 : queueState.redeem1).fullMulDiv(value, almCore.totalSupply());
        if (isToken0) owed = token1ToToken0(sqrtPrice, owed);
        expected = liquidityForAmounts(
            sqrtPrice,
            range.tickLower,
            range.tickUpper,
            (buffer0 - (isToken0 ? owed : 0)) * bps / ConfigLib.BPS_DENOMINATOR,
            (buffer1 - (isToken0 ? 0 : owed)) * bps / ConfigLib.BPS_DENOMINATOR
        );

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(5, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the queues and stakes that share of the open buffer.
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .clearAllRequests(false, true)
                .clearAllRequests(true, false)
                .clearAllRequests(false, false)
                .settleRequests()
                .stake(
                    range.index, range.unstakedTokenId, Sentinels.OPEN_BALANCE | bps, Sentinels.OPEN_BALANCE | bps, 0, 0
                )
        );

        // Then: The staked leg holds that liquidity.
        assertEq(almCore.getRange(range.index).stakedLiquidity, expected);

        // And: The redeem settles with its payout in escrow.
        assertEq(
            isToken0 ? almCore.getEscrowed0() : almCore.getEscrowed1(),
            (isToken0 ? almCore.redeemEpoch(asyncVault0, 0) : almCore.redeemEpoch(asyncVault1, 0)).amountOut
        );
    }
}
