/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { AsyncVaultGuard } from "../../../src/core/abstracts/mixins/AsyncVaultGuard.sol";
import { Claimable, Config, Epoch, Record } from "../../../src/core/types/State.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { QueueLib } from "../../../src/core/libraries/state/QueueLib.sol";
import { ShareLib } from "../../../src/core/libraries/state/ShareLib.sol";

/**
 * @notice Fuzz tests for the function "claimDepositRequest" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract ClaimDepositRequest_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_claimDepositRequest_OnlyAsyncVault(
        PoolState memory poolState,
        address caller,
        address controller,
        uint256 assets,
        address receiver
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        vm.assume(controller != address(0));
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        // And: A caller that is neither asynchronous vault.
        vm.assume(caller != asyncVault0 && caller != asyncVault1);

        // When: Calling claimDepositRequest().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(AsyncVaultGuard.OnlyAsyncVault.selector);
        almCore.claimDepositRequest(controller, assets, 0, receiver);
    }

    function testFuzz_Revert_claimDepositRequest_InsufficientClaimable(
        PoolState memory poolState,
        address controller,
        address receiver,
        uint128 claimableIn,
        uint128 claimableOut,
        uint256 assets
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        vm.assume(controller != address(0));
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        // And: A settled deposit and a claim above what it holds.
        claimableIn = uint128(bound(claimableIn, 1, uint128(Constants.MAX_FUZZED_AMOUNT)));
        almCore.stageClaimableDeposit(asyncVault0, controller, claimableIn, claimableOut);
        assets = bound(assets, uint256(claimableIn) + 1, type(uint256).max);

        // When: The vault claims it.
        // Then: It reverts.
        vm.prank(asyncVault0);
        vm.expectRevert(QueueLib.InsufficientClaimable.selector);
        almCore.claimDepositRequest(controller, assets, 0, receiver);
    }

    function testFuzz_Revert_claimDepositRequest_InsufficientClaimable_KeyedByVault(
        PoolState memory poolState,
        address controller,
        address receiver,
        uint128 claimableIn,
        uint128 claimableOut
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        vm.assume(controller != address(0));
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        // And: A settled deposit at the token0 vault only.
        vm.assume(receiver != address(0) && receiver != address(almCore) && receiver != address(1));
        claimableIn = uint128(bound(claimableIn, 1, uint128(Constants.MAX_FUZZED_AMOUNT)));
        claimableOut = uint128(bound(claimableOut, 0, uint128(Constants.MAX_FUZZED_AMOUNT)));
        almCore.stageClaimableDeposit(asyncVault0, controller, claimableIn, claimableOut);

        // When: The token1 vault claims for the same controller.
        // Then: It reverts.
        vm.prank(asyncVault1);
        vm.expectRevert(QueueLib.InsufficientClaimable.selector);
        almCore.claimDepositRequest(controller, claimableIn, 0, receiver);
    }

    function testFuzz_Revert_claimDepositRequest_PerUserCapExceeded(
        PoolState memory poolState,
        uint128 claimableIn,
        uint96 claimableOut,
        address receiver
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A settled deposit, and a per user cap one share short of what it pays.
        claimableIn = uint128(bound(claimableIn, 1, uint128(Constants.MAX_FUZZED_AMOUNT)));
        claimableOut = uint96(bound(claimableOut, 1, type(uint96).max));
        almCore.stageClaimableDeposit(asyncVault0, controller, claimableIn, claimableOut);
        vm.prank(factory);
        almCore.setPerUserCap(claimableOut - 1);
        vm.assume(receiver != controller && receiver != address(almCore) && receiver != address(0));

        // When: The vault claims all of it to any account apart from the controller.
        // Then: It reverts on the receiver's cap balance.
        vm.prank(asyncVault0);
        vm.expectRevert(ShareLib.PerUserCapExceeded.selector);
        almCore.claimDepositRequest(controller, claimableIn, claimableOut, receiver);
    }

    function testFuzz_Revert_claimDepositRequest_PerUserCapExceeded_HeldShares(
        PoolState memory poolState,
        uint128 claimableIn,
        uint96 claimableOut,
        uint256 cap,
        address receiver
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A settled deposit, and a receiver holding as many shares as it pays.
        claimableIn = uint128(bound(claimableIn, 1, uint128(Constants.MAX_FUZZED_AMOUNT)));
        claimableOut = uint96(bound(claimableOut, 1, type(uint96).max));
        almCore.stageClaimableDeposit(asyncVault0, controller, claimableIn, claimableOut);
        vm.assume(receiver != controller && receiver != address(almCore) && receiver != address(0));
        almCore.mintShares(receiver, claimableOut);

        // And: A per user cap fitting either alone but not both.
        vm.prank(factory);
        almCore.setPerUserCap(bound(cap, claimableOut, 2 * uint256(claimableOut) - 1));

        // When: The vault claims all of it to that receiver.
        // Then: It reverts on the receiver's cap balance.
        vm.prank(asyncVault0);
        vm.expectRevert(ShareLib.PerUserCapExceeded.selector);
        almCore.claimDepositRequest(controller, claimableIn, claimableOut, receiver);
    }

    function testFuzz_Revert_claimDepositRequest_CoreBalanceShort(
        PoolState memory poolState,
        uint128 claimableIn,
        uint96 claimableOut,
        uint96 coreShares,
        address receiver
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A settled deposit claiming more aLP than the core holds.
        vm.assume(receiver != address(0) && receiver != address(almCore));
        claimableIn = uint128(bound(claimableIn, 1, uint128(Constants.MAX_FUZZED_AMOUNT)));
        claimableOut = uint96(bound(claimableOut, 1, type(uint96).max));
        coreShares = uint96(bound(coreShares, 0, claimableOut - 1));
        almCore.mintShares(address(almCore), coreShares);
        almCore.setClaimableShares(controller, claimableOut);
        almCore.setClaimableDeposit(
            asyncVault0, controller, Claimable({ amountIn: claimableIn, amountOut: claimableOut })
        );

        // And: A per user cap the receiver stays within.
        Config memory config = coreViewLogic.getConfig(address(almCore));
        config.perUserCap = type(uint128).max;
        almCore.setConfig(config);

        // When: The vault claims all of it.
        // Then: It reverts before the escrow moves.
        vm.prank(asyncVault0);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        almCore.claimDepositRequest(controller, claimableIn, claimableOut, receiver);
    }

    function testFuzz_Success_claimDepositRequest_CapsTheShares(
        PoolState memory poolState,
        uint128 claimableIn,
        uint96 claimableOut,
        uint256 assets,
        uint256 maxShares
    ) public {
        // Given: A pool with depth at a fuzzed price, and a settled deposit.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        claimableIn = uint128(bound(claimableIn, 1, uint128(Constants.MAX_FUZZED_AMOUNT)));
        claimableOut = uint96(bound(claimableOut, 1, type(uint96).max));
        almCore.stageClaimableDeposit(asyncVault0, controller, claimableIn, claimableOut);

        // And: An asset amount and a share cap below what it is worth on the pile.
        assets = bound(assets, uint256(claimableIn).divUp(claimableOut), claimableIn);
        maxShares = bound(maxShares, 0, assets * claimableOut / claimableIn - 1);

        // When: The vault claims it.
        vm.prank(asyncVault0);
        uint256 shares = almCore.claimDepositRequest(controller, assets, maxShares, controller);

        // Then: The controller receives the cap, the pile gives up the assets and cap.
        assertEq(shares, maxShares);
        assertEq(almCore.balanceOf(controller), maxShares);
        Claimable memory claimed = almCore.claimableDeposit(asyncVault0, controller);
        assertEq(claimed.amountIn, claimableIn - assets);
        assertEq(claimed.amountOut, claimableOut - maxShares);
    }

    function testFuzz_Success_claimDepositRequest_PaysShares(
        PoolState memory poolState,
        address controller,
        address receiver,
        uint128 claimableIn,
        uint128 claimableOut,
        uint256 assets
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        vm.assume(controller != address(0));
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        // And: A settled deposit and a receiver that can hold shares.
        vm.assume(receiver != address(0) && receiver != address(almCore) && receiver != address(1));
        claimableIn = uint128(bound(claimableIn, 1, uint128(Constants.MAX_FUZZED_AMOUNT)));
        claimableOut = uint128(bound(claimableOut, 0, uint128(Constants.MAX_FUZZED_AMOUNT)));
        almCore.stageClaimableDeposit(asyncVault0, controller, claimableIn, claimableOut);
        assets = bound(assets, 0, claimableIn);

        // When: The vault claims part of it.
        uint256 shares = uint256(assets) * claimableOut / claimableIn;
        vm.prank(asyncVault0);
        uint256 paid = almCore.claimDepositRequest(controller, assets, type(uint256).max, receiver);

        // Then: The receiver holds the shares, whatever the per user cap says now.
        assertEq(paid, shares);
        assertEq(almCore.balanceOf(receiver), shares);

        // And: Both claimable figures fall by what was taken.
        Claimable memory claimed = almCore.claimableDeposit(asyncVault0, controller);
        assertEq(claimed.amountIn, claimableIn - assets);
        assertEq(claimed.amountOut, claimableOut - shares);

        // And: What is held for the controller falls by the shares paid out.
        assertEq(almCore.claimableSharesOf_(controller), claimableOut - shares);
        assertEq(almCore.balanceOf(address(almCore)), claimableOut - shares);
    }

    function testFuzz_Success_claimDepositRequest_CreditsTheEscrowRewardToTheProtocol(
        PoolState memory poolState,
        uint96 balance,
        uint128 claimableIn,
        uint96 claimableOut,
        uint256 assets,
        uint96 earned,
        uint256 seedShares,
        uint256 pick
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A controller with a balance and a settled deposit, claimed to another.
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        claimableIn = uint128(bound(claimableIn, 1, uint128(Constants.MAX_FUZZED_AMOUNT)));
        claimableOut = uint96(bound(claimableOut, 1, type(uint96).max));
        seedShares = bound(
            seedShares, FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max) + 1, type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(controller, balance);
        almCore.stageClaimableDeposit(asyncVault0, controller, claimableIn, claimableOut);
        assets = bound(assets, 0, claimableIn);

        // And: An uncredited accrual, on a chain that mints.
        earned = uint96(bound(earned, 1, type(uint96).max));
        mockEarned(gauge, address(almCore), earned);
        setMintableStatus(pick);
        uint256 rewardPerShare = (earned - uint256(earned) * almCore.protocolEmissionFeeBps_()
                / ConfigLib.BPS_DENOMINATOR)
        .fullMulDiv(1e18, seedShares + balance + claimableOut);

        // When: The vault claims part of the deposit.
        uint256 shares = uint256(assets) * claimableOut / claimableIn;
        vm.prank(asyncVault0);
        uint256 paid = almCore.claimDepositRequest(controller, assets, type(uint256).max, accountA);

        // Then: The protocol was credited on the escrow, the controller on nothing.
        assertEq(paid, shares);
        assertEq(almCore.getProtocolFeesReward(), uint256(claimableOut).fullMulDiv(rewardPerShare, 1e18));
        assertEq(almCore.getPendingReward(controller), 0);

        // And: The controller is still owed what its own balance earned.
        assertEq(almCore.getRewardOwed(controller), uint256(balance).fullMulDiv(rewardPerShare, 1e18));

        // And: The receiver holds the shares and the escrow released them.
        assertEq(almCore.balanceOf(accountA), shares);
        assertEq(almCore.claimableSharesOf_(controller), claimableOut - shares);

        // And: The core and the receiver were checkpointed at the new reward per share.
        assertEq(almCore.getProtocolRewardSnapshot(), rewardPerShare);
        assertEq(almCore.getRewardSnapshot(accountA), rewardPerShare);
    }

    function testFuzz_Success_claimDepositRequest_CountsTheGaugeOnAnyChainStatus(
        PoolState memory poolState,
        uint96 balance,
        uint128 claimableIn,
        uint96 claimableOut,
        uint96 earned,
        uint256 seedShares,
        uint48 windowEnd,
        uint256 status
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A controller with a balance and a settled deposit, all claimed to another.
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        claimableIn = uint128(bound(claimableIn, 1, uint128(Constants.MAX_FUZZED_AMOUNT)));
        claimableOut = uint96(bound(claimableOut, 1, type(uint96).max));
        seedShares = bound(
            seedShares, FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max) + 1, type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(controller, balance);
        almCore.stageClaimableDeposit(asyncVault0, controller, claimableIn, claimableOut);

        // And: Emissions earned at the gauge and a window end, on a fuzzed chain status.
        mockEarned(gauge, address(almCore), earned);
        windowEnd = uint48(bound(windowEnd, 1, type(uint48).max));
        almCore.setWindowEnd(windowEnd);
        setAnyStatus(status);
        uint256 net = earned - uint256(earned) * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        uint256 rewardPerShare = net.fullMulDiv(1e18, seedShares + balance + claimableOut);

        // When: The vault claims the whole deposit.
        vm.prank(asyncVault0);
        almCore.claimDepositRequest(controller, claimableIn, type(uint256).max, accountA);

        // Then: Reward per share and high water count the gauge on any chain status.
        assertEq(almCore.rewardPerShare_(), rewardPerShare);
        assertEq(almCore.getRewardHighWater(), net);

        // And: The protocol was credited on the escrow, the controller on nothing.
        assertEq(almCore.getProtocolFeesReward(), uint256(claimableOut).fullMulDiv(rewardPerShare, 1e18));
        assertEq(almCore.getPendingReward(controller), 0);

        // And: The window end is folded.
        assertEq(almCore.getWindowEnd(), 0);
    }

    function testFuzz_Success_claimDepositRequest_PaysTheControllerAndAccruesItsBalanceOnly(
        PoolState memory poolState,
        uint96 balance,
        uint128 claimableIn,
        uint96 claimableOut,
        uint256 assets,
        uint96 earned,
        uint256 seedShares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A controller with a balance and a settled deposit, claimed to itself.
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        claimableIn = uint128(bound(claimableIn, 1, uint128(Constants.MAX_FUZZED_AMOUNT)));
        claimableOut = uint96(bound(claimableOut, 1, type(uint96).max));
        seedShares = bound(
            seedShares, FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max) + 1, type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(controller, balance);
        almCore.stageClaimableDeposit(asyncVault0, controller, claimableIn, claimableOut);
        assets = bound(assets, 0, claimableIn);

        // And: An accrual not yet checkpointed.
        earned = uint96(bound(earned, 1, type(uint96).max));
        mockEarned(gauge, address(almCore), earned);
        uint256 net = earned - uint256(earned) * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        uint256 rewardPerShare = net.fullMulDiv(1e18, seedShares + balance + claimableOut);

        // When: The vault claims part of the deposit to the controller.
        uint256 shares = assets * claimableOut / claimableIn;
        vm.prank(asyncVault0);
        uint256 paid = almCore.claimDepositRequest(controller, assets, type(uint256).max, controller);

        // Then: The controller holds the shares and its escrow fell by them.
        assertEq(paid, shares);
        assertEq(almCore.balanceOf(controller), uint256(balance) + shares);
        assertEq(almCore.claimableSharesOf_(controller), claimableOut - shares);

        // And: It was credited on its balance only, the protocol on the escrow.
        assertEq(almCore.getPendingReward(controller), uint256(balance).fullMulDiv(rewardPerShare, 1e18));
        assertEq(almCore.getProtocolFeesReward(), uint256(claimableOut).fullMulDiv(rewardPerShare, 1e18));
    }

    function testFuzz_Success_claimDepositRequest_FirstClaimCreditsTheRecord(
        PoolState memory poolState,
        Record memory record,
        Epoch memory epoch,
        address receiver,
        uint256 assets
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        // And: A settled deposit record, not yet credited.
        vm.assume(receiver != address(0) && receiver != address(almCore));
        record.epoch = uint32(bound(record.epoch, 0, type(uint32).max - 1));
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint96).max));
        epoch.amountIn = record.amountIn;
        epoch.amountOut = uint128(bound(epoch.amountOut, 0, type(uint96).max));
        almCore.stageSettledDeposit(asyncVault0, controller, record, epoch);
        uint256 credited = uint256(record.amountIn).fullMulDiv(epoch.amountOut, epoch.amountIn);
        assets = bound(assets, 0, record.amountIn);

        // When: The vault claims part of it.
        uint256 shares = assets.fullMulDiv(credited, record.amountIn);
        vm.prank(asyncVault0);
        uint256 paid = almCore.claimDepositRequest(controller, assets, type(uint256).max, receiver);

        // Then: The record was credited at the epoch's rate, then claimed from the pile.
        assertEq(paid, shares);
        assertEq(almCore.balanceOf(receiver), shares);
        Claimable memory claimed = almCore.claimableDeposit(asyncVault0, controller);
        assertEq(claimed.amountIn, record.amountIn - assets);
        assertEq(claimed.amountOut, credited - shares);
        assertEq(almCore.claimableSharesOf_(controller), credited - shares);

        // And: The epoch remainders fall by the record and the record is cleared.
        Epoch memory remainder = almCore.depositEpoch(asyncVault0, record.epoch);
        assertEq(remainder.amountIn, epoch.amountIn - record.amountIn);
        assertEq(remainder.amountOut, epoch.amountOut - credited);
        Record memory cleared = almCore.depositRecord(asyncVault0, controller);
        assertEq(cleared.epoch, 0);
        assertEq(cleared.amountIn, 0);
        assertEq(cleared.pendingShares, 0);
    }

    function testFuzz_Success_claimDepositRequest_SecondClaimLeavesTheEpoch(
        PoolState memory poolState,
        Record memory record,
        Epoch memory epoch,
        address receiver
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        // And: A settled deposit record, credited by a first claim.
        vm.assume(receiver != address(0) && receiver != address(almCore));
        record.epoch = uint32(bound(record.epoch, 0, type(uint32).max - 1));
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint96).max));
        epoch.amountIn = record.amountIn;
        epoch.amountOut = uint128(bound(epoch.amountOut, 0, type(uint96).max));
        almCore.stageSettledDeposit(asyncVault0, controller, record, epoch);
        vm.prank(asyncVault0);
        almCore.claimDepositRequest(controller, 0, 0, receiver);
        Epoch memory before = almCore.depositEpoch(asyncVault0, record.epoch);

        // When: The vault claims again.
        vm.prank(asyncVault0);
        almCore.claimDepositRequest(controller, 0, 0, receiver);

        // Then: The epoch remainders are unchanged.
        Epoch memory remainder = almCore.depositEpoch(asyncVault0, record.epoch);
        assertEq(remainder.amountIn, before.amountIn);
        assertEq(remainder.amountOut, before.amountOut);
    }

    function testFuzz_Success_claimDepositRequest_ZeroOutputRecord(
        PoolState memory poolState,
        Record memory record,
        Epoch memory epoch,
        address receiver
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        // And: A settled deposit record whose share of the epoch floors to zero.
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
        almCore.stageSettledDeposit(asyncVault0, controller, record, epoch);

        // When: The vault claims nothing.
        vm.prank(asyncVault0);
        almCore.claimDepositRequest(controller, 0, 0, receiver);

        // Then: The record joined the pile as its input and no output.
        Claimable memory claimed = almCore.claimableDeposit(asyncVault0, controller);
        assertEq(claimed.amountIn, record.amountIn);
        assertEq(claimed.amountOut, 0);
    }

    function testFuzz_Success_claimDepositRequest_CreditEarnsTheEscrowForTheProtocol(
        PoolState memory poolState,
        Record memory record,
        Epoch memory epoch,
        uint96 escrowed,
        uint256 rewardPerShare
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        // And: A controller with escrowed shares and an uncredited settled record.
        record.epoch = uint32(bound(record.epoch, 0, type(uint32).max - 1));
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint96).max));
        epoch.amountIn = record.amountIn;
        epoch.amountOut = uint128(bound(epoch.amountOut, 0, type(uint96).max));
        almCore.stageClaimableDeposit(asyncVault0, controller, 1, escrowed);
        almCore.stageSettledDeposit(asyncVault0, controller, record, epoch);
        uint256 credited = uint256(record.amountIn).fullMulDiv(epoch.amountOut, epoch.amountIn);

        // And: A reward per share the core's aLP has not been credited at.
        rewardPerShare = bound(rewardPerShare, 0, type(uint64).max);
        almCore.setRewardAccounting(rewardPerShare, 0, 0, 0);

        // When: The vault claims nothing to a receiver apart from the controller.
        vm.prank(asyncVault0);
        almCore.claimDepositRequest(controller, 0, 0, accountA);

        // Then: The protocol earned on the escrow and settled aLP, not the controller.
        assertEq(
            almCore.getProtocolFeesReward(), (uint256(escrowed) + epoch.amountOut).fullMulDiv(rewardPerShare, 1e18)
        );
        assertEq(almCore.getPendingReward(controller), 0);

        // And: Its escrow gained the credited shares.
        assertEq(almCore.claimableSharesOf_(controller), uint256(escrowed) + credited);
    }

    function testFuzz_Success_claimDepositRequest_CreditReleasesThePendingShares(
        PoolState memory poolState,
        Record memory record,
        Epoch memory epoch
    ) public {
        // Given: A pool with depth at a fuzzed price, and a per user cap of nothing.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(0);

        // And: A settled deposit record and its pending aLP, not yet credited.
        record.epoch = uint32(bound(record.epoch, 0, type(uint32).max - 1));
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint96).max));
        epoch.amountIn = record.amountIn;
        epoch.amountOut = uint128(bound(epoch.amountOut, 0, type(uint96).max));
        almCore.stageSettledDeposit(asyncVault0, controller, record, epoch);
        uint256 credited = uint256(record.amountIn).fullMulDiv(epoch.amountOut, epoch.amountIn);

        // When: The vault claims nothing to the controller.
        vm.prank(asyncVault0);
        almCore.claimDepositRequest(controller, 0, 0, controller);

        // Then: The pending aLP is released and the shares escrowed, past the cap.
        assertEq(almCore.pendingShares_(controller), 0);
        assertEq(almCore.claimableSharesOf_(controller), credited);
    }

    function testFuzz_Success_claimDepositRequest_ToTheControllerAboveTheCap(
        PoolState memory poolState,
        uint128 claimableIn,
        uint96 claimableOut
    ) public {
        // Given: A pool at a fuzzed price, a settled deposit and a per user cap of zero.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        claimableIn = uint128(bound(claimableIn, 1, uint128(Constants.MAX_FUZZED_AMOUNT)));
        claimableOut = uint96(bound(claimableOut, 1, type(uint96).max));
        almCore.stageClaimableDeposit(asyncVault0, controller, claimableIn, claimableOut);
        vm.prank(factory);
        almCore.setPerUserCap(0);

        // When: The vault claims all of it to the controller.
        vm.prank(asyncVault0);
        almCore.claimDepositRequest(controller, claimableIn, claimableOut, controller);

        // Then: It is not checked.
        assertEq(almCore.balanceOf(controller), claimableOut);
    }

    function testFuzz_Success_claimDepositRequest_InWindowClaimableSharesCreditedToTheProtocol(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 window,
        uint256 accruedFor,
        uint256 emissions,
        uint256 assets,
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

        // And: A settled deposit of the controller.
        assets = bound(assets, 1, Constants.MAX_FUZZED_AMOUNT);
        shares = bound(shares, 1, coreState.supply);
        almCore.stageSettledDeposit(
            asyncVault0,
            controller,
            Record({ epoch: 0, amountIn: uint128(assets), pendingShares: 0 }),
            Epoch({ amountIn: uint128(assets), amountOut: uint128(shares) })
        );

        // And: Emissions the window hides, up to a block inside it, on a minting chain.
        emissions = bound(emissions, 1, Constants.MAX_EMISSIONS);
        accruedFor = bound(accruedFor, 1, window - 1);
        accrueForBlocks(pool, gauge, accruedFor, emissions);
        setMintableStatus(pick);
        uint256[] memory tokenIds = almCore.stakedTokenIds();
        uint256 hidden = hiddenEmissions(gauge, address(almCore), tokenIds);
        uint256 net = hidden - hidden * feeBps / ConfigLib.BPS_DENOMINATOR;
        uint256 supply = almCore.totalSupply();
        uint256 feesBefore = almCore.getProtocolFeesReward();

        // When: The vault claims the whole deposit to another account.
        vm.prank(asyncVault0);
        uint256 paid = almCore.claimDepositRequest(controller, assets, type(uint256).max, accountA);

        // Then: The settled shares were paid out.
        assertEq(paid, shares);
        assertEq(almCore.balanceOf(accountA), shares);
        assertEq(almCore.claimableSharesOf_(controller), 0);

        // And: The protocol is credited the claimed shares' part of the net emissions.
        assertEq(almCore.getProtocolFeesReward() - feesBefore, shares.fullMulDiv(net.fullMulDiv(1e18, supply), 1e18));
        assertEq(almCore.getPendingReward(controller), 0);

        // And: The claim's transfer pre-credited the hidden emissions, net of the fee.
        assertEq(almCore.getPreCredited(), net);
    }
}
