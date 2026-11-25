/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { stdError } from "@forge-std/StdError.sol";

/**
 * @notice Fuzz tests for the function "decodeRange" of library "ALMCoreViewLogic".
 */
contract DecodeRange_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_decodeRange(
        PoolState memory poolState,
        Range[3] memory ranges,
        uint256 count,
        uint256 index
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Up to three stored ranges, every field fuzzed.
        count = bound(count, 1, ranges.length);
        for (uint256 i; i < count; ++i) {
            almCore.pushRange(ranges[i]);
        }
        index = bound(index, 0, count - 1);

        // When: Decoding one range.
        (int24 tickLower, int24 tickUpper, uint128 stakedLiquidity) =
            coreViewLogic.decodeRange(coreViewLogic.readRangeWords(address(almCore)), index);

        // Then: It holds the range's ticks and staked liquidity.
        assertEq(tickLower, ranges[index].tickLower);
        assertEq(tickUpper, ranges[index].tickUpper);
        assertEq(stakedLiquidity, ranges[index].stakedLiquidity);
    }
}
