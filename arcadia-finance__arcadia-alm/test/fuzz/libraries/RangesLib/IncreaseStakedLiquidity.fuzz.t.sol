/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { RangesLib } from "../../../../src/core/libraries/state/RangesLib.sol";
import { RangesLib_Fuzz_Test } from "./_RangesLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "increaseStakedLiquidity" of library "RangesLib".
 */
contract IncreaseStakedLiquidity_RangesLib_Fuzz_Test is RangesLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_increaseStakedLiquidity_RangeNotStaked(
        PoolState memory poolState,
        Range memory held,
        uint256 amount0,
        uint256 amount1,
        bool windowOpen
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range with no staked side.
        held.stakedTokenId = 0;
        rangesLib.pushRange(held);

        // When: Adding liquidity to its staked side.
        // Then: It reverts.
        vm.expectRevert(RangesLib.RangeNotStaked.selector);
        rangesLib.increaseStakedLiquidity(0, amount0, amount1, windowOpen);
    }

    function testFuzz_Revert_increaseStakedLiquidity_PenaltyWindowOpen(
        PoolState memory poolState,
        RangeState memory range,
        uint128 extra
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range whose staked side was just deposited, so its window is open.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(range);

        // And: The amounts more liquidity takes, held by the ranges.
        extra = uint128(bound(extra, Constants.MIN_FUZZED_LIQUIDITY, range.liquidityStaked));
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, extra);
        token0.mint(address(rangesLib), amount0);
        token1.mint(address(rangesLib), amount1);

        // When: Topping up the staked side with its window reported open.
        // Then: It reverts.
        vm.expectRevert(abi.encodeWithSelector(RangesLib.PenaltyWindowOpen.selector, range.stakedTokenId));
        rangesLib.increaseStakedLiquidity(range.index, amount0, amount1, true);
    }

    function testFuzz_Success_increaseStakedLiquidity_TopsUpOutsideTheWindow(
        PoolState memory poolState,
        RangeState memory range,
        uint128 extra
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

        // And: The amounts more liquidity takes, held by the ranges.
        extra = uint128(bound(extra, Constants.MIN_FUZZED_LIQUIDITY, range.liquidityStaked));
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, extra);
        token0.mint(address(rangesLib), amount0);
        token1.mint(address(rangesLib), amount1);

        // When: Topping up the staked side with its window reported closed.
        (uint128 liquidity,) = rangesLib.increaseStakedLiquidity(range.index, amount0, amount1, false);

        // Then: The same token id grew by the liquidity added, redeposited this block.
        Range memory staked = rangesLib.getRange(range.index);
        assertEq(staked.stakedTokenId, range.stakedTokenId);
        assertEq(staked.stakedLiquidity, uint256(range.liquidityStaked) + liquidity);
        assertEq(positionLiquidity(range.stakedTokenId), staked.stakedLiquidity);
        assertTrue(gauge.stakedContains(address(rangesLib), range.stakedTokenId));
        assertEq(staked.stakedBlock, vm.getBlockNumber());
    }

    function testFuzz_Success_increaseStakedLiquidity_TopsUpInsideTheWindowWhenAccepted(
        PoolState memory poolState,
        RangeState memory range,
        uint128 extra
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range whose staked side was just deposited, so its window is open.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(range);

        // And: The amounts more liquidity takes, held by the ranges.
        extra = uint128(bound(extra, Constants.MIN_FUZZED_LIQUIDITY, range.liquidityStaked));
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, extra);
        token0.mint(address(rangesLib), amount0);
        token1.mint(address(rangesLib), amount1);

        // When: Topping up the staked side, the penalty accepted, so no window reported.
        (uint128 liquidity,) = rangesLib.increaseStakedLiquidity(range.index, amount0, amount1, false);

        // Then: The same token id grew by the liquidity added and was deposited again.
        Range memory staked = rangesLib.getRange(range.index);
        assertEq(staked.stakedTokenId, range.stakedTokenId);
        assertEq(staked.stakedLiquidity, uint256(range.liquidityStaked) + liquidity);
        assertTrue(gauge.stakedContains(address(rangesLib), range.stakedTokenId));
    }
}
