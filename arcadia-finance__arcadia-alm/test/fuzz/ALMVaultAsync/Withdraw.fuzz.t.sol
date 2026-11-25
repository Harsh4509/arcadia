/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultAsync_Fuzz_Test } from "./_ALMVaultAsync.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC7540Operator } from "../../../src/vaults/abstracts/tokens/ERC7540Operator.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

/**
 * @notice Fuzz tests for the function "withdraw" of contract "ALMVaultAsync".
 */
contract Withdraw_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultAsync_Fuzz_Test) {
        ALMVaultAsync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_withdraw_Unauthorized(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        address caller,
        bool isToken0
    ) public {
        // Given: A seeded core, a settled redeem of the controller, and another caller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setRedeemClaimable(poolState, range, isToken0, controller, shares);
        uint256 claimableOut = almCore.claimableRedeem(address(vault), controller).amountOut;
        vm.assume(caller != controller);

        // When: The caller claims it.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC7540Operator.Unauthorized.selector);
        vault.withdraw(claimableOut, caller, controller);
    }

    function testFuzz_Revert_withdraw_InsufficientClaimable(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 excess,
        bool isToken0
    ) public {
        // Given: A seeded core, and a redeem the keeper settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setRedeemClaimable(poolState, range, isToken0, controller, shares);
        uint256 claimableOut = almCore.claimableRedeem(address(vault), controller).amountOut;
        excess = bound(excess, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: The controller claims more assets than were settled.
        // Then: It reverts.
        vm.prank(controller);
        vm.expectRevert(ALMVaultAsync.InsufficientClaimable.selector);
        vault.withdraw(claimableOut + excess, controller, controller);
    }

    function testFuzz_Revert_withdraw_InsufficientClaimable_NothingClaimable(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        bool isToken0
    ) public {
        // Given: A seeded core, and a controller without a settled request.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        assets = bound(assets, 0, 1);

        // When: The controller claims zero or one.
        // Then: It reverts.
        vm.prank(controller);
        vm.expectRevert(ALMVaultAsync.InsufficientClaimable.selector);
        vault.withdraw(assets, controller, controller);
    }

    function testFuzz_Success_withdraw(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 assets,
        bool isToken0
    ) public {
        // Given: A seeded core, and a redeem the keeper settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setRedeemClaimable(poolState, range, isToken0, controller, shares);
        uint256 claimableIn = almCore.claimableRedeem(address(vault), controller).amountIn;
        uint256 claimableOut = almCore.claimableRedeem(address(vault), controller).amountOut;
        assets = bound(assets, 1, claimableOut);

        // When: The controller claims an exact asset amount.
        vm.prank(controller);
        uint256 spent = vault.withdraw(assets, controller, controller);

        // Then: It got that amount, for its part of the settled shares rounded up.
        assertEq((isToken0 ? token0 : token1).balanceOf(controller), assets);
        assertEq(spent, FixedPointMathLib.fullMulDivUp(assets, claimableIn, claimableOut));
    }

    function testFuzz_Success_withdraw_DeliversExactlyOnAOneToThreePile(PoolState memory poolState) public {
        // Given: A controller whose settled redeem pile is a share against three assets.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        token0.mint(address(almCore), 3);
        almCore.stageClaimableRedeem(asyncVault0, controller, 1, 3);

        // When: The controller claims two assets.
        vm.prank(controller);
        uint256 spent = asyncVault.withdraw(2, controller, controller);

        // Then: It holds two assets, the share is spent, and one asset stays claimable.
        assertEq(token0.balanceOf(controller), 2);
        assertEq(spent, 1);
        assertEq(almCore.claimableRedeem(address(asyncVault), controller).amountOut, 1);
    }

    function testFuzz_Success_withdraw_DrainsTheDustOfAPartialWithdraw(PoolState memory poolState) public {
        // Given: A one to three pile, a withdraw of two assets taking the whole share.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        token0.mint(address(almCore), 3);
        almCore.stageClaimableRedeem(asyncVault0, controller, 1, 3);
        vm.prank(controller);
        asyncVault.withdraw(2, controller, controller);

        // When: The controller claims the asset left, against no share.
        vm.prank(controller);
        uint256 spent = asyncVault.withdraw(1, controller, controller);

        // Then: It holds all three assets, and the pile is empty.
        assertEq(spent, 0);
        assertEq(token0.balanceOf(controller), 3);
        assertEq(asyncVault.maxWithdraw(controller), 0);
    }

    function testFuzz_Success_withdraw_All(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0
    ) public {
        // Given: A seeded core, and a redeem the keeper settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setRedeemClaimable(poolState, range, isToken0, controller, shares);
        uint256 claimableIn = almCore.claimableRedeem(address(vault), controller).amountIn;
        uint256 claimableOut = almCore.claimableRedeem(address(vault), controller).amountOut;

        // When: The controller claims every asset.
        vm.prank(controller);
        uint256 spent = vault.withdraw(claimableOut, controller, controller);

        // Then: It spent exactly the settled shares and holds every asset.
        assertEq(spent, claimableIn);
        assertEq((isToken0 ? token0 : token1).balanceOf(controller), claimableOut);
    }

    function testFuzz_Success_withdraw_MaxWithdrawOfASettledRecord(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0
    ) public {
        // Given: A seeded core, and a redeem record the keeper settled, not yet credited.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setRedeemSettled(poolState, range, isToken0, controller, shares);
        uint256 settled = almCore.redeemEpoch(address(vault), 0).amountOut;
        uint256 maxAssets = vault.maxWithdraw(controller);

        // When: The controller claims what maxWithdraw reports.
        vm.prank(controller);
        vault.withdraw(maxAssets, controller, controller);

        // Then: maxWithdraw was the whole epoch output, now in the controller's balance.
        assertEq(maxAssets, settled);
        assertEq((isToken0 ? token0 : token1).balanceOf(controller), maxAssets);
        assertEq(vault.maxWithdraw(controller), 0);
    }
}
