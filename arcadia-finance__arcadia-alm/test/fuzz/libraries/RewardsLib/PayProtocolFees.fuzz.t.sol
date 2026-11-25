/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { IERC20 } from "@forge-std/interfaces/IERC20.sol";
import { RewardsLib_Fuzz_Test } from "./_RewardsLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "payProtocolFees" of library "RewardsLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract PayProtocolFees_RewardsLib_Fuzz_Test is RewardsLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(RewardsLib_Fuzz_Test) {
        RewardsLib_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_payProtocolFees_PaysEverythingOwedWhenMeasured(
        uint128 claimed,
        uint128 measured,
        uint128 owed,
        uint256 supply,
        uint256 balance,
        address recipient
    ) public {
        // Given: A core with no new reward since its last checkpoint, at lifetime reward.
        deployRewardsLib();
        owed = uint128(bound(owed, 0, measured));
        rewardsLib.setRewards(0, claimed, claimed, measured, owed);
        deal(almCore.REWARD_TOKEN_(), address(rewardsLib), measured);

        // And: A recipient other than the core.
        vm.assume(recipient != address(rewardsLib) && recipient != address(0));
        uint256 recipientBefore = IERC20(almCore.REWARD_TOKEN_()).balanceOf(recipient);

        // When: Claiming the protocol fee.
        uint256 paid = rewardsLib.payProtocolFees(supply, recipient, balance);

        // Then: Everything owed is paid, the measured balance covering it.
        assertEq(paid, owed);
        (,,, uint128 measuredAfter, uint128 owedAfter) = rewardsLib.getRewards();
        assertEq(owedAfter, 0);
        assertEq(measuredAfter, measured - owed);
        assertEq(IERC20(almCore.REWARD_TOKEN_()).balanceOf(recipient), recipientBefore + owed);
    }

    function testFuzz_Success_payProtocolFees_StopsAtTheMeasuredBalance(
        uint128 claimed,
        uint128 measured,
        uint128 owed,
        uint256 supply,
        uint256 balance,
        address recipient
    ) public {
        // Given: No new reward since the checkpoint, owing more than measured.
        deployRewardsLib();
        measured = uint128(bound(measured, 0, type(uint128).max - 1));
        owed = uint128(bound(owed, uint256(measured) + 1, type(uint128).max));
        rewardsLib.setRewards(0, claimed, claimed, measured, owed);
        deal(almCore.REWARD_TOKEN_(), address(rewardsLib), measured);

        // And: A recipient other than the core.
        vm.assume(recipient != address(rewardsLib) && recipient != address(0));

        // When: Claiming the protocol fee.
        uint256 paid = rewardsLib.payProtocolFees(supply, recipient, balance);

        // Then: The measured balance is paid and the rest stays owed.
        assertEq(paid, measured);
        (,,, uint128 measuredAfter, uint128 owedAfter) = rewardsLib.getRewards();
        assertEq(owedAfter, owed - measured);
        assertEq(measuredAfter, 0);
    }

    function testFuzz_Success_payProtocolFees_AccruesTheCoresSharesFirst(
        uint128 claimed,
        uint128 accumulator,
        uint96 own,
        uint96 escrowed,
        uint256 supply,
        address recipient
    ) public {
        // Given: A core holding its own aLP beside escrowed aLP, its snapshot behind.
        deployRewardsLib();
        uint256 room = uint256(type(uint128).max) * 1e18 / (uint256(own) + escrowed + 1);
        accumulator = uint128(bound(accumulator, 1, room < type(uint128).max ? room : type(uint128).max));

        // And: No new reward since its last checkpoint, and a balance covering any fee.
        rewardsLib.setRewards(accumulator, claimed, claimed, type(uint128).max, 0);
        deal(almCore.REWARD_TOKEN_(), address(rewardsLib), type(uint128).max);

        // And: A recipient other than the core.
        vm.assume(recipient != address(rewardsLib) && recipient != address(0));

        // When: Claiming the protocol fee.
        uint256 paid = rewardsLib.payProtocolFees(supply, recipient, uint256(own) + escrowed);

        // Then: The protocol is credited on every aLP the core holds, and paid all of it.
        assertEq(paid, (uint256(own) + escrowed) * accumulator / 1e18);
        assertEq(rewardsLib.getProtocolRewardPerSharePaid(), accumulator);
    }

    function testFuzz_Success_payProtocolFees_NothingOwedTransfersNothing(
        uint128 claimed,
        uint128 measured,
        uint256 supply,
        uint256 balance,
        address recipient
    ) public {
        // Given: No new reward since the last checkpoint, and no protocol fee owed.
        deployRewardsLib();
        rewardsLib.setRewards(0, claimed, claimed, measured, 0);
        deal(almCore.REWARD_TOKEN_(), address(rewardsLib), measured);
        vm.assume(recipient != address(rewardsLib) && recipient != address(0));

        // When: Claiming the protocol fee.
        // Then: No reward token is transferred.
        vm.expectCall(almCore.REWARD_TOKEN_(), abi.encodeWithSelector(IERC20.transfer.selector), 0);
        uint256 paid = rewardsLib.payProtocolFees(supply, recipient, balance);

        // And: Nothing is paid, and the measured balance holds.
        assertEq(paid, 0);
        (,,, uint128 measuredAfter,) = rewardsLib.getRewards();
        assertEq(measuredAfter, measured);
    }
}
