/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreView_Fuzz_Test } from "./_ALMCoreView.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { Range } from "../../../src/core/types/Range.sol";

/**
 * @notice Fuzz tests for the function "getRanges" of contract "ALMCoreView".
 */
contract GetRanges_ALMCoreView_Fuzz_Test is ALMCoreView_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreView_Fuzz_Test) {
        ALMCoreView_Fuzz_Test.setUp();
        setSpotPoolState();
        deployCoreView();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getRanges_CoreNotValid(address notCore) public {
        // Given: An address the factory does not hold as a core.
        vm.assume(notCore != address(almCore));

        // When: Reading it through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getRanges(notCore);
    }

    function testFuzz_Revert_getRanges_CoreNotValid_HalfCreated(uint256 pick) public {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        address[4] memory vaults_ = halfCreatedVaults();
        address core = BaseVault(vaults_[bound(pick, 0, vaults_.length - 1)]).share();

        // When: Reading its core address through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getRanges(core);
    }

    function testFuzz_Success_getRanges_IsTheCoresRanges(Range[3] memory fuzzed, uint256 count) public {
        // Given: Up to three ranges, every field fuzzed, pushed through the accessor.
        count = bound(count, 0, fuzzed.length);
        for (uint256 i; i < count; ++i) {
            almCore.pushRange(fuzzed[i]);
        }

        // When: Reading the ranges through the lens.
        Range[] memory ranges = coreView.getRanges(address(almCore));

        // Then: Every field of every range reads back.
        assertEq(ranges.length, count);
        for (uint256 i; i < count; ++i) {
            assertEq(ranges[i].stakedLiquidity, fuzzed[i].stakedLiquidity);
            assertEq(ranges[i].tickLower, fuzzed[i].tickLower);
            assertEq(ranges[i].tickUpper, fuzzed[i].tickUpper);
            assertEq(ranges[i].unstakedTokenId, fuzzed[i].unstakedTokenId);
            assertEq(ranges[i].stakedTokenId, fuzzed[i].stakedTokenId);
            assertEq(ranges[i].stakedBlock, fuzzed[i].stakedBlock);
        }
    }
}
