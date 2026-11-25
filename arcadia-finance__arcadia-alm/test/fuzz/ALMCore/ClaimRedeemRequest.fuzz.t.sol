/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { AsyncVaultGuard } from "../../../src/core/abstracts/mixins/AsyncVaultGuard.sol";
import { Claimable, Epoch, Record } from "../../../src/core/types/State.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { QueueLib } from "../../../src/core/libraries/state/QueueLib.sol";

/**
 * @notice Fuzz tests for the function "claimRedeemRequest" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract ClaimRedeemRequest_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_claimRedeemRequest_OnlyAsyncVault(
        address caller,
        address controller,
        uint256 shares,
        address receiver
    ) public {
        // Given: A controller that is not the zero address.
        vm.assume(controller != address(0));

        // And: A caller that is neither asynchronous vault.
        vm.assume(caller != asyncVault0 && caller != asyncVault1);

        // When: Calling claimRedeemRequest().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(AsyncVaultGuard.OnlyAsyncVault.selector);
        almCore.claimRedeemRequest(controller, shares, 0, receiver);
    }

    function testFuzz_Revert_claimRedeemRequest_InsufficientClaimable(
        bool isToken0,
        address controller,
        address receiver,
        uint128 claimableIn,
        uint128 claimableOut,
        uint256 shares
    ) public {
        // Given: The asynchronous vault of either token.
        (address vault, ERC20Mock token) = isToken0 ? (asyncVault0, token0) : (asyncVault1, token1);

        // And: A controller that is not the zero address.
        vm.assume(controller != address(0));

        // And: A settled redeem and a claim above what it holds.
        claimableIn = uint128(bound(claimableIn, 1, uint128(Constants.MAX_FUZZED_AMOUNT)));
        claimableOut = uint128(bound(claimableOut, 0, uint128(Constants.MAX_FUZZED_AMOUNT)));
        token.mint(address(almCore), claimableOut);
        almCore.stageClaimableRedeem(vault, controller, claimableIn, claimableOut);
        shares = bound(shares, uint256(claimableIn) + 1, type(uint256).max);

        // When: The vault claims it.
        // Then: It reverts.
        vm.prank(vault);
        vm.expectRevert(QueueLib.InsufficientClaimable.selector);
        almCore.claimRedeemRequest(controller, shares, 0, receiver);
    }

    function testFuzz_Success_claimRedeemRequest_CapsTheAssets(
        bool isToken0,
        uint128 claimableIn,
        uint128 claimableOut,
        uint256 shares,
        uint256 maxAssets
    ) public {
        // Given: The asynchronous vault of either token.
        (address vault, ERC20Mock token) = isToken0 ? (asyncVault0, token0) : (asyncVault1, token1);

        // And: A settled redeem.
        claimableIn = uint128(bound(claimableIn, 1, uint128(Constants.MAX_FUZZED_AMOUNT)));
        claimableOut = uint128(bound(claimableOut, 1, uint128(Constants.MAX_FUZZED_AMOUNT)));
        token.mint(address(almCore), claimableOut);
        almCore.stageClaimableRedeem(vault, controller, claimableIn, claimableOut);

        // And: A share amount and an asset cap below what it is worth on the pile.
        shares = bound(shares, uint256(claimableIn).divUp(claimableOut), claimableIn);
        maxAssets = bound(maxAssets, 0, shares * claimableOut / claimableIn - 1);

        // When: The vault claims it.
        vm.prank(vault);
        uint256 assets = almCore.claimRedeemRequest(controller, shares, maxAssets, controller);

        // Then: The controller receives the cap, the pile gives up the shares and cap.
        assertEq(assets, maxAssets);
        assertEq(token.balanceOf(controller), maxAssets);
        Claimable memory claimed = almCore.claimableRedeem(vault, controller);
        assertEq(claimed.amountIn, claimableIn - shares);
        assertEq(claimed.amountOut, claimableOut - maxAssets);
    }

    function testFuzz_Success_claimRedeemRequest_PaysFromEscrow(
        bool isToken0,
        address controller,
        address receiver,
        uint128 claimableIn,
        uint128 claimableOut,
        uint256 shares
    ) public {
        // Given: The asynchronous vault of either token.
        (address vault, ERC20Mock token) = isToken0 ? (asyncVault0, token0) : (asyncVault1, token1);

        // And: A controller that is not the zero address.
        vm.assume(controller != address(0));

        // And: A settled redeem whose proceeds sit in escrow.
        vm.assume(receiver != address(0) && receiver != address(almCore));
        claimableIn = uint128(bound(claimableIn, 1, uint128(Constants.MAX_FUZZED_AMOUNT)));
        claimableOut = uint128(bound(claimableOut, 0, uint128(Constants.MAX_FUZZED_AMOUNT)));
        token.mint(address(almCore), claimableOut);
        almCore.stageClaimableRedeem(vault, controller, claimableIn, claimableOut);
        shares = bound(shares, 0, claimableIn);

        // When: The vault claims part of it.
        uint256 assets = uint256(shares) * claimableOut / claimableIn;
        vm.prank(vault);
        uint256 paid = almCore.claimRedeemRequest(controller, shares, type(uint256).max, receiver);

        // Then: The receiver is paid and the escrow falls by the same amount.
        assertEq(paid, assets);
        assertEq(token.balanceOf(receiver), assets);
        (uint256 escrowed, uint256 otherEscrowed) = isToken0
            ? (almCore.getEscrowed0(), almCore.getEscrowed1())
            : (almCore.getEscrowed1(), almCore.getEscrowed0());
        assertEq(escrowed, uint256(claimableOut) - assets);
        assertEq(otherEscrowed, 0);

        // And: Every token the core still holds is buffer, fee or escrow.
        assertEq(
            token.balanceOf(address(almCore)),
            isToken0
                ? almCore.bufferAmount0() + almCore.getProtocolFees0() + escrowed
                : almCore.bufferAmount1() + almCore.getProtocolFees1() + escrowed
        );
    }

    function testFuzz_Success_claimRedeemRequest_FullClaimEmptiesTheSide(
        bool isToken0,
        address controller,
        address receiver,
        uint128 claimableIn,
        uint128 claimableOut
    ) public {
        // Given: The asynchronous vault of either token.
        (address vault, ERC20Mock token) = isToken0 ? (asyncVault0, token0) : (asyncVault1, token1);

        // And: A controller that is not the zero address.
        vm.assume(controller != address(0));

        // And: A settled redeem whose proceeds sit in escrow.
        vm.assume(receiver != address(0) && receiver != address(almCore));
        claimableIn = uint128(bound(claimableIn, 1, uint128(Constants.MAX_FUZZED_AMOUNT)));
        claimableOut = uint128(bound(claimableOut, 0, uint128(Constants.MAX_FUZZED_AMOUNT)));
        token.mint(address(almCore), claimableOut);
        almCore.stageClaimableRedeem(vault, controller, claimableIn, claimableOut);

        // When: The vault claims all of it.
        vm.prank(vault);
        uint256 assets = almCore.claimRedeemRequest(controller, claimableIn, type(uint256).max, receiver);

        // Then: Nothing is left claimable and nothing is left escrowed.
        assertEq(assets, claimableOut);
        Claimable memory claimed = almCore.claimableRedeem(vault, controller);
        assertEq(claimed.amountIn, 0);
        assertEq(claimed.amountOut, 0);
        assertEq(almCore.getEscrowed0(), 0);
        assertEq(almCore.getEscrowed1(), 0);
    }

    function testFuzz_Success_claimRedeemRequest_FirstClaimCreditsTheRecord(
        bool isToken0,
        Record memory record,
        Epoch memory epoch,
        address receiver,
        uint256 shares
    ) public {
        // Given: The asynchronous vault of either token.
        (address vault, ERC20Mock token) = isToken0 ? (asyncVault0, token0) : (asyncVault1, token1);

        // And: A settled redeem record whose proceeds sit in escrow, not yet credited.
        vm.assume(receiver != address(0) && receiver != address(almCore));
        record.epoch = uint32(bound(record.epoch, 0, type(uint32).max - 1));
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint96).max));
        epoch.amountIn = record.amountIn;
        epoch.amountOut = uint128(bound(epoch.amountOut, 0, type(uint96).max));
        token.mint(address(almCore), epoch.amountOut);
        almCore.stageSettledRedeem(vault, controller, record, epoch);
        uint256 credited = uint256(record.amountIn).fullMulDiv(epoch.amountOut, epoch.amountIn);
        shares = bound(shares, 0, record.amountIn);

        // When: The vault claims part of it.
        uint256 assets = shares.fullMulDiv(credited, record.amountIn);
        vm.prank(vault);
        uint256 paid = almCore.claimRedeemRequest(controller, shares, type(uint256).max, receiver);

        // Then: The record was credited at the epoch's rate, then claimed from the pile.
        assertEq(paid, assets);
        assertEq(token.balanceOf(receiver), assets);
        Claimable memory claimed = almCore.claimableRedeem(vault, controller);
        assertEq(claimed.amountIn, record.amountIn - shares);
        assertEq(claimed.amountOut, credited - assets);

        // And: The vault token's escrow falls by the payout, the other stays empty.
        (uint256 escrowed, uint256 otherEscrowed) = isToken0
            ? (almCore.getEscrowed0(), almCore.getEscrowed1())
            : (almCore.getEscrowed1(), almCore.getEscrowed0());
        assertEq(escrowed, epoch.amountOut - assets);
        assertEq(otherEscrowed, 0);

        // And: The epoch remainders fall by the record and the record is cleared.
        Epoch memory remainder = almCore.redeemEpoch(vault, record.epoch);
        assertEq(remainder.amountIn, epoch.amountIn - record.amountIn);
        assertEq(remainder.amountOut, epoch.amountOut - credited);
        Record memory cleared = almCore.redeemRecord(vault, controller);
        assertEq(cleared.epoch, 0);
        assertEq(cleared.amountIn, 0);
    }

    function testFuzz_Success_claimRedeemRequest_SecondClaimLeavesTheEpoch(
        bool isToken0,
        Record memory record,
        Epoch memory epoch,
        address receiver
    ) public {
        // Given: The asynchronous vault of either token.
        (address vault, ERC20Mock token) = isToken0 ? (asyncVault0, token0) : (asyncVault1, token1);

        // And: A settled redeem record, credited by a first claim.
        vm.assume(receiver != address(0) && receiver != address(almCore));
        record.epoch = uint32(bound(record.epoch, 0, type(uint32).max - 1));
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint96).max));
        epoch.amountIn = record.amountIn;
        epoch.amountOut = uint128(bound(epoch.amountOut, 0, type(uint96).max));
        token.mint(address(almCore), epoch.amountOut);
        almCore.stageSettledRedeem(vault, controller, record, epoch);
        vm.prank(vault);
        almCore.claimRedeemRequest(controller, 0, 0, receiver);
        Epoch memory before = almCore.redeemEpoch(vault, record.epoch);

        // When: The vault claims again.
        vm.prank(vault);
        almCore.claimRedeemRequest(controller, 0, 0, receiver);

        // Then: The epoch remainders are unchanged.
        Epoch memory remainder = almCore.redeemEpoch(vault, record.epoch);
        assertEq(remainder.amountIn, before.amountIn);
        assertEq(remainder.amountOut, before.amountOut);
    }

    function testFuzz_Success_claimRedeemRequest_ZeroOutputRecord(
        bool isToken0,
        Record memory record,
        Epoch memory epoch,
        address receiver
    ) public {
        // Given: The asynchronous vault of either token.
        (address vault, ERC20Mock token) = isToken0 ? (asyncVault0, token0) : (asyncVault1, token1);

        // And: A settled redeem record whose share of the epoch floors to zero.
        vm.assume(receiver != address(0) && receiver != address(almCore));
        record.epoch = uint32(bound(record.epoch, 0, type(uint32).max - 1));
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint96).max));
        epoch.amountOut = uint128(
            bound(
                epoch.amountOut, 0, FixedPointMathLib.min(type(uint96).max, (type(uint128).max - 1) / record.amountIn)
            )
        );
        epoch.amountIn = uint128(
            bound(
                epoch.amountIn,
                FixedPointMathLib.max(record.amountIn, uint256(record.amountIn) * epoch.amountOut + 1),
                type(uint128).max
            )
        );
        token.mint(address(almCore), epoch.amountOut);
        almCore.stageSettledRedeem(vault, controller, record, epoch);

        // When: The vault claims nothing.
        vm.prank(vault);
        almCore.claimRedeemRequest(controller, 0, 0, receiver);

        // Then: The record joined the pile as its input and no output.
        Claimable memory claimed = almCore.claimableRedeem(vault, controller);
        assertEq(claimed.amountIn, record.amountIn);
        assertEq(claimed.amountOut, 0);

        // And: The vault token's escrow keeps the epoch's output, the other is empty.
        (uint256 escrowed, uint256 otherEscrowed) = isToken0
            ? (almCore.getEscrowed0(), almCore.getEscrowed1())
            : (almCore.getEscrowed1(), almCore.getEscrowed0());
        assertEq(escrowed, epoch.amountOut);
        assertEq(otherEscrowed, 0);
    }

    function testFuzz_Success_claimRedeemRequest_CreditPaysTheControllerNothing(
        bool isToken0,
        Record memory record,
        Epoch memory epoch,
        uint256 rewardPerShare
    ) public {
        // Given: The asynchronous vault of either token.
        (address vault, ERC20Mock token) = isToken0 ? (asyncVault0, token0) : (asyncVault1, token1);

        // And: A settled redeem record, not yet credited.
        record.epoch = uint32(bound(record.epoch, 0, type(uint32).max - 1));
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint96).max));
        epoch.amountIn = record.amountIn;
        epoch.amountOut = uint128(bound(epoch.amountOut, 0, type(uint96).max));
        token.mint(address(almCore), epoch.amountOut);
        almCore.stageSettledRedeem(vault, controller, record, epoch);

        // And: A reward per share.
        rewardPerShare = bound(rewardPerShare, 0, type(uint64).max);
        almCore.setRewardAccounting(rewardPerShare, 0, 0, 0);

        // When: The vault claims nothing.
        vm.prank(vault);
        almCore.claimRedeemRequest(controller, 0, 0, accountA);

        // Then: The record was credited to the pile, the controller credited no reward.
        assertEq(almCore.claimableRedeem(vault, controller).amountIn, record.amountIn);
        assertEq(almCore.getPendingReward(controller), 0);
    }

    function testFuzz_Success_claimRedeemRequest_CreditReleasesThePendingShares(
        bool isToken0,
        Record memory record,
        Epoch memory epoch
    ) public {
        // Given: The asynchronous vault of either token.
        (address vault, ERC20Mock token) = isToken0 ? (asyncVault0, token0) : (asyncVault1, token1);

        // And: A settled redeem record in pending shares.
        record.epoch = uint32(bound(record.epoch, 0, type(uint32).max - 1));
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint96).max));
        epoch.amountIn = record.amountIn;
        epoch.amountOut = uint128(bound(epoch.amountOut, 0, type(uint96).max));
        token.mint(address(almCore), epoch.amountOut);
        almCore.stageSettledRedeem(vault, controller, record, epoch);

        // When: The vault claims nothing.
        vm.prank(vault);
        almCore.claimRedeemRequest(controller, 0, 0, controller);

        // Then: The record's shares leave the controller's pending shares.
        assertEq(almCore.pendingShares_(controller), 0);
    }
}
