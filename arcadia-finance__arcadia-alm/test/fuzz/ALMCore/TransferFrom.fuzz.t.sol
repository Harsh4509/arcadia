/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { BaseCore } from "../../../src/core/abstracts/base/BaseCore.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { ShareLib } from "../../../src/core/libraries/state/ShareLib.sol";

/**
 * @notice Fuzz tests for the function "transferFrom" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unsafe-typecast, arbitrary-send-erc20, erc20-unchecked-transfer, unused-return)
contract TransferFrom_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_transferFrom_InsufficientAllowance(uint96 sharesA, uint96 amount, uint96 allowance)
        public
    {
        // Given: A holder and a spender approved for less than it moves.
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        almCore.mintShares(accountA, sharesA);
        amount = uint96(bound(amount, 1, sharesA));
        allowance = uint96(bound(allowance, 0, amount - 1));
        vm.prank(accountA);
        almCore.approve(accountC, allowance);

        // When: The spender calls transferFrom().
        // Then: It reverts.
        vm.prank(accountC);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        almCore.transferFrom(accountA, accountB, amount);
    }

    function testFuzz_Revert_transferFrom_InsufficientAllowance_EscrowedRedeem(
        uint96 shares,
        address caller,
        uint96 amount
    ) public {
        // Given: A pending redeem the core escrows.
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();
        shares = uint96(bound(shares, 1, type(uint96).max));
        recordRedeemAt(asyncVault0, controller, shares);

        // And: A caller but the core or the zero address, and part of the escrowed aLP.
        vm.assume(caller != address(almCore) && caller != address(0));
        amount = uint96(bound(amount, 1, shares));

        // When: The caller moves the escrowed aLP out of the core.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        almCore.transferFrom(address(almCore), caller, amount);
    }

    function testFuzz_Revert_transferFrom_InvalidRecipient(uint96 sharesA, uint96 amount) public {
        // Given: A holder and a spender approved for at most the shares the holder holds.
        almCore.mintShares(accountA, sharesA);
        amount = uint96(bound(amount, 0, sharesA));
        vm.prank(accountA);
        almCore.approve(accountC, amount);

        // When: The spender transfers to the zero address.
        // Then: It reverts.
        vm.prank(accountC);
        vm.expectRevert(BaseCore.InvalidRecipient.selector);
        almCore.transferFrom(accountA, address(0), amount);
    }

    function testFuzz_Revert_transferFrom_InsufficientBalance(uint96 sharesA, uint96 amount) public {
        // Given: A holder and a spender approved for more shares than the holder holds.
        sharesA = uint96(bound(sharesA, 0, type(uint96).max - 1));
        almCore.mintShares(accountA, sharesA);
        amount = uint96(bound(amount, uint256(sharesA) + 1, type(uint96).max));
        vm.prank(accountA);
        almCore.approve(accountC, amount);

        // When: The spender calls transferFrom().
        // Then: It reverts.
        vm.prank(accountC);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        almCore.transferFrom(accountA, accountB, amount);
    }

    function testFuzz_Revert_transferFrom_PerUserCapExceeded(uint96 sharesA, uint96 amount, address receiver) public {
        // Given: A holder, an approved spender, a per user cap a share short of the move.
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        almCore.mintShares(accountA, sharesA);
        amount = uint96(bound(amount, 1, sharesA));
        vm.prank(accountA);
        almCore.approve(accountC, amount);
        vm.prank(factory);
        almCore.setPerUserCap(amount - 1);
        vm.assume(receiver != accountA && receiver != address(almCore) && receiver != address(0));

        // When: The spender moves the shares to any other account.
        // Then: It reverts on the receiver's cap balance.
        vm.prank(accountC);
        vm.expectRevert(ShareLib.PerUserCapExceeded.selector);
        almCore.transferFrom(accountA, receiver, amount);
    }

    function testFuzz_Success_transferFrom_CreditsBothSidesBeforeTheBalanceMoves(
        uint96 sharesA,
        uint96 sharesB,
        uint96 amount,
        uint96 earned,
        uint256 seedShares
    ) public {
        // Given: No per user cap and no total cap.
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();

        // And: Two holders next to a supply the reward per share of the accrual fits.
        uint256 accrued = bound(earned, 1, Constants.MAX_FUZZED_AMOUNT);
        uint256 net = accrued - accrued * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_();
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        sharesB = uint96(bound(sharesB, 1, type(uint96).max));
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(net.fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES),
            type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(accountA, sharesA);
        almCore.mintShares(accountB, sharesB);

        // And: The spender is approved.
        amount = uint96(bound(amount, 0, sharesA));
        vm.prank(accountA);
        almCore.approve(accountC, amount);

        // And: An accrual neither holder has been credited with yet.
        mockEarned(gauge, address(almCore), accrued);
        uint256 rewardPerShare = almCore.rewardPerShare_() + net.fullMulDiv(1e18, almCore.totalSupply());
        uint256 owedA = almCore.getPendingReward(accountA)
            + uint256(sharesA).fullMulDiv(rewardPerShare - almCore.getRewardSnapshot(accountA), 1e18);
        uint256 owedB = almCore.getPendingReward(accountB)
            + uint256(sharesB).fullMulDiv(rewardPerShare - almCore.getRewardSnapshot(accountB), 1e18);

        // When: The spender moves the shares.
        vm.prank(accountC);
        almCore.transferFrom(accountA, accountB, amount);

        // Then: Both were credited against the balances they held before the move.
        assertEq(almCore.getPendingReward(accountA), owedA);
        assertEq(almCore.getPendingReward(accountB), owedB);
        assertEq(almCore.balanceOf(accountA), sharesA - amount);
        assertEq(almCore.balanceOf(accountB), uint256(sharesB) + amount);

        // And: Both snapshots are at the raised accumulator, the allowance is spent.
        assertEq(almCore.getRewardSnapshot(accountA), rewardPerShare);
        assertEq(almCore.getRewardSnapshot(accountB), rewardPerShare);
        assertEq(almCore.allowance(accountA, accountC), 0);
    }

    function testFuzz_Success_transferFrom_SpenderNotCredited(
        uint96 sharesA,
        uint96 amount,
        uint96 earned,
        uint256 seedShares
    ) public {
        // Given: No per user cap and no total cap.
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();

        // And: A holder next to a supply the reward per share of an accrual fits.
        uint256 accrued = bound(earned, 1, Constants.MAX_FUZZED_AMOUNT);
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(accrued.fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES),
            type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(accountA, sharesA);

        // And: An approved spender that holds nothing.
        amount = uint96(bound(amount, 0, sharesA));
        vm.prank(accountA);
        almCore.approve(accountC, amount);

        // And: The accrual.
        mockEarned(gauge, address(almCore), accrued);

        // When: The spender moves the shares.
        vm.prank(accountC);
        almCore.transferFrom(accountA, accountB, amount);

        // Then: The spender is owed nothing and its snapshot never moved.
        assertEq(almCore.getPendingReward(accountC), 0);
        assertEq(almCore.getRewardSnapshot(accountC), 0);
    }

    function testFuzz_Success_transferFrom_ToSelfAboveTheCap(uint96 sharesA, uint96 amount) public {
        // Given: A holder, a spender and no per user cap.
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        almCore.mintShares(accountA, sharesA);
        amount = uint96(bound(amount, 0, sharesA));
        vm.prank(accountA);
        almCore.approve(accountC, amount);

        // When: The spender moves the holder's shares back to the holder.
        vm.prank(accountC);
        almCore.transferFrom(accountA, accountA, amount);

        // Then: It is not checked.
        assertEq(almCore.balanceOf(accountA), sharesA);
    }

    function testFuzz_Success_transferFrom_CountsTheGaugeEarnedOnAnyChainStatus(
        uint96 sharesA,
        uint96 amount,
        uint96 earned,
        uint256 seedShares,
        uint256 status
    ) public {
        // Given: No per user cap and no total cap.
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();

        // And: A holder next to a supply the reward per share fits, and a spender.
        uint256 accrued = bound(earned, 1, Constants.MAX_FUZZED_AMOUNT);
        uint256 net = accrued - accrued * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_();
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(net.fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES),
            type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(accountA, sharesA);
        amount = uint96(bound(amount, 0, sharesA));
        vm.prank(accountA);
        almCore.approve(accountC, amount);

        // And: Emissions the gauge reports for the core, on any chain status.
        mockEarned(gauge, address(almCore), accrued);
        setAnyStatus(status);
        uint256 rewardPerShare = almCore.rewardPerShare_();
        uint256 highWater = almCore.getRewardHighWater();
        uint256 delta = FixedPointMathLib.fullMulDiv(net, 1e18, almCore.totalSupply());

        // When: The spender moves the shares.
        vm.prank(accountC);
        almCore.transferFrom(accountA, accountB, amount);

        // Then: The gauge earned is spread over the supply on any chain status.
        assertEq(almCore.rewardPerShare_(), rewardPerShare + delta);
        assertEq(almCore.getRewardHighWater(), highWater + net);

        // And: The holder is credited at the balance it held before the move.
        assertEq(almCore.getPendingReward(accountA), FixedPointMathLib.fullMulDiv(sharesA, delta, 1e18));
        assertEq(almCore.getRewardSnapshot(accountB), rewardPerShare + delta);
    }
}
