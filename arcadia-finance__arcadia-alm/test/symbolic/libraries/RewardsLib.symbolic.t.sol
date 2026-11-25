/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { RewardAccount } from "../../../src/core/types/State.sol";
import { RewardsLibExtension } from "../../utils/extensions/RewardsLibExtension.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { stdError } from "@forge-std/StdError.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";

/**
 * @notice Symbolic tests for the library "RewardsLib".
 */
contract RewardsLib_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    RewardsLibExtension internal rewardsLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public {
        rewardsLib = new RewardsLibExtension(address(0), address(0), address(0), address(0));
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_accrueBalanceReward_CreditsTheFlooredRewardSinceTheLastCredit(
        address account,
        uint128 shares,
        uint128 rewardPerShare,
        uint128 rewardPerSharePaid,
        uint128 rewardOwed
    ) public {
        // Given: Non-core holder credited up to the accumulator, credit in uint128.
        vm.assume(account != address(rewardsLib) && rewardPerSharePaid <= rewardPerShare);
        uint256 credit = uint256(shares) * (rewardPerShare - rewardPerSharePaid) / 1e18;
        vm.assume(credit <= type(uint128).max - rewardOwed);
        rewardsLib.setRewards(rewardPerShare, 0, 0, 0, 0);
        rewardsLib.setRewardAccount(account, RewardAccount(rewardPerSharePaid, rewardOwed));

        // When: Crediting the holder's balance.
        rewardsLib.accrueBalanceReward(account, shares);

        // Then: Owed reward rises by the balance's floored share of the rise, paid to it.
        RewardAccount memory rewardAccount = rewardsLib.getRewardAccount(account);
        assertEq(rewardAccount.rewardOwed, rewardOwed + credit);
        assertEq(rewardAccount.rewardPerSharePaid, rewardPerShare);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_accrueBalanceReward_SucceedsIffTheCreditFitsUint128(
        address account,
        uint128 shares,
        uint128 rewardPerShare,
        uint128 rewardPerSharePaid,
        uint128 rewardOwed
    ) public {
        // Given: A holder other than the core, last credited below the accumulator.
        vm.assume(account != address(rewardsLib) && rewardPerSharePaid < rewardPerShare);
        uint256 credit = uint256(shares) * (rewardPerShare - rewardPerSharePaid) / 1e18;
        rewardsLib.setRewards(rewardPerShare, 0, 0, 0, 0);
        rewardsLib.setRewardAccount(account, RewardAccount(rewardPerSharePaid, rewardOwed));

        // When: Crediting the holder's balance.
        (bool success, bytes memory result) =
            address(rewardsLib).call(abi.encodeCall(RewardsLibExtension.accrueBalanceReward, (account, shares)));

        // Then: Succeeds exactly when owed fits uint128, else the cast or sum overflows.
        assertEq(success, credit <= type(uint128).max - rewardOwed);
        if (!success) {
            assertEq(
                result,
                credit > type(uint128).max
                    ? abi.encodeWithSelector(SafeCastLib.Overflow.selector)
                    : stdError.arithmeticError
            );
        }
    }

    function prove_accrueBalanceReward_AtTheSameAccumulatorChangesNothing(
        address account,
        uint256 shares,
        uint128 rewardPerShare,
        uint128 rewardOwed
    ) public {
        // Given: A holder other than the core, credited at the accumulator.
        vm.assume(account != address(rewardsLib));
        rewardsLib.setRewards(rewardPerShare, 0, 0, 0, 0);
        rewardsLib.setRewardAccount(account, RewardAccount(rewardPerShare, rewardOwed));

        // When: Crediting the holder's balance again.
        rewardsLib.accrueBalanceReward(account, shares);

        // Then: Nothing changes.
        RewardAccount memory rewardAccount = rewardsLib.getRewardAccount(account);
        assertEq(rewardAccount.rewardOwed, rewardOwed);
        assertEq(rewardAccount.rewardPerSharePaid, rewardPerShare);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_accrueBalanceReward_ForTheCoreCreditsTheProtocolFees(
        uint128 shares,
        uint128 rewardPerShare,
        uint128 rewardPerSharePaid,
        uint128 protocolFees
    ) public {
        // Given: The core's balance credited up to the accumulator, credit in uint128.
        vm.assume(rewardPerSharePaid <= rewardPerShare);
        uint256 credit = uint256(shares) * (rewardPerShare - rewardPerSharePaid) / 1e18;
        vm.assume(credit <= type(uint128).max - protocolFees);
        rewardsLib.setRewards(rewardPerShare, 0, 0, 0, protocolFees);
        rewardsLib.setProtocolRewardPerSharePaid(rewardPerSharePaid);

        // When: Crediting the core's balance.
        rewardsLib.accrueBalanceReward(address(rewardsLib), shares);

        // Then: Protocol fees rise by its floored share of the rise, paid up to it.
        assertEq(rewardsLib.getProtocolFeesReward(), protocolFees + credit);
        assertEq(rewardsLib.getProtocolRewardPerSharePaid(), rewardPerShare);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getRewardPerShare_WithoutAWindowSpreadsTheExcessOverTheSupply(
        uint128 rewardPerShare,
        uint128 highWater,
        uint128 preCredited,
        uint256 supply,
        uint128 total
    ) public {
        // Given: No penalty window, high water accumulator, uint128 total, step < 2^128.
        uint256 step = total > highWater && supply > 0 ? uint256(total - highWater) * 1e18 / supply : 0;
        vm.assume(step < 1 << 128);
        rewardsLib.setRewards(rewardPerShare, highWater, 0, 0, 0);
        rewardsLib.setPreCredited(preCredited);
        rewardsLib.setWindowEnd(0);
        uint256 expected = (uint256(rewardPerShare) + step) % (1 << 128);

        // When: Taking the reward per share.
        (uint128 rewardPerShare_, uint256 highWater_, uint256 preCredited_, uint48 windowEnd) =
            rewardsLib.getRewardPerShare(supply, total);

        // Then: Rises by the per-share excess over high water mod 2^128, which follows.
        assertEq(rewardPerShare_, expected);
        assertEq(highWater_, total > highWater ? total : highWater);
        assertEq(preCredited_, preCredited);
        assertEq(windowEnd, 0);
    }
}
