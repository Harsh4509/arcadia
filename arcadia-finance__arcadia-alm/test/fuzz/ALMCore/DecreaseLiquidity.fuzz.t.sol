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
import { IMetadexCLGaugeFactory } from "../../../src/interfaces/IMetadexCLGaugeFactory.sol";
import { Plan } from "../../utils/Plan.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";

/**
 * @notice Fuzz tests for the function "decreaseLiquidity" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract DecreaseLiquidity_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_decreaseLiquidity_OnlyKeeper(
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
            Plan.init().decreaseLiquidity(range.index, almCore.getRange(range.index).unstakedTokenId, 1, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling decreaseLiquidity().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ALMKeeperExtension.OnlyKeeper.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_decreaseLiquidity_RangeMismatch_StakedTokenId(
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
        Plan.Steps memory plan = Plan.init().decreaseLiquidity(range.index, range.stakedTokenId, range.liquidity, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls decreaseLiquidity().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, range.index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_decreaseLiquidity_RangeMismatch_OutOfBounds(
        PoolState memory poolState,
        uint256 index,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No ranges at all, and a step naming one.
        index = bound(index, 0, type(uint8).max);
        Plan.Steps memory plan = Plan.init().decreaseLiquidity(index, Sentinels.OPENED, 1, 0, 0);
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

    function testFuzz_Revert_decreaseLiquidity_RangeMismatch_ZeroTokenId(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range, and a step naming it by token id zero.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Plan.Steps memory plan = Plan.init().decreaseLiquidity(range.index, 0, 1, 0, 0);
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

    function testFuzz_Revert_decreaseLiquidity_RangeMismatch_OpenedNotInThePlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range opened before the plan, and a step naming it as opened.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Plan.Steps memory plan = Plan.init().decreaseLiquidity(range.index, Sentinels.OPENED, 1, 0, 0);
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

    function testFuzz_Revert_decreaseLiquidity_RangeMismatch_ClosedEarlierInThePlan(
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

        // And: A neighbour, and a plan closing the range then decreasing its token id.
        givenValidRangeState(neighbour, poolState, false);
        setRangeState(neighbour);
        Plan.Steps memory plan = Plan.init()
            .closeRange(range.index, range.unstakedTokenId)
            .decreaseLiquidity(range.index, range.unstakedTokenId, 1, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it, the step meeting the range moved into the slot.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSelector(ALMKeeperExtension.RangeMismatch.selector, range.index));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_decreaseLiquidity_InvalidPayload(
        PoolState memory poolState,
        uint256 length,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A decrease payload of any length but its own.
        length = bound(length, 0, 2 * CalldataLogic.DECREASE_LIQUIDITY_LENGTH);
        vm.assume(length != CalldataLogic.DECREASE_LIQUIDITY_LENGTH);
        Plan.Steps memory plan = Plan.init().add(CommandLogic.DECREASE_LIQUIDITY, new bytes(length));
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

    function testFuzz_Revert_decreaseLiquidity_RemovesMoreThanTheSide(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidity,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range, and more liquidity than its side holds, short of the sentinel.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        liquidity = uint128(bound(liquidity, uint256(range.liquidity) + 1, Sentinels.RANGE_LIQUIDITY - 1));
        Plan.Steps memory plan = Plan.init().decreaseLiquidity(range.index, range.unstakedTokenId, liquidity, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: The position manager reverts.
        vm.prank(users.keeper);
        vm.expectRevert(bytes(""));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_decreaseLiquidity_ZeroLiquidity(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range, and a step removing no liquidity.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Plan.Steps memory plan = Plan.init().decreaseLiquidity(range.index, range.unstakedTokenId, 0, 0, 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: The position manager reverts.
        vm.prank(users.keeper);
        vm.expectRevert(bytes(""));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_decreaseLiquidity_PriceSlippageCheck(
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

        // And: A range without a staked leg.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        liquidityRemoved = uint128(bound(liquidityRemoved, 1, range.liquidity));

        // And: A minimum above what the removed liquidity releases of one token.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityRemoved);
        amountMin = bound(amountMin, (minOnToken0 ? amount0 : amount1) + 1, type(uint256).max);
        Plan.Steps memory plan = Plan.init()
            .decreaseLiquidity(
                range.index,
                range.unstakedTokenId,
                liquidityRemoved,
                minOnToken0 ? amountMin : 0,
                minOnToken0 ? 0 : amountMin
            );
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls decreaseLiquidity().
        // Then: It reverts with the position manager's slippage check.
        vm.prank(users.keeper);
        vm.expectRevert(bytes("PS"));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_decreaseLiquidity(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 liquidityRemoved,
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
        uint128 liquidityBefore = positionLiquidity(almCore.getRange(range.index).unstakedTokenId);
        liquidityRemoved = uint128(bound(liquidityRemoved, 1, liquidityBefore));
        (uint256 amount0, uint256 amount1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityRemoved);
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls decreaseLiquidity().
        runPlan(
            Plan.init()
                .decreaseLiquidity(range.index, almCore.getRange(range.index).unstakedTokenId, liquidityRemoved, 0, 0)
        );

        // Then: The cached liquidity tracks the leg, the buffer holds what was released.
        Range memory staged = almCore.getRange(range.index);
        assertEq(positionLiquidity(staged.unstakedTokenId), liquidityBefore - liquidityRemoved);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1());

        // And: The buffer grew by the removed principal, rounded down by the pool.
        assertEq(almCore.bufferAmount0() - buffer0Before, amount0);
        assertEq(almCore.bufferAmount1() - buffer1Before, amount1);
    }

    function testFuzz_Success_decreaseLiquidity_MinAtTheRelease(
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

        // And: A range without a staked leg.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        liquidityRemoved = uint128(bound(liquidityRemoved, 1, range.liquidity));

        // And: A minimum equal to what the removed liquidity releases of one token.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityRemoved);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls decreaseLiquidity().
        runPlan(
            Plan.init()
                .decreaseLiquidity(
                    range.index,
                    range.unstakedTokenId,
                    liquidityRemoved,
                    minOnToken0 ? amount0 : 0,
                    minOnToken0 ? 0 : amount1
                )
        );

        // Then: The liquidity is removed.
        assertEq(positionLiquidity(almCore.getRange(range.index).unstakedTokenId), range.liquidity - liquidityRemoved);
    }

    function testFuzz_Success_decreaseLiquidity_CreditsBuffer(
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
        uint128 liquidityBefore = positionLiquidity(almCore.getRange(range.index).unstakedTokenId);
        (uint256 amount0, uint256 amount1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityBefore);
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager removes all of it.
        runPlan(
            Plan.init()
                .decreaseLiquidity(range.index, almCore.getRange(range.index).unstakedTokenId, liquidityBefore, 0, 0)
        );

        // Then: The whole principal, rounded down by the pool, is back in the buffer.
        assertEq(almCore.bufferAmount0() - buffer0Before, amount0);
        assertEq(almCore.bufferAmount1() - buffer1Before, amount1);
    }

    function testFuzz_Success_decreaseLiquidity_AccruesTheProtocolFeeOnce(
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

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 2, true, amountIn, poolSwapOut(true, amountIn));
        setPlanLimits(configState);

        // When: The manager swaps through the range and then removes all of it.
        runPlan(
            Plan.init()
                .swapViaPool(true, amountIn, priceLimit(true), 0)
                .decreaseLiquidity(range.index, range.unstakedTokenId, range.liquidity, 0, 0)
        );

        // Then: The protocol share of the decrease's fees is floored once.
        assertGt(fees0, 0);
        assertEq(almCore.getProtocolFees0(), fees0 * feeBps / almCore.BPS_DENOMINATOR_());
        assertEq(almCore.getProtocolFees1(), fees1 * feeBps / almCore.BPS_DENOMINATOR_());
    }

    function testFuzz_Success_decreaseLiquidity_Paused(
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
        uint128 liquidityBefore = positionLiquidity(almCore.getRange(range.index).unstakedTokenId);
        vm.prank(factory);
        almCore.pause();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls decreaseLiquidity().
        runPlan(
            Plan.init()
                .decreaseLiquidity(range.index, almCore.getRange(range.index).unstakedTokenId, liquidityBefore, 0, 0)
        );

        // Then: The liquidity is removed.
        assertEq(positionLiquidity(almCore.getRange(range.index).unstakedTokenId), 0);
    }

    function testFuzz_Success_decreaseLiquidity_RemovesDonatedLiquidity(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 donation,
        uint128 liquidity,
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

        // And: A third party added liquidity to the range's position.
        uint256 tokenId = range.unstakedTokenId;
        donateToRange(range, uint128(bound(donation, 1, range.liquidity)));
        uint128 liquidityBefore = positionLiquidity(tokenId);
        assertGt(liquidityBefore, range.liquidity);

        // And: A decrease above what the core minted but within the position.
        liquidity = uint128(bound(liquidity, uint256(range.liquidity) + 1, liquidityBefore));
        (uint256 principal0, uint256 principal1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager removes it.
        runPlan(Plan.init().decreaseLiquidity(range.index, tokenId, liquidity, 0, 0));

        // Then: The position shrank by it and the buffer holds its principal.
        assertEq(positionLiquidity(tokenId), liquidityBefore - liquidity);
        assertEq(almCore.bufferAmount0() - buffer0Before, principal0);
        assertEq(almCore.bufferAmount1() - buffer1Before, principal1);
    }

    function testFuzz_Success_decreaseLiquidity_SentinelRemovesTheDonatedLiquidity(
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

        // And: A third party added liquidity to the range's position.
        uint256 tokenId = range.unstakedTokenId;
        donateToRange(range, uint128(bound(donation, 1, range.liquidity)));
        uint128 liquidityBefore = positionLiquidity(tokenId);
        assertGt(liquidityBefore, range.liquidity);
        (uint256 principal0, uint256 principal1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidityBefore);
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager removes the whole side with the sentinel.
        runPlan(Plan.init().decreaseLiquidity(range.index, tokenId, Sentinels.RANGE_LIQUIDITY, 0, 0));

        // Then: The whole position and the donation are removed, the principal buffered.
        assertEq(positionLiquidity(tokenId), 0);
        assertEq(almCore.bufferAmount0() - buffer0Before, principal0);
        assertEq(almCore.bufferAmount1() - buffer1Before, principal1);
    }

    function testFuzz_Success_decreaseLiquidity_ReadsNoPenaltyWindow(
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
        uint128 liquidityBefore = positionLiquidity(almCore.getRange(range.index).unstakedTokenId);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager removes liquidity from the unstaked side.
        // Then: The gauge factory's penalty config is not read.
        vm.expectCall(
            almCore.GAUGE_FACTORY_(), abi.encodeWithSelector(IMetadexCLGaugeFactory.effectivePenaltyConfig.selector), 0
        );
        runPlan(
            Plan.init()
                .decreaseLiquidity(range.index, almCore.getRange(range.index).unstakedTokenId, liquidityBefore, 0, 0)
        );
    }
}
