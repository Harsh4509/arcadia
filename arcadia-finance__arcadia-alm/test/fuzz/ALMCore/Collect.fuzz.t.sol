/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { Constants } from "../../utils/Constants.sol";
import { Plan } from "../../utils/Plan.sol";

/**
 * @notice Fuzz tests for the function "collect" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract Collect_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_collect_OnlyKeeper(
        address caller,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range and a caller that is not the manager.
        vm.assume(caller != users.keeper);
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Plan.Steps memory plan = Plan.init().collect(range.unstakedTokenId);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling collect().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ALMKeeperExtension.OnlyKeeper.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_collect_StakedTokenId(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg the gauge holds, and a step collecting it.
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
        Plan.Steps memory plan = Plan.init().collect(range.stakedTokenId);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls collect().
        // Then: The position manager reverts without data.
        vm.prank(users.keeper);
        vm.expectRevert(bytes(""));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_collect_ClosedEarlierInThePlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range, and a plan that closes it and then collects its burned position.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        Plan.Steps memory plan =
            Plan.init().closeRange(range.index, range.unstakedTokenId).collect(range.unstakedTokenId);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper runs it.
        // Then: It reverts with the position manager's check on a burned token.
        vm.prank(users.keeper);
        vm.expectRevert(bytes("ERC721: operator query for nonexistent token"));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_collect_NothingOwed(
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
        uint256 bufferBefore = almCore.bufferAmount0();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls collect().
        runPlan(Plan.init().collect(almCore.getRange(range.index).unstakedTokenId));

        // Then: Nothing moves.
        assertEq(almCore.bufferAmount0(), bufferBefore);
        assertEq(almCore.getProtocolFees0(), 0);
        assertEq(almCore.getProtocolFees1(), 0);
    }

    function testFuzz_Success_collect_CreditsBufferNetOfFee(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 amountIn,
        uint16 feeBps,
        bool zeroForOne,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A protocol share of every collection.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(0, feeBps, users.feeRecipient);

        // And: A range around the price that earned fees in the token a trade sold.
        givenValidRangeState(range, poolState, true, false);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        swapInPool(
            pool,
            users.liquidityProvider,
            zeroForOne ? address(token0) : address(token1),
            zeroForOne ? address(token1) : address(token0),
            feeEarningTrade(pool, range.liquidity, amountIn, zeroForOne)
        );

        // And: The TWAP has caught up with the trade.
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        // And: What the range earned, from the pool's fee growth inside its ticks.
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();
        (uint256 gross0, uint256 gross1) = positionFees(pool, range.unstakedTokenId);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls collect().
        runPlan(Plan.init().collect(range.unstakedTokenId));

        // Then: The collection of each token is split between protocol fees and buffer.
        uint256 fee0 = gross0 * feeBps / almCore.BPS_DENOMINATOR_();
        uint256 fee1 = gross1 * feeBps / almCore.BPS_DENOMINATOR_();
        assertEq(almCore.getProtocolFees0(), fee0);
        assertEq(almCore.getProtocolFees1(), fee1);
        assertEq(almCore.bufferAmount0(), buffer0Before + gross0 - fee0);
        assertEq(almCore.bufferAmount1(), buffer1Before + gross1 - fee1);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0() + almCore.getProtocolFees0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1() + almCore.getProtocolFees1());
    }

    function testFuzz_Success_collect_CreditsFeesEarnedInThePlan(
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
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(0, feeBps, users.feeRecipient);

        // And: The range's fees and the output of the same swap made in the pool.
        uint256 snapshot = vm.snapshotState();
        uint256 amountOut = swapInPool(pool, users.liquidityProvider, address(token0), address(token1), amountIn);
        (uint256 gross0, uint256 gross1) = positionFees(pool, range.unstakedTokenId);
        vm.revertToState(snapshot);
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 2, true, amountIn, amountOut);
        setPlanLimits(configState);

        // When: The manager swaps through the range and then collects it.
        runPlan(Plan.init().swapViaPool(true, amountIn, priceLimit(true), 0).collect(range.unstakedTokenId));

        // Then: The collection splits into protocol fees and the buffer, net of the swap.
        uint256 fee0 = gross0 * feeBps / almCore.BPS_DENOMINATOR_();
        uint256 fee1 = gross1 * feeBps / almCore.BPS_DENOMINATOR_();
        assertGt(gross0, 0);
        assertEq(almCore.getProtocolFees0(), fee0);
        assertEq(almCore.getProtocolFees1(), fee1);
        assertEq(almCore.bufferAmount0(), buffer0Before - amountIn + gross0 - fee0);
        assertEq(almCore.bufferAmount1(), buffer1Before + amountOut + gross1 - fee1);
    }

    function testFuzz_Success_collect_Paused(
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
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(0, feeBps, users.feeRecipient);

        // And: A range around the price that earned swap fees, a real share of the room.
        givenValidRangeState(range, poolState, true, false);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            feeEarningTrade(pool, range.liquidity, amountIn, true)
        );

        // And: The TWAP has caught up with the trade.
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);
        vm.prank(factory);
        almCore.pause();

        // And: What the range earned, from the pool's fee growth inside its ticks.
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();
        (uint256 gross0, uint256 gross1) = positionFees(pool, range.unstakedTokenId);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls collect().
        runPlan(Plan.init().collect(range.unstakedTokenId));

        // Then: The fees net of the protocol share are in the buffer.
        uint256 fee0 = gross0 * feeBps / almCore.BPS_DENOMINATOR_();
        uint256 fee1 = gross1 * feeBps / almCore.BPS_DENOMINATOR_();
        assertGt(gross0, 0);
        assertEq(almCore.bufferAmount0() - buffer0Before, gross0 - fee0);
        assertEq(almCore.bufferAmount1() - buffer1Before, gross1 - fee1);
    }
}
