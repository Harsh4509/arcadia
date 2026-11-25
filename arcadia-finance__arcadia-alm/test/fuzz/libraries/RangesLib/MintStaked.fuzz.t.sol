/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { RangesLib } from "../../../../src/core/libraries/state/RangesLib.sol";
import { RangesLib_Fuzz_Test } from "./_RangesLib.fuzz.t.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "mintStaked" of library "RangesLib".
 */
contract MintStaked_RangesLib_Fuzz_Test is RangesLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_mintStaked_RangeStaked(
        PoolState memory poolState,
        Range memory held,
        uint256 amount0,
        uint256 amount1
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range that already holds a staked side.
        held.stakedTokenId = uint80(bound(held.stakedTokenId, 1, type(uint80).max));
        rangesLib.pushRange(held);

        // When: Minting its staked side.
        // Then: It reverts.
        vm.expectRevert(RangesLib.RangeStaked.selector);
        rangesLib.mintStaked(0, amount0, amount1);
    }

    function testFuzz_Success_mintStaked_MintsAndStakesAtTheRangeTicks(
        PoolState memory poolState,
        RangeState memory range,
        uint128 extra
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range holding an unstaked side only.
        range.liquidityStaked = 0;
        givenValidRangeState(range, poolState, false);
        pushRangeOf(range);

        // And: The amounts a staked side takes, held by the ranges.
        extra = uint128(bound(extra, Constants.MIN_FUZZED_LIQUIDITY, range.liquidity));
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, extra);
        token0.mint(address(rangesLib), amount0);
        token1.mint(address(rangesLib), amount1);

        // When: Minting its staked side.
        (uint128 liquidity, TokenDelta delta) = rangesLib.mintStaked(range.index, amount0, amount1);

        // Then: A staked side was minted at the range's ticks and deposited this block.
        Range memory staked = rangesLib.getRange(range.index);
        assertGt(staked.stakedTokenId, 0);
        assertEq(staked.stakedLiquidity, liquidity);
        assertEq(liquidity, liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1));
        assertEq(positionLiquidity(staked.stakedTokenId), liquidity);
        (int24 tickLower, int24 tickUpper) = positionTicks(staked.stakedTokenId);
        assertEq(tickLower, range.tickLower);
        assertEq(tickUpper, range.tickUpper);
        assertTrue(gauge.stakedContains(address(rangesLib), staked.stakedTokenId));
        assertEq(staked.stakedBlock, vm.getBlockNumber());

        // And: The unstaked side is untouched.
        assertEq(staked.unstakedTokenId, range.unstakedTokenId);
        assertEq(positionLiquidity(staked.unstakedTokenId), range.liquidity);

        // And: The delta takes exactly what the mint consumed.
        assertEq(-int256(delta.amount0()), int256(amount0 - token0.balanceOf(address(rangesLib))));
        assertEq(-int256(delta.amount1()), int256(amount1 - token1.balanceOf(address(rangesLib))));
    }
}
