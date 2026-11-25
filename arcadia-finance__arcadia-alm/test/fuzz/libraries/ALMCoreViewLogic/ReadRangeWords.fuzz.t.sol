/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { STATE_SLOT } from "../../../../src/core/abstracts/storage/Storage.sol";

/**
 * @notice Fuzz tests for the function "readRangeWords" of library "ALMCoreViewLogic".
 */
contract ReadRangeWords_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_readRangeWords_ReadsTwoWordsPerRange(
        PoolState memory poolState,
        Range[3] memory ranges,
        uint256 count
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Up to three stored ranges, every field fuzzed.
        count = bound(count, 0, ranges.length);
        for (uint256 i; i < count; ++i) {
            almCore.pushRange(ranges[i]);
        }

        // When: Reading the ranges' words.
        bytes32[] memory words = coreViewLogic.readRangeWords(address(almCore));

        // Then: They are the two words per range at keccak256(B + 19), in order.
        assertEq(words.length, 2 * count);
        uint256 element = uint256(keccak256(abi.encode(uint256(STATE_SLOT) + 19)));
        for (uint256 i; i < words.length; ++i) {
            assertEq(words[i], vm.load(address(almCore), bytes32(element + i)));
        }
    }
}
