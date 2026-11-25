/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { IALMCore } from "../../../../src/interfaces/IALMCore.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SnapshotLib_Fuzz_Test } from "./_SnapshotLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "idle" of library "SnapshotLib".
 */
contract Idle_SnapshotLib_Fuzz_Test is SnapshotLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_idle_IsBufferPlusFees(
        uint256 buffer0,
        uint256 buffer1,
        uint256 fees0,
        uint256 fees1,
        uint256 supply
    ) public view {
        // Given: A snapshot with fuzzed buffers and uncollected fees.
        buffer0 = bound(buffer0, 0, type(uint128).max);
        buffer1 = bound(buffer1, 0, type(uint128).max);
        fees0 = bound(fees0, 0, type(uint128).max);
        fees1 = bound(fees1, 0, type(uint128).max);
        Snapshot memory snapshot = Snapshot({
            buffer0: buffer0,
            buffer1: buffer1,
            fees0: fees0,
            fees1: fees1,
            supply: supply,
            sqrtPriceX96: 0,
            tick: 0,
            fee: 0,
            core: IALMCore(address(0)),
            ranges: new PricedRange[](0)
        });

        // When: Calling idle().
        (uint256 idle0, uint256 idle1) = snapshotLib.idle(snapshot);

        // Then: Each token's idle balance is its buffer plus its uncollected fees.
        assertEq(idle0, buffer0 + fees0);
        assertEq(idle1, buffer1 + fees1);
    }
}
