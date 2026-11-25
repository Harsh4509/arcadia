/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { BaseVault_Fuzz_Test } from "./_BaseVault.fuzz.t.sol";
import { ERC7540Operator } from "../../../src/vaults/abstracts/tokens/ERC7540Operator.sol";

/**
 * @notice Fuzz tests for the function "setPaused" of contract "BaseVault", over both vault kinds.
 */
contract SetPaused_BaseVault_Fuzz_Test is BaseVault_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(BaseVault_Fuzz_Test) {
        BaseVault_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_setPaused_Unauthorized_Pause(address caller, uint256 index) public {
        // Given: The four vaults over a pool, and a caller other than their factory.
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];
        vm.assume(caller != factory);

        // When: The caller pauses one of them.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC7540Operator.Unauthorized.selector);
        vault.setPaused(true);
    }

    function testFuzz_Revert_setPaused_Unauthorized_Unpause(address caller, uint256 index) public {
        // Given: The four vaults over a pool, one paused, and a non-factory caller.
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];
        vm.prank(factory);
        vault.setPaused(true);
        vm.assume(caller != factory);

        // When: The caller unpauses it.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC7540Operator.Unauthorized.selector);
        vault.setPaused(false);
    }

    function testFuzz_Success_setPaused_Pauses(uint256 index) public {
        // Given: The four vaults over a pool.
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];

        // When: The factory pauses one of them.
        vm.prank(factory);
        vm.expectEmit(address(vault));
        emit BaseVault.PausedSet(true);
        vault.setPaused(true);

        // Then: It is paused.
        assertTrue(vault.paused());
    }

    function testFuzz_Success_setPaused_Unpauses(uint256 index) public {
        // Given: The four vaults over a pool, one paused.
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];
        vm.prank(factory);
        vault.setPaused(true);

        // When: The factory unpauses it.
        vm.prank(factory);
        vm.expectEmit(address(vault));
        emit BaseVault.PausedSet(false);
        vault.setPaused(false);

        // Then: It is no longer paused.
        assertFalse(vault.paused());
    }
}
