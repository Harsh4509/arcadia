/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreView_Fuzz_Test } from "./_ALMCoreView.fuzz.t.sol";
import { IALMFactory } from "../../../src/interfaces/IALMFactory.sol";

/**
 * @notice Fuzz tests for the constructor of contract "ALMCoreView".
 */
contract Constructor_ALMCoreView_Fuzz_Test is ALMCoreView_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreView_Fuzz_Test) {
        ALMCoreView_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_constructor_ZeroAddress(uint256 salt) public {
        // Given: The zero address as the factory.

        // When: Deploying the lens over the zero address.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.ZeroAddress.selector);
        new ALMCoreView{ salt: bytes32(salt) }(address(0));
    }

    function testFuzz_Success_constructor_ServesTheCoresOfItsFactory(uint128 buffer0) public {
        // Given: The core's buffer.
        almCore.setBuffers(buffer0, 0);

        // When: Deploying a lens over the factory that created the core.
        ALMCoreView lens = new ALMCoreView(factory);

        // Then: It asks that factory, and serves the core.
        vm.expectCall(factory, abi.encodeCall(IALMFactory.isCore, (address(almCore))));
        assertEq(lens.getPoolTokens(address(almCore)).buffer.amount0, buffer0);
    }
}
