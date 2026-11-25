/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMRegistry } from "../../../src/registry/ALMRegistry.sol";
import { ALMRegistry_Fuzz_Test } from "./_ALMRegistry.fuzz.t.sol";
import { Ownable } from "@solady/auth/Ownable.sol";

/**
 * @notice Fuzz tests for the constructor of contract "ALMRegistry".
 */
contract Constructor_ALMRegistry_Fuzz_Test is ALMRegistry_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMRegistry_Fuzz_Test) {
        ALMRegistry_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_constructor_ZeroAddress(address sender) public {
        // Given: Any deployer.

        // When: Deploying the registry with no owner.
        // Then: It reverts.
        vm.prank(sender);
        vm.expectRevert(ALMRegistry.ZeroAddress.selector);
        new ALMRegistry(address(0));
    }

    function testFuzz_Success_constructor(address sender, address owner_) public {
        // Given: Any deployer and a non-zero owner.
        vm.assume(owner_ != address(0));

        // When: Deploying the registry.
        vm.expectEmit();
        emit Ownable.OwnershipTransferred(address(0), owner_);
        vm.prank(sender);
        ALMRegistry registry_ = new ALMRegistry(owner_);

        // Then: The owner is set.
        assertEq(registry_.owner(), owner_);

        // And: No factory is registered.
        assertEq(registry_.factoriesLength(), 0);
    }
}
