/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreView_Fuzz_Test } from "./_ALMCoreView.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { RewardAccount } from "../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getRewardAccount" of contract "ALMCoreView".
 */
contract GetRewardAccount_ALMCoreView_Fuzz_Test is ALMCoreView_Fuzz_Test {
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

    function testFuzz_Revert_getRewardAccount_CoreNotValid(address notCore, address account) public {
        // Given: An address the factory does not hold as a core.
        vm.assume(notCore != address(almCore));

        // When: Reading it through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getRewardAccount(notCore, account);
    }

    function testFuzz_Revert_getRewardAccount_CoreNotValid_HalfCreated(address account) public {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        address core = BaseVault(halfCreatedVaults()[0]).share();

        // When: Reading its core address through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getRewardAccount(core, account);
    }

    function testFuzz_Success_getRewardAccount_IsTheHoldersRecord(address account, RewardAccount memory record) public {
        // Given: A holder's record, written through the accessor.
        almCore.setRewardSnapshot(account, record.rewardPerSharePaid);
        almCore.setPendingReward(account, record.rewardOwed);

        // When: Reading it through the lens.
        RewardAccount memory read = coreView.getRewardAccount(address(almCore), account);

        // Then: Every field reads back.
        assertEq(read.rewardPerSharePaid, record.rewardPerSharePaid);
        assertEq(read.rewardOwed, record.rewardOwed);
    }
}
