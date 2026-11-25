/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "../../ALMCore/_ALMCore.fuzz.t.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { SnapshotLibExtension } from "../../../utils/extensions/SnapshotLibExtension.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "decodePricedRanges" of library "SnapshotLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract DecodePricedRanges_SnapshotLib_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    SnapshotLibExtension internal snapshotLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        snapshotLib = new SnapshotLibExtension();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_decodePricedRanges(
        PoolState memory poolState,
        Range[3] memory ranges,
        uint128[3] memory liquidities,
        uint256 count
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Up to three stored ranges, each liquidity sum within a uint128.
        count = bound(count, 0, ranges.length);
        uint128[] memory positionLiquidity = new uint128[](count);
        for (uint256 i; i < count; ++i) {
            ranges[i].tickLower = int24(bound(ranges[i].tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
            ranges[i].tickUpper = int24(bound(ranges[i].tickUpper, ranges[i].tickLower + 1, TickMath.MAX_TICK));
            ranges[i].stakedLiquidity = uint128(bound(ranges[i].stakedLiquidity, 0, type(uint128).max - liquidities[i]));
            almCore.pushRange(ranges[i]);
            positionLiquidity[i] = liquidities[i];
        }

        // When: Decoding the ranges' words and liquidities into priced ranges.
        PricedRange[] memory priced =
            snapshotLib.decodePricedRanges(coreViewLogic.readRangeWords(address(almCore)), positionLiquidity);

        // Then: Each holds its summed and unstaked liquidity and its ticks' prices.
        assertEq(priced.length, count);
        for (uint256 i; i < count; ++i) {
            assertEq(priced[i].liquidity, uint256(liquidities[i]) + ranges[i].stakedLiquidity);
            assertEq(priced[i].unstakedLiquidity, liquidities[i]);
            assertEq(priced[i].sqrtPriceLowerX96, TickMath.getSqrtPriceAtTick(ranges[i].tickLower));
            assertEq(priced[i].sqrtPriceUpperX96, TickMath.getSqrtPriceAtTick(ranges[i].tickUpper));
        }
    }
}
