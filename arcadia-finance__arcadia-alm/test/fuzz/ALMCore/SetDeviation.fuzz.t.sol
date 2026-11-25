/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMAdminExtension } from "../../../src/core/ALMAdminExtension.sol";
import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { BaseCore } from "../../../src/core/abstracts/base/BaseCore.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";

/**
 * @notice Fuzz tests for the function "setDeviation" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events, unsafe-typecast)
contract SetDeviation_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_setDeviation_Unauthorized(
        address caller,
        uint32 twapWindow,
        uint256 maxSpotFromTwap,
        uint256 maxFromTrusted
    ) public {
        // Given: The caller is not the factory.
        vm.assume(caller != factory);

        // When: Calling setDeviation().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseCore.Unauthorized.selector);
        almCore.setDeviation(twapWindow, maxSpotFromTwap, maxFromTrusted, maxFromTrusted);
    }

    function testFuzz_Revert_setDeviation_InvalidTwapWindow(uint256 maxSpotFromTwap, uint256 maxFromTrusted) public {
        // Given: The factory calls.

        // When: Calling setDeviation() with a zero TWAP window.
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.InvalidTwapWindow.selector);
        almCore.setDeviation(0, maxSpotFromTwap, maxFromTrusted, maxFromTrusted);
    }

    function testFuzz_Revert_setDeviation_BandOverflow(uint32 twapWindow, uint256[3] memory bands, uint8 overflowing)
        public
    {
        // Given: A non-zero TWAP window and one of three bounds wider than its storage.
        twapWindow = uint32(bound(twapWindow, 1, type(uint32).max));
        overflowing = uint8(bound(overflowing, 0, 2));
        for (uint256 i; i < 3; ++i) {
            bands[i] = i == overflowing
                ? bound(bands[i], uint256(type(uint64).max) + 1, type(uint256).max)
                : bound(bands[i], 0, type(uint64).max);
        }

        // And: The factory calls.

        // When: Calling setDeviation().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(SafeCastLib.Overflow.selector);
        almCore.setDeviation(twapWindow, bands[0], bands[1], bands[2]);
    }

    function testFuzz_Success_setDeviation(uint32 twapWindow, uint256[3] memory bands) public {
        // Given: A non-zero TWAP window and three bounds inside their range.
        twapWindow = uint32(bound(twapWindow, 1, type(uint32).max));
        for (uint256 i; i < 3; ++i) {
            bands[i] = bound(bands[i], 0, type(uint64).max);
        }

        // And: The factory calls.
        vm.prank(factory);

        // When: Calling setDeviation().
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.DeviationSet(twapWindow, bands[0], bands[1], bands[2]);
        almCore.setDeviation(twapWindow, bands[0], bands[1], bands[2]);

        // Then: The deviation bounds are updated.
        assertEq(almCore.twapWindow_(), twapWindow);
        assertEq(almCore.maxSpotFromTwap_(), bands[0]);
        assertEq(almCore.maxSpotFromTrusted_(), bands[1]);
        assertEq(almCore.maxTwapFromTrusted_(), bands[2]);
    }
}
