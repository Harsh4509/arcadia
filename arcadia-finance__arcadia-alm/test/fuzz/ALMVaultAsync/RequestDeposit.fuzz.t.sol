/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultAsync_Fuzz_Test } from "./_ALMVaultAsync.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC7540Deposit } from "../../../src/vaults/abstracts/tokens/ERC7540Deposit.sol";
import { ERC7540Operator } from "../../../src/vaults/abstracts/tokens/ERC7540Operator.sol";
import { QueueLib } from "../../../src/core/libraries/state/QueueLib.sol";

/**
 * @notice Fuzz tests for the function "requestDeposit" of contract "ALMVaultAsync".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract RequestDeposit_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultAsync_Fuzz_Test) {
        ALMVaultAsync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_requestDeposit_Paused(PoolState memory poolState, uint256 assets, bool isToken0) public {
        // Given: The vaults over a pool, the async one paused, and an owner with asset.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        assets = bound(assets, 1, Constants.MAX_FUZZED_AMOUNT);
        fundRequester(isToken0, users.unprivilegedAddress, assets);
        vm.prank(factory);
        vault.setPaused(true);

        // When: The owner requests a deposit.
        // Then: It reverts.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(BaseVault.Paused.selector);
        vault.requestDeposit(assets, controller, users.unprivilegedAddress);
    }

    function testFuzz_Revert_requestDeposit_Unauthorized(
        PoolState memory poolState,
        uint256 assets,
        address caller,
        bool isToken0
    ) public {
        // Given: The vaults over a pool, an owner with asset, and a non-operator caller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        assets = bound(assets, 1, Constants.MAX_FUZZED_AMOUNT);
        fundRequester(isToken0, users.unprivilegedAddress, assets);
        vm.assume(caller != users.unprivilegedAddress);

        // When: The caller requests a deposit out of the owner's asset.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC7540Operator.Unauthorized.selector);
        asyncVaultFor(isToken0).requestDeposit(assets, caller, users.unprivilegedAddress);
    }

    function testFuzz_Revert_requestDeposit_ZeroAddress(PoolState memory poolState, uint256 assets, bool isToken0)
        public
    {
        // Given: The vaults over a pool, and an owner holding the asset.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        assets = bound(assets, 1, Constants.MAX_FUZZED_AMOUNT);
        fundRequester(isToken0, users.unprivilegedAddress, assets);

        // When: The owner requests a deposit held for no controller.
        // Then: It reverts.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(QueueLib.ZeroAddress.selector);
        asyncVaultFor(isToken0).requestDeposit(assets, address(0), users.unprivilegedAddress);
    }

    function testFuzz_Revert_requestDeposit_ZeroAmount(PoolState memory poolState, bool isToken0) public {
        // Given: The vaults over a pool.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // When: An owner requests a deposit of nothing.
        // Then: It reverts.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(QueueLib.ZeroAmount.selector);
        asyncVaultFor(isToken0).requestDeposit(0, controller, users.unprivilegedAddress);
    }

    function testFuzz_Success_requestDeposit(PoolState memory poolState, uint256 assets, bool isToken0) public {
        // Given: The vaults over a pool, and an owner holding the asset.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        assets = bound(assets, 1, Constants.MAX_FUZZED_AMOUNT);
        fundRequester(isToken0, users.unprivilegedAddress, assets);
        uint256 coreBefore = (isToken0 ? token0 : token1).balanceOf(address(almCore));

        // When: The owner requests a deposit held for a controller.
        vm.prank(users.unprivilegedAddress);
        vm.expectEmit(address(vault));
        emit ERC7540Deposit.DepositRequest(controller, users.unprivilegedAddress, 0, users.unprivilegedAddress, assets);
        uint256 id = vault.requestDeposit(assets, controller, users.unprivilegedAddress);

        // Then: The asset moved from the owner straight to the core.
        assertEq((isToken0 ? token0 : token1).balanceOf(users.unprivilegedAddress), 0);
        assertEq((isToken0 ? token0 : token1).balanceOf(address(almCore)), coreBefore + assets);
        assertEq((isToken0 ? token0 : token1).balanceOf(address(vault)), 0);

        // And: The request id is 0, the record is pending and its assets are in escrow.
        assertEq(id, 0);
        assertEq(almCore.depositRecord(address(vault), controller).epoch, 0);
        assertEq(almCore.depositRecord(address(vault), controller).amountIn, assets);
        assertEq(isToken0 ? almCore.getEscrowed0() : almCore.getEscrowed1(), assets);
    }

    function testFuzz_Success_requestDeposit_ByOperator(PoolState memory poolState, uint256 assets, bool isToken0)
        public
    {
        // Given: The vaults over a pool, an owner holding the asset, and its operator.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        assets = bound(assets, 1, Constants.MAX_FUZZED_AMOUNT);
        fundRequester(isToken0, users.unprivilegedAddress, assets);
        vm.prank(users.unprivilegedAddress);
        vault.setOperator(secondController, true);

        // When: The operator requests a deposit out of the owner's asset.
        vm.prank(secondController);
        vault.requestDeposit(assets, controller, users.unprivilegedAddress);

        // Then: The owner paid it, and it is pending for the controller.
        assertEq((isToken0 ? token0 : token1).balanceOf(users.unprivilegedAddress), 0);
        assertEq(vault.pendingDepositRequest(0, controller), assets);
    }
}
