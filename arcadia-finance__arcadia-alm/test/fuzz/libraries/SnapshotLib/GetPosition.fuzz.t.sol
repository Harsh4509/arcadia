/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { EquivalentPosition } from "../../../../src/vaults/types/EquivalentPosition.sol";
import { FixedPoint96 } from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { IALMCore } from "../../../../src/interfaces/IALMCore.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SnapshotLib_Fuzz_Test } from "./_SnapshotLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getPosition" of library "SnapshotLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetPosition_SnapshotLib_Fuzz_Test is SnapshotLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getPosition_IdleOnly(
        uint256 buffer0,
        uint256 buffer1,
        uint256 fees0,
        uint256 fees1,
        uint160 sqrtPriceX96,
        bool zeroForOne
    ) public view {
        // Given: A snapshot without ranges, with fuzzed buffers and uncollected fees.
        buffer0 = bound(buffer0, 0, type(uint128).max);
        buffer1 = bound(buffer1, 0, type(uint128).max);
        fees0 = bound(fees0, 0, type(uint128).max);
        fees1 = bound(fees1, 0, type(uint128).max);
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        Snapshot memory snapshot = Snapshot({
            buffer0: buffer0,
            buffer1: buffer1,
            fees0: fees0,
            fees1: fees1,
            supply: 1,
            sqrtPriceX96: 0,
            tick: 0,
            fee: 0,
            core: IALMCore(address(0)),
            ranges: new PricedRange[](0)
        });

        // When: Building the equivalent position.
        EquivalentPosition memory position = snapshotLib.getPosition(snapshot, sqrtPriceX96, zeroForOne);

        // Then: It holds no liquidity, its constants owe each token's buffer plus fees.
        assertEq(position.liquidity, 0);
        assertEq(position.unstakedLiquidity, 0);
        assertEq(position.constant0, -int256(buffer0 + fees0));
        assertEq(position.constant1, -int256(buffer1 + fees1));

        // And: Its bound is the pool's price limit in the swap's direction.
        assertEq(position.sqrtPriceBound, zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1);
    }

    function testFuzz_Success_getPosition_OneRangeAroundThePrice(
        RangeState memory range,
        uint256 buffer0,
        uint256 buffer1,
        uint256 fees0,
        uint256 fees1,
        uint160 sqrtPriceX96,
        bool zeroForOne
    ) public view {
        // Given: A range holding liquidity, a price strictly inside it, buffers and fees.
        range.liquidity = uint128(bound(range.liquidity, 1, type(uint128).max));
        givenValidRange(range);
        RangeState[] memory ranges = new RangeState[](1);
        ranges[0] = range;
        PricedRange[] memory priced = pricedOf(ranges);
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, priced[0].sqrtPriceLowerX96 + 1, priced[0].sqrtPriceUpperX96 - 1));
        buffer0 = bound(buffer0, 0, type(uint128).max);
        buffer1 = bound(buffer1, 0, type(uint128).max);
        fees0 = bound(fees0, 0, type(uint128).max);
        fees1 = bound(fees1, 0, type(uint128).max);
        Snapshot memory snapshot = Snapshot({
            buffer0: buffer0,
            buffer1: buffer1,
            fees0: fees0,
            fees1: fees1,
            supply: 1,
            sqrtPriceX96: 0,
            tick: 0,
            fee: 0,
            core: IALMCore(address(0)),
            ranges: priced
        });

        // When: Building the equivalent position.
        EquivalentPosition memory position = snapshotLib.getPosition(snapshot, sqrtPriceX96, zeroForOne);

        // Then: It holds the range's liquidity, and its unstaked part.
        assertEq(position.liquidity, priced[0].liquidity);
        assertEq(position.unstakedLiquidity, priced[0].unstakedLiquidity);

        // And: Its constants are the range's amounts at its far edges, less the idle.
        assertEq(
            position.constant0,
            int256(FullMath.mulDiv(priced[0].liquidity, FixedPoint96.Q96, priced[0].sqrtPriceUpperX96))
                - int256(buffer0 + fees0)
        );
        assertEq(
            position.constant1,
            int256(FullMath.mulDiv(priced[0].liquidity, priced[0].sqrtPriceLowerX96, FixedPoint96.Q96))
                - int256(buffer1 + fees1)
        );

        // And: Its bound is the range's edge in the swap's direction.
        assertEq(position.sqrtPriceBound, zeroForOne ? priced[0].sqrtPriceLowerX96 : priced[0].sqrtPriceUpperX96);
    }
}
