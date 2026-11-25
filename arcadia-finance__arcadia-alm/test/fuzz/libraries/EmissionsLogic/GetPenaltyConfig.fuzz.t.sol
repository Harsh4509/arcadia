/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { EmissionsLogic_Fuzz_Test } from "./_EmissionsLogic.fuzz.t.sol";
import { IMetadexCLGaugeFactory } from "../../../../src/interfaces/IMetadexCLGaugeFactory.sol";

/**
 * @notice Fuzz tests for the function "getPenaltyConfig" of library "EmissionsLogic".
 */
contract GetPenaltyConfig_EmissionsLogic_Fuzz_Test is EmissionsLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(EmissionsLogic_Fuzz_Test) {
        EmissionsLogic_Fuzz_Test.setUp();
        deployStakedPool();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getPenaltyConfig_FactoryConfig(uint256 minStakeBlocks, uint256 penaltyRate) public {
        // Given: A factory penalty config, no override for the gauge.
        minStakeBlocks = bound(minStakeBlocks, 0, type(uint32).max);
        penaltyRate = bound(penaltyRate, 0, MAX_PIPS);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // When: Getting the gauge's penalty config.
        IMetadexCLGaugeFactory.PenaltyConfig memory config =
            emissionsLogic.getPenaltyConfig(address(clGaugeFactory), address(gauge));

        // Then: It is the factory's.
        assertEq(config.minStakeBlocks, minStakeBlocks);
        assertEq(config.penaltyRate, penaltyRate);
    }

    function testFuzz_Success_getPenaltyConfig_GaugeOverride(
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 overrideBlocks
    ) public {
        // Given: A factory penalty config.
        minStakeBlocks = bound(minStakeBlocks, 0, type(uint32).max);
        penaltyRate = bound(penaltyRate, 0, MAX_PIPS);
        setPenaltyConfig(minStakeBlocks, penaltyRate);

        // And: A window override for the gauge.
        overrideBlocks = bound(overrideBlocks, 1, type(uint32).max);
        setMinStakeBlocks(gauge, overrideBlocks);

        // When: Getting the gauge's penalty config.
        IMetadexCLGaugeFactory.PenaltyConfig memory config =
            emissionsLogic.getPenaltyConfig(address(clGaugeFactory), address(gauge));

        // Then: It is the override's window at the factory's rate.
        assertEq(config.minStakeBlocks, overrideBlocks);
        assertEq(config.penaltyRate, penaltyRate);
    }
}
