/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { Ownable } from "@solady/auth/Ownable.sol";

/**
 * @notice Fuzz tests for the function "transferOwnership" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract TransferOwnership_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_transferOwnership_Unauthorized(
        PoolState memory poolState,
        address caller,
        address newOwner
    ) public {
        // Given: A factory with every role set.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: The caller is not the owner.
        vm.assume(caller != users.owner);

        // When: Calling transferOwnership().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.transferOwnership(newOwner);
    }

    function testFuzz_Revert_transferOwnership_NewOwnerIsZeroAddress(PoolState memory poolState) public {
        // Given: A factory with every role set.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // When: The owner hands the role to nobody.
        // Then: It reverts.
        vm.prank(users.owner);
        vm.expectRevert(Ownable.NewOwnerIsZeroAddress.selector);
        almFactory.transferOwnership(address(0));
    }

    function testFuzz_Success_transferOwnership(PoolState memory poolState, address newOwner) public {
        // Given: A factory with every role set.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A new owner other than the current one.
        vm.assume(newOwner != address(0) && newOwner != users.owner);

        // When: The owner hands the role over.
        vm.prank(users.owner);
        vm.expectEmit(address(almFactory));
        emit Ownable.OwnershipTransferred(users.owner, newOwner);
        almFactory.transferOwnership(newOwner);

        // Then: The new owner holds it.
        assertEq(almFactory.owner(), newOwner);
    }

    function testFuzz_Success_transferOwnership_FormerOwnerLosesTheRole(PoolState memory poolState, address newOwner)
        public
    {
        // Given: A factory with every role set.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: The owner handed the role to a new owner.
        vm.assume(newOwner != address(0) && newOwner != users.owner);
        vm.prank(users.owner);
        almFactory.transferOwnership(newOwner);

        // When: The former owner calls setAdmin().
        // Then: It reverts.
        vm.prank(users.owner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.setAdmin(users.owner);
    }
}
