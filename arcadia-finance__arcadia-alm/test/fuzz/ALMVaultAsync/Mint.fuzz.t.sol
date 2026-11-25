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
import { ShareLib } from "../../../src/core/libraries/state/ShareLib.sol";

/**
 * @notice Fuzz tests for the function "mint" of contract "ALMVaultAsync".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract Mint_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultAsync_Fuzz_Test) {
        ALMVaultAsync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_mint_Unauthorized(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        address caller,
        bool isToken0
    ) public {
        // Given: A seeded core, a settled deposit of the controller, and another caller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setDepositClaimable(poolState, range, queueState, isToken0, controller);
        uint256 claimableOut = almCore.claimableDeposit(address(vault), controller).amountOut;
        vm.assume(caller != controller);

        // When: The caller claims it.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC7540Operator.Unauthorized.selector);
        vault.mint(claimableOut, caller, controller);
    }

    function testFuzz_Revert_mint_InsufficientClaimable(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 excess,
        bool isToken0
    ) public {
        // Given: A seeded core, and a deposit the keeper settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setDepositClaimable(poolState, range, queueState, isToken0, controller);
        uint256 claimableOut = almCore.claimableDeposit(address(vault), controller).amountOut;
        excess = bound(excess, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: The controller claims more shares than were settled.
        // Then: It reverts.
        vm.prank(controller);
        vm.expectRevert(ALMVaultAsync.InsufficientClaimable.selector);
        vault.mint(claimableOut + excess, controller);
    }

    function testFuzz_Revert_mint_InsufficientClaimable_NothingClaimable(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0
    ) public {
        // Given: A seeded core, and a controller without a settled request.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        shares = bound(shares, 0, 1);

        // When: The controller claims zero or one.
        // Then: It reverts.
        vm.prank(controller);
        vm.expectRevert(ALMVaultAsync.InsufficientClaimable.selector);
        vault.mint(shares, controller, controller);
    }

    function testFuzz_Revert_mint_PerUserCapExceeded(PoolState memory poolState, uint96 claimableOut) public {
        // Given: A settled deposit, and a per user cap one share short of it.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        claimableOut = uint96(bound(claimableOut, 1, type(uint96).max));
        almCore.stageClaimableDeposit(asyncVault0, controller, 1, claimableOut);
        vm.prank(factory);
        almCore.setPerUserCap(claimableOut - 1);

        // When: The controller claims every share to an account apart from itself.
        // Then: It reverts on the receiver's cap balance.
        vm.prank(controller);
        vm.expectRevert(ShareLib.PerUserCapExceeded.selector);
        asyncVault.mint(claimableOut, secondController, controller);
    }

    function testFuzz_Success_mint(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 shares,
        bool isToken0
    ) public {
        // Given: A seeded core, and a deposit the keeper settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setDepositClaimable(poolState, range, queueState, isToken0, controller);
        uint256 claimableIn = almCore.claimableDeposit(address(vault), controller).amountIn;
        uint256 claimableOut = almCore.claimableDeposit(address(vault), controller).amountOut;
        shares = bound(shares, 1, claimableOut);

        // When: The controller claims an exact share amount.
        vm.prank(controller);
        uint256 spent = vault.mint(shares, controller);

        // Then: It got those shares, for their part of the settled amount rounded up.
        assertEq(almCore.balanceOf(controller), shares);
        assertEq(spent, FixedPointMathLib.fullMulDivUp(shares, claimableIn, claimableOut));
    }

    function testFuzz_Success_mint_DeliversExactlyOnAOneToThreePile(PoolState memory poolState) public {
        // Given: A controller whose settled deposit pile is one asset for three shares.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.stageClaimableDeposit(asyncVault0, controller, 1, 3);

        // When: The controller claims two shares.
        vm.prank(controller);
        uint256 spent = asyncVault.mint(2, controller, controller);

        // Then: It holds two shares, the asset is spent, and one share stays claimable.
        assertEq(almCore.balanceOf(controller), 2);
        assertEq(spent, 1);
        assertEq(almCore.claimableDeposit(address(asyncVault), controller).amountOut, 1);
    }

    function testFuzz_Success_mint_DrainsTheDustOfAPartialMint(PoolState memory poolState) public {
        // Given: A one to three pile, of which a mint of two shares took the whole asset.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.stageClaimableDeposit(asyncVault0, controller, 1, 3);
        vm.prank(controller);
        asyncVault.mint(2, controller, controller);

        // When: The controller claims the share left, against no asset.
        vm.prank(controller);
        uint256 spent = asyncVault.mint(1, controller, controller);

        // Then: It holds all three shares, and the pile is empty.
        assertEq(spent, 0);
        assertEq(almCore.balanceOf(controller), 3);
        assertEq(asyncVault.maxMint(controller), 0);
    }

    function testFuzz_Success_mint_All(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        bool isToken0
    ) public {
        // Given: A seeded core, and a deposit the keeper settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setDepositClaimable(poolState, range, queueState, isToken0, controller);
        uint256 claimableIn = almCore.claimableDeposit(address(vault), controller).amountIn;
        uint256 claimableOut = almCore.claimableDeposit(address(vault), controller).amountOut;

        // When: The controller claims every share.
        vm.prank(controller);
        uint256 spent = vault.mint(claimableOut, controller);

        // Then: It spent exactly the settled amount and holds every share.
        assertEq(spent, claimableIn);
        assertEq(almCore.balanceOf(controller), claimableOut);
    }

    function testFuzz_Success_mint_MaxMintOfASettledRecord(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        bool isToken0
    ) public {
        // Given: A seeded core, and a deposit the keeper settled, not yet credited.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setDepositSettled(poolState, range, queueState, isToken0, controller);
        uint256 settled = almCore.depositEpoch(address(vault), 0).amountOut;
        uint256 maxShares = vault.maxMint(controller);

        // When: The controller claims what maxMint reports.
        vm.prank(controller);
        vault.mint(maxShares, controller);

        // Then: maxMint was the whole epoch output, now in the controller's balance.
        assertEq(maxShares, settled);
        assertEq(almCore.balanceOf(controller), maxShares);
        assertEq(vault.maxMint(controller), 0);
    }
}
