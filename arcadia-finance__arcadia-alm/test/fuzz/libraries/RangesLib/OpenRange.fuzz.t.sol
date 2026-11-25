/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { RangesLib } from "../../../../src/core/libraries/state/RangesLib.sol";
import { RangesLib_Fuzz_Test } from "./_RangesLib.fuzz.t.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "openRange" of library "RangesLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract OpenRange_RangesLib_Fuzz_Test is RangesLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_openRange_RangeCapExceeded(
        PoolState memory poolState,
        RangeState memory range,
        Range memory held,
        uint8 cap,
        uint256 count
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: As many ranges as the cap allows, or more.
        cap = uint8(bound(cap, 0, ConfigLib.MAX_RANGE_CAP));
        rangesLib.setRangeCap(cap);
        count = bound(count, cap, ConfigLib.MAX_RANGE_CAP);
        for (uint256 i; i < count; ++i) {
            rangesLib.pushRange(held);
        }

        // And: The amounts a new range takes, held by the ranges.
        givenValidRangeState(range, poolState, false);
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        token0.mint(address(rangesLib), amount0);
        token1.mint(address(rangesLib), amount1);

        // When: Opening another range.
        // Then: It reverts.
        vm.expectRevert(RangesLib.RangeCapExceeded.selector);
        rangesLib.openRange(range.tickLower, range.tickUpper, amount0, amount1, 0, 0);
    }

    function testFuzz_Success_openRange_PushesTheUnstakedSide(
        PoolState memory poolState,
        RangeState memory range,
        Range memory held,
        uint256 count
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: Fewer ranges than the cap allows.
        count = bound(count, 0, ConfigLib.MAX_RANGE_CAP - 1);
        for (uint256 i; i < count; ++i) {
            rangesLib.pushRange(held);
        }

        // And: The amounts a new range takes, held by the ranges.
        givenValidRangeState(range, poolState, false);
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        token0.mint(address(rangesLib), amount0);
        token1.mint(address(rangesLib), amount1);

        // When: Opening a range with those amounts.
        (uint128 liquidity, TokenDelta delta) =
            rangesLib.openRange(range.tickLower, range.tickUpper, amount0, amount1, 0, 0);

        // Then: It is appended at the old length, the liquidity on its unstaked side.
        assertEq(rangesLib.getRangesLength(), count + 1);
        Range memory opened = rangesLib.getRange(count);
        assertEq(opened.tickLower, range.tickLower);
        assertEq(opened.tickUpper, range.tickUpper);
        assertEq(positionLiquidity(opened.unstakedTokenId), liquidity);
        assertEq(liquidity, liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1));
        assertEq(opened.stakedLiquidity, 0);
        assertEq(opened.stakedTokenId, 0);
        assertEq(opened.stakedBlock, 0);

        // And: Its token id is the ranges' own and holds that liquidity.
        assertEq(POSITION_MANAGER.ownerOf(opened.unstakedTokenId), address(rangesLib));
        assertEq(positionLiquidity(opened.unstakedTokenId), liquidity);

        // And: The delta takes exactly what the mint consumed.
        assertEq(-int256(delta.amount0()), int256(amount0 - token0.balanceOf(address(rangesLib))));
        assertEq(-int256(delta.amount1()), int256(amount1 - token1.balanceOf(address(rangesLib))));
    }
}
