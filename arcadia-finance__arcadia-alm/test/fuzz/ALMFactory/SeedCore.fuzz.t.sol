/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory } from "../../../src/factory/ALMFactory.sol";
import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { Ownable } from "@solady/auth/Ownable.sol";

/**
 * @notice Fuzz tests for the function "seedCore" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract SeedCore_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_seedCore_Unauthorized(
        PoolState memory poolState,
        address caller,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    ) public {
        // Given: A configured core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        setVaultConfigured();

        // And: The caller is not the steward.
        vm.assume(caller != users.steward);

        // When: Calling seedCore().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.seedCore(address(core), amount0, amount1, shares, caller);
    }

    function testFuzz_Revert_seedCore_Unauthorized_Role(
        PoolState memory poolState,
        uint256 pick,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    ) public {
        // Given: A configured core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        setVaultConfigured();

        // And: The caller holds another role than the steward.
        address caller = roleAt(pick);
        vm.assume(caller != users.steward);

        // When: Calling seedCore().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.seedCore(address(core), amount0, amount1, shares, caller);
    }

    function testFuzz_Revert_seedCore_CoreNotValid(
        PoolState memory poolState,
        address candidate,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    ) public {
        // Given: A configured core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        setVaultConfigured();

        // And: A candidate the factory did not create.
        vm.assume(candidate != address(core));

        // When: The steward seeds the candidate.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.seedCore(candidate, amount0, amount1, shares, users.steward);
    }

    function testFuzz_Revert_seedCore_CoreNotValid_HalfCreated(
        PoolState memory poolState,
        bool withSyncVaults,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    ) public {
        // Given: A pool whose creation stopped after one or two of its transactions.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        address halfCreated = setHalfCreated(withSyncVaults);

        // When: The steward seeds the address its core will take.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.CoreNotValid.selector);
        almFactory.seedCore(halfCreated, amount0, amount1, shares, users.steward);
    }

    function testFuzz_Revert_seedCore_RoleCallsCoreDirectly(
        PoolState memory poolState,
        uint256 pick,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    ) public {
        // Given: A configured core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        setVaultConfigured();
        address caller = roleAt(pick);

        // When: A role holder calls seed() on the core itself.
        // Then: It reverts, the role being the factory's and not the caller's.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        core.seed(amount0, amount1, shares, caller);
    }

    function testFuzz_Success_seedCore(
        PoolState memory poolState,
        uint256 amount0,
        uint256 amount1,
        uint256 shares,
        address receiver
    ) public {
        // Given: A configured core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        setVaultConfigured();

        // And: A seed of both tokens held by the steward, minted to another account.
        amount0 = bound(amount0, 1, Constants.MAX_FUZZED_AMOUNT);
        amount1 = bound(amount1, 1, Constants.MAX_FUZZED_AMOUNT);
        shares = bound(shares, Constants.DEAD_SHARES + 1, Constants.MAX_FUZZED_AMOUNT);
        vm.assume(receiver != address(0) && receiver != address(1));

        token0.mint(users.steward, amount0);
        token1.mint(users.steward, amount1);
        vm.startPrank(users.steward);
        token0.approve(address(almFactory), amount0);
        token1.approve(address(almFactory), amount1);
        vm.stopPrank();

        // When: The steward seeds the core.
        vm.prank(users.steward);
        vm.expectEmit(address(core));
        emit IALMCoreEvents.Seeded(receiver, shares, amount0, amount1);
        almFactory.seedCore(address(core), amount0, amount1, shares, receiver);

        // Then: Both amounts are pulled from the steward into the core.
        assertEq(token0.balanceOf(users.steward), 0);
        assertEq(token1.balanceOf(users.steward), 0);
        assertEq(token0.balanceOf(address(core)), amount0);
        assertEq(token1.balanceOf(address(core)), amount1);

        // And: The dead shares go to address(1), the rest of the supply to the receiver.
        assertEq(core.totalSupply(), shares);
        assertEq(core.balanceOf(address(1)), Constants.DEAD_SHARES);
        assertEq(core.balanceOf(receiver), shares - Constants.DEAD_SHARES);
    }

    function testFuzz_Success_seedCore_HoldsNothing(
        PoolState memory poolState,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    ) public {
        // Given: A configured core created by the factory.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        setVaultConfigured();

        // And: A seed of both tokens, the steward holding them.
        amount0 = bound(amount0, 1, Constants.MAX_FUZZED_AMOUNT);
        amount1 = bound(amount1, 1, Constants.MAX_FUZZED_AMOUNT);
        shares = bound(shares, Constants.DEAD_SHARES + 1, Constants.MAX_FUZZED_AMOUNT);

        // When: The steward seeds the core, minting the supply to itself.
        token0.mint(users.steward, amount0);
        token1.mint(users.steward, amount1);
        vm.startPrank(users.steward);
        token0.approve(address(almFactory), amount0);
        token1.approve(address(almFactory), amount1);
        vm.stopPrank();
        vm.prank(users.steward);
        almFactory.seedCore(address(core), amount0, amount1, shares, users.steward);

        // Then: The factory holds no token or aLP and leaves no allowance on the core.
        assertEq(token0.balanceOf(address(almFactory)), 0);
        assertEq(token1.balanceOf(address(almFactory)), 0);
        assertEq(core.balanceOf(address(almFactory)), 0);
        assertEq(token0.allowance(address(almFactory), address(core)), 0);
        assertEq(token1.allowance(address(almFactory), address(core)), 0);
    }
}
