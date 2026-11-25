/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { RewardsLib_Fuzz_Test } from "./_RewardsLib.fuzz.t.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";

/**
 * @notice Fuzz tests for the function "accrueBalanceReward" of library "RewardsLib".
 */
// forge-lint: disable-next-item(unsafe-typecast, divide-before-multiply)
contract AccrueBalanceReward_RewardsLib_Fuzz_Test is RewardsLib_Fuzz_Test {
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

    function testFuzz_Revert_accrueBalanceReward_Overflow(uint128 shares, uint128 rewardPerShare) public {
        // Given: A holder whose accumulator growth past its snapshot overflows a uint128.
        rewardPerShare = uint128(bound(rewardPerShare, 1e18 + 1, type(uint128).max));
        shares = uint128(
            bound(
                shares,
                FixedPointMathLib.fullMulDivUp(uint256(type(uint128).max) + 1, 1e18, rewardPerShare),
                type(uint128).max
            )
        );
        almCore.mintShares(accountA, shares);
        almCore.setRewardAccounting(rewardPerShare, 0, 0, 0);

        // When: Crediting the holder.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        almCore.accrueBalanceReward(accountA);
    }

    function testFuzz_Success_accrueBalanceReward_CreditsBalanceShare(
        uint16 feeBps,
        uint96 shares,
        uint96 received,
        uint256 seedShares,
        address holder
    ) public {
        // Given: An emission fee within the ceiling.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);

        // And: Any holder but the core and the seed's, next to the supply seed.
        vm.assume(holder != address(almCore) && holder != address(1) && holder != address(0));
        shares = uint96(bound(shares, 1, type(uint96).max));
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(
                FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max), Constants.DEAD_SHARES
            ) + 1,
            type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(holder, shares);

        // And: Reward token arrived.
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);

        // And: The reward is checkpointed.
        almCore.checkpoint_();
        uint256 protocolFeesBefore = almCore.getProtocolFeesReward();

        // When: Crediting the holder.
        almCore.accrueBalanceReward(holder);

        // Then: It gets its share of the net reward, and its snapshot is the accumulator.
        uint256 accumulator = (received - uint256(received) * feeBps / 10_000) * 1e18 / (seedShares + shares);
        assertEq(almCore.rewardPerShare_(), accumulator);
        assertEq(almCore.getPendingReward(holder), uint256(shares) * accumulator / 1e18);
        assertEq(almCore.getRewardSnapshot(holder), accumulator);

        // And: None of it went to the protocol.
        assertEq(almCore.getProtocolFeesReward(), protocolFeesBefore);
    }

    function testFuzz_Success_accrueBalanceReward_AddsToTheOwedReward(
        uint96 shares,
        uint96 receivedFirst,
        uint96 receivedSecond,
        uint256 seedShares,
        address holder
    ) public {
        // Given: Any holder but the core and the seed's, next to the supply seed.
        vm.assume(holder != address(almCore) && holder != address(1) && holder != address(0));
        shares = uint96(bound(shares, 1, type(uint96).max));
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(
                FixedPointMathLib.fullMulDivUp(2 * uint256(type(uint96).max), 1e18, type(uint128).max),
                Constants.DEAD_SHARES
            ) + 1,
            type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(holder, shares);

        // And: A first reward, checkpointed and credited to the holder.
        deal(almCore.REWARD_TOKEN_(), address(almCore), receivedFirst);
        almCore.checkpoint_();
        almCore.accrueBalanceReward(holder);

        // And: A second reward, checkpointed.
        deal(almCore.REWARD_TOKEN_(), address(almCore), uint256(receivedFirst) + receivedSecond);
        almCore.checkpoint_();

        // When: Crediting the holder again.
        almCore.accrueBalanceReward(holder);

        // Then: Its share of the second reward is added to the share of the first.
        uint256 supply = seedShares + shares;
        uint256 accumulatorFirst = uint256(receivedFirst) * 1e18 / supply;
        uint256 accumulator = accumulatorFirst + uint256(receivedSecond) * 1e18 / supply;
        assertEq(almCore.rewardPerShare_(), accumulator);
        assertEq(
            almCore.getPendingReward(holder),
            uint256(shares) * accumulatorFirst / 1e18 + uint256(shares) * (accumulator - accumulatorFirst) / 1e18
        );
    }

    function testFuzz_Success_accrueBalanceReward_ZeroBalance(uint96 shares, uint96 earned, uint256 seedShares) public {
        // Given: A supply held entirely by another account.
        uint256 sharesB = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(
                FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max), Constants.DEAD_SHARES
            ) + 1,
            type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(accountB, sharesB);

        // And: An accrual, and the accumulator it sets.
        earned = uint96(bound(earned, 1, type(uint96).max));
        mockEarned(gauge, address(almCore), earned);
        uint256 net = uint256(earned) - uint256(earned) * almCore.protocolEmissionFeeBps_() / 10_000;
        uint256 accumulator = net * 1e18 / (seedShares + sharesB);

        // And: The accrual is checkpointed.
        almCore.checkpoint_();

        // When: Crediting an account that holds nothing.
        almCore.accrueBalanceReward(accountA);

        // Then: It is credited nothing, but its snapshot advances.
        assertEq(almCore.getPendingReward(accountA), 0);
        assertEq(almCore.getRewardSnapshot(accountA), accumulator);
    }

    function testFuzz_Success_accrueBalanceReward_Idempotent(uint96 shares, uint96 earned, uint256 seedShares) public {
        // Given: A holder and an accrual.
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(
                FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max), Constants.DEAD_SHARES
            ) + 1,
            type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(accountA, bound(shares, 1, Constants.MAX_FUZZED_AMOUNT));
        mockEarned(gauge, address(almCore), bound(earned, 1, Constants.MAX_FUZZED_AMOUNT));
        almCore.checkpoint_();
        almCore.accrueBalanceReward(accountA);
        uint256 creditedOnce = almCore.getPendingReward(accountA);

        // When: Crediting again without a further accrual.
        almCore.accrueBalanceReward(accountA);

        // Then: Nothing is added.
        assertEq(almCore.getPendingReward(accountA), creditedOnce);
    }

    function testFuzz_Success_accrueBalanceReward_SecondHolderUnaffected(
        uint96 sharesA,
        uint96 sharesB,
        uint96 earned,
        uint256 seedShares
    ) public {
        // Given: Two holders and an accrual.
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(
                FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max), Constants.DEAD_SHARES
            ) + 1,
            type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(accountA, bound(sharesA, 1, Constants.MAX_FUZZED_AMOUNT));
        almCore.mintShares(accountB, bound(sharesB, 1, Constants.MAX_FUZZED_AMOUNT));
        mockEarned(gauge, address(almCore), bound(earned, 1, Constants.MAX_FUZZED_AMOUNT));

        // And: The accrual is checkpointed.
        almCore.checkpoint_();
        uint256 rewardPerShare = almCore.rewardPerShare_();
        uint256 snapshotB = almCore.getRewardSnapshot(accountB);

        // When: Crediting the first holder.
        almCore.accrueBalanceReward(accountA);

        // Then: The second holder's reward account and the accumulator are unchanged.
        assertEq(almCore.getRewardSnapshot(accountB), snapshotB);
        assertEq(almCore.getPendingReward(accountB), 0);
        assertEq(almCore.rewardPerShare_(), rewardPerShare);
    }

    function testFuzz_Success_accrueBalanceReward_SkipsTheSharesHeldForIt(
        uint96 escrowed,
        uint96 received,
        uint256 seedShares
    ) public {
        // Given: aLP the core holds for a controller that holds none itself.
        escrowed = uint96(bound(escrowed, 1, type(uint96).max));
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(
                FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max), Constants.DEAD_SHARES
            ) + 1,
            type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(address(almCore), escrowed);
        almCore.setClaimableShares(accountA, escrowed);

        // And: Reward token arrived and is checkpointed.
        received = uint96(bound(received, 1, type(uint96).max));
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);
        almCore.checkpoint_();

        // When: Crediting the controller.
        almCore.accrueBalanceReward(accountA);

        // Then: It is credited nothing for the aLP held for it.
        assertEq(almCore.getPendingReward(accountA), 0);
    }

    function testFuzz_Success_accrueBalanceReward_CoreCountsEveryShareItHolds(
        uint96 escrowed,
        uint96 own,
        uint96 received,
        uint256 seedShares,
        uint16 feeBps
    ) public {
        // Given: An emission fee within the ceiling.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);

        // And: aLP the core holds for a controller, next to aLP it holds for no one.
        escrowed = uint96(bound(escrowed, 1, type(uint96).max));
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(
                FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max), Constants.DEAD_SHARES
            ) + 1,
            type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(address(almCore), uint256(escrowed) + own);
        almCore.setClaimableShares(accountA, escrowed);

        // And: Reward token arrived and is checkpointed, setting the fee and accumulator.
        received = uint96(bound(received, 1, type(uint96).max));
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);
        uint256 feeBefore = almCore.getProtocolFeesReward();
        almCore.checkpoint_();
        uint256 protocolFee = uint256(received) * almCore.protocolEmissionFeeBps_() / 10_000;
        uint256 accumulator = (received - protocolFee) * 1e18 / (seedShares + uint256(escrowed) + own);

        // When: Crediting the core.
        almCore.accrueBalanceReward(address(almCore));

        // Then: The protocol is credited for the controller's aLP and the core's own.
        assertEq(
            almCore.getProtocolFeesReward() - feeBefore - protocolFee, (uint256(escrowed) + own) * accumulator / 1e18
        );
    }
}
