/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { ShareAccount } from "../../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getShareAccount" of library "ALMCoreViewLogic".
 */
contract GetShareAccount_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getShareAccount_ReadsTheWordUnderItsOwnKey(
        address account,
        address secondAccount,
        ShareAccount memory shareAccount
    ) public {
        // Given: One account's claimable and pending aLP, and another account.
        vm.assume(account != secondAccount);
        almCore.setClaimableShares(account, shareAccount.claimableShares);
        almCore.setPendingShares(account, shareAccount.pendingShares);

        // When: Reading both accounts.
        ShareAccount memory read = coreViewLogic.getShareAccount(address(almCore), account);
        ShareAccount memory second = coreViewLogic.getShareAccount(address(almCore), secondAccount);

        // Then: Both halves read back under the account's key, the other's stays empty.
        assertEq(read.claimableShares, shareAccount.claimableShares);
        assertEq(read.pendingShares, shareAccount.pendingShares);
        assertEq(second.claimableShares, 0);
        assertEq(second.pendingShares, 0);
    }
}
