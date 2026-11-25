/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultAsync_Fuzz_Test } from "./_ALMVaultAsync.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC7540Operator } from "../../../src/vaults/abstracts/tokens/ERC7540Operator.sol";

/**
 * @notice Fuzz tests for the function "redeem" of contract "ALMVaultAsync".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract Redeem_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultAsync_Fuzz_Test) {
        ALMVaultAsync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_redeem_Unauthorized(
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
        uint256 claimableIn = almCore.claimableRedeem(address(vault), controller).amountIn;
        vm.assume(caller != controller);

        // When: The caller claims it.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC7540Operator.Unauthorized.selector);
        vault.redeem(claimableIn, caller, controller);
    }

    function testFuzz_Revert_redeem_InsufficientClaimable(
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
        uint256 claimableIn = almCore.claimableRedeem(address(vault), controller).amountIn;
        excess = bound(excess, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: The controller claims against more shares than were settled.
        // Then: It reverts.
        vm.prank(controller);
        vm.expectRevert(ALMVaultAsync.InsufficientClaimable.selector);
        vault.redeem(claimableIn + excess, controller, controller);
    }

    function testFuzz_Revert_redeem_InsufficientClaimable_EmptyPile(
        PoolState memory poolState,
        uint256 shares,
        bool isToken0
    ) public {
        // Given: The vaults over a pool, and nothing settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        ALMVaultAsync vault = asyncVaultFor(isToken0);

        // When: The controller claims.
        // Then: It reverts.
        vm.prank(controller);
        vm.expectRevert(ALMVaultAsync.InsufficientClaimable.selector);
        vault.redeem(shares, controller, controller);
    }

    function testFuzz_Success_redeem_ReadsNoPile(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0
    ) public {
        // Given: A seeded core, and a settled claim for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setRedeemClaimable(poolState, range, isToken0, controller, shares);
        shares = almCore.claimableRedeem(address(vault), controller).amountIn;

        // When: The controller claims all of it.
        vm.expectCall(address(almCore), abi.encodeWithSelector(bytes4(0xdbd035ff)), 0);
        vm.expectCall(address(almCore), abi.encodeWithSelector(bytes4(0x35fd631a)), 0);
        vm.expectCall(address(almCore), abi.encodeWithSelector(bytes4(0x1e2eaeaf)), 0);
        vm.prank(controller);
        vault.redeem(shares, controller, controller);

        // Then: The vault read no storage of the core, and nothing stays claimable.
        assertEq(almCore.claimableRedeem(address(vault), controller).amountIn, 0);
    }

    function testFuzz_Success_redeem(
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

        // When: The controller claims all of it to another account.
        vm.prank(controller);
        vm.expectEmit(address(vault));
        emit BaseVault.Withdraw(controller, secondController, controller, claimableOut, claimableIn);
        uint256 assets = vault.redeem(claimableIn, secondController, controller);

        // Then: The receiver holds all assets the settlement left, none stay claimable.
        assertEq(assets, claimableOut);
        assertEq((isToken0 ? token0 : token1).balanceOf(secondController), claimableOut);
        assertEq(vault.maxRedeem(controller), 0);
    }

    function testFuzz_Success_redeem_RoundsAgainstTheCaller(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 part,
        bool isToken0
    ) public {
        // Given: A seeded core, a redeem settled for the controller, and a part of it.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setRedeemClaimable(poolState, range, isToken0, controller, shares);
        uint256 claimableIn = almCore.claimableRedeem(address(vault), controller).amountIn;
        uint256 claimableOut = almCore.claimableRedeem(address(vault), controller).amountOut;
        part = bound(part, 1, claimableIn);

        // When: The controller claims against that part.
        vm.prank(controller);
        uint256 assets = vault.redeem(part, controller, controller);

        // Then: It received the part's share of the pile rounded down, and the part left.
        assertEq(assets, part * claimableOut / claimableIn);
        assertEq((isToken0 ? token0 : token1).balanceOf(controller), assets);
        assertEq(vault.maxRedeem(controller), claimableIn - part);
    }

    function testFuzz_Success_redeem_ByOperator(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0
    ) public {
        // Given: A seeded core, a redeem settled for the controller, and its operator.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setRedeemClaimable(poolState, range, isToken0, controller, shares);
        uint256 claimableIn = almCore.claimableRedeem(address(vault), controller).amountIn;
        uint256 claimableOut = almCore.claimableRedeem(address(vault), controller).amountOut;
        vm.prank(controller);
        vault.setOperator(secondController, true);

        // When: The operator claims it to itself.
        vm.prank(secondController);
        vault.redeem(claimableIn, secondController, controller);

        // Then: The operator holds the asset.
        assertEq((isToken0 ? token0 : token1).balanceOf(secondController), claimableOut);
    }
}
