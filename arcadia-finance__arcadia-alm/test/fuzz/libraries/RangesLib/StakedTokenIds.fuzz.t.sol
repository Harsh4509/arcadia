/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Range } from "../../../../src/core/types/Range.sol";
import { RangesLib_Fuzz_Test } from "./_RangesLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "stakedTokenIds" of library "RangesLib".
 */
// forge-lint: disable-next-item(calls-loop, uninitialized-local, unsafe-typecast)
contract StakedTokenIds_RangesLib_Fuzz_Test is RangesLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(RangesLib_Fuzz_Test) {
        RangesLib_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_stakedTokenIds_NoRanges(PoolState memory poolState) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: No ranges at all.

        // When: Listing the staked token ids.
        // Then: The list is empty.
        assertEq(rangesLib.stakedTokenIds().length, 0);
    }

    function testFuzz_Success_stakedTokenIds_SkipsRangesWithNoStakedSibling(
        PoolState memory poolState,
        uint80[8] memory tokenIds,
        uint8 mask
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: Eight ranges, of which the mask decides which carry a staked sibling.
        uint256[8] memory expected;
        uint256 count;
        for (uint256 i; i < 8; ++i) {
            uint80 tokenId = mask >> i & 1 == 1 ? uint80(bound(tokenIds[i], 1, type(uint80).max)) : 0;
            if (tokenId != 0) expected[count++] = tokenId;
            rangesLib.pushRange(
                Range({
                    stakedLiquidity: 0,
                    tickLower: TICK_LOWER,
                    tickUpper: TICK_UPPER,
                    unstakedTokenId: 1,
                    stakedTokenId: tokenId,
                    stakedBlock: uint48(vm.getBlockNumber())
                })
            );
        }

        // When: Listing the staked token ids.
        uint256[] memory stakedTokenIds = rangesLib.stakedTokenIds();

        // Then: Only ranges with a staked side are listed, by token id, in range order.
        assertEq(stakedTokenIds.length, count);
        for (uint256 i; i < count; ++i) {
            assertEq(stakedTokenIds[i], expected[i]);
        }
    }
}
