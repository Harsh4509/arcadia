/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreView_Fuzz_Test } from "./_ALMCoreView.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { Config } from "../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getConfig" of contract "ALMCoreView".
 */
contract GetConfig_ALMCoreView_Fuzz_Test is ALMCoreView_Fuzz_Test {
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

    function testFuzz_Revert_getConfig_CoreNotValid(address notCore) public {
        // Given: An address the factory does not hold as a core.
        vm.assume(notCore != address(almCore));

        // When: Reading it through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getConfig(notCore);
    }

    function testFuzz_Revert_getConfig_CoreNotValid_HalfCreated(uint256 pick) public {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        address[4] memory vaults_ = halfCreatedVaults();
        address core = BaseVault(vaults_[bound(pick, 0, vaults_.length - 1)]).share();

        // When: Reading its core address through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getConfig(core);
    }

    function testFuzz_Success_getConfig_IsTheCoresConfig(Config memory config) public {
        // Given: Every field of the configuration, written through the accessor.
        almCore.setConfig(config);

        // When: Reading the configuration through the lens.
        Config memory read = coreView.getConfig(address(almCore));

        // Then: Every field reads back.
        assertEq(read.totalCap, config.totalCap);
        assertEq(read.perUserCap, config.perUserCap);
        assertEq(read.paused, config.paused);
        assertEq(read.protocolEmissionFeeBps, config.protocolEmissionFeeBps);
        assertEq(read.protocolSwapFeeBps, config.protocolSwapFeeBps);
        assertEq(read.feeRecipient, config.feeRecipient);
        assertEq(read.twapWindow, config.twapWindow);
        assertEq(read.maxSpotFromTwap, config.maxSpotFromTwap);
        assertEq(read.maxSpotFromTrusted, config.maxSpotFromTrusted);
        assertEq(read.maxTwapFromTrusted, config.maxTwapFromTrusted);
        assertEq(read.maxShortfallBps, config.maxShortfallBps);
        assertEq(read.maxSwapCostBps, config.maxSwapCostBps);
        assertEq(read.minPlanInterval, config.minPlanInterval);
        assertEq(read.rangeCap, config.rangeCap);
        assertEq(read.lastPlanAt, config.lastPlanAt);
    }
}
