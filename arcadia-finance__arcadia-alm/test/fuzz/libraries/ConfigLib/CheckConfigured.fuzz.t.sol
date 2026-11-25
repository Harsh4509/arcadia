/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Config } from "../../../../src/core/types/State.sol";
import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { ConfigLib_Fuzz_Test } from "./_ConfigLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "checkConfigured" of library "ConfigLib".
 */
contract CheckConfigured_ConfigLib_Fuzz_Test is ConfigLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_checkConfigured_NotConfigured_TwapWindow(Config memory config) public {
        // Given: A configuration with the TWAP window at zero and the other three set.
        config.rangeCap = uint8(bound(config.rangeCap, 1, type(uint8).max));
        config.totalCap = uint128(bound(config.totalCap, 1, type(uint128).max));
        config.perUserCap = uint128(bound(config.perUserCap, 1, type(uint128).max));
        config.twapWindow = 0;
        configLib.setConfig(config);

        // When: Checking it.
        // Then: It reverts.
        vm.expectRevert(ConfigLib.NotConfigured.selector);
        configLib.checkConfigured();
    }

    function testFuzz_Revert_checkConfigured_NotConfigured_RangeCap(Config memory config) public {
        // Given: A configuration with the range cap left at zero and the other three set.
        config.twapWindow = uint32(bound(config.twapWindow, 1, type(uint32).max));
        config.totalCap = uint128(bound(config.totalCap, 1, type(uint128).max));
        config.perUserCap = uint128(bound(config.perUserCap, 1, type(uint128).max));
        config.rangeCap = 0;
        configLib.setConfig(config);

        // When: Checking it.
        // Then: It reverts.
        vm.expectRevert(ConfigLib.NotConfigured.selector);
        configLib.checkConfigured();
    }

    function testFuzz_Revert_checkConfigured_NotConfigured_TotalCap(Config memory config) public {
        // Given: A configuration with the total cap left at zero and the other three set.
        config.twapWindow = uint32(bound(config.twapWindow, 1, type(uint32).max));
        config.rangeCap = uint8(bound(config.rangeCap, 1, type(uint8).max));
        config.perUserCap = uint128(bound(config.perUserCap, 1, type(uint128).max));
        config.totalCap = 0;
        configLib.setConfig(config);

        // When: Checking it.
        // Then: It reverts.
        vm.expectRevert(ConfigLib.NotConfigured.selector);
        configLib.checkConfigured();
    }

    function testFuzz_Revert_checkConfigured_NotConfigured_PerUserCap(Config memory config) public {
        // Given: A configuration with the per user cap at zero and the other three set.
        config.twapWindow = uint32(bound(config.twapWindow, 1, type(uint32).max));
        config.rangeCap = uint8(bound(config.rangeCap, 1, type(uint8).max));
        config.totalCap = uint128(bound(config.totalCap, 1, type(uint128).max));
        config.perUserCap = 0;
        configLib.setConfig(config);

        // When: Checking it.
        // Then: It reverts.
        vm.expectRevert(ConfigLib.NotConfigured.selector);
        configLib.checkConfigured();
    }

    function testFuzz_Success_checkConfigured_AllSet(Config memory config) public {
        // Given: A configuration with all four parameters a mint relies on set.
        config.twapWindow = uint32(bound(config.twapWindow, 1, type(uint32).max));
        config.rangeCap = uint8(bound(config.rangeCap, 1, type(uint8).max));
        config.totalCap = uint128(bound(config.totalCap, 1, type(uint128).max));
        config.perUserCap = uint128(bound(config.perUserCap, 1, type(uint128).max));
        configLib.setConfig(config);

        // When: Checking it.
        (bool success,) = address(configLib).staticcall(abi.encodeCall(configLib.checkConfigured, ()));

        // Then: It does not revert.
        assertTrue(success);
    }
}
