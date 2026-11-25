/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { CalldataLogic } from "../../../src/core/libraries/logic/CalldataLogic.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { CommandLogic } from "../../../src/core/libraries/logic/CommandLogic.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { Plan } from "../../utils/Plan.sol";
import { PoolTokensLib } from "../../../src/core/libraries/state/PoolTokensLib.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { RangesLib } from "../../../src/core/libraries/state/RangesLib.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";
import { stdError } from "@forge-std/StdError.sol";

/**
 * @notice Fuzz tests for the function "openRange" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events, unsafe-typecast, unused-return)
contract OpenRange_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_openRange_OnlyKeeper(
        address caller,
        PoolState memory poolState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);

        // And: The caller is not a keeper.
        vm.assume(caller != users.keeper);
        Plan.Steps memory plan = Plan.init().openRange(range.tickLower, range.tickUpper, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling openRange().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ALMKeeperExtension.OnlyKeeper.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_openRange_Paused(
        PoolState memory poolState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);

        // And: The vault is paused.
        vm.prank(factory);
        almCore.pause();
        Plan.Steps memory plan = Plan.init().openRange(range.tickLower, range.tickUpper, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls openRange().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.Paused.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_openRange_InvalidOrder_AClearedEpochIsUnsettled(
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
        Plan.Steps memory plan =
            Plan.init().clearAllRequests(true, true).openRange(range.tickLower, range.tickUpper, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper calls openRange() before the settlement.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.InvalidOrder.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_openRange_InvalidPayload(
        PoolState memory poolState,
        RangeState memory range,
        uint256 bps,
        bool onToken0,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);

        // And: An open buffer flag on a remainder above the bps denominator, one token.
        bps = bound(bps, ConfigLib.BPS_DENOMINATOR + 1, Sentinels.OPEN_BALANCE - 1);
        Plan.Steps memory plan = Plan.init()
            .openRange(
                range.tickLower,
                range.tickUpper,
                onToken0 ? Sentinels.OPEN_BALANCE | bps : 0,
                onToken0 ? 0 : Sentinels.OPEN_BALANCE | bps,
                0,
                0
            );
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper opens the range.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_openRange_TargetRatioOnAMintFieldIsAnOverflowingLiteral(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 bps,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price.
        givenValidRangeState(range, poolState, true, false);

        // And: A seeded vault.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: The buffer holds the amounts the range needs.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        fundBuffer(amount0, amount1);

        // And: A target ratio flag on the token0 amount.
        bps = bound(bps, 0, Sentinels.TO_TARGET_RATIO - 1);
        Plan.Steps memory plan =
            Plan.init().openRange(range.tickLower, range.tickUpper, Sentinels.TO_TARGET_RATIO | bps, amount1, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper opens the range.
        // Then: The position manager reverts on the liquidity of the literal amount.
        vm.prank(users.keeper);
        vm.expectRevert(bytes(""));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_openRange_RangeCapExceeded(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A single range fills a range cap of one.
        vm.prank(factory);
        almCore.setRangeCap(1);
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Plan.Steps memory plan =
            Plan.init().openRange(range.tickLower - poolState.tickSpacing, range.tickUpper, 0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls openRange() for a second range.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(RangesLib.RangeCapExceeded.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_openRange_PriceSlippageCheck(
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
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: The buffer holds the amounts the range needs.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        fundBuffer(amount0, amount1);

        // And: A minimum above the desired amount of one token.
        amountMin = bound(amountMin, (minOnToken0 ? amount0 : amount1) + 1, type(uint256).max);
        Plan.Steps memory plan = Plan.init()
            .openRange(
                range.tickLower,
                range.tickUpper,
                amount0,
                amount1,
                minOnToken0 ? amountMin : 0,
                minOnToken0 ? 0 : amountMin
            );
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls openRange().
        // Then: It reverts with the position manager's slippage check.
        vm.prank(users.keeper);
        vm.expectRevert(bytes("PSC"));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_openRange_InvalidPayload_Length(
        PoolState memory poolState,
        bytes memory payload,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An open payload of any length but its own.
        vm.assume(payload.length != CalldataLogic.OPEN_RANGE_LENGTH);
        Plan.Steps memory plan = Plan.init().add(CommandLogic.OPEN_RANGE, payload);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper opens the range.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_openRange_ArithmeticError_MintWithinTheEscrow(
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

        // And: Ticks above the price, so a range there takes only token0.
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

        // And: A seeded vault whose buffer holds what such a range needs.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

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

        // And: Token0 past the buffer by half the escrow.
        amount0 =
            bound(amount0, almCore.bufferAmount0() + almCore.getEscrowed0() / 2, token0.balanceOf(address(almCore)));
        Plan.Steps memory plan = Plan.init().openRange(range.tickLower, range.tickUpper, amount0, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper opens the range.
        // Then: The buffer ledger underflows.
        vm.prank(users.keeper);
        vm.expectRevert(stdError.arithmeticError);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_openRange_InsufficientBuffer_PayoutAboveTheBuffer(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Ticks below the price, so a range there takes only token1.
        givenValidRangeState(range, poolState, false, false);
        range.tickUpper = int24(
            bound(
                range.tickUpper / poolState.tickSpacing,
                -(bandTick(poolState.tickSpacing) / poolState.tickSpacing) + 2,
                (poolState.tickCurrent - poolState.tickSpacing) / poolState.tickSpacing
            )
        ) * poolState.tickSpacing;
        range.tickLower = int24(
            bound(
                range.tickLower / poolState.tickSpacing,
                -(bandTick(poolState.tickSpacing) / poolState.tickSpacing) + 1,
                range.tickUpper / poolState.tickSpacing - 1
            )
        ) * poolState.tickSpacing;
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A vault with token1 worth sixteen token0 wei and thrice the dead shares.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        uint256 least = FixedPointMathLib.fullMulDivUp(16, poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192) + 3
            * almCore.DEAD_SHARES_();
        coreState.buffer1 = bound(coreState.buffer1, least, FixedPointMathLib.max(coreState.buffer1, least));

        // And: Token0 worth an eighth of the token1 at most, a supply up to the value.
        coreState.buffer0 = bound(coreState.buffer0, 1, token1ToToken0(poolState.sqrtPrice, coreState.buffer1) / 8);
        coreState.supply = bound(
            coreState.supply,
            3 * almCore.DEAD_SHARES_(),
            FixedPointMathLib.max(
                coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0), 3 * almCore.DEAD_SHARES_()
            )
        );
        setCoreState(coreState);

        // And: A token0 redeem only, owed at least twice the token0 buffer.
        givenValidQueueState(queueState, 0, 0);
        (queueState.deposit0, queueState.deposit1, queueState.redeem1) = (0, 0, 0);
        uint256 value = almCore.bufferAmount1() + token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0());
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            FixedPointMathLib.fullMulDivUp(
                2 * almCore.bufferAmount0() + 1, poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192
            ),
            almCore.totalSupply(),
            value
        );
        queueState.redeem0 = bound(queueState.redeem0, floor, FixedPointMathLib.max(queueState.redeem0, floor));
        setQueueState(queueState);
        Plan.Steps memory plan = Plan.init()
            .clearAllRequests(true, false)
            .settleRequests()
            .openRange(
                range.tickLower,
                range.tickUpper,
                Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                0,
                0
            );
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper clears and mints the open buffer, token0's floored at zero.
        // Then: The settlement finds the token0 buffer short of the payout.
        vm.prank(users.keeper);
        vm.expectRevert(PoolTokensLib.InsufficientBuffer.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_openRange_TLU_TicksSwapped(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: The buffer holds the amounts the range needs.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        fundBuffer(amount0, amount1);
        Plan.Steps memory plan = Plan.init().openRange(range.tickUpper, range.tickLower, amount0, amount1, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper opens the range with its ticks swapped.
        // Then: The pool rejects the ticks.
        vm.prank(users.keeper);
        vm.expectRevert(bytes("TLU"));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_openRange_PriceSlippageCheck_MinimumAboveTheAmountUsed(
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

        // And: A range around the price.
        givenValidRangeState(range, poolState, true, false);

        // And: A seeded vault.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: Desired amounts doubling one token, so the range uses less than desired.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        (amount0, amount1) = minOnToken0 ? (2 * amount0 + 1, amount1) : (amount0, 2 * amount1 + 1);
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
            .openRange(
                range.tickLower,
                range.tickUpper,
                amount0,
                amount1,
                minOnToken0 ? amountMin : 0,
                minOnToken0 ? 0 : amountMin
            );
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper opens the range.
        // Then: It reverts with the position manager's slippage check.
        vm.prank(users.keeper);
        vm.expectRevert(bytes("PSC"));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_openRange_ZeroLiquidity(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool share,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: The buffer holds the amounts the range needs.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        fundBuffer(amount0, amount1);

        // And: Zero amounts, as literals or as a zero share of the open buffer.
        uint256 amount = share ? Sentinels.OPEN_BALANCE : 0;
        Plan.Steps memory plan = Plan.init().openRange(range.tickLower, range.tickUpper, amount, amount, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper opens the range.
        // Then: The pool rejects a mint of zero liquidity.
        vm.prank(users.keeper);
        vm.expectRevert(bytes(""));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_openRange_SecondRangeAtTheSameTicks(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range already exists at these ticks.
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        uint256 first = range.index;

        // When: The manager calls openRange() at the same ticks.
        setRangeState(range);
        uint256 second = range.index;

        // Then: Both ranges hold their own position.
        assertEq(almCore.getRangesLength(), 2);
        assertTrue(almCore.getRange(first).unstakedTokenId != almCore.getRange(second).unstakedTokenId);
        assertEq(almCore.getRange(second).tickLower, range.tickLower);
        assertEq(almCore.getRange(second).tickUpper, range.tickUpper);
    }

    function testFuzz_Success_openRange(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: The buffer holds the amounts the range needs.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        fundBuffer(amount0, amount1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls openRange().
        uint256 index = almCore.getRangesLength();
        runPlan(Plan.init().openRange(range.tickLower, range.tickUpper, amount0, amount1, 0, 0));

        // Then: The range is opened with its unstaked leg and no staked leg.
        assertEq(index, 0);
        assertEq(almCore.getRangesLength(), 1);
        Range memory staged = almCore.getRange(index);
        assertEq(staged.tickLower, range.tickLower);
        assertEq(staged.tickUpper, range.tickUpper);
        assertEq(staged.stakedTokenId, 0);
        assertEq(staged.stakedLiquidity, 0);
        assertGt(staged.unstakedTokenId, 0);

        // And: The leg holds the liquidity the amounts buy.
        assertEq(
            positionLiquidity(staged.unstakedTokenId),
            liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1)
        );
    }

    function testFuzz_Success_openRange_TheSentinelNamesAThirdRange(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory second,
        RangeState memory opened,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding two ranges without staked legs.
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

        // And: A third range, and a buffer twice what it needs, to open it and stake it.
        givenValidRangeState(opened, poolState, false);
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), opened.tickLower, opened.tickUpper, opened.liquidity);
        fundBuffer(2 * amount0, 2 * amount1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        setPlanLimits(configState);

        // When: The plan opens it, then stakes it through the opened sentinel at index 2.
        runPlan(
            Plan.init()
                .openRange(opened.tickLower, opened.tickUpper, amount0, amount1, 0, 0)
                .stake(2, Sentinels.OPENED, amount0, amount1, 0, 0)
        );

        // Then: The third range is staked.
        assertEq(almCore.getRangesLength(), 3);
        assertTrue(almCore.getRange(2).stakedTokenId != 0);
    }

    function testFuzz_Success_openRange_DebitsBufferByAmountsUsed(
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
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: The buffer holds up to twice what the range needs.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        (surplus0, surplus1) = (bound(surplus0, 0, amount0), bound(surplus1, 0, amount1));
        fundBuffer(amount0 + surplus0, amount1 + surplus1);
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls openRange() with the whole buffer as both amounts.
        uint256 index = almCore.getRangesLength();
        runPlan(Plan.init().openRange(range.tickLower, range.tickUpper, buffer0Before, buffer1Before, 0, 0));

        // Then: The buffer is debited by what the position manager consumed.
        Range memory staged = almCore.getRange(index);
        (uint256 used0, uint256 used1) = amountsRoundedUp(
            sqrtPriceX96(pool), range.tickLower, range.tickUpper, positionLiquidity(staged.unstakedTokenId)
        );
        assertEq(almCore.bufferAmount0(), buffer0Before - used0);
        assertEq(almCore.bufferAmount1(), buffer1Before - used1);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1());
    }

    function testFuzz_Success_openRange_OpenBalanceLeavesThePayouts(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Ticks around the price, for a range the seed funds.
        givenValidRangeState(range, poolState, true, false);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

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

        // And: The liquidity the step buys from the buffer net of the payout.
        uint256 expected;
        uint256 buffer0 = almCore.bufferAmount0() + queueState.deposit0;
        uint256 buffer1 = almCore.bufferAmount1() + queueState.deposit1;
        for (uint256 i; i < 1; ++i) {
            uint256 open0 = token1ToToken0(
                poolState.sqrtPrice,
                queueState.redeem0
                    .fullMulDiv(
                        buffer1 - queueState.deposit1
                            + token0ToToken1(poolState.sqrtPrice, buffer0 - queueState.deposit0),
                        almCore.totalSupply()
                    )
            );
            open0 = (buffer0 - open0) * (ConfigLib.BPS_DENOMINATOR) / ConfigLib.BPS_DENOMINATOR;
            uint128 bought = liquidityForAmounts(
                uint160(poolState.sqrtPrice),
                range.tickLower,
                range.tickUpper,
                open0,
                buffer1 * (ConfigLib.BPS_DENOMINATOR) / ConfigLib.BPS_DENOMINATOR
            );
            (uint256 amount0, uint256 amount1) =
                amountsRoundedUp(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, bought);
            (buffer0, buffer1) = (buffer0 - amount0, buffer1 - amount1);
            if (i >= 0) expected += bought;
        }

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(5, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the queues and opens a range with the open buffer.
        runPlan(
            Plan.init()
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
        );

        // Then: The redeem settles with its payout in escrow.
        assertEq(almCore.getEscrowed0(), almCore.redeemEpoch(asyncVault0, 0).amountOut);

        // And: The range holds that liquidity.
        assertEq(positionLiquidity(almCore.getRange(0).unstakedTokenId), expected);
    }

    function testFuzz_Success_openRange_OpenBalanceShare(
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
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: The buffer holds up to twice what the range needs.
        {
            (uint256 amount0, uint256 amount1) =
                amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
            (surplus0, surplus1) = (bound(surplus0, 0, amount0), bound(surplus1, 0, amount1));
            fundBuffer(amount0 + surplus0, amount1 + surplus1);
        }
        uint256 buffer0 = almCore.bufferAmount0();
        uint256 buffer1 = almCore.bufferAmount1();

        // And: A share buying at least the liquidity floor, and the liquidity it buys.
        {
            (uint256 least0, uint256 least1) =
                amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
            bps = bound(
                bps,
                FixedPointMathLib.max(
                    least0 == 0 ? 0 : FixedPointMathLib.divUp(least0 * ConfigLib.BPS_DENOMINATOR, buffer0),
                    least1 == 0 ? 0 : FixedPointMathLib.divUp(least1 * ConfigLib.BPS_DENOMINATOR, buffer1)
                ),
                ConfigLib.BPS_DENOMINATOR
            );
        }
        uint128 liquidity = liquidityForAmounts(
            sqrtPriceX96(pool),
            range.tickLower,
            range.tickUpper,
            buffer0 * bps / ConfigLib.BPS_DENOMINATOR,
            buffer1 * bps / ConfigLib.BPS_DENOMINATOR
        );

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper opens the range with that share of the open buffer.
        runPlan(
            Plan.init()
                .openRange(
                    range.tickLower, range.tickUpper, Sentinels.OPEN_BALANCE | bps, Sentinels.OPEN_BALANCE | bps, 0, 0
                )
        );

        // Then: The range holds that liquidity, and the buffer paid exactly its amounts.
        (uint256 used0, uint256 used1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);
        assertEq(positionLiquidity(almCore.getRange(0).unstakedTokenId), liquidity);
        assertEq(almCore.bufferAmount0(), buffer0 - used0);
        assertEq(almCore.bufferAmount1(), buffer1 - used1);
    }

    function testFuzz_Success_openRange_EmitsRangeOpened(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: The buffer holds the amounts the range needs.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        fundBuffer(amount0, amount1);

        // And: The token id the position manager mints next, and the liquidity bought.
        uint256 tokenId = POSITION_MANAGER.totalSupply() + 1;
        uint128 liquidity = liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls openRange().
        Plan.Steps memory plan = Plan.init().openRange(range.tickLower, range.tickUpper, amount0, amount1, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        vm.expectEmit(address(almCore));
        // Then: It emits RangeOpened.
        emit IALMCoreEvents.RangeOpened(0, range.tickLower, range.tickUpper, tokenId, liquidity);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_openRange_SecondRangeAtDistinctTicks(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory second
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A first range.
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A second range at other ticks.
        givenValidRangeState(second, poolState, false);
        vm.assume(second.tickLower != range.tickLower || second.tickUpper != range.tickUpper);

        // When: The manager opens it.
        setRangeState(second);

        // Then: Both ranges are held.
        assertEq(second.index, 1);
        assertEq(almCore.getRangesLength(), 2);
        assertEq(almCore.getRange(1).tickLower, second.tickLower);
        assertEq(almCore.getRange(1).tickUpper, second.tickUpper);
    }

    function testFuzz_Success_openRange_UpToTheRangeCap(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 cap
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: A range cap, all its slots but one taken by ranges of the least liquidity.
        cap = bound(cap, 1, ConfigLib.MAX_RANGE_CAP);
        vm.prank(factory);
        almCore.setRangeCap(uint8(cap));
        for (uint256 i = 1; i < cap; ++i) {
            setRangeState(
                RangeState({
                    index: 0,
                    tickLower: range.tickLower,
                    tickUpper: range.tickUpper,
                    liquidity: Constants.MIN_FUZZED_LIQUIDITY,
                    liquidityStaked: 0,
                    unstakedTokenId: 0,
                    stakedTokenId: 0
                })
            );
        }

        // When: The keeper opens a range in the last slot.
        setRangeState(range);

        // Then: The core holds as many ranges as its cap.
        assertEq(range.index, cap - 1);
        assertEq(almCore.getRangesLength(), cap);
    }

    function testFuzz_Success_openRange_MinimumAtTheAmountsUsed(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: The buffer holds the amounts the range needs, and what it uses of them.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        fundBuffer(amount0, amount1);
        uint128 liquidity = liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1);
        (uint256 used0, uint256 used1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);
        uint256 buffer0 = almCore.bufferAmount0();
        uint256 buffer1 = almCore.bufferAmount1();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper opens the range with minimums at the amounts used.
        runPlan(Plan.init().openRange(range.tickLower, range.tickUpper, amount0, amount1, used0, used1));

        // Then: The range holds the liquidity, the buffer paid exactly the amounts used.
        assertEq(positionLiquidity(almCore.getRange(0).unstakedTokenId), liquidity);
        assertEq(almCore.bufferAmount0(), buffer0 - used0);
        assertEq(almCore.bufferAmount1(), buffer1 - used1);
    }

    function testFuzz_Success_openRange_AboveThePriceTakesOnlyToken0(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 surplus1,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range above the price.
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

        // And: A seeded vault.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: The buffer holds the token0 the range needs, and token1 it does not take.
        (uint256 amount0,) = amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        surplus1 = bound(surplus1, 0, Constants.MAX_FUZZED_AMOUNT / 4);
        fundBuffer(amount0, surplus1);
        uint256 buffer0 = almCore.bufferAmount0();
        uint256 buffer1 = almCore.bufferAmount1();
        uint128 liquidity = liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, buffer0, 0);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper opens the range with the whole buffer.
        runPlan(Plan.init().openRange(range.tickLower, range.tickUpper, buffer0, buffer1, 0, 0));

        // Then: The range holds what the token0 buys, and only token0 left the buffer.
        (uint256 used0,) = amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);
        assertEq(positionLiquidity(almCore.getRange(0).unstakedTokenId), liquidity);
        assertEq(almCore.bufferAmount0(), buffer0 - used0);
        assertEq(almCore.bufferAmount1(), buffer1);
    }

    function testFuzz_Success_openRange_BelowThePriceTakesOnlyToken1(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 surplus0,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range below the price.
        givenValidRangeState(range, poolState, false, false);
        range.tickUpper = int24(
            bound(
                range.tickUpper / poolState.tickSpacing,
                -(bandTick(poolState.tickSpacing) / poolState.tickSpacing) + 2,
                (poolState.tickCurrent - poolState.tickSpacing) / poolState.tickSpacing
            )
        ) * poolState.tickSpacing;
        range.tickLower = int24(
            bound(
                range.tickLower / poolState.tickSpacing,
                -(bandTick(poolState.tickSpacing) / poolState.tickSpacing) + 1,
                range.tickUpper / poolState.tickSpacing - 1
            )
        ) * poolState.tickSpacing;
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A seeded vault.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: The buffer holds the token1 the range needs, and token0 it does not take.
        (, uint256 amount1) = amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        surplus0 = bound(surplus0, 0, Constants.MAX_FUZZED_AMOUNT / 4);
        fundBuffer(surplus0, amount1);
        uint256 buffer0 = almCore.bufferAmount0();
        uint256 buffer1 = almCore.bufferAmount1();
        uint128 liquidity = liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, 0, buffer1);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper opens the range with the whole buffer.
        runPlan(Plan.init().openRange(range.tickLower, range.tickUpper, buffer0, buffer1, 0, 0));

        // Then: The range holds what the token1 buys, and only token1 left the buffer.
        (, uint256 used1) = amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);
        assertEq(positionLiquidity(almCore.getRange(0).unstakedTokenId), liquidity);
        assertEq(almCore.bufferAmount0(), buffer0);
        assertEq(almCore.bufferAmount1(), buffer1 - used1);
    }

    function testFuzz_Success_openRange_OpenBalanceSharePastThePayout(
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

        // And: Ticks around the price, for a range the seed funds.
        givenValidRangeState(range, poolState, true, false);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

        // And: A seeded vault worth no more in the other token than in the redeemed one.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 2, 0, 0);
        if (isToken0) {
            coreState.buffer1 = bound(
                coreState.buffer1, 1, FixedPointMathLib.max(token0ToToken1(poolState.sqrtPrice, coreState.buffer0), 1)
            );
        } else {
            coreState.buffer0 = bound(
                coreState.buffer0, 1, FixedPointMathLib.max(token1ToToken0(poolState.sqrtPrice, coreState.buffer1), 1)
            );
        }
        setCoreState(coreState);

        // And: Pending deposits of up to the buffer, and a redeem of one token only.
        givenValidQueueState(queueState, 0, 0);
        queueState.deposit0 =
            bound(queueState.deposit0, 0, FixedPointMathLib.min(queueState.deposit0, almCore.bufferAmount0()));
        queueState.deposit1 =
            bound(queueState.deposit1, 0, FixedPointMathLib.min(queueState.deposit1, almCore.bufferAmount1()));
        queueState.redeem0 = isToken0 ? bound(queueState.redeem0, 1, FixedPointMathLib.max(queueState.redeem0, 1)) : 0;
        queueState.redeem1 = isToken0 ? 0 : bound(queueState.redeem1, 1, FixedPointMathLib.max(queueState.redeem1, 1));
        setQueueState(queueState);

        // And: The payout settled before the step, and the liquidity an open share buys.
        bps = bound(bps, 1, ConfigLib.BPS_DENOMINATOR);
        uint128 expected;
        uint160 sqrtPrice = sqrtPriceX96(pool);
        uint256 buffer0 = almCore.bufferAmount0() + queueState.deposit0;
        uint256 buffer1 = almCore.bufferAmount1() + queueState.deposit1;
        uint256 value = almCore.bufferAmount1() + token0ToToken1(sqrtPrice, almCore.bufferAmount0());
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

        // When: The keeper clears the queues and opens a range with that share.
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
        );

        // Then: The range holds that liquidity.
        assertEq(positionLiquidity(almCore.getRange(0).unstakedTokenId), expected);

        // And: The redeem settles with its payout in escrow.
        assertEq(
            isToken0 ? almCore.getEscrowed0() : almCore.getEscrowed1(),
            (isToken0 ? almCore.redeemEpoch(asyncVault0, 0) : almCore.redeemEpoch(asyncVault1, 0)).amountOut
        );
    }
}
