/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { AsyncVaultGuard } from "../../../src/core/abstracts/mixins/AsyncVaultGuard.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { Config, Epoch, Record } from "../../../src/core/types/State.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { QueueLib } from "../../../src/core/libraries/state/QueueLib.sol";
import { ShareLib } from "../../../src/core/libraries/state/ShareLib.sol";

/**
 * @notice Fuzz tests for the function "cancelRedeemRequest" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract CancelRedeemRequest_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_cancelRedeemRequest_OnlyAsyncVault(
        PoolState memory poolState,
        address caller,
        address controller,
        address owner_
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        vm.assume(controller != address(0));

        // And: A caller that is neither asynchronous vault.
        vm.assume(caller != asyncVault0 && caller != asyncVault1);

        // When: Calling cancelRedeemRequest().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(AsyncVaultGuard.OnlyAsyncVault.selector);
        almCore.cancelRedeemRequest(1, controller, owner_);
    }

    function testFuzz_Revert_cancelRedeemRequest_NotPending_Empty(
        PoolState memory poolState,
        address controller,
        address owner_,
        uint256 requestId
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        vm.assume(controller != address(0));

        // And: A controller with an empty record.

        // When: The vault cancels for it.
        // Then: It reverts.
        vm.prank(asyncVault1);
        vm.expectRevert(QueueLib.RequestNotPending.selector);
        almCore.cancelRedeemRequest(requestId, controller, owner_);
    }

    function testFuzz_Revert_cancelRedeemRequest_NotPending_Settled(
        PoolState memory poolState,
        address controller,
        address owner_,
        uint128 shares,
        uint32 recordEpoch,
        uint256 requestId
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A redeem record in an epoch that is no longer the pending one.
        shares = uint128(bound(shares, 1, type(uint128).max));
        recordEpoch = uint32(bound(recordEpoch, 0, type(uint32).max - 1));
        almCore.setRedeemRecord(
            asyncVault0, controller, Record({ epoch: recordEpoch, amountIn: shares, pendingShares: 0 })
        );
        almCore.setPendingEpochs(asyncVault0, 0, recordEpoch + 1);

        // When: The vault cancels for it.
        // Then: It reverts.
        vm.prank(asyncVault0);
        vm.expectRevert(QueueLib.RequestNotPending.selector);
        almCore.cancelRedeemRequest(requestId, controller, owner_);
    }

    function testFuzz_Revert_cancelRedeemRequest_CoreBalanceShort(
        PoolState memory poolState,
        uint96 coreShares,
        uint96 shares,
        address receiver
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A pending redeem for more aLP than the core holds.
        vm.assume(receiver != address(0) && receiver != address(almCore));
        coreShares = uint96(bound(coreShares, 0, type(uint96).max - 1));
        shares = uint96(bound(shares, uint256(coreShares) + 1, type(uint96).max));
        almCore.mintShares(address(almCore), coreShares);
        almCore.setRedeemRecord(asyncVault0, controller, Record({ epoch: 0, amountIn: shares, pendingShares: 0 }));
        almCore.setRedeemEpoch(asyncVault0, 0, Epoch({ amountIn: shares, amountOut: 0 }));

        // And: A per user cap the receiver stays within.
        Config memory config = coreViewLogic.getConfig(address(almCore));
        config.perUserCap = type(uint128).max;
        almCore.setConfig(config);

        // When: The vault cancels it.
        // Then: It reverts before the escrow moves.
        vm.prank(asyncVault0);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        almCore.cancelRedeemRequest(0, controller, receiver);
    }

    function testFuzz_Revert_cancelRedeemRequest_PerUserCapExceeded(
        PoolState memory poolState,
        uint256 shares,
        address receiver
    ) public {
        // Given: A pool at a fuzzed price, a pending redeem and a per user cap one short.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        recordRedeemAt(asyncVault0, controller, shares);
        vm.prank(factory);
        almCore.setPerUserCap(shares - 1);
        vm.assume(receiver != controller && receiver != address(almCore) && receiver != address(0));

        // When: The vault cancels it to any account apart from the controller.
        // Then: It reverts on the receiver's cap balance.
        vm.prank(asyncVault0);
        vm.expectRevert(ShareLib.PerUserCapExceeded.selector);
        almCore.cancelRedeemRequest(0, controller, receiver);
    }

    function testFuzz_Success_cancelRedeemRequest_ReturnsTheShares(
        PoolState memory poolState,
        address controller,
        address owner_,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        // And: A pending redeem whose shares the core took custody of.
        vm.assume(owner_ != address(0) && owner_ != address(almCore));
        vm.assume(controller != address(0) && controller != address(almCore) && controller != owner_);
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        recordRedeemAt(asyncVault0, controller, shares);

        // When: The vault cancels it.
        vm.prank(asyncVault0);
        uint256 returned = almCore.cancelRedeemRequest(0, controller, owner_);

        // Then: The receiver has the shares back and the core's balance has none of them.
        assertEq(returned, shares);
        assertEq(almCore.balanceOf(owner_), shares);
        assertEq(almCore.balanceOf(address(almCore)), 0);

        // And: The record, epoch input and pending shares are empty.
        assertEq(almCore.pendingShares_(controller), 0);
        assertEq(almCore.redeemRecord(asyncVault0, controller).amountIn, 0);
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountIn, 0);
    }

    function testFuzz_Success_cancelRedeemRequest_LeavesEscrowAlone(
        PoolState memory poolState,
        address controller,
        address owner_,
        uint256 shares,
        uint256 escrowed
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        vm.assume(controller != address(0));

        // And: A pending redeem alongside a token0 escrow from some other request.
        vm.assume(owner_ != address(0) && owner_ != address(almCore));
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        escrowed = bound(escrowed, 1, Constants.MAX_FUZZED_AMOUNT);
        token0.mint(address(almCore), escrowed);
        almCore.setEscrowed(escrowed, 0);
        recordRedeemAt(asyncVault0, controller, shares);

        // When: The vault cancels the redeem.
        vm.prank(asyncVault0);
        almCore.cancelRedeemRequest(0, controller, owner_);

        // Then: The pool tokens held for the other request did not move.
        uint256 escrowed0 = almCore.getEscrowed0();
        uint256 escrowed1 = almCore.getEscrowed1();
        assertEq(escrowed0, escrowed);
        assertEq(escrowed1, 0);
    }

    function testFuzz_Success_cancelRedeemRequest_CreditsTheEscrowRewardToTheProtocol(
        PoolState memory poolState,
        uint96 shares,
        uint96 earned,
        uint256 seedShares,
        uint256 pick
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        // And: A pending redeem, returned to a receiver apart from the controller.
        shares = uint96(bound(shares, 1, type(uint96).max));
        seedShares = bound(
            seedShares, FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max) + 1, type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        recordRedeemAt(asyncVault0, controller, shares);

        // And: An accrual not yet checkpointed, on a chain that mints.
        earned = uint96(bound(earned, 1, type(uint96).max));
        mockEarned(gauge, address(almCore), earned);
        setMintableStatus(pick);
        uint256 net = earned - uint256(earned) * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        uint256 rewardPerShare = net.fullMulDiv(1e18, seedShares + shares);

        // When: The vault cancels the redeem.
        vm.prank(asyncVault0);
        almCore.cancelRedeemRequest(0, controller, accountA);

        // Then: The escrowed shares earned for the protocol, not for the controller.
        assertEq(almCore.getProtocolFeesReward(), uint256(shares).fullMulDiv(rewardPerShare, 1e18));
        assertEq(almCore.getPendingReward(controller), 0);

        // And: The receiver's balance has the shares.
        assertEq(almCore.balanceOf(accountA), shares);

        // And: The core and the receiver were checkpointed at the new reward per share.
        assertEq(almCore.getProtocolRewardSnapshot(), rewardPerShare);
        assertEq(almCore.getRewardSnapshot(accountA), rewardPerShare);
    }

    function testFuzz_Success_cancelRedeemRequest_CountsTheGaugeOnAnyChainStatus(
        PoolState memory poolState,
        uint96 shares,
        uint96 earned,
        uint256 seedShares,
        uint48 windowEnd,
        uint256 status
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        // And: A pending redeem, returned to a receiver apart from the controller.
        shares = uint96(bound(shares, 1, type(uint96).max));
        seedShares = bound(
            seedShares, FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max) + 1, type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        recordRedeemAt(asyncVault0, controller, shares);

        // And: Emissions earned at the gauge and a window end, on a fuzzed chain status.
        mockEarned(gauge, address(almCore), earned);
        windowEnd = uint48(bound(windowEnd, 1, type(uint48).max));
        almCore.setWindowEnd(windowEnd);
        setAnyStatus(status);
        uint256 net = earned - uint256(earned) * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        uint256 rewardPerShare = net.fullMulDiv(1e18, seedShares + shares);

        // When: The vault cancels the redeem.
        vm.prank(asyncVault0);
        almCore.cancelRedeemRequest(0, controller, accountA);

        // Then: Reward per share and high water count the gauge on any chain status.
        assertEq(almCore.rewardPerShare_(), rewardPerShare);
        assertEq(almCore.getRewardHighWater(), net);

        // And: The escrowed shares earned up to that reward per share for the protocol.
        assertEq(almCore.getProtocolFeesReward(), uint256(shares).fullMulDiv(rewardPerShare, 1e18));
        assertEq(almCore.getPendingReward(controller), 0);

        // And: The window end is folded.
        assertEq(almCore.getWindowEnd(), 0);
    }

    function testFuzz_Success_cancelRedeemRequest_ReturnsToTheControllerAndAccruesItsBalanceOnly(
        PoolState memory poolState,
        uint96 balance,
        uint96 shares,
        uint96 earned,
        uint256 seedShares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A controller with a balance and a pending redeem, returned to itself.
        shares = uint96(bound(shares, 1, type(uint96).max));
        seedShares = bound(
            seedShares, FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max) + 1, type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        recordRedeemAt(asyncVault0, controller, shares);
        almCore.mintShares(controller, balance);

        // And: An accrual not yet checkpointed.
        earned = uint96(bound(earned, 1, type(uint96).max));
        mockEarned(gauge, address(almCore), earned);
        uint256 net = earned - uint256(earned) * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        uint256 rewardPerShare = net.fullMulDiv(1e18, seedShares + shares + balance);

        // When: The vault cancels the redeem to the controller.
        vm.prank(asyncVault0);
        almCore.cancelRedeemRequest(0, controller, controller);

        // Then: The controller holds the shares again and nothing is escrowed for it.
        assertEq(almCore.balanceOf(controller), uint256(balance) + shares);
        assertEq(almCore.claimableSharesOf_(controller), 0);

        // And: It was credited on its balance only, the protocol on the escrowed shares.
        assertEq(almCore.getPendingReward(controller), uint256(balance).fullMulDiv(rewardPerShare, 1e18));
        assertEq(almCore.getProtocolFeesReward(), uint256(shares).fullMulDiv(rewardPerShare, 1e18));
    }

    function testFuzz_Success_cancelRedeemRequest_ToTheControllerAboveTheCap(PoolState memory poolState, uint256 shares)
        public
    {
        // Given: A pool at a fuzzed price, a pending redeem and a per user cap of zero.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        recordRedeemAt(asyncVault0, controller, shares);
        vm.prank(factory);
        almCore.setPerUserCap(0);

        // When: The vault cancels it to the controller.
        vm.prank(asyncVault0);
        almCore.cancelRedeemRequest(0, controller, controller);

        // Then: It is not checked.
        assertEq(almCore.balanceOf(controller), shares);
    }

    function testFuzz_Success_cancelRedeemRequest_InWindowEscrowCreditedToTheProtocol(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 window,
        uint256 accruedFor,
        uint256 emissions,
        uint256 shares,
        uint16 feeBps,
        uint256 pick
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge hiding staked emissions for a window, and a protocol share.
        window = bound(window, 2, type(uint40).max);
        setPenaltyConfig(window, MAX_PIPS);
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        uint16 protocolSwapFeeBps = almCore.protocolSwapFeeBps_();
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, protocolSwapFeeBps, users.feeRecipient);

        // And: A seeded vault whose staked range opens its window now.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A pending redeem of the controller, recorded before the emissions accrue.
        shares = bound(shares, 1, coreState.supply);
        recordRedeemAt(asyncVault0, controller, shares);

        // And: Emissions the window hides, up to a block in it, on a minting chain.
        emissions = bound(emissions, 1, Constants.MAX_EMISSIONS);
        accruedFor = bound(accruedFor, 1, window - 1);
        accrueForBlocks(pool, gauge, accruedFor, emissions);
        setMintableStatus(pick);
        uint256[] memory tokenIds = almCore.stakedTokenIds();
        uint256 hidden = hiddenEmissions(gauge, address(almCore), tokenIds);
        uint256 net = hidden - hidden * feeBps / ConfigLib.BPS_DENOMINATOR;
        uint256 supply = almCore.totalSupply();

        // When: The controller cancels the redeem to another account.
        vm.prank(asyncVault0);
        almCore.cancelRedeemRequest(0, controller, accountA);

        // Then: The protocol is credited the escrowed shares' part of the net emissions.
        assertEq(almCore.getProtocolFeesReward(), shares.fullMulDiv(net.fullMulDiv(1e18, supply), 1e18));
        assertEq(almCore.getPendingReward(controller), 0);

        // And: The transfer back pre-credited the hidden emissions, net of the fee.
        assertEq(almCore.getPreCredited(), net);

        // And: The shares moved from escrow to the receiver.
        assertEq(almCore.balanceOf(accountA), shares);
        assertEq(almCore.balanceOf(address(almCore)), 0);
    }
}
