/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMFactory } from "../../../src/factory/ALMFactory.sol";
import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { ICLPool } from "../../utils/fixtures/metadex/interfaces/ICLPool.sol";
import { Ownable } from "@solady/auth/Ownable.sol";

/**
 * @notice Fuzz tests for the function "removeKeeper" of contract "ALMFactory".
 */
contract RemoveKeeper_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_removeKeeper_Unauthorized(PoolState memory poolState, address caller, address keeper)
        public
    {
        // Given: A factory with every role set and a core it created.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The keeper is in the core's keeper set.
        vm.prank(users.admin);
        almFactory.addKeeper(address(core), keeper);

        // And: The caller is neither the guardian nor the steward.
        vm.assume(caller != users.guardian && caller != users.steward);

        // When: Calling removeKeeper().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.removeKeeper(address(core), keeper);
    }

    function testFuzz_Revert_removeKeeper_Unauthorized_Role(PoolState memory poolState, uint256 pick, address keeper)
        public
    {
        // Given: A factory with every role set and a core it created.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The keeper is in the core's keeper set.
        vm.prank(users.admin);
        almFactory.addKeeper(address(core), keeper);

        // And: The caller holds another role than the guardian or the steward.
        address caller = roleAt(pick);
        vm.assume(caller != users.guardian && caller != users.steward);

        // When: Calling removeKeeper().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.removeKeeper(address(core), keeper);
    }

    function testFuzz_Revert_removeKeeper_CoreNotValid(
        PoolState memory poolState,
        bool byGuardian,
        address candidate,
        address keeper
    ) public {
        // Given: A factory with every role set.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: An address the factory did not create a core at.
        vm.assume(!almFactory.isCore(candidate));

        // When: The guardian or the steward calls removeKeeper() on the candidate.
        // Then: It reverts.
        vm.prank(byGuardian ? users.guardian : users.steward);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.removeKeeper(candidate, keeper);
    }

    function testFuzz_Revert_execute_OnlyKeeper_RemovedKeeper(
        PoolState memory poolState,
        bool byGuardian,
        bool onSecondCore,
        address keeper,
        bytes memory commands,
        bytes[] memory inputs,
        uint160 trustedSqrtPriceX96
    ) public {
        // Given: Two cores created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        ICLPool secondPool = createPool(
            address(token0),
            address(token1),
            poolState.tickSpacing == TICK_SPACING ? TICK_SPACING / 2 : TICK_SPACING,
            SQRT_PRICE_ONE_X96,
            OBSERVATION_CARDINALITY
        );
        createGauge(secondPool, true);
        ALMCore secondCore = ALMCore(
            createInThreeTransactions(
                almFactory, address(secondPool), creationCodes(), users.steward, users.feeRecipient
            )
        );
        ALMCore target = onSecondCore ? secondCore : core;

        // And: A keeper the admin added and the guardian or the steward removed.
        vm.prank(users.admin);
        almFactory.addKeeper(address(target), keeper);
        vm.prank(byGuardian ? users.guardian : users.steward);
        almFactory.removeKeeper(address(target), keeper);

        // When: The removed keeper calls execute() on that core.
        // Then: It reverts.
        vm.prank(keeper);
        vm.expectRevert(ALMKeeperExtension.OnlyKeeper.selector);
        target.execute(commands, inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_removeKeeper(PoolState memory poolState, bool byGuardian, address keeper) public {
        // Given: A factory with every role set and a core it created.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The keeper is in the core's keeper set.
        vm.prank(users.admin);
        almFactory.addKeeper(address(core), keeper);

        // When: The guardian or the steward calls removeKeeper().
        vm.prank(byGuardian ? users.guardian : users.steward);
        vm.expectEmit(address(almFactory));
        emit ALMFactory.KeeperSet(address(core), keeper, false);
        almFactory.removeKeeper(address(core), keeper);

        // Then: The keeper is no longer in the core's keeper set.
        assertFalse(almFactory.isKeeper(address(core), keeper));
    }
}
