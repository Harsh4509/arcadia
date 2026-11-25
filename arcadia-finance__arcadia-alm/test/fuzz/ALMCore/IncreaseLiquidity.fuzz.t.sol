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
import { IMetadexCLGaugeFactory } from "../../../src/interfaces/IMetadexCLGaugeFactory.sol";
import { Plan } from "../../utils/Plan.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";
import { stdError } from "@forge-std/StdError.sol";

/**
 * @notice Fuzz tests for the function "increaseLiquidity" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract IncreaseLiquidity_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_increaseLiquidity_OnlyKeeper(
        address caller,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
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

        // And: A caller that is not the keeper.
        vm.assume(caller != users.keeper);
        Plan.Steps memory plan =
            Plan.init().increaseLiquidity(range.index, almCore.getRange(range.index).unstakedTokenId, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling increaseLiquidity().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ALMKeeperExtension.OnlyKeeper.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseLiquidity_Paused(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
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
        vm.prank(factory);
        almCore.pause();
        Plan.Steps memory plan =
            Plan.init().increaseLiquidity(range.index, almCore.getRange(range.index).unstakedTokenId, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls increaseLiquidity().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.Paused.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseLiquidity_InvalidOrder_AClearedEpochIsUnsettled(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
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

        // And: A pending token0 deposit, cleared by the plan before the step.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);
        Plan.Steps memory plan = Plan.init()
            .clearAllRequests(true, true)
            .increaseLiquidity(range.index, almCore.getRange(range.index).unstakedTokenId, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper calls increaseLiquidity() before the settlement.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.InvalidOrder.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseLiquidity_InvalidPayload(
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
            .increaseLiquidity(
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

    function testFuzz_Revert_increaseLiquidity_RangeMismatch_StakedTokenId(
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
        Plan.Steps memory plan = Plan.init().increaseLiquidity(range.index, range.stakedTokenId, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls increaseLiquidity().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, range.index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseLiquidity_PriceSlippageCheck(
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

        // And: A range.
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: The buffer is refunded with the amounts of a second helping.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        fundBuffer(amount0, amount1);

        // And: A minimum above the desired amount of one token.
        amountMin = bound(amountMin, (minOnToken0 ? amount0 : amount1) + 1, type(uint256).max);
        Plan.Steps memory plan = Plan.init()
            .increaseLiquidity(
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

        // When: The manager calls increaseLiquidity().
        // Then: It reverts with the position manager's slippage check.
        vm.prank(users.keeper);
        vm.expectRevert(bytes("PSC"));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseLiquidity_InvalidPayload_Length(
        PoolState memory poolState,
        bytes memory payload,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An increase payload of any length but its own.
        vm.assume(payload.length != CalldataLogic.INCREASE_LIQUIDITY_LENGTH);
        Plan.Steps memory plan = Plan.init().add(CommandLogic.INCREASE_LIQUIDITY, payload);
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

    function testFuzz_Revert_increaseLiquidity_RangeMismatch_IndexOutOfBounds(
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
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        index = bound(index, almCore.getRangesLength(), type(uint8).max);
        Plan.Steps memory plan = Plan.init().increaseLiquidity(index, range.unstakedTokenId, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper adds liquidity.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseLiquidity_RangeMismatch_NotOpenedInThePlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range from an earlier plan, named by the opened sentinel.
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Plan.Steps memory plan = Plan.init().increaseLiquidity(range.index, Sentinels.OPENED, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper adds liquidity.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, range.index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseLiquidity_RangeMismatch_ClosedEarlierInThePlan(
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

        // And: A neighbour, and a plan closing the range, then adding to its id.
        givenValidRangeState(neighbour, poolState, false);
        setRangeState(neighbour);
        Plan.Steps memory plan = Plan.init()
            .closeRange(range.index, range.unstakedTokenId)
            .increaseLiquidity(range.index, range.unstakedTokenId, 0, 0, 0, 0);
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

    function testFuzz_Revert_increaseLiquidity_ArithmeticError_IncreaseWithinTheEscrow(
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

        // And: A range above the price, so it takes only token0.
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
        Plan.Steps memory plan = Plan.init().increaseLiquidity(range.index, range.unstakedTokenId, amount0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper adds liquidity.
        // Then: The buffer ledger underflows.
        vm.prank(users.keeper);
        vm.expectRevert(stdError.arithmeticError);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseLiquidity_PriceSlippageCheck_MinimumAboveTheAmountUsed(
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

        // And: A range around the price, its edges a spacing from it at least.
        givenValidRangeState(range, poolState, true);
        if (range.tickUpper - poolState.tickCurrent <= poolState.tickSpacing) range.tickUpper += poolState.tickSpacing;
        if (poolState.tickCurrent - range.tickLower < poolState.tickSpacing) range.tickLower -= poolState.tickSpacing;
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Desired amounts doubling one token, so the range uses less than desired.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        (amount0, amount1) = minOnToken0 ? (2 * amount0 + 2, amount1) : (amount0, 2 * amount1 + 2);
        fundBuffer(amount0, amount1);
        (uint256 used0, uint256 used1) = amountsRoundedUp(
            sqrtPriceX96(pool),
            range.tickLower,
            range.tickUpper,
            liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1)
        );

        // And: A minimum on that token above what the range uses, within what is desired.
        amountMin = minOnToken0 ? bound(amountMin, used0 + 1, amount0) : bound(amountMin, used1 + 1, amount1);
        Plan.Steps memory plan = Plan.init()
            .increaseLiquidity(
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

        // When: The keeper adds liquidity.
        // Then: It reverts with the position manager's slippage check.
        vm.prank(users.keeper);
        vm.expectRevert(bytes("PSC"));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_increaseLiquidity_ZeroLiquidity_OneTokenInRange(
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

        // And: A range around the price.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

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
            Plan.init().increaseLiquidity(range.index, range.unstakedTokenId, amount0, amount1, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper adds liquidity.
        // Then: The pool rejects a mint of zero liquidity.
        vm.prank(users.keeper);
        vm.expectRevert(bytes(""));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_increaseLiquidity(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityAdded,
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
        uint128 liquidityBefore = positionLiquidity(almCore.getRange(range.index).unstakedTokenId);

        // And: The buffer is refunded with the amounts of a second helping.
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

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls increaseLiquidity().
        runPlan(
            Plan.init()
                .increaseLiquidity(range.index, almCore.getRange(range.index).unstakedTokenId, amount0, amount1, 0, 0)
        );

        // Then: The leg grew by what the amounts buy, and the buffer paid for it.
        Range memory staged = almCore.getRange(range.index);
        assertEq(
            positionLiquidity(staged.unstakedTokenId),
            uint256(liquidityBefore)
                + liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1)
        );
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1());
    }

    function testFuzz_Success_increaseLiquidity_DebitsBufferByAmountsUsed(
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

        // And: A range.
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        liquidityAdded = uint128(
            bound(
                liquidityAdded,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, 2 * Constants.MIN_FUZZED_LIQUIDITY) / 2
            )
        );
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityAdded);
        (surplus0, surplus1) = (bound(surplus0, 0, amount0), bound(surplus1, 0, amount1));
        fundBuffer(amount0 + surplus0, amount1 + surplus1);
        uint128 liquidityBefore = positionLiquidity(almCore.getRange(range.index).unstakedTokenId);
        surplus0 = almCore.bufferAmount0();
        surplus1 = almCore.bufferAmount1();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls increaseLiquidity() with the whole buffer.
        runPlan(
            Plan.init()
                .increaseLiquidity(range.index, almCore.getRange(range.index).unstakedTokenId, surplus0, surplus1, 0, 0)
        );

        // Then: The buffer is debited by what the position manager consumed.
        (amount0, amount1) = amountsRoundedUp(
            sqrtPriceX96(pool),
            range.tickLower,
            range.tickUpper,
            positionLiquidity(almCore.getRange(range.index).unstakedTokenId) - liquidityBefore
        );
        assertEq(almCore.bufferAmount0(), surplus0 - amount0);
        assertEq(almCore.bufferAmount1(), surplus1 - amount1);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1());
    }

    function testFuzz_Success_increaseLiquidity_OpenBalanceLeavesThePayouts(
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

        // And: The open buffer share the range opens with.
        bps = bound(bps, 1, ConfigLib.BPS_DENOMINATOR - 1);

        // And: The liquidity each step buys from the buffer net of the payout.
        uint256 expected;
        {
            uint256 buffer0 = almCore.bufferAmount0() + queueState.deposit0;
            uint256 buffer1 = almCore.bufferAmount1() + queueState.deposit1;
            buffer0 -= token1ToToken0(
                poolState.sqrtPrice,
                queueState.redeem0
                    .fullMulDiv(
                        buffer1 - queueState.deposit1
                            + token0ToToken1(poolState.sqrtPrice, buffer0 - queueState.deposit0),
                        almCore.totalSupply()
                    )
            );
            for (uint256 i; i < 2; ++i) {
                uint256 share = i == 0 ? bps : ConfigLib.BPS_DENOMINATOR;
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
                expected += bought;
            }
        }

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(6, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears, opens a range, and adds the whole open buffer to it.
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .clearAllRequests(false, true)
                .clearAllRequests(true, false)
                .clearAllRequests(false, false)
                .settleRequests()
                .openRange(
                    range.tickLower, range.tickUpper, Sentinels.OPEN_BALANCE | bps, Sentinels.OPEN_BALANCE | bps, 0, 0
                )
                .increaseLiquidity(
                    0,
                    Sentinels.OPENED,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    0,
                    0
                )
        );

        // Then: The redeem settles with its payout in escrow.
        assertEq(almCore.getEscrowed0(), almCore.redeemEpoch(asyncVault0, 0).amountOut);

        // And: The range holds the liquidity both steps bought.
        assertEq(positionLiquidity(almCore.getRange(0).unstakedTokenId), expected);
    }

    function testFuzz_Success_increaseLiquidity_OpenBalanceShare(
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

        // And: A range.
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        uint128 liquidityBefore = positionLiquidity(almCore.getRange(range.index).unstakedTokenId);

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

        // When: The keeper adds that share of the open buffer to the range.
        runPlan(
            Plan.init()
                .increaseLiquidity(
                    range.index,
                    almCore.getRange(range.index).unstakedTokenId,
                    Sentinels.OPEN_BALANCE | bps,
                    Sentinels.OPEN_BALANCE | bps,
                    0,
                    0
                )
        );

        // Then: The range took that liquidity, and the buffer paid exactly its amounts.
        (uint256 used0, uint256 used1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);
        assertEq(positionLiquidity(almCore.getRange(range.index).unstakedTokenId), liquidityBefore + liquidity);
        assertEq(almCore.bufferAmount0(), amount0 - used0);
        assertEq(almCore.bufferAmount1(), amount1 - used1);
    }

    function testFuzz_Success_increaseLiquidity_ReadsNoPenaltyWindow(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityAdded,
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

        // And: The buffer is refunded with the amounts of a second helping.
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

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager adds liquidity to the unstaked side.
        // Then: The gauge factory's penalty config is not read.
        vm.expectCall(
            almCore.GAUGE_FACTORY_(), abi.encodeWithSelector(IMetadexCLGaugeFactory.effectivePenaltyConfig.selector), 0
        );
        runPlan(
            Plan.init()
                .increaseLiquidity(range.index, almCore.getRange(range.index).unstakedTokenId, amount0, amount1, 0, 0)
        );
    }

    function testFuzz_Success_increaseLiquidity_OpenBalanceSharePastThePayout(
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

        // And: A range around the price, a real share of the room.
        givenValidRangeState(range, poolState, true, false);
        {
            uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
            range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));
        }

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

        // When: The keeper clears the queues and adds that share to the range.
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .clearAllRequests(false, true)
                .clearAllRequests(true, false)
                .clearAllRequests(false, false)
                .settleRequests()
                .increaseLiquidity(
                    range.index, range.unstakedTokenId, Sentinels.OPEN_BALANCE | bps, Sentinels.OPEN_BALANCE | bps, 0, 0
                )
        );

        // Then: The range took that liquidity.
        assertEq(positionLiquidity(almCore.getRange(range.index).unstakedTokenId), uint256(range.liquidity) + expected);

        // And: The redeem settles with its payout in escrow.
        assertEq(
            isToken0 ? almCore.getEscrowed0() : almCore.getEscrowed1(),
            (isToken0 ? almCore.redeemEpoch(asyncVault0, 0) : almCore.redeemEpoch(asyncVault1, 0)).amountOut
        );
    }
}
