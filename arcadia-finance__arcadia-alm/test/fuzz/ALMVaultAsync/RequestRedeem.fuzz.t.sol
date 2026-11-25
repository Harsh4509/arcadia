/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultAsync_Fuzz_Test } from "./_ALMVaultAsync.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { ERC7540Redeem } from "../../../src/vaults/abstracts/tokens/ERC7540Redeem.sol";
import { QueueLib } from "../../../src/core/libraries/state/QueueLib.sol";

/**
 * @notice Fuzz tests for the function "requestRedeem" of contract "ALMVaultAsync".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract RequestRedeem_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultAsync_Fuzz_Test) {
        ALMVaultAsync_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_requestRedeem_InsufficientAllowance(
        uint256 shares,
        uint256 allowance,
        address caller,
        bool isToken0
    ) public {
        // Given: The vaults over a pool, and an owner with shares.
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        fundRedeemer(users.unprivilegedAddress, shares);

        // And: A caller that is neither the owner nor its operator, approved for less.
        vm.assume(caller != users.unprivilegedAddress);
        allowance = bound(allowance, 0, shares - 1);
        vm.prank(users.unprivilegedAddress);
        almCore.approve(caller, allowance);

        // When: The caller requests a redeem of the owner's shares.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        asyncVaultFor(isToken0).requestRedeem(shares, caller, users.unprivilegedAddress);
    }

    function testFuzz_Revert_requestRedeem_ZeroAmount(bool isToken0) public {
        // Given: The vaults over a pool.

        // When: An owner requests a redeem of nothing.
        // Then: It reverts.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(QueueLib.ZeroAmount.selector);
        asyncVaultFor(isToken0).requestRedeem(0, controller, users.unprivilegedAddress);
    }

    function testFuzz_Success_requestRedeem(uint256 shares, bool isToken0) public {
        // Given: The vaults over a pool, and an owner holding shares, approving no one.
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        fundRedeemer(users.unprivilegedAddress, shares);

        // When: The owner requests a redeem held for a controller.
        vm.prank(users.unprivilegedAddress);
        vm.expectEmit(address(vault));
        emit ERC7540Redeem.RedeemRequest(controller, users.unprivilegedAddress, 0, users.unprivilegedAddress, shares);
        uint256 id = vault.requestRedeem(shares, controller, users.unprivilegedAddress);

        // Then: The shares moved from the owner into the core's escrow.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), 0);
        assertEq(almCore.balanceOf(address(almCore)), shares);
        assertEq(almCore.balanceOf(address(vault)), 0);

        // And: The request id is 0 and the record sits in the pending epoch.
        assertEq(id, 0);
        assertEq(almCore.redeemRecord(address(vault), controller).epoch, 0);
        assertEq(almCore.redeemRecord(address(vault), controller).amountIn, shares);
    }

    function testFuzz_Success_requestRedeem_WhilePaused(uint256 shares, bool isToken0) public {
        // Given: The vaults over a pool, the async one paused, and an owner with shares.
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        fundRedeemer(users.unprivilegedAddress, shares);
        vm.prank(factory);
        vault.setPaused(true);

        // When: The owner requests a redeem.
        vm.prank(users.unprivilegedAddress);
        vault.requestRedeem(shares, controller, users.unprivilegedAddress);

        // Then: The exit is queued, a pause blocking entries only.
        assertEq(vault.pendingRedeemRequest(0, controller), shares);
    }

    function testFuzz_Success_requestRedeem_ByOperator(uint256 shares, bool isToken0) public {
        // Given: The vaults over a pool, an owner holding shares, and its operator.
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        fundRedeemer(users.unprivilegedAddress, shares);
        vm.prank(users.unprivilegedAddress);
        vault.setOperator(secondController, true);

        // When: The operator requests a redeem of the owner's shares.
        vm.prank(secondController);
        vault.requestRedeem(shares, controller, users.unprivilegedAddress);

        // Then: The owner's shares are queued for the controller, no allowance was used.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), 0);
        assertEq(vault.pendingRedeemRequest(0, controller), shares);
        assertEq(almCore.allowance(users.unprivilegedAddress, secondController), 0);
    }

    function testFuzz_Success_requestRedeem_BySpender(uint256 shares, uint256 allowance, address spender, bool isToken0)
        public
    {
        // Given: The vaults over a pool, and an owner holding shares.
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        fundRedeemer(users.unprivilegedAddress, shares);

        // And: A spender that is not an operator, approved on the core for the shares.
        vm.assume(spender != users.unprivilegedAddress && spender != address(0));
        allowance = bound(allowance, shares, type(uint256).max - 1);
        vm.prank(users.unprivilegedAddress);
        almCore.approve(spender, allowance);

        // When: The spender requests a redeem of the owner's shares.
        vm.prank(spender);
        vault.requestRedeem(shares, controller, users.unprivilegedAddress);

        // Then: The shares are queued for the controller, and the allowance dropped.
        assertEq(vault.pendingRedeemRequest(0, controller), shares);
        assertEq(almCore.allowance(users.unprivilegedAddress, spender), allowance - shares);
    }
}
