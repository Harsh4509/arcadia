/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Config, ShareAccount } from "../../../../src/core/types/State.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { ShareLib } from "../../../../src/core/libraries/state/ShareLib.sol";
import { ShareLib_Fuzz_Test } from "./_ShareLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "checkPerUserCap" of library "ShareLib".
 */
contract CheckPerUserCap_ShareLib_Fuzz_Test is ShareLib_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_checkPerUserCap_PerUserCapExceeded(
        Config memory config,
        address account,
        ShareAccount memory shareAccount,
        uint256 balance
    ) public {
        // Given: A per user cap, and an account that is neither the core nor exempt.
        vm.assume(account != address(shareLib));
        shareLib.setConfig(config);
        shareLib.setShareAccount(account, shareAccount);

        // And: A balance whose sum with the escrowed and pending shares passes the cap.
        uint256 held = uint256(shareAccount.claimableShares) + shareAccount.pendingShares;
        uint256 floor = config.perUserCap >= held ? config.perUserCap - held + 1 : 0;
        balance = bound(balance, floor, type(uint256).max - held);

        // When: Checking the account.
        // Then: It reverts.
        vm.expectRevert(ShareLib.PerUserCapExceeded.selector);
        shareLib.checkPerUserCap(account, balance);
    }

    function testFuzz_Revert_checkPerUserCap_PerUserCapExceeded_BalanceEqualToTheEscrowedShares(
        Config memory config,
        address account,
        ShareAccount memory shareAccount
    ) public {
        // Given: A per user cap, and an account that is neither the core nor exempt.
        vm.assume(account != address(shareLib));
        config.perUserCap = uint128(bound(config.perUserCap, 1, type(uint128).max));

        // And: Claimable and pending shares summing above half the cap, at most it.
        shareAccount.claimableShares = uint128(bound(shareAccount.claimableShares, 0, config.perUserCap));
        shareAccount.pendingShares = uint128(
            bound(
                shareAccount.pendingShares,
                (uint256(config.perUserCap) / 2 + 1).zeroFloorSub(shareAccount.claimableShares),
                config.perUserCap - shareAccount.claimableShares
            )
        );
        shareLib.setConfig(config);
        shareLib.setShareAccount(account, shareAccount);

        // When: Checking the account at a balance equal to that sum.
        // Then: It reverts.
        vm.expectRevert(ShareLib.PerUserCapExceeded.selector);
        shareLib.checkPerUserCap(account, uint256(shareAccount.claimableShares) + shareAccount.pendingShares);
    }

    function testFuzz_Revert_checkPerUserCap_PerUserCapExceeded_PendingEqualToTheBalanceAndClaimable(
        Config memory config,
        address account,
        ShareAccount memory shareAccount
    ) public {
        // Given: A per user cap, and an account that is neither the core nor exempt.
        vm.assume(account != address(shareLib));
        config.perUserCap = uint128(bound(config.perUserCap, 1, type(uint128).max));

        // And: Pending shares above half the cap and at most it, claimable within them.
        shareAccount.pendingShares =
            uint128(bound(shareAccount.pendingShares, config.perUserCap / 2 + 1, config.perUserCap));
        shareAccount.claimableShares = uint128(bound(shareAccount.claimableShares, 0, shareAccount.pendingShares));
        shareLib.setConfig(config);
        shareLib.setShareAccount(account, shareAccount);

        // When: Checking at a balance that with the claimable sums to the pending.
        // Then: It reverts.
        vm.expectRevert(ShareLib.PerUserCapExceeded.selector);
        shareLib.checkPerUserCap(account, shareAccount.pendingShares - shareAccount.claimableShares);
    }

    function testFuzz_Success_checkPerUserCap_TheCore(
        Config memory config,
        ShareAccount memory shareAccount,
        uint256 balance
    ) public {
        // Given: A per user cap, and the core's own escrowed and pending shares.
        shareLib.setConfig(config);
        shareLib.setShareAccount(address(shareLib), shareAccount);

        // When: Checking the core at any balance.
        (bool success,) =
            address(shareLib).staticcall(abi.encodeCall(shareLib.checkPerUserCap, (address(shareLib), balance)));

        // Then: It does not revert.
        assertTrue(success);
    }

    function testFuzz_Success_checkPerUserCap_ExemptAccount(
        Config memory config,
        address account,
        ShareAccount memory shareAccount,
        uint256 balance
    ) public {
        // Given: A per user cap, and an exempt account.
        shareLib.setConfig(config);
        shareLib.setShareAccount(account, shareAccount);
        shareLib.setCapExempt(account, true);

        // When: Checking the account at any balance.
        (bool success,) = address(shareLib).staticcall(abi.encodeCall(shareLib.checkPerUserCap, (account, balance)));

        // Then: It does not revert.
        assertTrue(success);
    }

    function testFuzz_Success_checkPerUserCap_AtOrBelowTheCap(
        Config memory config,
        address account,
        ShareAccount memory shareAccount,
        uint256 balance
    ) public {
        // Given: An account not exempt, and a per user cap at least what it holds.
        shareAccount.pendingShares =
            uint128(bound(shareAccount.pendingShares, 0, type(uint128).max - shareAccount.claimableShares));
        uint256 held = uint256(shareAccount.claimableShares) + shareAccount.pendingShares;
        config.perUserCap = uint128(bound(config.perUserCap, held, type(uint128).max));
        shareLib.setConfig(config);
        shareLib.setShareAccount(account, shareAccount);

        // And: A balance that keeps the sum at or below the cap.
        balance = bound(balance, 0, config.perUserCap - held);

        // When: Checking the account.
        (bool success,) = address(shareLib).staticcall(abi.encodeCall(shareLib.checkPerUserCap, (account, balance)));

        // Then: It does not revert.
        assertTrue(success);
    }
}
