/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreView_Fuzz_Test } from "./_ALMCoreView.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { PoolTokens } from "../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getPoolTokens" of contract "ALMCoreView".
 */
contract GetPoolTokens_ALMCoreView_Fuzz_Test is ALMCoreView_Fuzz_Test {
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

    function testFuzz_Revert_getPoolTokens_CoreNotValid(address notCore) public {
        // Given: An address the factory does not hold as a core.
        vm.assume(notCore != address(almCore));

        // When: Reading it through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getPoolTokens(notCore);
    }

    function testFuzz_Revert_getPoolTokens_CoreNotValid_HalfCreated(uint256 pick) public {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        address[4] memory vaults_ = halfCreatedVaults();
        address core = BaseVault(vaults_[bound(pick, 0, vaults_.length - 1)]).share();

        // When: Reading its core address through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getPoolTokens(core);
    }

    function testFuzz_Revert_getPoolTokens_CoreNotValid_AnotherFactory(uint128 buffer0) public {
        // Given: The core's buffer, and a lens over a factory without a core.
        almCore.setBuffers(buffer0, 0);
        ALMCoreView lens = new ALMCoreView(
            address(deployFactory(extensionCreationCodes(), address(routerTrampoline), users.owner, users.steward))
        );

        // When: Reading the first factory's core through that lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        lens.getPoolTokens(address(almCore));
    }

    function testFuzz_Success_getPoolTokens_IsTheCoresPoolTokens(
        uint128 buffer0,
        uint128 buffer1,
        uint128 protocolFees0,
        uint128 protocolFees1,
        uint128 escrowed0,
        uint128 escrowed1
    ) public {
        // Given: The buffer, the protocol fees and the escrow, written directly.
        almCore.setBuffers(buffer0, buffer1);
        almCore.setFeesOwed(protocolFees0, protocolFees1, 0);
        almCore.setEscrowed(escrowed0, escrowed1);

        // When: Reading the pool tokens through the lens.
        PoolTokens memory poolTokens = coreView.getPoolTokens(address(almCore));

        // Then: Every field reads back.
        assertEq(poolTokens.buffer.amount0, buffer0);
        assertEq(poolTokens.buffer.amount1, buffer1);
        assertEq(poolTokens.protocolFees.amount0, protocolFees0);
        assertEq(poolTokens.protocolFees.amount1, protocolFees1);
        assertEq(poolTokens.escrowed.amount0, escrowed0);
        assertEq(poolTokens.escrowed.amount1, escrowed1);
    }
}
