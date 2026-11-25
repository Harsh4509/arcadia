/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { RewardAccount } from "../../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getRewardAccount" of library "ALMCoreViewLogic".
 */
contract GetRewardAccount_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
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

    function testFuzz_Success_getRewardAccount_ReadsTheWordUnderItsOwnKey(
        address account,
        address secondAccount,
        RewardAccount memory record
    ) public {
        // Given: One holder's record written through the accessor, and another holder.
        vm.assume(account != secondAccount);
        almCore.setRewardSnapshot(account, record.rewardPerSharePaid);
        almCore.setPendingReward(account, record.rewardOwed);

        // When: Reading both holders' records.
        RewardAccount memory read = coreViewLogic.getRewardAccount(address(almCore), account);
        RewardAccount memory second = coreViewLogic.getRewardAccount(address(almCore), secondAccount);

        // Then: Every field reads back under the holder's key, the other's stays empty.
        assertEq(read.rewardPerSharePaid, record.rewardPerSharePaid);
        assertEq(read.rewardOwed, record.rewardOwed);
        assertEq(second.rewardPerSharePaid, 0);
        assertEq(second.rewardOwed, 0);
    }
}
