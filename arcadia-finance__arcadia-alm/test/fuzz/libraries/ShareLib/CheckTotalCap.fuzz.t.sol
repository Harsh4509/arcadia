/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Config } from "../../../../src/core/types/State.sol";
import { ShareLib } from "../../../../src/core/libraries/state/ShareLib.sol";
import { ShareLib_Fuzz_Test } from "./_ShareLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "checkTotalCap" of library "ShareLib".
 */
contract CheckTotalCap_ShareLib_Fuzz_Test is ShareLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_checkTotalCap_TotalCapExceeded(Config memory config, uint256 supply) public {
        // Given: A total cap, and a supply above it.
        config.totalCap = uint128(bound(config.totalCap, 0, type(uint128).max - 1));
        shareLib.setConfig(config);
        supply = bound(supply, uint256(config.totalCap) + 1, type(uint256).max);

        // When: Checking the supply.
        // Then: It reverts.
        vm.expectRevert(ShareLib.TotalCapExceeded.selector);
        shareLib.checkTotalCap(supply);
    }

    function testFuzz_Success_checkTotalCap_AtOrBelowTheCap(Config memory config, uint256 supply) public {
        // Given: A total cap, and a supply at or below it.
        shareLib.setConfig(config);
        supply = bound(supply, 0, config.totalCap);

        // When: Checking the supply.
        (bool success,) = address(shareLib).staticcall(abi.encodeCall(shareLib.checkTotalCap, (supply)));

        // Then: It does not revert.
        assertTrue(success);
    }
}
