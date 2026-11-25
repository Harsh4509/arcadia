/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic } from "../../../src/core/libraries/logic/ALMCoreViewLogic.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { RangesLib } from "../../../src/core/libraries/state/RangesLib.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";

/**
 * @notice Symbolic tests for the storage layout of a "Range", as "RangesLib" and "ALMCoreViewLogic" read it.
 */
contract Layout_RangesLib_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                                 STORAGE
    ////////////////////////////////////////////////////////////// */

    Range[] internal ranges;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function prove_unsafeAccess_MatchesTheCompilerSlot(uint256 length, uint256 index) public {
        // Given: An array of any length and an index inside it.
        vm.assume(index < length);
        assembly ("memory-safe") {
            sstore(ranges.slot, length)
        }

        // When: Accessing the range without the bounds check.
        Range storage unsafeRange = RangesLib.unsafeAccess(ranges, index);

        // Then: It is the slot the compiler assigns to that index.
        Range storage range = ranges[index];
        uint256 unsafeSlot;
        uint256 slot;
        assembly ("memory-safe") {
            unsafeSlot := unsafeRange.slot
            slot := range.slot
        }
        assertEq(unsafeSlot, slot);
    }

    function prove_decodeRanges_RoundTripsTheStoredWords(Range memory stored) public {
        // Given: Any range, stored by the compiler.
        ranges.push(stored);
        uint256 rangesSlot;
        assembly ("memory-safe") {
            rangesSlot := ranges.slot
        }
        uint256 base = uint256(keccak256(abi.encode(rangesSlot)));
        bytes32[] memory words = new bytes32[](2);
        words[0] = vm.load(address(this), bytes32(base));
        words[1] = vm.load(address(this), bytes32(base + 1));

        // When: Decoding its two storage words.
        Range[] memory decoded = ALMCoreViewLogic.decodeRanges(words);

        // Then: Every field comes back as it was stored.
        assertEq(decoded.length, 1);
        assertEq(decoded[0].tickLower, stored.tickLower);
        assertEq(decoded[0].tickUpper, stored.tickUpper);
        assertEq(decoded[0].unstakedTokenId, stored.unstakedTokenId);
        assertEq(decoded[0].stakedLiquidity, stored.stakedLiquidity);
        assertEq(decoded[0].stakedTokenId, stored.stakedTokenId);
        assertEq(decoded[0].stakedBlock, stored.stakedBlock);
    }

    function prove_decodeRange_ReadsTheTicksAndTheStakedLiquidityOfTheStoredWord(Range memory stored) public {
        // Given: Any range, stored by the compiler.
        ranges.push(stored);
        uint256 rangesSlot;
        assembly ("memory-safe") {
            rangesSlot := ranges.slot
        }
        uint256 base = uint256(keccak256(abi.encode(rangesSlot)));
        bytes32[] memory words = new bytes32[](2);
        words[0] = vm.load(address(this), bytes32(base));
        words[1] = vm.load(address(this), bytes32(base + 1));

        // When: Decoding its ticks and staked liquidity.
        (int24 tickLower, int24 tickUpper, uint128 stakedLiquidity) = ALMCoreViewLogic.decodeRange(words, 0);

        // Then: Each comes back as it was stored.
        assertEq(tickLower, stored.tickLower);
        assertEq(tickUpper, stored.tickUpper);
        assertEq(stakedLiquidity, stored.stakedLiquidity);
    }
}
