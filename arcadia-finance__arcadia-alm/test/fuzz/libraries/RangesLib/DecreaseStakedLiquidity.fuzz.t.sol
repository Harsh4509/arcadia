/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { IALMCoreEvents } from "../../../../src/interfaces/IALMCoreEvents.sol";
import { LiquidityAmounts } from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { RangesLib } from "../../../../src/core/libraries/state/RangesLib.sol";
import { RangesLib_Fuzz_Test } from "./_RangesLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "decreaseStakedLiquidity" of library "RangesLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract DecreaseStakedLiquidity_RangesLib_Fuzz_Test is RangesLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error VoterBroken();

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_decreaseStakedLiquidity_RangeNotStaked(
        PoolState memory poolState,
        Range memory held,
        uint128 liquidity,
        bool windowOpen
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range with no staked side.
        held.stakedTokenId = 0;
        rangesLib.pushRange(held);

        // When: Removing liquidity from its staked side.
        // Then: It reverts.
        vm.expectRevert(RangesLib.RangeNotStaked.selector);
        rangesLib.decreaseStakedLiquidity(0, liquidity, windowOpen);
    }

    function testFuzz_Revert_decreaseStakedLiquidity_PenaltyWindowOpen(
        PoolState memory poolState,
        Range memory held,
        uint128 liquidity
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range with a staked side.
        held.stakedTokenId = uint80(bound(held.stakedTokenId, 1, type(uint80).max));
        rangesLib.pushRange(held);

        // When: Removing staked liquidity in a penalty window the caller did not accept.
        // Then: It reverts.
        vm.expectRevert(abi.encodeWithSelector(RangesLib.PenaltyWindowOpen.selector, held.stakedTokenId));
        rangesLib.decreaseStakedLiquidity(0, liquidity, true);
    }

    function testFuzz_Revert_decreaseStakedLiquidity_NE(
        PoolState memory poolState,
        RangeState memory range,
        uint128 liquidity
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range with a staked side, and a gauge factory with emergency mode off.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(range);
        setEmergencyWithdrawEnabled(false);

        // When: Taking the staked side out in emergency mode.
        // Then: The gauge reverts.
        vm.expectRevert(bytes("NE"));
        rangesLib.decreaseStakedLiquidity(range.index, liquidity, false, true);
    }

    function testFuzz_Revert_decreaseStakedLiquidity_RemovesMoreThanTheSide(
        PoolState memory poolState,
        RangeState memory range,
        uint128 liquidity
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range whose staked side sat out its window, and more than it holds.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(range);
        closePenaltyWindow(gauge);
        liquidity = uint128(bound(liquidity, uint256(range.liquidityStaked) + 1, type(uint128).max));

        // When: Removing it from the staked side.
        // Then: The position manager reverts.
        vm.expectRevert(bytes(""));
        rangesLib.decreaseStakedLiquidity(range.index, liquidity, false);
    }

    function testFuzz_Success_decreaseStakedLiquidity_PartlyIsDepositedAgain(
        PoolState memory poolState,
        RangeState memory range,
        uint128 liquidity
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range whose staked side sat out its penalty window, and a part of it.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(range);
        closePenaltyWindow(gauge);
        liquidity = uint128(bound(liquidity, 1, range.liquidityStaked - 1));

        // When: Removing that part from the staked side.
        (TokenDelta principal,) = rangesLib.decreaseStakedLiquidity(range.index, liquidity, false);

        // Then: The staked side shrank by it and is deposited again this block.
        Range memory decreased = rangesLib.getRange(range.index);
        assertEq(decreased.stakedLiquidity, range.liquidityStaked - liquidity);
        assertEq(positionLiquidity(range.stakedTokenId), range.liquidityStaked - liquidity);
        assertTrue(gauge.stakedContains(address(rangesLib), range.stakedTokenId));
        assertEq(decreased.stakedTokenId, range.stakedTokenId);
        assertEq(decreased.stakedBlock, vm.getBlockNumber());

        // And: Its principal was released to the ranges.
        assertEq(int256(principal.amount0()), int256(token0.balanceOf(address(rangesLib))));
        assertEq(int256(principal.amount1()), int256(token1.balanceOf(address(rangesLib))));
    }

    function testFuzz_Success_decreaseStakedLiquidity_DrainedIsBurned(
        PoolState memory poolState,
        RangeState memory range
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range whose staked side has sat out its penalty window.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(range);
        closePenaltyWindow(gauge);
        uint48 stakedBlock = rangesLib.getRange(range.index).stakedBlock;

        // When: Removing the whole staked side.
        rangesLib.decreaseStakedLiquidity(range.index, range.liquidityStaked, false);

        // Then: The staked side's liquidity and token id cleared, the token id burned.
        Range memory decreased = rangesLib.getRange(range.index);
        assertEq(decreased.stakedLiquidity, 0);
        assertEq(decreased.stakedTokenId, 0);
        assertFalse(gauge.stakedContains(address(rangesLib), range.stakedTokenId));

        // And: Its staked block, read only while a token id is set, is left as it was.
        assertEq(decreased.stakedBlock, stakedBlock);
    }

    function testFuzz_Success_decreaseStakedLiquidity_ReturnsTheGrossFees(
        PoolState memory poolState,
        RangeState memory range,
        uint128 liquidity,
        uint256 amountIn,
        uint16 feeBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range whose staked side sat out its window and earned trade fees.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(range);
        closePenaltyWindow(gauge);
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            feeEarningTrade(pool, range.liquidityStaked, amountIn, true)
        );
        liquidity = uint128(bound(liquidity, 1, range.liquidityStaked));

        // And: A protocol share of every collection.
        feeBps = uint16(bound(feeBps, 1, almCore.MAX_FEE_BPS_()));
        rangesLib.setProtocolSwapFeeBps(feeBps);

        // When: Removing that part from the staked side.
        (TokenDelta principal, TokenDelta fees) = rangesLib.decreaseStakedLiquidity(range.index, liquidity, false);

        // Then: Everything collected beyond the principal is returned as fees.
        assertEq(int256(principal.amount0()) + fees.amount0(), int256(token0.balanceOf(address(rangesLib))));
        assertEq(int256(principal.amount1()) + fees.amount1(), int256(token1.balanceOf(address(rangesLib))));

        // And: No protocol fee accrues.
        assertEq(rangesLib.getPoolTokens().protocolFees.amount0, 0);
        assertEq(rangesLib.getPoolTokens().protocolFees.amount1, 0);
    }

    function testFuzz_Success_decreaseStakedLiquidity_EmergencyLeavesWithoutAClaim(
        PoolState memory poolState,
        RangeState memory range,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range whose staked side earned emissions settled any blocks later.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(range);
        accrueForBlocks(pool, gauge, bound(blocks, 0, type(uint32).max), bound(emissions, 2, Constants.MAX_EMISSIONS));
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = range.stakedTokenId;
        // And: Emissions of a wei or more, a hole for accruals too small to earn one.
        vm.assume(earnedWithoutPenalty(gauge, address(rangesLib), tokenIds) > 0);

        // And: Emergency withdrawals on.
        setEmergencyWithdrawEnabled(true);
        uint256 deferred = gauge.deferredEmissions(address(rangesLib));
        uint256 rewardBalance = ERC20(receiptToken).balanceOf(address(rangesLib));
        uint256 positions = POSITION_MANAGER.totalSupply();

        // And: The principal of the staked side at the current price, rounded down.
        (uint256 principal0, uint256 principal1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96(pool),
            TickMath.getSqrtPriceAtTick(range.tickLower),
            TickMath.getSqrtPriceAtTick(range.tickUpper),
            range.liquidityStaked
        );

        // When: Taking the whole staked side out in emergency mode.
        vm.expectEmit(address(rangesLib));
        emit IALMCoreEvents.Unstaked(range.index, range.stakedTokenId);
        (TokenDelta principal, TokenDelta fees,) =
            rangesLib.decreaseStakedLiquidity(range.index, range.liquidityStaked, false, true);

        // Then: Its position left the gauge and is burned, the staked side cleared.
        Range memory decreased = rangesLib.getRange(range.index);
        assertEq(decreased.stakedLiquidity, 0);
        assertEq(decreased.stakedTokenId, 0);
        assertFalse(gauge.stakedContains(address(rangesLib), range.stakedTokenId));
        assertEq(POSITION_MANAGER.totalSupply(), positions - 1);

        // And: Its principal was returned to the ranges, with no fees.
        assertEq(int256(principal.amount0()), int256(principal0));
        assertEq(int256(principal.amount1()), int256(principal1));
        assertEq(int256(fees.amount0()), 0);
        assertEq(int256(fees.amount1()), 0);
        assertEq(token0.balanceOf(address(rangesLib)), principal0);
        assertEq(token1.balanceOf(address(rangesLib)), principal1);

        // And: The gauge neither claimed nor deferred the emissions.
        assertEq(gauge.deferredEmissions(address(rangesLib)), deferred);
        assertEq(ERC20(receiptToken).balanceOf(address(rangesLib)), rewardBalance);
    }

    function testFuzz_Success_decreaseStakedLiquidity_EmergencyIgnoresTheLiquidity(
        PoolState memory poolState,
        RangeState memory range,
        uint128 liquidity
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range holding both sides, and emergency withdrawals on.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(range);
        setEmergencyWithdrawEnabled(true);

        // And: The principal of the staked side at the current price, rounded down.
        (uint256 principal0, uint256 principal1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96(pool),
            TickMath.getSqrtPriceAtTick(range.tickLower),
            TickMath.getSqrtPriceAtTick(range.tickUpper),
            range.liquidityStaked
        );

        // When: Taking any liquidity out of the staked side in emergency mode.
        (TokenDelta principal,, uint128 liquidityRemoved) =
            rangesLib.decreaseStakedLiquidity(range.index, liquidity, false, true);

        // Then: The whole staked side left, and the params carry its liquidity.
        assertEq(liquidityRemoved, range.liquidityStaked);
        assertEq(rangesLib.getRange(range.index).stakedLiquidity, 0);
        assertEq(rangesLib.getRange(range.index).stakedTokenId, 0);
        assertEq(int256(principal.amount0()), int256(principal0));
        assertEq(int256(principal.amount1()), int256(principal1));

        // And: The unstaked side is untouched.
        assertEq(positionLiquidity(rangesLib.getRange(range.index).unstakedTokenId), range.liquidity);
        assertEq(rangesLib.getRange(range.index).unstakedTokenId, range.unstakedTokenId);
    }

    function testFuzz_Success_decreaseStakedLiquidity_EmergencyWorksWhileTheVoterReverts(
        PoolState memory poolState,
        RangeState memory range,
        uint256 elapsed
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range with a staked side, any time later, and emergency withdrawals on.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(range);
        vm.warp(vm.getBlockTimestamp() + bound(elapsed, 1, type(uint32).max));
        setEmergencyWithdrawEnabled(true);

        // And: A voter whose gauge settlement reverts.
        vm.mockCallRevert(
            address(leafVoter),
            abi.encodeWithSelector(leafVoter.settleGauge.selector, address(gauge)),
            abi.encodeWithSelector(VoterBroken.selector)
        );

        // And: Taking the whole staked side out the normal way reverts.
        vm.expectRevert(VoterBroken.selector);
        rangesLib.decreaseStakedLiquidity(range.index, range.liquidityStaked, false);

        // When: Taking it out in emergency mode.
        rangesLib.decreaseStakedLiquidity(range.index, range.liquidityStaked, false, true);

        // Then: The staked side left the gauge and is cleared.
        Range memory decreased = rangesLib.getRange(range.index);
        assertEq(decreased.stakedLiquidity, 0);
        assertEq(decreased.stakedTokenId, 0);
        assertFalse(gauge.stakedContains(address(rangesLib), range.stakedTokenId));
    }
}
