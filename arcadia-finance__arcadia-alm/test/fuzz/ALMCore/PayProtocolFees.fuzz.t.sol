/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { Vm } from "@forge-std/Vm.sol";

/**
 * @notice Fuzz tests for the function "payProtocolFees" of contract "ALMCore".
 */
// forge-lint: disable-next-item(divide-before-multiply, reentrancy-events, unsafe-typecast, unused-return)
contract PayProtocolFees_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_payProtocolFees_PaysEveryOwedBalanceWhoeverCalls(
        uint256 supply,
        address caller,
        uint96 owed0,
        uint96 owed1,
        uint96 owedReward
    ) public {
        // Given: The caller is neither the vault nor its fee recipient.
        vm.assume(caller != address(almCore) && caller != users.feeRecipient);

        // And: A supply from the dead shares up.
        supply = bound(supply, Constants.DEAD_SHARES, Constants.MAX_FUZZED_AMOUNT);
        almCore.mintShares(address(1), supply);

        // And: A protocol fee owed on all three tokens, covered by the balances.
        token0.mint(address(almCore), owed0);
        token1.mint(address(almCore), owed1);
        deal(almCore.REWARD_TOKEN_(), address(almCore), owedReward);
        almCore.setFeesOwed(owed0, owed1, owedReward);
        almCore.setRewardAccounting(0, 0, 0, owedReward);

        // When: Anyone calls payProtocolFees().
        vm.prank(caller);
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.ProtocolFeesPaid(owed0, owed1, owedReward);
        (uint256 amount0, uint256 amount1, uint256 amountReward) = almCore.payProtocolFees();

        // Then: The three owed balances are paid to the fee recipient.
        assertEq(amount0, owed0);
        assertEq(amount1, owed1);
        assertEq(amountReward, owedReward);
        assertEq(token0.balanceOf(users.feeRecipient), owed0);
        assertEq(token1.balanceOf(users.feeRecipient), owed1);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(users.feeRecipient), owedReward);

        // And: Nothing is owed any more.
        assertEq(almCore.getProtocolFees0(), 0);
        assertEq(almCore.getProtocolFees1(), 0);
        assertEq(almCore.getProtocolFeesReward(), 0);
    }

    function testFuzz_Success_payProtocolFees_PaysTheCoresOwnAccrual(uint256 supply, uint96 coreShares, uint96 received)
        public
    {
        // Given: No emission fee.
        uint16 swapFeeBps = almCore.protocolSwapFeeBps_();
        vm.prank(factory);
        almCore.setProtocolFees(0, swapFeeBps, users.feeRecipient);

        // And: The core holding aLP next to a supply the reward per share fits.
        coreShares = uint96(bound(coreShares, 1, type(uint96).max));
        received = uint96(bound(received, 1, type(uint96).max));
        supply = bound(
            supply,
            FixedPointMathLib.max(uint256(received).fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES),
            Constants.MAX_FUZZED_AMOUNT
        );
        almCore.mintShares(deadAddress, supply);
        almCore.mintShares(address(almCore), coreShares);

        // And: Reward token that arrived after the core's balance last moved.
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);

        uint256 delta = uint256(received).fullMulDiv(1e18, supply + coreShares);
        uint256 expected = uint256(coreShares).fullMulDiv(delta, 1e18);
        uint256 rewardPerShare = almCore.rewardPerShare_();
        uint256 claimedCumulative = almCore.getClaimedCumulative();
        uint256 highWater = almCore.getRewardHighWater();

        // When: Calling payProtocolFees().
        (,, uint256 amountReward) = almCore.payProtocolFees();

        // Then: The core's own accrual is paid to the fee recipient.
        assertEq(amountReward, expected);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(users.feeRecipient), expected);

        // And: The reward received is claimed, the core snapshotted at the new rate.
        assertEq(almCore.getClaimedCumulative(), claimedCumulative + received);
        assertEq(almCore.getRewardHighWater(), highWater + received);
        assertEq(almCore.getProtocolRewardSnapshot(), rewardPerShare + delta);
    }

    function testFuzz_Success_payProtocolFees_LeavesTheAccountedBalancesCovered(
        uint256 supply,
        uint96 owed0,
        uint96 owed1,
        uint96 owedReward,
        uint256 buffer0,
        uint256 buffer1
    ) public {
        // Given: A supply from the dead shares up.
        supply = bound(supply, Constants.DEAD_SHARES, Constants.MAX_FUZZED_AMOUNT);
        almCore.mintShares(address(1), supply);

        // And: A protocol fee owed next to a buffer, all covered by the balances.
        token0.mint(address(almCore), owed0);
        token1.mint(address(almCore), owed1);
        deal(almCore.REWARD_TOKEN_(), address(almCore), owedReward);
        almCore.setFeesOwed(owed0, owed1, owedReward);
        almCore.setRewardAccounting(0, 0, 0, owedReward);
        fundBuffer(bound(buffer0, 0, Constants.MAX_FUZZED_AMOUNT), bound(buffer1, 0, Constants.MAX_FUZZED_AMOUNT));

        // When: Calling payProtocolFees().
        almCore.payProtocolFees();

        // Then: The raw balances are the buffers, nothing owed left.
        assertEq(almCore.getProtocolFees0(), 0);
        assertEq(almCore.getProtocolFees1(), 0);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1());
    }

    function testFuzz_Success_payProtocolFees_LeavesTheAccumulatorUnchanged(
        uint256 supply,
        uint16 feeBps,
        uint96 shares,
        uint96 received
    ) public {
        // Given: A non-zero emission fee within the ceiling.
        feeBps = uint16(bound(feeBps, 1, almCore.MAX_FEE_BPS_()));
        uint16 swapFeeBps = almCore.protocolSwapFeeBps_();
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, swapFeeBps, users.feeRecipient);

        // And: A holder next to a supply the reward per share of the reward fits.
        shares = uint96(bound(shares, 1, type(uint96).max));
        received = uint96(bound(received, 1, type(uint96).max));
        supply = bound(
            supply,
            FixedPointMathLib.max(uint256(received).fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES),
            Constants.MAX_FUZZED_AMOUNT
        );
        almCore.mintShares(address(1), supply);
        almCore.mintShares(accountA, shares);

        // And: Reward token arrived and checkpointed.
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);
        almCore.checkpoint_();

        uint256 accumulatorBefore = almCore.rewardPerShare_();
        uint256 entitlementBefore = almCore.getPendingReward(accountA)
            + uint256(shares).fullMulDiv(almCore.rewardPerShare_() - almCore.getRewardSnapshot(accountA), 1e18);

        // When: Calling payProtocolFees() and checkpointing after it.
        almCore.payProtocolFees();
        almCore.checkpoint_();

        // Then: The payout was not read back as a reward.
        assertEq(almCore.rewardPerShare_(), accumulatorBefore);
        assertEq(
            almCore.getPendingReward(accountA)
                + uint256(shares).fullMulDiv(almCore.rewardPerShare_() - almCore.getRewardSnapshot(accountA), 1e18),
            entitlementBefore
        );
        assertEq(almCore.getLastRewardBalance(), ERC20(almCore.REWARD_TOKEN_()).balanceOf(address(almCore)));
    }

    function testFuzz_Success_payProtocolFees_LeavesEveryHolderStillPayable(
        uint256 supply,
        uint16 feeBps,
        uint96 shares,
        uint96 received
    ) public {
        // Given: A non-zero emission fee within the ceiling.
        feeBps = uint16(bound(feeBps, 1, almCore.MAX_FEE_BPS_()));
        uint16 swapFeeBps = almCore.protocolSwapFeeBps_();
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, swapFeeBps, users.feeRecipient);

        // And: A holder next to a supply the reward per share of the reward fits.
        shares = uint96(bound(shares, 1, type(uint96).max));
        received = uint96(bound(received, 1, type(uint96).max));
        supply = bound(
            supply,
            FixedPointMathLib.max(uint256(received).fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES),
            Constants.MAX_FUZZED_AMOUNT
        );
        almCore.mintShares(address(1), supply);
        almCore.mintShares(accountA, shares);

        // And: Reward token arrived and checkpointed.
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);
        almCore.checkpoint_();

        uint256 entitlementBefore = almCore.getPendingReward(accountA)
            + uint256(shares).fullMulDiv(almCore.rewardPerShare_() - almCore.getRewardSnapshot(accountA), 1e18);

        // When: Claiming the protocol fees and then the holder's reward.
        (,, uint256 amountReward) = almCore.payProtocolFees();
        uint256 paid = almCore.claimEmissions(accountA);

        // Then: The holder is paid in full.
        assertEq(paid, entitlementBefore);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(accountA), entitlementBefore);

        // And: The protocol is paid its fee on what arrived.
        assertEq(amountReward, uint256(received).fullMulDiv(feeBps, ConfigLib.BPS_DENOMINATOR));
    }

    function testFuzz_Success_payProtocolFees_NothingOwed(uint96 shares) public {
        // Given: A holder with no fee accrued behind it.
        almCore.mintShares(accountA, bound(shares, 1, Constants.MAX_FUZZED_AMOUNT));

        // When: Calling payProtocolFees().
        (uint256 amount0, uint256 amount1, uint256 amountReward) = almCore.payProtocolFees();

        // Then: Nothing is paid.
        assertEq(amount0, 0);
        assertEq(amount1, 0);
        assertEq(amountReward, 0);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(users.feeRecipient), 0);
    }

    function testFuzz_Success_payProtocolFees_MovesNoTokenWithNothingOwed(uint96 owed, bool isToken0) public {
        // Given: A protocol fee owed on one pool token only, covered by the balance.
        owed = uint96(bound(owed, 1, type(uint96).max));
        (isToken0 ? token0 : token1).mint(address(almCore), owed);
        almCore.setFeesOwed(isToken0 ? owed : 0, isToken0 ? 0 : owed, 0);

        // When: Anyone calls payProtocolFees().
        vm.recordLogs();
        almCore.payProtocolFees();

        // Then: The token with nothing owed emitted nothing, not even an empty transfer.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].emitter != address(isToken0 ? token1 : token0));
        }
    }

    function testFuzz_Success_payProtocolFees_CountsTheGaugeEarnedOnAnyChainStatus(
        uint256 supply,
        uint96 coreShares,
        uint96 received,
        uint96 earned,
        uint256 status
    ) public {
        // Given: No emission fee.
        uint16 swapFeeBps = almCore.protocolSwapFeeBps_();
        vm.prank(factory);
        almCore.setProtocolFees(0, swapFeeBps, users.feeRecipient);

        // And: The core holding aLP next to a supply the reward per share fits.
        coreShares = uint96(bound(coreShares, 1, type(uint96).max));
        received = uint96(bound(received, 1, type(uint96).max));
        uint256 counted = uint256(received) + earned;
        supply = bound(
            supply,
            FixedPointMathLib.max(counted.fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES),
            Constants.MAX_FUZZED_AMOUNT
        );
        almCore.mintShares(deadAddress, supply);
        almCore.mintShares(address(almCore), coreShares);

        // And: Reward token arrived, gauge emissions, on any chain status.
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);
        mockEarned(gauge, address(almCore), earned);
        setAnyStatus(status);
        uint256 delta = counted.fullMulDiv(1e18, supply + coreShares);
        uint256 accrual = uint256(coreShares).fullMulDiv(delta, 1e18);
        uint256 expected = FixedPointMathLib.min(accrual, received);
        uint256 rewardPerShare = almCore.rewardPerShare_();
        uint256 highWater = almCore.getRewardHighWater();

        // When: Calling payProtocolFees().
        (,, uint256 amountReward) = almCore.payProtocolFees();

        // Then: The gauge earned is spread over the supply on any chain status.
        assertEq(almCore.rewardPerShare_(), rewardPerShare + delta);
        assertEq(almCore.getRewardHighWater(), highWater + counted);
        assertEq(almCore.getProtocolRewardSnapshot(), rewardPerShare + delta);

        // And: The core's accrual is paid up to the reward received, the rest stays owed.
        assertEq(amountReward, expected);
        assertEq(almCore.getProtocolFeesReward(), accrual - expected);
        assertEq(almCore.getLastRewardBalance(), uint256(received) - expected);
    }
}
