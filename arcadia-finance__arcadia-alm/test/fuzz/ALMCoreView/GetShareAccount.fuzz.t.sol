/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreView_Fuzz_Test } from "./_ALMCoreView.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { ShareAccount } from "../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getShareAccount" of contract "ALMCoreView".
 */
contract GetShareAccount_ALMCoreView_Fuzz_Test is ALMCoreView_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreView_Fuzz_Test) {
        ALMCoreView_Fuzz_Test.setUp();
        setSpotPoolState();
        deployCoreView();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getShareAccount_CoreNotValid(address notCore, address account) public {
        // Given: An address the factory does not hold as a core.
        vm.assume(notCore != address(almCore));

        // When: Reading it through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getShareAccount(notCore, account);
    }

    function testFuzz_Revert_getShareAccount_CoreNotValid_HalfCreated(address account) public {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        address core = BaseVault(halfCreatedVaults()[0]).share();

        // When: Reading its core address through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getShareAccount(core, account);
    }

    function testFuzz_Success_getShareAccount_IsTheAccountsShares(address account, ShareAccount memory shareAccount)
        public
    {
        // Given: An account's claimable and pending aLP, written through the accessors.
        almCore.setClaimableShares(account, shareAccount.claimableShares);
        almCore.setPendingShares(account, shareAccount.pendingShares);

        // When: Reading it through the lens.
        ShareAccount memory read = coreView.getShareAccount(address(almCore), account);

        // Then: Both halves read back.
        assertEq(read.claimableShares, shareAccount.claimableShares);
        assertEq(read.pendingShares, shareAccount.pendingShares);
    }
}
