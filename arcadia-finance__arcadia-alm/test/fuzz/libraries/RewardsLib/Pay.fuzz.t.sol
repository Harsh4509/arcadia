/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ERC20 } from "@solady/tokens/ERC20.sol";
import { RewardsLib_Fuzz_Test } from "./_RewardsLib.fuzz.t.sol";
import { stdError } from "@forge-std/StdError.sol";

/**
 * @notice Fuzz tests for the function "pay" of library "RewardsLib".
 */
// forge-lint: disable-next-item(unused-return)
contract Pay_RewardsLib_Fuzz_Test is RewardsLib_Fuzz_Test {
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

    function testFuzz_Revert_pay_MoreThanMeasured(uint128 measured, uint128 amount) public {
        // Given: A measured reward balance short of the amount paid.
        deployRewardsLib();
        measured = uint128(bound(measured, 0, type(uint128).max - 1));
        amount = uint128(bound(amount, uint256(measured) + 1, type(uint128).max));
        rewardsLib.setRewards(0, 0, 0, measured, 0);

        // When: Paying the amount.
        // Then: It reverts on the underflow.
        vm.expectRevert(stdError.arithmeticError);
        rewardsLib.pay(accountA, amount);
    }

    function testFuzz_Success_pay_TransfersAndLowersTheMeasuredBalance(uint128 measured, uint128 amount) public {
        // Given: A measured reward balance the core holds, covering the amount paid.
        deployRewardsLib();
        amount = uint128(bound(amount, 0, measured));
        rewardsLib.setRewards(0, 0, 0, measured, 0);
        deal(almCore.REWARD_TOKEN_(), address(rewardsLib), measured);

        // When: Paying the amount.
        rewardsLib.pay(accountA, amount);

        // Then: The account received it and the measured balance fell by it.
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(accountA), amount);
        (,,, uint128 measuredAfter,) = rewardsLib.getRewards();
        assertEq(measuredAfter, measured - amount);
    }
}
