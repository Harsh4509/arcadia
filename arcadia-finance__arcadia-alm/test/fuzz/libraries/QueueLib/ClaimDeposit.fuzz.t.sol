/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Claimable, ShareAccount } from "../../../../src/core/types/State.sol";
import { QueueLib } from "../../../../src/core/libraries/state/QueueLib.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "claimDeposit" of library "QueueLib".
 */
contract ClaimDeposit_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_claimDeposit_InsufficientClaimable(
        address vault,
        address controller,
        uint256 assets,
        uint256 maxShares
    ) public {
        // Given: A controller with nothing claimable.

        // When: Claiming.
        // Then: It reverts.
        vm.expectRevert(QueueLib.InsufficientClaimable.selector);
        queueLib.claimDeposit(vault, controller, assets, maxShares);
    }

    function testFuzz_Success_claimDeposit_TakesTheClaimable(
        address vault,
        address controller,
        Claimable memory claimable,
        uint256 assets,
        uint256 maxShares
    ) public {
        // Given: A controller with a claimable deposit and no record.
        claimable.amountIn = uint128(bound(claimable.amountIn, 1, type(uint128).max));
        queueLib.setClaimableDeposit(vault, controller, claimable);

        // And: Assets within the claimable input.
        assets = bound(assets, 0, claimable.amountIn);

        // When: Claiming.
        uint256 shares = queueLib.claimDeposit(vault, controller, assets, maxShares);

        // Then: The shares are the pro-rata output, capped.
        uint256 expected = assets * claimable.amountOut / claimable.amountIn;
        assertEq(shares, expected < maxShares ? expected : maxShares);

        // And: The claimable pile falls by the input and the shares.
        Claimable memory claimableAfter = queueLib.getClaimableDeposit(vault, controller);
        assertEq(claimableAfter.amountIn, claimable.amountIn - assets);
        assertEq(claimableAfter.amountOut, claimable.amountOut - shares);
    }

    function testFuzz_Success_claimDeposit_TakesTheSharesOffTheClaimableShares(
        address vault,
        address controller,
        Claimable memory claimable,
        ShareAccount memory shareAccount,
        uint256 maxShares
    ) public {
        // Given: A controller with a claimable deposit and no record.
        claimable.amountIn = uint128(bound(claimable.amountIn, 1, type(uint128).max));
        claimable.amountOut = uint128(bound(claimable.amountOut, 1, type(uint128).max));
        queueLib.setClaimableDeposit(vault, controller, claimable);

        // And: Claimable aLP on the controller of at least the deposit's.
        shareAccount.claimableShares =
            uint128(bound(shareAccount.claimableShares, claimable.amountOut, type(uint128).max));
        queueLib.setShareAccount(controller, shareAccount);

        // When: Claiming the whole input, the shares capped at no less than its output.
        maxShares = bound(maxShares, claimable.amountOut, type(uint256).max);
        uint256 shares = queueLib.claimDeposit(vault, controller, claimable.amountIn, maxShares);

        // Then: The whole output is taken off the controller's claimable aLP.
        assertEq(shares, claimable.amountOut);
        assertEq(
            queueLib.getShareAccount(controller).claimableShares, shareAccount.claimableShares - claimable.amountOut
        );
    }
}
