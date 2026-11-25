/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreExtension } from "../../utils/extensions/ALMCoreExtension.sol";
import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreViewLogic } from "../../../src/core/libraries/logic/ALMCoreViewLogic.sol";
import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { BaseHandler } from "./BaseHandler.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { Claimable, Epoch, Record } from "../../../src/core/types/State.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { ERC7540Operator } from "../../../src/vaults/abstracts/tokens/ERC7540Operator.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCore } from "../../../src/interfaces/IALMCore.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { ICLGauge } from "../../utils/fixtures/metadex/interfaces/ICLGauge.sol";
import { ICLGaugeFactory } from "../../utils/fixtures/metadex/interfaces/ICLGaugeFactory.sol";
import { ILeafVoter } from "../../utils/fixtures/metadex/interfaces/ILeafVoter.sol";
import { IMetadexCLPool } from "../../../src/interfaces/IMetadexCLPool.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { QueueLib } from "../../../src/core/libraries/state/QueueLib.sol";
import { ShareLib } from "../../../src/core/libraries/state/ShareLib.sol";
import { Snapshot, SnapshotLib } from "../../../src/vaults/types/Snapshot.sol";
import { VmSafe } from "@forge-std/Vm.sol";

/**
 * @notice Drives the share-holder facing surface of "ALMCore" for the invariant suite.
 */
