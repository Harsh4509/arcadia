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
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { Plan } from "../../utils/Plan.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { RangesLib } from "../../../src/core/libraries/state/RangesLib.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";
import { stdError } from "@forge-std/StdError.sol";

/**
 * @notice Fuzz tests for the function "increaseStakedLiquidity" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract IncreaseStakedLiquidity_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_increaseStakedLiquidity_OnlyKeeper(
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

        // And: A caller that is not the keeper.
        vm.assume(caller != users.keeper);
        Plan.Steps memory plan =
            Plan.init().increaseStakedLiquidity(range.index, range.stakedTokenId, 0, 0, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling increaseStakedLiquidity().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ALMKeeperExtension.OnlyKeeper.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseStakedLiquidity_Paused(
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
        vm.prank(factory);
        almCore.pause();
        Plan.Steps memory plan =
            Plan.init().increaseStakedLiquidity(range.index, range.stakedTokenId, 0, 0, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls increaseStakedLiquidity().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.Paused.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseStakedLiquidity_InvalidOrder_AClearedEpochIsUnsettled(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
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

        // And: A pending token0 deposit, cleared by the plan before the step.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        Plan.Steps memory plan = Plan.init()
            .clearAllRequests(true, true)
            .increaseStakedLiquidity(range.index, range.stakedTokenId, 0, 0, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper calls increaseStakedLiquidity() before the settlement.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.InvalidOrder.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseStakedLiquidity_InvalidPayload(
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

        // And: A range.
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: An open buffer flag on a remainder above the bps denominator, one token.
        bps = bound(bps, ConfigLib.BPS_DENOMINATOR + 1, Sentinels.OPEN_BALANCE - 1);
        Plan.Steps memory plan = Plan.init()
            .increaseStakedLiquidity(
                range.index,
                range.stakedTokenId,
                onToken0 ? Sentinels.OPEN_BALANCE | bps : 0,
                onToken0 ? 0 : Sentinels.OPEN_BALANCE | bps,
                0,
                0,
                false
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

    function testFuzz_Revert_increaseStakedLiquidity_RangeMismatch_UnstakedTokenId(
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
        Plan.Steps memory plan =
            Plan.init().increaseStakedLiquidity(range.index, range.unstakedTokenId, 0, 0, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls increaseStakedLiquidity().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, range.index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseStakedLiquidity_RangeMismatch_NotOpenedInThePlan(
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
        Plan.Steps memory plan = Plan.init().increaseStakedLiquidity(range.index, Sentinels.OPENED, 0, 0, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls increaseStakedLiquidity().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, range.index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseStakedLiquidity_RangeNotStaked(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool acceptPenalty,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range without a staked leg, and a step naming its empty staked side.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Plan.Steps memory plan =
            Plan.init().increaseStakedLiquidity(range.index, range.stakedTokenId, 0, 0, 0, 0, acceptPenalty);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls increaseStakedLiquidity().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(RangesLib.RangeNotStaked.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseStakedLiquidity_PenaltyWindowOpen(
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
        Plan.Steps memory plan =
            Plan.init().increaseStakedLiquidity(range.index, range.stakedTokenId, 0, 0, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager tops the leg up without accepting the penalty.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(RangesLib.PenaltyWindowOpen.selector, range.stakedTokenId));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseStakedLiquidity_PriceSlippageCheck(
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

        // And: A buffer holding the amounts of a top-up the leg's size.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked);
        fundBuffer(amount0, amount1);

        // And: A minimum above the desired amount of one token.
        amountMin = bound(amountMin, (minOnToken0 ? amount0 : amount1) + 1, type(uint256).max);
        Plan.Steps memory plan = Plan.init()
            .increaseStakedLiquidity(
                range.index,
                range.stakedTokenId,
                amount0,
                amount1,
                minOnToken0 ? amountMin : 0,
                minOnToken0 ? 0 : amountMin,
                false
            );
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls increaseStakedLiquidity().
        // Then: It reverts with the position manager's slippage check.
        vm.prank(users.keeper);
        vm.expectRevert(bytes("PSC"));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseStakedLiquidity_InvalidPayload_Length(
        PoolState memory poolState,
        bytes memory payload,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A staked increase payload of any length but its own.
        vm.assume(payload.length != CalldataLogic.INCREASE_STAKED_LIQUIDITY_LENGTH);
        Plan.Steps memory plan = Plan.init().add(CommandLogic.INCREASE_STAKED_LIQUIDITY, payload);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper tops up the staked side.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseStakedLiquidity_RangeMismatch_IndexOutOfBounds(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 index,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg, and a step naming an index past the last range.
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
        index = bound(index, almCore.getRangesLength(), type(uint8).max);
        Plan.Steps memory plan = Plan.init().increaseStakedLiquidity(index, range.stakedTokenId, 0, 0, 0, 0, true);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper tops up the staked side.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseStakedLiquidity_RangeMismatch_ClosedEarlierInThePlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory neighbour,
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

        // And: A neighbour, and a plan closing then topping up the range.
        givenValidRangeState(neighbour, poolState, false);
        setRangeState(neighbour);
        Plan.Steps memory plan =
            Plan.init().unstake(range.index, range.stakedTokenId, Sentinels.RANGE_LIQUIDITY, 0, 0, true);
        plan = plan.closeRange(range.index, range.unstakedTokenId)
            .increaseStakedLiquidity(range.index, range.stakedTokenId, 0, 0, 0, 0, true);
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

    function testFuzz_Revert_increaseStakedLiquidity_ArithmeticError_TopUpWithinTheEscrow(
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

        // And: A range above the price with a staked leg, so it takes only token0.
        givenValidRangeState(range, poolState, false);
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
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

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
        Plan.Steps memory plan =
            Plan.init().increaseStakedLiquidity(range.index, range.stakedTokenId, amount0, 0, 0, 0, true);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper tops up the staked side.
        // Then: The buffer ledger underflows.
        vm.prank(users.keeper);
        vm.expectRevert(stdError.arithmeticError);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseStakedLiquidity_ZeroLiquidity_OneTokenInRange(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityAdded,
        bool onToken0,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range spanning the price with a staked leg outside its penalty window.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: A buffered top-up of one token only.
        liquidityAdded = uint128(
            bound(
                liquidityAdded,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY)
            )
        );
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityAdded);
        (amount0, amount1) = (onToken0 ? amount0 : 0, onToken0 ? 0 : amount1);
        fundBuffer(amount0, amount1);
        Plan.Steps memory plan =
            Plan.init().increaseStakedLiquidity(range.index, range.stakedTokenId, amount0, amount1, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper tops up the staked side.
        // Then: The pool rejects a mint of zero liquidity.
        vm.prank(users.keeper);
        vm.expectRevert(bytes(""));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_increaseStakedLiquidity(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityAdded,
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
        Range memory before = almCore.getRange(range.index);

        // And: A buffer holding the amounts of the top-up.
        liquidityAdded = uint128(
            bound(
                liquidityAdded,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY)
            )
        );
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityAdded);
        fundBuffer(amount0, amount1);

        // And: The liquidity the amounts buy, and the buffer left after the pool's cost.
        uint128 added = liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1);
        uint256 expected0;
        uint256 expected1;
        (uint256 used0, uint256 used1) = amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, added);
        (expected0, expected1) = (almCore.bufferAmount0() - used0, almCore.bufferAmount1() - used1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls increaseStakedLiquidity().
        runPlan(Plan.init().increaseStakedLiquidity(range.index, range.stakedTokenId, amount0, amount1, 0, 0, false));

        // Then: The same staked leg is back in the gauge, grown by what was added.
        Range memory staged = almCore.getRange(range.index);
        assertEq(staged.stakedTokenId, before.stakedTokenId);
        assertEq(staged.unstakedTokenId, before.unstakedTokenId);
        assertEq(positionLiquidity(staged.unstakedTokenId), positionLiquidity(before.unstakedTokenId));
        assertEq(staged.stakedLiquidity, uint256(before.stakedLiquidity) + added);
        assertEq(staged.stakedLiquidity, positionLiquidity(staged.stakedTokenId));
        assertTrue(gauge.stakedContains(address(almCore), staged.stakedTokenId));

        // And: The buffer paid for the added liquidity.
        assertEq(almCore.bufferAmount0(), expected0);
        assertEq(almCore.bufferAmount1(), expected1);

        // And: The leg was restaked now, the window end moved to its new window's end.
        assertEq(staged.stakedBlock, vm.getBlockNumber());
        assertEq(almCore.getWindowEnd(), vm.getBlockNumber() + clGaugeFactory.minStakeBlocks(address(gauge)));
    }

    function testFuzz_Success_increaseStakedLiquidity_ClaimsOrDefersTheEmissionsByChainStatus(
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

        // And: A buffer holding the amounts of a top-up the size of the staked leg.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked);
        fundBuffer(amount0, amount1);

        // And: A fuzzed chain status, what the leg earned and the core's reward balance.
        if (mintable) setMintableStatus(pick);
        else setNotMintableStatus(pick);
        uint256 earned = gauge.earned(address(almCore), almCore.stakedTokenIds());
        assertGt(earned, 0);
        uint256 rewardBalance = ERC20(almCore.REWARD_TOKEN_()).balanceOf(address(almCore));

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager tops the leg up.
        runPlan(Plan.init().increaseStakedLiquidity(range.index, range.stakedTokenId, amount0, amount1, 0, 0, false));

        // Then: A minting chain paid the core the emissions, else the gauge deferred.
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(address(almCore)), rewardBalance + (mintable ? earned : 0));
        assertEq(gauge.deferredEmissions(address(almCore)), mintable ? 0 : earned);

        // And: The leg is back in the gauge.
        assertTrue(gauge.stakedContains(address(almCore), range.stakedTokenId));
    }

    function testFuzz_Success_increaseStakedLiquidity_AcceptPenaltyInsideTheWindow(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityAdded,
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

        // And: A buffer holding the amounts of the top-up.
        liquidityAdded = uint128(
            bound(
                liquidityAdded,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY)
            )
        );
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityAdded);
        fundBuffer(amount0, amount1);
        uint128 before = almCore.getRange(range.index).stakedLiquidity;
        (amount0, amount1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        uint128 added = liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager tops the leg up with the whole buffer, accepting the penalty.
        runPlan(Plan.init().increaseStakedLiquidity(range.index, range.stakedTokenId, amount0, amount1, 0, 0, true));

        // Then: The same leg is back in the gauge, grown by what was added.
        Range memory staged = almCore.getRange(range.index);
        assertEq(staged.stakedTokenId, range.stakedTokenId);
        assertEq(staged.stakedLiquidity, uint256(before) + added);
        assertTrue(gauge.stakedContains(address(almCore), range.stakedTokenId));

        // And: The buffer paid for it, and the window restarted in this block.
        (uint256 used0, uint256 used1) = amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, added);
        assertEq(almCore.bufferAmount0(), amount0 - used0);
        assertEq(almCore.bufferAmount1(), amount1 - used1);
        assertEq(almCore.getWindowEnd(), vm.getBlockNumber() + clGaugeFactory.minStakeBlocks(address(gauge)));
    }

    function testFuzz_Success_increaseStakedLiquidity_OpenBalanceLeavesThePayouts(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 bps,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Ticks around the price, for a range the seed funds.
        givenValidRangeState(range, poolState, true, false);
        {
            uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
            range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));
        }

        // And: A seeded vault, token1 worth at most its token0, its holder with shares.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 2, 0, 0);
        coreState.buffer1 = bound(
            coreState.buffer1, 1, FixedPointMathLib.max(token0ToToken1(poolState.sqrtPrice, coreState.buffer0), 1)
        );
        setCoreState(coreState);

        // And: Deposits up to the buffer, and a token0 redeem it pays twice over.
        givenValidQueueState(
            queueState, 0, 0, Constants.QUEUE_DEPOSIT0 | Constants.QUEUE_DEPOSIT1 | Constants.QUEUE_REDEEM0
        );
        queueState.deposit0 =
            bound(queueState.deposit0, 0, FixedPointMathLib.min(queueState.deposit0, almCore.bufferAmount0()));
        queueState.deposit1 =
            bound(queueState.deposit1, 0, FixedPointMathLib.min(queueState.deposit1, almCore.bufferAmount1()));
        {
            uint256 value = almCore.bufferAmount1() + token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0());
            uint256 ceiling = token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0())
                .fullMulDiv(almCore.totalSupply(), 2 * (value + 1));
            queueState.redeem0 = bound(
                queueState.redeem0, 1, FixedPointMathLib.max(FixedPointMathLib.min(queueState.redeem0, ceiling), 1)
            );
        }
        setQueueState(queueState);

        // And: The open buffer share the range opens and stakes with.
        bps = bound(bps, 1, ConfigLib.BPS_DENOMINATOR - 1);

        // And: The liquidity each step buys from the buffer net of the payout.
        uint256 expected;
        uint256 buffer0 = almCore.bufferAmount0() + queueState.deposit0;
        uint256 buffer1 = almCore.bufferAmount1() + queueState.deposit1;
        buffer0 -= token1ToToken0(
            poolState.sqrtPrice,
            queueState.redeem0
                .fullMulDiv(
                    buffer1 - queueState.deposit1 + token0ToToken1(poolState.sqrtPrice, buffer0 - queueState.deposit0),
                    almCore.totalSupply()
                )
        );
        for (uint256 i; i < 3; ++i) {
            uint256 share = i == 2 ? ConfigLib.BPS_DENOMINATOR : bps;
            uint128 bought = liquidityForAmounts(
                uint160(poolState.sqrtPrice),
                range.tickLower,
                range.tickUpper,
                buffer0 * share / ConfigLib.BPS_DENOMINATOR,
                buffer1 * share / ConfigLib.BPS_DENOMINATOR
            );
            (uint256 amount0, uint256 amount1) =
                amountsRoundedUp(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, bought);
            (buffer0, buffer1) = (buffer0 - amount0, buffer1 - amount1);
            if (i >= 1) expected += bought;
        }

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(7, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears, opens and stakes a range, then stakes the open buffer.
        Plan.Steps memory plan = Plan.init()
            .clearAllRequests(true, true)
            .clearAllRequests(false, true)
            .clearAllRequests(true, false)
            .clearAllRequests(false, false)
            .settleRequests()
            .openRange(
                range.tickLower, range.tickUpper, Sentinels.OPEN_BALANCE | bps, Sentinels.OPEN_BALANCE | bps, 0, 0
            );
        plan = plan.stake(0, Sentinels.OPENED, Sentinels.OPEN_BALANCE | bps, Sentinels.OPEN_BALANCE | bps, 0, 0);
        runPlan(
            plan.increaseStakedLiquidity(
                0,
                Sentinels.OPENED,
                Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                0,
                0,
                true
            )
        );

        // Then: The redeem settles with its payout in escrow.
        assertEq(almCore.getEscrowed0(), almCore.redeemEpoch(asyncVault0, 0).amountOut);

        // And: The staked side holds the liquidity the stake and the top-up bought.
        assertEq(almCore.getRange(0).stakedLiquidity, expected);
    }

    function testFuzz_Success_increaseStakedLiquidity_OpenBalanceShare(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityAdded,
        uint256 bps,
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
        uint128 liquidityBefore = almCore.getRange(range.index).stakedLiquidity;

        // And: A buffered top-up, and a share of it buying the liquidity floor.
        liquidityAdded = uint128(
            bound(
                liquidityAdded,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY)
            )
        );
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityAdded);
        fundBuffer(amount0, amount1);
        (amount0, amount1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
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

        // And: The liquidity the share of each token buys.
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

        // When: The keeper adds that share of the open buffer to the staked side.
        runPlan(
            Plan.init()
                .increaseStakedLiquidity(
                    range.index,
                    range.stakedTokenId,
                    Sentinels.OPEN_BALANCE | bps,
                    Sentinels.OPEN_BALANCE | bps,
                    0,
                    0,
                    false
                )
        );

        // Then: The staked side took that liquidity, the buffer paying its amounts.
        (uint256 used0, uint256 used1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);
        assertEq(almCore.getRange(range.index).stakedLiquidity, liquidityBefore + liquidity);
        assertEq(almCore.bufferAmount0(), amount0 - used0);
        assertEq(almCore.bufferAmount1(), amount1 - used1);
    }

    function testFuzz_Success_increaseStakedLiquidity_RangeOpenedEarlierInThePlan(
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

        // And: A seeded vault whose buffer funds the range, its staked leg and top-up.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        (uint256 staked0, uint256 staked1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked);
        fundShortfall(amount0 + 2 * staked0, amount1 + 2 * staked1);
        uint256 index = almCore.getRangesLength();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(3, 0), 0);
        setPlanLimits(configState);

        // When: One plan opens, stakes and tops up the range via the opened sentinel.
        Plan.Steps memory plan = Plan.init().openRange(range.tickLower, range.tickUpper, amount0, amount1, 0, 0);
        plan = plan.stake(index, Sentinels.OPENED, staked0, staked1, 0, 0);
        plan = plan.increaseStakedLiquidity(index, Sentinels.OPENED, staked0, staked1, 0, 0, true);
        runPlan(plan);

        // Then: The staked leg holds both additions and is held by the gauge.
        Range memory staged = almCore.getRange(index);
        uint128 added = liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, staked0, staked1);
        assertEq(staged.stakedLiquidity, 2 * uint256(added));
        assertEq(staged.stakedLiquidity, positionLiquidity(staged.stakedTokenId));
        assertTrue(gauge.stakedContains(address(almCore), staged.stakedTokenId));
    }

    function testFuzz_Success_increaseStakedLiquidity_SurplusLeavesTheBuffer(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityAdded,
        uint256 surplus0,
        uint256 surplus1,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg outside its penalty window.
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

        // And: The buffer holds up to twice what the top-up needs, which the room takes.
        liquidityAdded = uint128(
            bound(
                liquidityAdded,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, 2 * Constants.MIN_FUZZED_LIQUIDITY) / 2
            )
        );
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityAdded);
        fundBuffer(amount0 + bound(surplus0, 0, amount0), amount1 + bound(surplus1, 0, amount1));
        (amount0, amount1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        uint128 added = liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper tops up the staked side with the whole buffer.
        runPlan(Plan.init().increaseStakedLiquidity(range.index, range.stakedTokenId, amount0, amount1, 0, 0, false));

        // Then: The staked side took what the buffer buys, the surplus stays.
        (uint256 used0, uint256 used1) = amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, added);
        assertEq(almCore.getRange(range.index).stakedLiquidity, uint256(range.liquidityStaked) + added);
        assertEq(almCore.bufferAmount0(), amount0 - used0);
        assertEq(almCore.bufferAmount1(), amount1 - used1);
    }

    function testFuzz_Success_increaseStakedLiquidity_AcceptPenaltyForfeitsThePreCredit(
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

        // And: A range around the price with a staked leg.
        givenValidRangeState(range, poolState, true);
        {
            uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
            range.liquidityStaked = uint128(bound(range.liquidityStaked, 2 * Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        }

        // And: A seeded vault with the range staked inside its window.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A pending token0 deposit only, and a buffered top-up of the staked side.
        givenValidQueueState(queueState, 0, 0);
        queueState.deposit0 = bound(queueState.deposit0, 1, FixedPointMathLib.max(queueState.deposit0, 1));
        (queueState.deposit1, queueState.redeem0, queueState.redeem1) = (0, 0, 0);
        setQueueState(queueState);
        (coreState.buffer0, coreState.buffer1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked / 2);
        fundBuffer(coreState.buffer0, coreState.buffer1);
        Plan.Steps memory plan = Plan.init().clearAllRequests(true, true);
        plan = plan.settleRequests()
            .increaseStakedLiquidity(range.index, range.stakedTokenId, coreState.buffer0, coreState.buffer1, 0, 0, true);

        // And: The staked liquidity and the buffer once both steps ran.
        {
            uint128 added = liquidityForAmounts(
                sqrtPriceX96(pool), range.tickLower, range.tickUpper, coreState.buffer0, coreState.buffer1
            );
            range.liquidityStaked += added;
            (coreState.buffer0, coreState.buffer1) =
                amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, added);
        }
        coreState.buffer0 = almCore.bufferAmount0() + queueState.deposit0 - coreState.buffer0;
        coreState.buffer1 = almCore.bufferAmount1() - coreState.buffer1;

        // And: Emissions accrued inside the window.
        blocks = bound(blocks, 1, minStakeBlocks - 1);
        accrueForBlocks(pool, gauge, blocks, bound(emissions, MAX_PIPS + 1, Constants.MAX_EMISSIONS));
        uint256 highWater = hiddenEmissions(gauge, address(almCore), gauge.stakedValues(address(almCore)));
        highWater -= highWater * feeBps / ConfigLib.BPS_DENOMINATOR;

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);
        uint256 snapshot = vm.snapshotState();
        almCore.checkpoint_();
        highWater += almCore.getRewardHighWater();
        uint256 rewardPerShare = almCore.rewardPerShare_();

        // When: The keeper settles, then tops up the staked side accepting its penalty.
        runPlan(plan);

        // Then: The next checkpoint folds the forfeited pre-credit into the high water.
        almCore.checkpoint_();
        assertEq(almCore.getPreCredited(), 0);
        assertEq(almCore.getRewardHighWater(), highWater);
        assertEq(almCore.rewardPerShare_(), rewardPerShare);

        // And: With no checkpoint before the plan, the settlement's reaches the ledger.
        vm.revertToState(snapshot);
        runPlan(plan);
        almCore.checkpoint_();
        assertEq(almCore.getPreCredited(), 0);
        assertEq(almCore.getRewardHighWater(), highWater);
        assertEq(almCore.rewardPerShare_(), rewardPerShare);

        // And: The staked side grew by what the buffer paid for, its window restarted.
        assertEq(almCore.getRange(range.index).stakedLiquidity, range.liquidityStaked);
        assertEq(almCore.bufferAmount0(), coreState.buffer0);
        assertEq(almCore.bufferAmount1(), coreState.buffer1);
        assertEq(almCore.getWindowEnd(), vm.getBlockNumber() + minStakeBlocks);
    }

    function testFuzz_Success_increaseStakedLiquidity_EmitsStaked(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityAdded,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg outside its penalty window.
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

        // And: A buffer holding the amounts of the top-up, and the liquidity they buy.
        liquidityAdded = uint128(
            bound(
                liquidityAdded,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY)
            )
        );
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityAdded);
        fundBuffer(amount0, amount1);
        uint128 added = liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper tops up the staked side.
        Plan.Steps memory plan =
            Plan.init().increaseStakedLiquidity(range.index, range.stakedTokenId, amount0, amount1, 0, 0, false);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(address(almCore));
        // Then: It emits Staked with the liquidity added.
        emit IALMCoreEvents.Staked(range.index, range.stakedTokenId, added);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_increaseStakedLiquidity_OpenBalanceSharePastThePayout(
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

        // And: A range around the price with a staked leg, a real share of the room.
        givenValidRangeState(range, poolState, true);
        {
            uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
            range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));
            range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        }

        // And: A vault whose holder holds shares, the range staked on top of its buffer.
        givenBufferPaysShares(coreState, poolState, range, isToken0 ? 3 : 0, isToken0 ? 0 : 3);
        setCoreState(coreState);
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            fundBuffer(amount0, amount1);
        }
        setRangeState(range);
        closePenaltyWindow(gauge);

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

        // When: The keeper clears the queues and adds that share to the staked side.
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .clearAllRequests(false, true)
                .clearAllRequests(true, false)
                .clearAllRequests(false, false)
                .settleRequests()
                .increaseStakedLiquidity(
                    range.index,
                    range.stakedTokenId,
                    Sentinels.OPEN_BALANCE | bps,
                    Sentinels.OPEN_BALANCE | bps,
                    0,
                    0,
                    false
                )
        );

        // Then: The staked side took that liquidity.
        assertEq(almCore.getRange(range.index).stakedLiquidity, uint256(range.liquidityStaked) + expected);

        // And: The redeem settles with its payout in escrow.
        assertEq(
            isToken0 ? almCore.getEscrowed0() : almCore.getEscrowed1(),
            (isToken0 ? almCore.redeemEpoch(asyncVault0, 0) : almCore.redeemEpoch(asyncVault1, 0)).amountOut
        );
    }
}
