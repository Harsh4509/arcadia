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
 * @notice Fuzz tests for the function "addKeeper" of contract "ALMFactory".
 */
contract AddKeeper_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_addKeeper_Unauthorized(PoolState memory poolState, address caller, address keeper) public {
        // Given: A factory with every role set and a core it created.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The caller is not the admin.
        vm.assume(caller != users.admin);

        // When: Calling addKeeper().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.addKeeper(address(core), keeper);
    }

    function testFuzz_Revert_addKeeper_Unauthorized_Role(PoolState memory poolState, uint256 pick, address keeper)
        public
    {
        // Given: A factory with every role set and a core it created.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: The caller holds another role than the admin.
        address caller = roleAt(pick);
        vm.assume(caller != users.admin);

        // When: Calling addKeeper().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.addKeeper(address(core), keeper);
    }

    function testFuzz_Revert_addKeeper_CoreNotValid(PoolState memory poolState, address candidate, address keeper)
        public
    {
        // Given: A factory with every role set.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: An address the factory did not create a core at.
        vm.assume(!almFactory.isCore(candidate));

        // When: The admin calls addKeeper() on the candidate.
        // Then: It reverts.
        vm.prank(users.admin);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.addKeeper(candidate, keeper);
    }

    function testFuzz_Revert_execute_OnlyKeeper_KeeperOfAnotherCore(
        PoolState memory poolState,
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

        // And: A keeper the admin added on the first core only.
        vm.prank(users.admin);
        almFactory.addKeeper(address(core), keeper);

        // When: The keeper calls execute() on the second core.
        // Then: It reverts.
        vm.prank(keeper);
        vm.expectRevert(ALMKeeperExtension.OnlyKeeper.selector);
        secondCore.execute(commands, inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_addKeeper(PoolState memory poolState, address keeper) public {
        // Given: A factory with every role set and a core it created.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // When: The admin calls addKeeper().
        vm.prank(users.admin);
        vm.expectEmit(address(almFactory));
        emit ALMFactory.KeeperSet(address(core), keeper, true);
        almFactory.addKeeper(address(core), keeper);

        // Then: The keeper is in the core's keeper set.
        assertTrue(almFactory.isKeeper(address(core), keeper));
    }
}