// forge-lint: disable-next-item(calls-loop, uninitialized-local, unsafe-typecast, unused-return)
contract ALMCoreHandler is BaseHandler {
    using ALMCoreViewLogic for IALMCore;
    using ALMCoreViewLogic for bytes32[];
    using FixedPointMathLib for uint256;
    using SnapshotLib for IALMCore;
    using SnapshotLib for Snapshot;

    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The states of a controller's record in one queue.
    uint8 internal constant RECORD_NONE = 0;
    uint8 internal constant RECORD_PENDING = 1;
    uint8 internal constant RECORD_SETTLED = 2;

    // The kinds of action the request state machine classifies the last move by.
    uint8 public constant MOVE_OTHER = 0;
    uint8 public constant MOVE_REQUEST = 1;
    uint8 public constant MOVE_CANCEL = 2;
    uint8 public constant MOVE_CLAIM = 3;
    uint8 public constant MOVE_PLAN = 4;
    uint8 public constant MOVE_ANY = 5;

    /* //////////////////////////////////////////////////////////////
                                 STRUCTS
    ////////////////////////////////////////////////////////////// */

    // A controller's request in one queue: its record's state and epoch, and whether its claimable pile holds any.
    struct RequestState {
        uint8 record;
        bool claimable;
        uint32 epoch;
    }

    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    ALMCoreExtension internal immutable ALM_CORE;
    ERC20Mock internal immutable TOKEN0;
    ERC20Mock internal immutable TOKEN1;
    ALMVaultAsync internal immutable ASYNC_VAULT0;
    ALMVaultAsync internal immutable ASYNC_VAULT1;
    address internal immutable FACTORY;
    ICLGaugeFactory internal immutable GAUGE_FACTORY;
    // The holder of the gauge factory's penalty role.
    address internal immutable GAUGE_ADMIN;
    // The receiver of the seed's aLP.
    address internal immutable STEWARD;
    // The most liquidity the pool takes on one tick.
    uint256 internal immutable MAX_LIQUIDITY_PER_TICK;

    address[] internal actors;
    // The vaults an actor may approve an operator on.
    address[] internal vaults;
    address[] internal asyncVaults;

    uint256 public ghostSharesMinted;
    uint256 public ghostSharesBurned;
    uint256 public ghostRewardPaid;
    // The reward claims paid while the high water and the pre-credit were within what was claimed.
    uint256 public ghostBackedRewardPaid;
    uint256 public ghostPendingMoved;
    uint256 public ghostSkimmed0;
    uint256 public ghostSkimmed1;
    // The bystander credits compared across an action while they were non-zero.
    uint256 public ghostPendingWatched;
    // The mints that left the supply above the total cap.
    uint256 public ghostTotalCapBreaches;
    // The calls checked against the per user cap that left an account that is not exempt above it.
    uint256 public ghostUserCapBreaches;
    // The mints to an exempt account the per user cap turned away.
    uint256 public ghostExemptRefusals;
    // The mints and deposit requests a paused core or vault accepted.
    uint256 public ghostPausedAccepts;
    // The mints and withdraws after which the stayers' value per share fell.
    uint256 public ghostPerShareFalls;
    // The emission fee raises that left emissions earned at the gauge.
    uint256 public ghostRaisesLeavingEarned;
    // The hidden emissions, net of the protocol fee, the burns forfeited at most.
    uint256 public ghostForfeited;
    // The emission fee raises that went through.
    uint256 public ghostFeeRaises;
    // The actions after which the stored pre-credit was lower than before them.
    uint256 public ghostPreCreditDrops;
    // The state-changing core calls that went through.
    uint256 public ghostCheckpoints;
    // The burns that reverted.
    uint256 public ghostUnexpectedBurnReverts;
    // The accumulators, epoch ids and plan times seen falling between two actions.
    uint256 public ghostMonotoneBreaks;
    // The claims that paid more than their pro-rata part of the claimable pile.
    uint256 public ghostClaimBreaks;
    // The claims within the claimable views that reverted for a reason other than the receiver's cap or the caller.
    uint256 public ghostClaimRefusals;
    // The mints within maxMint that reverted while spot sat inside the band.
    uint256 public ghostMaxMintRefusals;
    // The claims that went through, by kind.
    uint256 public ghostOperatorCalls;
    uint256 public ghostAsyncMints;
    uint256 public ghostAsyncWithdraws;
    uint256 public ghostTransfersFrom;
    uint256 public ghostSpenderBurns;
    // The fair reward baselines set after a gauge config move or a protocol fee change.
    uint256 public ghostFairRebases;
    // The highest aLP supply seen after an action.
    uint256 public ghostMaxSupply;
    // The lifetime reward, net of the protocol fee and before the penalty, at the last fair reward update.
    uint256 internal lastLifetimeReward;

    // The values the monotonicity check saw after the last action.
    uint256 internal lastRewardPerShare;
    uint256 internal lastHighWater;
    uint256 internal lastClaimedCumulative;
    uint256 internal lastPlanAt;
    uint256 internal lastPreCredited;
    mapping(address vault => uint256 epoch) internal lastPendingDepositEpoch;
    mapping(address vault => uint256 epoch) internal lastPendingRedeemEpoch;
    mapping(address vault => uint256 epoch) internal lastHighestDepositEpoch;
    mapping(address vault => uint256 epoch) internal lastHighestRedeemEpoch;

    mapping(address actor => uint256 amount) public ghostRewardPaidOf;
    // The reward each actor earned on its reward balance for the blocks it held it.
    mapping(address actor => uint256 amount) public ghostFairRewardOf;

    uint256[] internal pendingBefore;

    // The requests, cancels and claims that went through from a caller without the authority over them.
    uint256 public ghostUnauthorizedAsyncAccepted;
    // The refusals of a caller without the authority that reverted for another reason than the missing authority.
    uint256 public ghostUnauthorizedWrongReasons;
    // The redeem requests, cancels and claims a pause turned away.
    uint256 public ghostPausedRefusals;
    // The protocol fee payouts that paid other than the booked fees, or to other than the recipient.
    uint256 public ghostFeePayoutBreaks;
    uint256 public ghostFeePayouts;
    // The emission claims that paid other than the reward owed before them while the reward balance covered it.
    uint256 public ghostOwedClaimBreaks;
    uint256 public ghostOwedClaimsChecked;
    // The request state moves that are not an edge of the request state machine.
    uint256 public ghostIllegalRequestMoves;
    // The settlements of an epoch already settled or still pending, and those whose epoch then held another amount.
    uint256 public ghostEpochResettles;
    uint256 public ghostSettlementEventMismatches;
    uint256 public ghostEpochsSettled;
    // The cancels tried on a settled, unclaimed record, and those that went through or reverted for another reason.
    uint256 public ghostSettledCancelsTried;
    uint256 public ghostSettledCancelBreaks;
    // The reward payouts above the reward balance the core held when it paid them.
    uint256 public ghostPayoutsAboveRewardBalance;
    // The aLP moves an unauthorised caller tried, and those that took an owner's aLP beyond the caller's allowance.
    uint256 public ghostUnauthorizedMovesTried;
    uint256 public ghostUnauthorizedMoves;

    // The last action's kind and the request it named, for the request state machine.
    uint8 internal move;
    address internal moveVault;
    bool internal moveIsDeposit;
    address internal moveController;
    mapping(address vault => mapping(bool isDeposit => mapping(address controller => RequestState state))) internal
        lastRequests;

    // The epochs a plan settled, with the amounts their settlement booked.
    mapping(address vault => mapping(bool isDeposit => mapping(uint32 epoch => bool settled))) public ghostEpochSettled;
    mapping(address vault => mapping(bool isDeposit => mapping(uint32 epoch => Epoch booked))) internal settledEpochs;
    mapping(address vault => mapping(bool isDeposit => bool settled)) public ghostQueueSettled;

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(
        ALMCoreExtension almCore,
        ERC20Mock token0,
        ERC20Mock token1,
        address[] memory actors_,
        address[] memory vaults_,
        address factory,
        address gaugeAdmin,
        address steward,
        uint256 maxLiquidityPerTick
    ) {
        ALM_CORE = almCore;
        TOKEN0 = token0;
        TOKEN1 = token1;
        ASYNC_VAULT0 = ALMVaultAsync(almCore.asyncVault_(address(token0)));
        ASYNC_VAULT1 = ALMVaultAsync(almCore.asyncVault_(address(token1)));
        FACTORY = factory;
        GAUGE_FACTORY = ICLGaugeFactory(almCore.GAUGE_FACTORY_());
        GAUGE_ADMIN = gaugeAdmin;
        STEWARD = steward;
        MAX_LIQUIDITY_PER_TICK = maxLiquidityPerTick;
        for (uint256 i; i < actors_.length; ++i) {
            actors.push(actors_[i]);
        }
        for (uint256 i; i < vaults_.length; ++i) {
            vaults.push(vaults_[i]);
        }
        asyncVaults.push(address(ASYNC_VAULT0));
        asyncVaults.push(address(ASYNC_VAULT1));
    }

    /* //////////////////////////////////////////////////////////////
                                 ACTIONS
    ////////////////////////////////////////////////////////////// */

    function mint(uint256 actorSeed, uint256 shares) external countCall(this.mint.selector) advanceBlock {
        address actor = actorAt(actorSeed);
        Snapshot memory snapshot = IALMCore(address(ALM_CORE)).getSnapshot(ALM_CORE.pool_(), address(this));
        (uint160 sqrtPriceX96,,,,,) = IMetadexCLPool(ALM_CORE.pool_()).slot0();
        {
            uint256 ceiling = IALMCore(address(ALM_CORE)).maxMint(actor);
            if (ceiling == 0) {
                (uint256 held0, uint256 held1) = _holdings(
                    snapshot.ranges, sqrtPriceX96, snapshot.buffer0 + snapshot.fees0, snapshot.buffer1 + snapshot.fees1
                );
                ceiling = snapshot.supply
                    .fullMulDiv(
                        Constants.MAX_FUZZED_AMOUNT, FixedPointMathLib.max(FixedPointMathLib.max(held0, held1), 1)
                    );
            }
            ceiling = boundByTickHeadroom(snapshot, ceiling);
            if (ceiling == 0) return;
            shares = bound(shares, 1, ceiling);
        }
        (uint256 cost0, uint256 cost1,) = snapshot.getMintAmounts(sqrtPriceX96, shares, true);
        TOKEN0.mint(actor, cost0);
        TOKEN1.mint(actor, cost1);

        _trackFairShares();
        _snapshotPending();
        (uint256 valueBefore, uint256 supplyBefore) = _valueAndSupply();
        bool paused = ALM_CORE.paused_();
        bool withinMax = shares <= IALMCore(address(ALM_CORE)).maxMint(actor) && _inBand();

        vm.startPrank(actor);
        TOKEN0.approve(address(ALM_CORE), type(uint256).max);
        TOKEN1.approve(address(ALM_CORE), type(uint256).max);
        try ALM_CORE.mint(shares, actor) {
            ghostCheckpoints++;
            ghostSharesMinted += shares;
            if (paused) ghostPausedAccepts++;
            if (ALM_CORE.totalSupply() > ALM_CORE.totalCap_()) ghostTotalCapBreaches++;
            _countCapBreach(actor);
            _countPerShareFall(valueBefore, supplyBefore);
        } catch (bytes memory reason) {
            _recordRevert(this.mint.selector, reason);
            if (ALM_CORE.isExempt_(actor) && _selectorOf(reason) == ShareLib.PerUserCapExceeded.selector) {
                ghostExemptRefusals++;
            }
            if (withinMax) ghostMaxMintRefusals++;
        }
        vm.stopPrank();

        _countPendingMoves(actor, actor);
    }

    function burn(uint256 ownerSeed, uint256 spenderSeed, uint256 receiverSeed, uint256 shares, uint256 path)
        external
        countCall(this.burn.selector)
        advanceBlock
    {
        address owner = actorAt(ownerSeed);
        address spender = actorAt(spenderSeed);
        address receiver = actorAt(receiverSeed);
        uint256 balance = ALM_CORE.balanceOf(owner);
        if (balance == 0) return;
        shares = bound(shares, 1, balance);
        path = bound(path, 0, 2);
        if (path == 0) spender = owner;
        else if (path == 1 && spender != owner) _approve(owner, spender, shares);
        else if (spender != owner) _setOperator(owner, spender, true, 0);

        _trackFairShares();
        _snapshotPending();
        (uint256 valueBefore, uint256 supplyBefore) = _valueAndSupply();
        uint256 forfeited = forfeitOf(hiddenEmissions(ALM_CORE.stakedTokenIds()));

        vm.prank(spender);
        try ALM_CORE.burn(shares, receiver, owner) {
            ghostCheckpoints++;
            ghostSharesBurned += shares;
            ghostForfeited += forfeited;
            if (spender != owner) ghostSpenderBurns++;
            _countPerShareFall(valueBefore, supplyBefore);
        } catch (bytes memory reason) {
            _recordRevert(this.burn.selector, reason);
            ghostUnexpectedBurnReverts++;
        }

        _countPendingMoves(owner, receiver);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 shares, bool viaAllowance)
        external
        countCall(this.transfer.selector)
        advanceBlock
    {
        address from = actorAt(fromSeed);
        address to = actorAt(toSeed);
        address spender = actorAt(spenderSeed);
        uint256 balance = ALM_CORE.balanceOf(from);
        if (balance == 0 || from == to) return;
        shares = bound(shares, 1, balance);
        if (viaAllowance && spender != from) _approve(from, spender, shares);
        _trackFairShares();
        _snapshotPending();

        if (viaAllowance && spender != from) {
            vm.prank(spender);
            try ALM_CORE.transferFrom(from, to, shares) {
                ghostCheckpoints++;
                ghostTransfersFrom++;
                _countCapBreach(to);
            } catch (bytes memory reason) {
                _recordRevert(this.transfer.selector, reason);
            }
        } else {
            vm.prank(from);
            try ALM_CORE.transfer(to, shares) {
                ghostCheckpoints++;
                _countCapBreach(to);
            } catch (bytes memory reason) {
                _recordRevert(this.transfer.selector, reason);
            }
        }

        _countPendingMoves(from, to);
    }

    function moveUnauthorized(uint256 ownerSeed, uint256 callerSeed, uint256 receiverSeed, uint256 shares, uint256 kind)
        external
        countCall(this.moveUnauthorized.selector)
        advanceBlock
    {
        address caller = actorAt(callerSeed);
        address receiver = actorAt(receiverSeed);
        address owner;
        uint256 balance;
        uint256 allowance;
        for (uint256 i; i < actors.length; ++i) {
            owner = actors[(ownerSeed % actors.length + i) % actors.length];
            (balance, allowance) = (ALM_CORE.balanceOf(owner), ALM_CORE.allowance(owner, caller));
            if (owner != caller && !IALMCore(address(ALM_CORE)).isOperator(owner, caller) && balance > allowance) {
                break;
            }
            balance = 0;
        }
        if (balance == 0) return;
        shares = bound(shares, allowance + 1, balance);
        kind = bound(kind, 0, 4);
        address vault = vaults[kind == 4 ? 2 + shares % 2 : shares % 2];
        bytes memory data;
        if (kind == 0) {
            data = abi.encodeCall(ERC20.transferFrom, (owner, receiver, shares));
        } else if (kind == 1) {
            data = abi.encodeCall(ALM_CORE.burn, (shares, receiver, owner));
        } else if (kind == 2) {
            data = abi.encodeWithSignature("redeem(uint256,address,address)", shares, receiver, owner);
        } else if (kind == 4) {
            data = abi.encodeCall(ALMVaultAsync.requestRedeem, (shares, receiver, owner));
        } else {
            (bool previewed, bytes memory result) =
                vault.staticcall(abi.encodeWithSignature("previewRedeem(uint256)", shares));
            if (!previewed) return;
            data = abi.encodeWithSignature(
                "withdraw(uint256,address,address)",
                FixedPointMathLib.max(abi.decode(result, (uint256)), 1),
                receiver,
                owner
            );
        }
        ghostUnauthorizedMovesTried++;
        _trackFairShares();
        _snapshotPending();
        uint256 forfeited = forfeitOf(hiddenEmissions(ALM_CORE.stakedTokenIds()));

        vm.prank(caller);
        (bool success, bytes memory reason) = (kind < 2 ? address(ALM_CORE) : vault).call(data);
        if (success) {
            uint256 moved = balance - ALM_CORE.balanceOf(owner);
            if (moved > allowance) ghostUnauthorizedMoves++;
            ghostCheckpoints++;
            ghostSharesBurned += moved;
            ghostForfeited += forfeited;
        } else {
            _recordRevert(this.moveUnauthorized.selector, reason);
        }

        _countPendingMoves(owner, receiver);
    }

    function claimEmissions(uint256 holderSeed, uint256 blocksPassed)
        external
        countCall(this.claimEmissions.selector)
        advanceBlock
    {
        address holder = holderAt(holderSeed);
        vm.roll(vm.getBlockNumber() + bound(blocksPassed, 1, GAUGE_FACTORY.minStakeBlocks(ALM_CORE.gauge()) + 1));
        _trackFairShares();
        _snapshotPending();
        uint256 owed = holder == address(ALM_CORE) ? 0 : IALMCore(address(ALM_CORE)).getRewardOwed(holder);

        try ALM_CORE.claimEmissions(holder) returns (uint256 amount) {
            ghostCheckpoints++;
            _countPayoutAboveRewardBalance(amount);
            ghostRewardPaid += amount;
            ghostRewardPaidOf[holder] += amount;
            if (ALM_CORE.getRewardHighWater() + ALM_CORE.getPreCredited() <= ALM_CORE.getClaimedCumulative()) {
                ghostBackedRewardPaid += amount;
            }
            if (holder != address(ALM_CORE)) {
                ghostOwedClaimsChecked++;
                if (amount > owed || (amount < owed && ALM_CORE.getLastRewardBalance() != 0)) ghostOwedClaimBreaks++;
            }
        } catch (bytes memory reason) {
            _recordRevert(this.claimEmissions.selector, reason);
        }

        _countPendingMoves(holder, holder);
    }

    function skim() external countCall(this.skim.selector) advanceBlock {
        _trackFairShares();
        _snapshotPending();

        (uint256 fees0, uint256 fees1) = (ALM_CORE.getProtocolFees0(), ALM_CORE.getProtocolFees1());
        try ALM_CORE.skim() {
            ghostCheckpoints++;
            ghostSkimmed0 += ALM_CORE.getProtocolFees0() - fees0;
            ghostSkimmed1 += ALM_CORE.getProtocolFees1() - fees1;
        } catch (bytes memory reason) {
            _recordRevert(this.skim.selector, reason);
        }

        _countPendingMoves(address(0), address(0));
    }

    function setOperator(uint256 controllerSeed, uint256 operatorSeed, uint256 vaultSeed, bool approved)
        external
        countCall(this.setOperator.selector)
        advanceBlock
    {
        address controller = actorAt(controllerSeed);
        address operator = actorAt(operatorSeed);
        _setOperator(controller, operator, approved, vaultSeed);
        if (IALMCore(address(ALM_CORE)).isOperator(controller, operator) != approved) ghostMonotoneBreaks++;
    }

    function requestDeposit(
        uint256 ownerSeed,
        uint256 controllerSeed,
        uint256 callerSeed,
        uint256 assets,
        bool isToken0
    ) external countCall(this.requestDeposit.selector) advanceBlock {
        address owner = actorAt(ownerSeed);
        address controller = actorAt(controllerSeed);
        address caller = actorAt(callerSeed);
        ALMVaultAsync vault = isToken0 ? ASYNC_VAULT0 : ASYNC_VAULT1;
        ERC20Mock asset = isToken0 ? TOKEN0 : TOKEN1;
        {
            uint256 ceiling = maxRequestAssets(controller, isToken0);
            assets = bound(assets, 1, ceiling == 0 ? Constants.MAX_FUZZED_AMOUNT : ceiling);
        }
        asset.mint(owner, assets);
        vm.prank(owner);
        asset.approve(address(vault), assets);
        bool paused = BaseVault(address(vault)).paused();
        bool authorized = caller == owner || IALMCore(address(ALM_CORE)).isOperator(owner, caller);

        _trackFairShares();
        _snapshotPending();

        vm.prank(caller);
        try vault.requestDeposit(assets, controller, owner) {
            ghostCheckpoints++;
            if (caller != owner) ghostOperatorCalls++;
            if (paused) ghostPausedAccepts++;
            if (!authorized) ghostUnauthorizedAsyncAccepted++;
            _countCapBreach(controller);
            _noteMove(MOVE_REQUEST, address(vault), true, controller);
        } catch (bytes memory reason) {
            _recordRevert(this.requestDeposit.selector, reason);
            bytes4 selector = _selectorOf(reason);
            if (!authorized && selector != ERC7540Operator.Unauthorized.selector) {
                if (!paused || selector != BaseVault.Paused.selector) ghostUnauthorizedWrongReasons++;
            }
        }

        _countPendingMoves(owner, controller);
    }

    function requestRedeem(
        uint256 ownerSeed,
        uint256 controllerSeed,
        uint256 callerSeed,
        uint256 shares,
        bool isToken0,
        bool viaAllowance
    ) external countCall(this.requestRedeem.selector) advanceBlock {
        address owner = actorAt(ownerSeed);
        address controller = actorAt(controllerSeed);
        address caller = actorAt(callerSeed);
        uint256 balance = ALM_CORE.balanceOf(owner);
        if (balance == 0) return;
        shares = bound(shares, 1, balance);
        ALMVaultAsync vault = isToken0 ? ASYNC_VAULT0 : ASYNC_VAULT1;
        if (viaAllowance && caller != owner) _approve(owner, caller, shares);
        bool authorized = caller == owner || IALMCore(address(ALM_CORE)).isOperator(owner, caller)
            || ALM_CORE.allowance(owner, caller) >= shares;

        _trackFairShares();
        _snapshotPending();

        vm.prank(caller);
        try vault.requestRedeem(shares, controller, owner) {
            ghostCheckpoints++;
            if (caller != owner) ghostOperatorCalls++;
            if (!authorized) ghostUnauthorizedAsyncAccepted++;
            if (owner != controller) _countCapBreach(controller);
            _noteMove(MOVE_REQUEST, address(vault), false, controller);
        } catch (bytes memory reason) {
            _recordRevert(this.requestRedeem.selector, reason);
            _countPausedRefusal(reason);
            if (!authorized && _selectorOf(reason) != ERC20.InsufficientAllowance.selector) {
                ghostUnauthorizedWrongReasons++;
            }
        }

        _countPendingMoves(owner, controller);
    }

    function cancel(uint256 controllerSeed, uint256 receiverSeed, uint256 callerSeed, bool isRedeem, bool isToken0)
        external
        countCall(this.cancel.selector)
        advanceBlock
    {
        address controller = actorAt(controllerSeed);
        address receiver = actorAt(receiverSeed);
        address caller = actorAt(callerSeed);
        ALMVaultAsync vault = isToken0 ? ASYNC_VAULT0 : ASYNC_VAULT1;
        uint256 pending =
            isRedeem ? vault.pendingRedeemRequest(0, controller) : vault.pendingDepositRequest(0, controller);
        Record memory record = isRedeem
            ? ALM_CORE.redeemRecord(address(vault), controller)
            : ALM_CORE.depositRecord(address(vault), controller);
        bool settled = pending == 0 && record.amountIn != 0;
        if (pending == 0 && !settled) return;
        bool authorized = _isAuthorized(caller, controller);
        if (settled) ghostSettledCancelsTried++;
        _trackFairShares();
        _snapshotPending();

        vm.prank(caller);
        (bool success, bytes memory reason) = address(vault)
            .call(
                isRedeem
                    ? abi.encodeCall(ALMVaultAsync.cancelRedeemRequest, (0, controller, receiver))
                    : abi.encodeCall(ALMVaultAsync.cancelDepositRequest, (0, controller, receiver))
            );
        if (success) {
            ghostCheckpoints++;
            if (settled) ghostSettledCancelBreaks++;
            if (caller != controller) ghostOperatorCalls++;
            if (isRedeem && receiver != controller) _countCapBreach(receiver);
            _countUnauthorizedAccept(authorized);
            _noteMove(MOVE_CANCEL, address(vault), !isRedeem, controller);
        } else {
            _recordRevert(this.cancel.selector, reason);
            if (!settled) {
                _countClaimRefusal(reason, authorized, controller, receiver);
            } else if (
                _selectorOf(reason)
                    != (authorized ? QueueLib.RequestNotPending.selector : ERC7540Operator.Unauthorized.selector)
            ) {
                ghostSettledCancelBreaks++;
            }
        }

        _countPendingMoves(controller, receiver);
    }

    function claimDepositRequest(
        uint256 controllerSeed,
        uint256 receiverSeed,
        uint256 callerSeed,
        uint256 amount,
        uint256 kind,
        bool isToken0
    ) external countCall(this.claimDepositRequest.selector) advanceBlock {
        address controller = actorAt(controllerSeed);
        address receiver = actorAt(receiverSeed);
        address caller = actorAt(callerSeed);
        ALMVaultAsync vault = isToken0 ? ASYNC_VAULT0 : ASYNC_VAULT1;
        (uint256 claimableIn, uint256 claimableOut) =
            IALMCore(address(ALM_CORE)).getClaimableDeposit(address(vault), controller);
        kind = bound(kind, 0, 3);
        if (kind >= 2) caller = controller;
        {
            uint256 ceiling = kind % 2 == 1 ? vault.maxMint(controller) : vault.maxDeposit(controller);
            if (ceiling == 0) return;
            amount = bound(amount, 1, ceiling);
        }
        bool authorized = _isAuthorized(caller, controller);
        _trackFairShares();
        _snapshotPending();
        uint256 balanceBefore = ALM_CORE.balanceOf(receiver);

        bytes memory data = kind == 0
            ? abi.encodeWithSignature("deposit(uint256,address,address)", amount, receiver, controller)
            : kind == 1
                ? abi.encodeWithSignature("mint(uint256,address,address)", amount, receiver, controller)
                : kind == 2
                    ? abi.encodeWithSignature("deposit(uint256,address)", amount, receiver)
                    : abi.encodeWithSignature("mint(uint256,address)", amount, receiver);
        vm.prank(caller);
        (bool success, bytes memory reason) = address(vault).call(data);
        if (success) {
            ghostCheckpoints++;
            if (caller != controller) ghostOperatorCalls++;
            if (kind % 2 == 1) ghostAsyncMints++;
            if (receiver != controller) _countCapBreach(receiver);
            (uint256 claimableInAfter,) = IALMCore(address(ALM_CORE)).getClaimableDeposit(address(vault), controller);
            uint256 sharesOut = ALM_CORE.balanceOf(receiver) - balanceBefore;
            if (claimableIn != 0 && sharesOut > (claimableIn - claimableInAfter).fullMulDiv(claimableOut, claimableIn))
            {
                ghostClaimBreaks++;
            }
            _countUnauthorizedAccept(authorized);
        } else {
            _recordRevert(this.claimDepositRequest.selector, reason);
            _countClaimRefusal(reason, authorized, controller, receiver);
        }
        if (success) _noteMove(MOVE_CLAIM, address(vault), true, controller);

        _countPendingMoves(controller, receiver);
    }

    function claimRedeemRequest(
        uint256 controllerSeed,
        uint256 receiverSeed,
        uint256 callerSeed,
        uint256 amount,
        bool byAssets,
        bool isToken0
    ) external countCall(this.claimRedeemRequest.selector) advanceBlock {
        address controller = actorAt(controllerSeed);
        address receiver = actorAt(receiverSeed);
        address caller = actorAt(callerSeed);
        ALMVaultAsync vault = isToken0 ? ASYNC_VAULT0 : ASYNC_VAULT1;
        ERC20Mock asset = isToken0 ? TOKEN0 : TOKEN1;
        (uint256 claimableAssets, uint256 claimableShares) =
            IALMCore(address(ALM_CORE)).getClaimableRedeem(address(vault), controller);
        {
            uint256 ceiling = byAssets ? vault.maxWithdraw(controller) : vault.maxRedeem(controller);
            if (ceiling == 0) return;
            amount = bound(amount, 1, ceiling);
        }
        bool authorized = _isAuthorized(caller, controller);
        _trackFairShares();
        _snapshotPending();
        uint256 balanceBefore = asset.balanceOf(receiver);

        bytes memory data = byAssets
            ? abi.encodeCall(ALMVaultAsync.withdraw, (amount, receiver, controller))
            : abi.encodeCall(ALMVaultAsync.redeem, (amount, receiver, controller));
        vm.prank(caller);
        (bool success, bytes memory reason) = address(vault).call(data);
        if (success) {
            ghostCheckpoints++;
            if (caller != controller) ghostOperatorCalls++;
            if (byAssets) ghostAsyncWithdraws++;
            (, uint256 claimableSharesAfter) =
                IALMCore(address(ALM_CORE)).getClaimableRedeem(address(vault), controller);
            uint256 assetsOut = asset.balanceOf(receiver) - balanceBefore;
            if (
                claimableShares != 0
                    && assetsOut > (claimableShares - claimableSharesAfter).fullMulDiv(claimableAssets, claimableShares)
            ) {
                ghostClaimBreaks++;
            }
            _countUnauthorizedAccept(authorized);
        } else {
            _recordRevert(this.claimRedeemRequest.selector, reason);
            _countClaimRefusal(reason, authorized, controller, receiver);
        }
        if (success) _noteMove(MOVE_CLAIM, address(vault), false, controller);

        _countPendingMoves(controller, receiver);
    }

    function payProtocolFees() external countCall(this.payProtocolFees.selector) advanceBlock {
        _trackFairShares();
        _snapshotPending();
        address recipient = ALM_CORE.feeRecipient_();
        uint256[3] memory booked =
            [ALM_CORE.getProtocolFees0(), ALM_CORE.getProtocolFees1(), ALM_CORE.getProtocolFeesReward()];
        uint256 rewardBalance = ALM_CORE.getLastRewardBalance();
        uint256[3] memory balances = _balancesOf(recipient);

        try ALM_CORE.payProtocolFees() returns (uint256 amount0, uint256 amount1, uint256 amountReward) {
            ghostCheckpoints++;
            _countPayoutAboveRewardBalance(amountReward);
            ghostFeePayouts++;
            if (amount0 != booked[0] || amount1 != booked[1] || ALM_CORE.getProtocolFees0() != 0) {
                ghostFeePayoutBreaks++;
            }
            if (ALM_CORE.getProtocolFees1() != 0 || amountReward < FixedPointMathLib.min(booked[2], rewardBalance)) {
                ghostFeePayoutBreaks++;
            }
            if (ALM_CORE.getProtocolFeesReward() != 0 && ALM_CORE.getLastRewardBalance() != 0) ghostFeePayoutBreaks++;
            uint256[3] memory received = _balancesOf(recipient);
            address rewardToken = ALM_CORE.REWARD_TOKEN_();
            if (rewardToken == address(TOKEN0)) amount0 += amountReward;
            else if (rewardToken == address(TOKEN1)) amount1 += amountReward;
            else if (received[2] != balances[2] + amountReward) ghostFeePayoutBreaks++;
            if (received[0] != balances[0] + amount0 || received[1] != balances[1] + amount1) ghostFeePayoutBreaks++;
        } catch (bytes memory reason) {
            _recordRevert(this.payProtocolFees.selector, reason);
        }

        _countPendingMoves(address(0), address(0));
    }

    function setProtocolFees(uint16 protocolEmissionFeeBps, uint16 protocolSwapFeeBps, uint256 recipientSeed)
        external
        countCall(this.setProtocolFees.selector)
        advanceBlock
    {
        uint256 maxFeeBps = ALM_CORE.MAX_FEE_BPS_();
        protocolEmissionFeeBps = uint16(bound(protocolEmissionFeeBps, 0, maxFeeBps));
        protocolSwapFeeBps = uint16(bound(protocolSwapFeeBps, 0, maxFeeBps));
        address recipient = recipientSeed % 2 == 0 ? ALM_CORE.feeRecipient_() : actorAt(recipientSeed);
        uint256 bpsBefore = ALM_CORE.protocolEmissionFeeBps_();
        bool raise = protocolEmissionFeeBps > bpsBefore;
        _trackFairShares();
        _snapshotPending();

        vm.prank(FACTORY);
        try ALM_CORE.setProtocolFees(protocolEmissionFeeBps, protocolSwapFeeBps, recipient) {
            ghostCheckpoints++;
            if (raise) {
                if (ICLGauge(ALM_CORE.gauge()).earned(address(ALM_CORE)) > 0) ghostRaisesLeavingEarned++;
                ghostFeeRaises++;
            }
            _rebaseFairShares();
        } catch (bytes memory reason) {
            _recordRevert(this.setProtocolFees.selector, reason);
        }

        _countPendingMoves(address(0), address(0));
    }

    /* //////////////////////////////////////////////////////////////
                                  HOOKS
    ////////////////////////////////////////////////////////////// */

    function watchPending() external {
        _snapshotPending();
    }

    function trackFairShares() external {
        _trackFairShares();
    }

    function rebaseFairShares() external {
        _rebaseFairShares();
    }

    function countPendingMoves(address acting, address counterparty) external {
        _countPendingMoves(acting, counterparty);
    }

    function countCapBreach(address account) external {
        _countCapBreach(account);
    }

    function checkMonotone() external {
        _checkMonotone();
    }

    function noteMove(uint8 kind) external {
        _noteMove(kind, address(0), false, address(0));
    }

    function noteSettlements(VmSafe.Log[] memory logs) external {
        for (uint256 i; i < logs.length; ++i) {
            bytes32 topic = logs[i].topics.length == 0 ? bytes32(0) : logs[i].topics[0];
            bool isDeposit = topic == IALMCoreEvents.DepositEpochSettled.selector;
            if (logs[i].emitter != address(ALM_CORE)) continue;
            if (!isDeposit && topic != IALMCoreEvents.RedeemEpochSettled.selector) continue;
            address vault = address(uint160(uint256(logs[i].topics[1])));
            uint32 epoch = uint32(uint256(logs[i].topics[2]));
            (uint256 assets, uint256 shares) = abi.decode(logs[i].data, (uint256, uint256));
            Epoch memory booked = isDeposit
                ? Epoch({ amountIn: uint128(assets), amountOut: uint128(shares) })
                : Epoch({ amountIn: uint128(shares), amountOut: uint128(assets) });
            _noteSettlement(vault, isDeposit, epoch, booked);
        }
    }

    function _afterAction() internal override {
        _checkMonotone();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function _approve(address owner, address spender, uint256 shares) internal {
        vm.prank(owner);
        ALM_CORE.approve(spender, shares);
    }

    function _setOperator(address controller, address operator, bool approved, uint256 vaultSeed) internal {
        vm.prank(controller);
        ERC7540Operator(vaults[bound(vaultSeed, 0, vaults.length - 1)]).setOperator(operator, approved);
    }

    function _countClaimRefusal(bytes memory reason, bool authorized, address controller, address receiver) internal {
        _countPausedRefusal(reason);
        bytes4 selector = _selectorOf(reason);
        if (!authorized) {
            if (selector != ERC7540Operator.Unauthorized.selector) ghostUnauthorizedWrongReasons++;
            return;
        }
        if (selector == ShareLib.PerUserCapExceeded.selector && receiver != controller) return;
        ghostClaimRefusals++;
    }

    function _countPayoutAboveRewardBalance(uint256 amount) internal {
        address rewardToken = ALM_CORE.REWARD_TOKEN_();
        uint256 reserve;
        if (rewardToken == address(TOKEN0)) {
            reserve = ALM_CORE.bufferAmount0() + ALM_CORE.getProtocolFees0() + ALM_CORE.getEscrowed0();
        } else if (rewardToken == address(TOKEN1)) {
            reserve = ALM_CORE.bufferAmount1() + ALM_CORE.getProtocolFees1() + ALM_CORE.getEscrowed1();
        }
        // The reward balance at the payout is what the core held then outside the pool token reserve.
        if (amount + reserve > ERC20Mock(rewardToken).balanceOf(address(ALM_CORE)) + amount) {
            ghostPayoutsAboveRewardBalance++;
        }
    }

    function _countPausedRefusal(bytes memory reason) internal {
        if (_selectorOf(reason) == BaseVault.Paused.selector) ghostPausedRefusals++;
    }

    function _countUnauthorizedAccept(bool authorized) internal {
        if (!authorized) ghostUnauthorizedAsyncAccepted++;
    }

    function _isAuthorized(address caller, address controller) internal view returns (bool authorized) {
        authorized = caller == controller || IALMCore(address(ALM_CORE)).isOperator(controller, caller);
    }

    function _balancesOf(address account) internal view returns (uint256[3] memory balances) {
        balances = [
            TOKEN0.balanceOf(account), TOKEN1.balanceOf(account), ERC20Mock(ALM_CORE.REWARD_TOKEN_()).balanceOf(account)
        ];
    }

    function _noteMove(uint8 kind, address vault, bool isDeposit, address controller) internal {
        (move, moveVault, moveIsDeposit, moveController) = (kind, vault, isDeposit, controller);
    }

    function _noteSettlement(address vault, bool isDeposit, uint32 epoch, Epoch memory booked) internal {
        ghostEpochsSettled++;
        (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = ALM_CORE.pendingEpochs(vault);
        if (ghostEpochSettled[vault][isDeposit][epoch]) ghostEpochResettles++;
        if (epoch == (isDeposit ? pendingDepositEpoch : pendingRedeemEpoch)) ghostEpochResettles++;
        Epoch memory stored = isDeposit ? ALM_CORE.depositEpoch(vault, epoch) : ALM_CORE.redeemEpoch(vault, epoch);
        if (stored.amountIn != booked.amountIn || stored.amountOut != booked.amountOut) {
            ghostSettlementEventMismatches++;
        }
        ghostEpochSettled[vault][isDeposit][epoch] = true;
        ghostQueueSettled[vault][isDeposit] = true;
        settledEpochs[vault][isDeposit][epoch] = booked;
    }

    function _checkRequests() internal {
        for (uint256 q; q < 2 * asyncVaults.length; ++q) {
            address vault = asyncVaults[q / 2];
            bool isDeposit = q % 2 == 0;
            for (uint256 i; i < actors.length; ++i) {
                RequestState memory before = lastRequests[vault][isDeposit][actors[i]];
                RequestState memory state = requestState(vault, isDeposit, actors[i]);
                bool target = vault == moveVault && isDeposit == moveIsDeposit && actors[i] == moveController;
                uint8 kind = target || move == MOVE_PLAN || move == MOVE_ANY ? move : MOVE_OTHER;
                if (!_isLegalRequestMove(kind, before, state)) ghostIllegalRequestMoves++;
                if (state.record == RECORD_SETTLED && !ghostEpochSettled[vault][isDeposit][state.epoch]) {
                    ghostIllegalRequestMoves++;
                }
                lastRequests[vault][isDeposit][actors[i]] = state;
            }
        }
        _noteMove(MOVE_OTHER, address(0), false, address(0));
    }

    function _isLegalRequestMove(uint8 kind, RequestState memory before, RequestState memory state)
        internal
        pure
        returns (bool legal)
    {
        bool sameClaimable = state.claimable == before.claimable;
        bool sameEpoch = state.epoch == before.epoch;
        if (kind == MOVE_ANY) return true;
        if (kind == MOVE_OTHER) return state.record == before.record && sameClaimable && sameEpoch;
        if (kind == MOVE_PLAN) {
            if (!sameClaimable) return false;
            if (before.record == RECORD_NONE) return state.record == RECORD_NONE;
            if (before.record == RECORD_SETTLED) return state.record == RECORD_SETTLED && sameEpoch;
            return state.record != RECORD_PENDING || sameEpoch;
        }
        if (kind == MOVE_REQUEST) {
            return state.record == RECORD_PENDING && (before.record != RECORD_PENDING || sameEpoch)
                && (sameClaimable || (before.record == RECORD_SETTLED && state.claimable));
        }
        if (kind == MOVE_CANCEL) {
            return before.record == RECORD_PENDING && state.record == RECORD_NONE && sameClaimable;
        }
        if (!before.claimable && before.record != RECORD_SETTLED) return false;
        legal =
            before.record == RECORD_SETTLED ? state.record == RECORD_NONE : state.record == before.record && sameEpoch;
    }

    function requestState(address vault, bool isDeposit, address controller)
        public
        view
        returns (RequestState memory state)
    {
        (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = ALM_CORE.pendingEpochs(vault);
        Record memory record =
            isDeposit ? ALM_CORE.depositRecord(vault, controller) : ALM_CORE.redeemRecord(vault, controller);
        Claimable memory claimable =
            isDeposit ? ALM_CORE.claimableDeposit(vault, controller) : ALM_CORE.claimableRedeem(vault, controller);
        state.epoch = record.epoch;
        state.claimable = claimable.amountIn != 0 || claimable.amountOut != 0;
        if (record.amountIn == 0) return state;
        state.record =
            record.epoch == (isDeposit ? pendingDepositEpoch : pendingRedeemEpoch) ? RECORD_PENDING : RECORD_SETTLED;
    }

    function settledEpoch(address vault, bool isDeposit, uint32 epoch) external view returns (Epoch memory booked) {
        booked = settledEpochs[vault][isDeposit][epoch];
    }

    function _checkMonotone() internal {
        uint256 rewardPerShare = ALM_CORE.rewardPerShare_();
        uint256 highWater = ALM_CORE.getRewardHighWater();
        uint256 claimedCumulative = ALM_CORE.getClaimedCumulative();
        uint256 planAt = ALM_CORE.lastPlanAt_();
        if (
            rewardPerShare < lastRewardPerShare || highWater < lastHighWater
                || claimedCumulative < lastClaimedCumulative || planAt < lastPlanAt
        ) ghostMonotoneBreaks++;
        (lastRewardPerShare, lastHighWater, lastClaimedCumulative, lastPlanAt) =
        (rewardPerShare, highWater, claimedCumulative, planAt);
        uint256 preCredited = ALM_CORE.getPreCredited();
        if (preCredited < lastPreCredited) ghostPreCreditDrops++;
        lastPreCredited = preCredited;
        _checkQueues(address(ASYNC_VAULT0));
        _checkQueues(address(ASYNC_VAULT1));
        _checkRequests();
        ghostMaxSupply = FixedPointMathLib.max(ghostMaxSupply, ALM_CORE.totalSupply());
    }

    function _checkQueues(address vault) internal {
        (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = ALM_CORE.pendingEpochs(vault);
        (uint32 lastClearedDepositEpoch, uint32 lastClearedRedeemEpoch) = ALM_CORE.lastClearedEpochs(vault);
        uint256 highestDepositEpoch = FixedPointMathLib.max(pendingDepositEpoch, lastClearedDepositEpoch);
        uint256 highestRedeemEpoch = FixedPointMathLib.max(pendingRedeemEpoch, lastClearedRedeemEpoch);
        if (
            pendingDepositEpoch < lastPendingDepositEpoch[vault] || pendingRedeemEpoch < lastPendingRedeemEpoch[vault]
                || highestDepositEpoch < lastHighestDepositEpoch[vault]
                || highestRedeemEpoch < lastHighestRedeemEpoch[vault]
        ) ghostMonotoneBreaks++;
        (lastPendingDepositEpoch[vault], lastPendingRedeemEpoch[vault]) = (pendingDepositEpoch, pendingRedeemEpoch);
        (lastHighestDepositEpoch[vault], lastHighestRedeemEpoch[vault]) = (highestDepositEpoch, highestRedeemEpoch);
    }

    function _snapshotPending() internal {
        delete pendingBefore;
        for (uint256 i; i < actors.length; ++i) {
            pendingBefore.push(ALM_CORE.getPendingReward(actors[i]));
        }
    }

    function _countPendingMoves(address acting, address counterparty) internal {
        for (uint256 i; i < actors.length; ++i) {
            if (actors[i] == acting || actors[i] == counterparty) continue;
            if (pendingBefore[i] != 0) ghostPendingWatched++;
            if (ALM_CORE.getPendingReward(actors[i]) != pendingBefore[i]) ghostPendingMoved++;
        }
    }

    function _countCapBreach(address account) internal {
        if (ALM_CORE.isExempt_(account) || account == address(ALM_CORE)) return;
        uint256 capBalance =
            ALM_CORE.balanceOf(account) + ALM_CORE.claimableSharesOf_(account) + ALM_CORE.pendingShares_(account);
        if (capBalance > ALM_CORE.perUserCap_()) ghostUserCapBreaches++;
    }

    function _countPerShareFall(uint256 valueBefore, uint256 supplyBefore) internal {
        (uint256 valueAfter, uint256 supplyAfter) = _valueAndSupply();
        (uint160 sqrtPriceX96,,,,,) = IMetadexCLPool(ALM_CORE.pool_()).slot0();
        uint256 tolerance = ALM_CORE.getRangesLength() * (2 + CLMath.convert(sqrtPriceX96, true, 1, false)) + 1;
        if ((valueAfter + tolerance).fullMulDiv(supplyBefore, supplyAfter) < valueBefore) ghostPerShareFalls++;
    }

    function _valueAndSupply() internal view returns (uint256 value, uint256 supply) {
        (uint160 sqrtPriceX96,,,,,) = IMetadexCLPool(ALM_CORE.pool_()).slot0();
        Snapshot memory snapshot = IALMCore(address(ALM_CORE)).getSnapshot(ALM_CORE.pool_(), address(this));
        (uint256 amount0, uint256 amount1) = _holdings(
            snapshot.ranges, sqrtPriceX96, snapshot.buffer0 + snapshot.fees0, snapshot.buffer1 + snapshot.fees1
        );
        value = amount1 + CLMath.convert(sqrtPriceX96, true, amount0, false);
        supply = snapshot.supply;
    }

    function _inBand() internal view returns (bool inside) {
        (uint160 sqrtPriceX96,,,,,) = IMetadexCLPool(ALM_CORE.pool_()).slot0();
        (uint256 sqrtPriceLowerX96, uint256 sqrtPriceUpperX96) =
            CLMath.getBand(ALM_CORE.meanSqrtPriceX96_(), ALM_CORE.maxSpotFromTwap_());
        inside = sqrtPriceX96 >= sqrtPriceLowerX96 && sqrtPriceX96 <= sqrtPriceUpperX96;
    }

    function actorsLength() external view returns (uint256 length) {
        length = actors.length;
    }

    function actorAt(uint256 seed) public view returns (address actor) {
        actor = actors[bound(seed, 0, actors.length - 1)];
    }

    function maxRequestAssets(address controller, bool isToken0) public view returns (uint256 assets) {
        if (ALM_CORE.isExempt_(controller)) return Constants.MAX_FUZZED_AMOUNT;
        uint256 capBalance = ALM_CORE.balanceOf(controller) + ALM_CORE.claimableSharesOf_(controller)
            + ALM_CORE.pendingShares_(controller);
        uint256 perUserCap = ALM_CORE.perUserCap_();
        if (capBalance >= perUserCap) return 0;
        assets = requestAssetsFor(perUserCap - capBalance, isToken0);
    }

    function requestAssetsFor(uint256 shares, bool isToken0) public view returns (uint256 assets) {
        (uint256 supplyPerValueX128, uint160 lastSqrtPriceX96) = ALM_CORE.lastExchangeRate_();
        if (lastSqrtPriceX96 == 0) return 0;
        (uint160 sqrtPriceX96,,,,,) = IMetadexCLPool(ALM_CORE.pool_()).slot0();
        // The most assets whose value, rounded up at each step, is at most the value of the shares.
        uint256 value = shares.fullMulDiv(1 << 128, supplyPerValueX128);
        if (isToken0) {
            uint256 upper = FixedPointMathLib.max(sqrtPriceX96, lastSqrtPriceX96);
            assets = value.fullMulDiv(1 << 96, upper).fullMulDiv(1 << 96, upper);
        } else {
            assets = sqrtPriceX96 >= lastSqrtPriceX96
                ? value
                : value.fullMulDiv(sqrtPriceX96, lastSqrtPriceX96).fullMulDiv(sqrtPriceX96, lastSqrtPriceX96);
        }
    }

    function boundByTickHeadroom(Snapshot memory snapshot, uint256 shares) public view returns (uint256 bounded) {
        Range[] memory ranges = IALMCore(address(ALM_CORE)).readRangeWords().decodeRanges();
        bounded = shares;
        for (uint256 i; i < ranges.length; ++i) {
            uint256 liquidity = snapshot.ranges[i].liquidity;
            if (liquidity == 0) continue;
            (uint128 grossLower,,,,,,,,,) = IMetadexCLPool(ALM_CORE.pool_()).ticks(ranges[i].tickLower);
            (uint128 grossUpper,,,,,,,,,) = IMetadexCLPool(ALM_CORE.pool_()).ticks(ranges[i].tickUpper);
            uint256 headroom = MAX_LIQUIDITY_PER_TICK - FixedPointMathLib.max(grossLower, grossUpper);
            bounded = FixedPointMathLib.min(bounded, snapshot.supply.fullMulDiv(headroom, liquidity));
        }
    }

    function asyncVaultsLength() external view returns (uint256 length) {
        length = asyncVaults.length;
    }

    function asyncVaultAt(uint256 seed) public view returns (address vault) {
        vault = asyncVaults[bound(seed, 0, asyncVaults.length - 1)];
    }

    function creditedAndAccrued() external view returns (uint256 credited, uint256 accrued) {
        uint256 rewardPerShare = ALM_CORE.rewardPerShare_();
        credited = ALM_CORE.getProtocolFeesReward() + ALM_CORE.getClaimedCumulative() - ALM_CORE.getLastRewardBalance();
        for (uint256 i; i < actors.length + 2; ++i) {
            address holder = holderAt(i);
            credited += ALM_CORE.getPendingReward(holder);
            accrued += ALM_CORE.balanceOf(holder).fullMulDiv(rewardPerShare - ALM_CORE.getRewardSnapshot(holder), 1e18);
        }
        accrued += ALM_CORE.balanceOf(address(ALM_CORE))
            .fullMulDiv(rewardPerShare - ALM_CORE.getProtocolRewardSnapshot(), 1e18);
    }

    function viewsRevert(address holder, address lens) external view returns (bool reverted) {
        address core = address(ALM_CORE);
        for (uint256 v; v < asyncVaults.length; ++v) {
            address vault = asyncVaults[v];
            reverted = reverted || _reverts(vault, abi.encodeCall(ALMVaultAsync.pendingDepositRequest, (0, holder)))
                || _reverts(vault, abi.encodeCall(ALMVaultAsync.pendingRedeemRequest, (0, holder)))
                || _reverts(vault, abi.encodeCall(ALMVaultAsync.claimableDepositRequest, (0, holder)))
                || _reverts(vault, abi.encodeCall(ALMVaultAsync.claimableRedeemRequest, (0, holder)))
                || _reverts(vault, abi.encodeCall(ALMVaultAsync.maxDeposit, (holder)))
                || _reverts(vault, abi.encodeCall(ALMVaultAsync.maxMint, (holder)))
                || _reverts(vault, abi.encodeCall(ALMVaultAsync.maxRedeem, (holder)))
                || _reverts(vault, abi.encodeCall(ALMVaultAsync.maxWithdraw, (holder)))
                || _reverts(lens, abi.encodeCall(ALMCoreView.getDepositRecord, (core, vault, holder)))
                || _reverts(lens, abi.encodeCall(ALMCoreView.getClaimableRedeem, (core, vault, holder)));
        }
        if (holder != core) reverted = reverted || _reverts(core, abi.encodeCall(IALMCore.getRewardOwed, (holder)));
        reverted = reverted || _reverts(lens, abi.encodeCall(ALMCoreView.getRewardAccount, (core, holder)))
            || _reverts(lens, abi.encodeCall(ALMCoreView.getShareAccount, (core, holder)))
            || _reverts(core, abi.encodeCall(IALMCore.getUnstakedPositions, ()))
            || _reverts(lens, abi.encodeCall(ALMCoreView.getConfig, (core)))
            || _reverts(lens, abi.encodeCall(ALMCoreView.getRewards, (core)))
            || _reverts(lens, abi.encodeCall(ALMCoreView.getPoolTokens, (core)))
            || _reverts(lens, abi.encodeCall(ALMCoreView.getRanges, (core)))
            || _reverts(lens, abi.encodeCall(ALMCoreView.getLastExchangeRate, (core)));
    }

    function _reverts(address target, bytes memory data) internal view returns (bool reverted) {
        (bool success,) = target.staticcall(data);
        reverted = !success;
    }

    function holderAt(uint256 seed) public view returns (address holder) {
        seed = bound(seed, 0, actors.length + 2);
        if (seed < actors.length) return actors[seed];
        if (seed == actors.length) return STEWARD;
        holder = seed == actors.length + 1 ? address(1) : address(ALM_CORE);
    }

    function _trackFairShares() internal {
        uint256 lifetime = _lifetimeReward();
        uint256 supply = ALM_CORE.totalSupply();
        if (lifetime > lastLifetimeReward && supply > 0) {
            uint256 delta = lifetime - lastLifetimeReward;
            for (uint256 i; i < actors.length; ++i) {
                ghostFairRewardOf[actors[i]] += delta.fullMulDivUp(ALM_CORE.balanceOf(actors[i]), supply);
            }
        }
        lastLifetimeReward = lifetime;
    }

    function _rebaseFairShares() internal {
        ghostFairRebases++;
        lastLifetimeReward = _lifetimeReward();
        for (uint256 i; i < actors.length; ++i) {
            ghostFairRewardOf[actors[i]] = ALM_CORE.getRewardOwed(actors[i]) + ghostRewardPaidOf[actors[i]]
                + ALM_CORE.balanceOf(actors[i]) / 1e18 + 1;
        }
    }

    function _lifetimeReward() internal returns (uint256 lifetime) {
        (uint256 received,,) = ALM_CORE.getRewardTotals();
        lifetime = ALM_CORE.getClaimedCumulative() + netOfTheEmissionFee(received);
        uint256[] memory tokenIds = ALM_CORE.stakedTokenIds();
        lifetime += netOfTheEmissionFee(
            ALM_CORE.getWindowEnd() == 0
                ? ICLGauge(ALM_CORE.gauge()).earned(address(ALM_CORE), tokenIds)
                : earnedWithoutPenalty(tokenIds)
        );
    }

    function earnedWithoutPenalty(uint256[] memory tokenIds) public returns (uint256 amount) {
        ICLGauge gauge = ICLGauge(ALM_CORE.gauge());
        uint256 minStakeBlocks = GAUGE_FACTORY.minStakeBlocks(address(gauge));

        uint256 snapshot = vm.snapshotState();
        vm.prank(GAUGE_ADMIN);
        GAUGE_FACTORY.setPenaltyConfig(minStakeBlocks, 0);
        amount = gauge.earned(address(ALM_CORE), tokenIds);
        vm.revertToStateAndDelete(snapshot);
    }

    function hiddenEmissions(uint256[] memory tokenIds) public returns (uint256 amount) {
        amount = earnedWithoutPenalty(tokenIds) - ICLGauge(ALM_CORE.gauge()).earned(address(ALM_CORE), tokenIds);
    }

    function forfeitOf(uint256 gross) public view returns (uint256 forfeit) {
        if (gross != 0) forfeit = netOfTheEmissionFee(gross) + 1;
    }

    function netOfTheEmissionFee(uint256 gross) public view returns (uint256 net) {
        net = gross - gross.fullMulDiv(ALM_CORE.protocolEmissionFeeBps_(), ALM_CORE.BPS_DENOMINATOR_());
    }

    function isMintable() public view returns (bool mintable) {
        ILeafVoter.ChainStatus status = ILeafVoter(ALM_CORE.LEAF_VOTER_()).chainStatus();
        mintable = status == ILeafVoter.ChainStatus.Active || status == ILeafVoter.ChainStatus.Sunset;
    }
}
