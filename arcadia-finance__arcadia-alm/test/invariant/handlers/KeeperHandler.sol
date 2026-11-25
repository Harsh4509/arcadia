/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreExtension } from "../../utils/extensions/ALMCoreExtension.sol";
import { ALMCoreHandler } from "./ALMCoreHandler.sol";
import { ALMCoreViewLogic } from "../../../src/core/libraries/logic/ALMCoreViewLogic.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { BaseHandler } from "./BaseHandler.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { CommandLogic } from "../../../src/core/libraries/logic/CommandLogic.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCore } from "../../../src/interfaces/IALMCore.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { ICLGauge } from "../../utils/fixtures/metadex/interfaces/ICLGauge.sol";
import { ICLGaugeFactory } from "../../utils/fixtures/metadex/interfaces/ICLGaugeFactory.sol";
import { IMetadexCLPool } from "../../../src/interfaces/IMetadexCLPool.sol";
import { IMetadexCLPositionManager } from "../../../src/interfaces/IMetadexCLPositionManager.sol";
import { IMetadexSwapRouter } from "../../utils/fixtures/metadex/interfaces/IMetadexSwapRouter.sol";
import { Plan } from "../../utils/Plan.sol";
import { PoolTokensLib } from "../../../src/core/libraries/state/PoolTokensLib.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { RangesLib } from "../../../src/core/libraries/state/RangesLib.sol";
import { Record } from "../../../src/core/types/State.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";
import { SnapshotLib } from "../../../src/vaults/types/Snapshot.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { VmSafe } from "@forge-std/Vm.sol";

/**
 * @notice Drives the keeper plan surface of "ALMCore" for the invariant suite.
 */
// forge-lint: disable-next-item(calls-loop, missing-zero-check, uninitialized-local, unsafe-typecast, unused-return)
contract KeeperHandler is BaseHandler {
    using FixedPointMathLib for uint256;
    using Plan for Plan.Steps;
    using ALMCoreViewLogic for IALMCore;
    using SnapshotLib for IALMCore;
    using ALMCoreViewLogic for bytes32[];

    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The most steps of a random plan, one per opcode.
    uint256 public immutable PLAN_STEPS = Constants.OPCODES.length;
    // The topic of the pool's Swap event.
    bytes32 internal constant SWAP_TOPIC = keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)");

    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    ALMCoreExtension internal immutable ALM_CORE;
    ALMCoreHandler internal immutable CORE_HANDLER;
    IMetadexCLPool internal immutable POOL;
    address internal immutable KEEPER;
    int24 internal immutable TICK_SPACING;
    // The router the keeper routes swaps through.
    address internal immutable SWAP_ROUTER;
    ICLGaugeFactory internal immutable GAUGE_FACTORY;
    address internal immutable ASYNC_VAULT0;
    address internal immutable ASYNC_VAULT1;

    uint256 public ghostRangesOpened;
    uint256 public ghostRangesClosed;
    uint256 public ghostWindowTouches;
    uint256 public ghostSharesSettledIn;
    uint256 public ghostSharesSettledOut;
    uint256 public ghostLossBoundBreaches;
    // The plans that executed.
    uint256 public ghostPlansExecuted;
    // The stake and unstake steps tried while the range's penalty window was open.
    uint256 public ghostWindowAttempts;
    // The plans that ran a step a paused core refuses.
    uint256 public ghostPausedAccepts;
    // The deposit settlements that left the supply above the total cap.
    uint256 public ghostTotalCapBreaches;
    // The plans below their minimum output that executed.
    uint256 public ghostBelowMinimumOutputs;
    // The plans that reverted below their minimum output.
    uint256 public ghostPlansReverted;
    // The plans of more than one step that executed.
    uint256 public ghostMultiStepPlans;
    // The random plans that executed.
    uint256 public ghostRandomPlans;
    // The router swaps that executed.
    uint256 public ghostRouterSwaps;
    // The emissions, net of the protocol fee, the emergency unstakes and the penalised unstakes forfeited at most.
    uint256 public ghostForfeited;
    // The state-changing core calls that went through, one per executed plan.
    uint256 public ghostCheckpoints;
    uint256 public ghostSettleOnlyLosses;
    // The plans whose aLP or token escrow moved by other than the epochs they settled.
    uint256 public ghostSettlementMismatches;
    // The settled epochs paid more than their pro-rata part of the plan's value.
    uint256 public ghostSettlementBreaches;
    // The settlements that were checked against their pro-rata part.
    uint256 public ghostSettlementsChecked;
    // The settlements a step followed whose plan prefix through the settlement reverted on its own.
    uint256 public ghostSettlementsUnmeasured;
    // The plans that executed before the minimum plan interval had passed.
    uint256 public ghostPlanSpacingBreaches;
    // The plans that opened a range and left more ranges than the range cap.
    uint256 public ghostRangeCapBreaches;
    // The clears after which the highest epoch id of the queue did not rise.
    uint256 public ghostEpochIdBreaches;
    // The swaps that sold more than their output at the plan's starting spot and the max swap cost covers.
    uint256 public ghostSwapCostBreaches;
    uint256 public ghostSwapsChecked;
    // The plans after which a watched account's tokens moved by other than its cancelled deposits.
    uint256 public ghostPlanGains;
    // The plans that executed at a trusted price outside a band, and those refused for the band inside both.
    uint256 public ghostTrustedOutsideAccepts;
    uint256 public ghostTrustedInsideRefusals;
    uint256 public ghostTrustedOutsideDraws;
    // The plans that moved a range other than through a step that may.
    uint256 public ghostIllegalRangeMoves;
    // The steps a plan must refuse that executed, and the refusals for another reason than the expected one.
    uint256 public ghostRefusedStepsAccepted;
    uint256 public ghostWrongRefusals;
    uint256 public ghostRefusalsTried;
    // The empty plans refused inside both bands.
    uint256 public ghostEmptyPlanRefusals;
    uint256 public ghostEmptyPlans;
    // The sentinel-sized plans tried, and those refused at spot for a payout their queue steps alone pay.
    uint256 public ghostSentinelPlans;
    uint256 public ghostSentinelPayoutShortfalls;
    // The pool swaps executed plans made, and the executed plans that made more than one.
    uint256 public ghostSwapsExecuted;
    uint256 public ghostMultiSwapPlans;
    // The plans refused for a second swap, and for clearing a queue they did not settle before building or ending.
    uint256 public ghostTooManySwapsRefusals;
    uint256 public ghostOrderRefusals;

    // The controller a cancel step names, whose own credit the step may move.
    address internal cancelled;
    // True while a plan cancels redeems of controllers the bystander check cannot name.
    bool internal skipPendingCheck;
    // Whether the plan settles at its end, and else its value at the trusted price right after the settlement.
    bool internal settlesAtTheEnd;
    bool internal settlementMeasured;
    uint256 internal settlementValue;
    // Whether the plan swaps before its settlement.
    bool internal swappedBeforeSettlement;

    // The ranges a random plan acts on, as the core holds them after each step built so far.
    Range[] internal model;
    // The unstaked side's liquidity of every model range, uint128.max once a step made it unknown.
    uint128[] internal modelUnstaked;
    // One bit per model range the plan opened.
    uint256 internal opened;
    // One bit per model range whose penalty window is open.
    uint256 internal windows;
    // True when a step of the random plan acts on a staked side inside its window without accepting the penalty.
    bool internal expectWindowRefusal;
    // True when a step of the random plan may forfeit emissions.
    bool internal forfeits;
    // The vault side and queue most queue steps of the random plan act on.
    uint256 internal focusQueue;

    mapping(address vault => mapping(bool isDeposit => mapping(address controller => Record record))) internal
        recordsBefore;
    mapping(address vault => mapping(bool isDeposit => uint256 epoch)) internal pendingEpochBefore;
    mapping(address vault => mapping(bool isDeposit => uint256 epoch)) internal highestEpochBefore;
    // The supply, ranges, value at the trusted price, loss floor and earliest plan time before the plan under way.
    uint256 internal supplyBefore;
    uint256 internal rangesBefore;
    uint256 internal valueBefore;
    uint256 internal valueFloor;
    uint256 internal earliestPlanAt;
    uint256 internal escrowedSharesBefore;
    // The requests the plan under way cleared and cancelled, and the epoch it cleared them into, per vault and queue.
    mapping(address vault => mapping(bool isDeposit => uint256 amount)) internal cleared;
    mapping(address vault => mapping(bool isDeposit => uint256 amount)) internal cancelledIn;
    mapping(address vault => mapping(bool isDeposit => uint32 epoch)) internal clearedEpoch;
    uint256 internal escrowed0Before;
    uint256 internal escrowed1Before;
    // The accounts no plan may pay, and their token0, token1 and reward token balances before the plan under way.
    address[] internal watched;
    uint256[3][] internal watchedBefore;
    // The ranges before the plan under way.
    Range[] internal rangesSnapshot;
    // The reason the last refused plan reverted with, and whether the trusted price of the last plan sat in both bands.
    bytes4 internal lastRefusal;
    bool internal lastInBands;

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(
        ALMCoreExtension almCore,
        ALMCoreHandler coreHandler,
        IMetadexCLPool pool,
        address keeper,
        int24 tickSpacing,
        address swapRouter,
        address[] memory watched_
    ) {
        ALM_CORE = almCore;
        CORE_HANDLER = coreHandler;
        POOL = pool;
        KEEPER = keeper;
        TICK_SPACING = tickSpacing;
        SWAP_ROUTER = swapRouter;
        GAUGE_FACTORY = ICLGaugeFactory(almCore.GAUGE_FACTORY_());
        ASYNC_VAULT0 = almCore.asyncVault_(almCore.token0());
        ASYNC_VAULT1 = almCore.asyncVault_(almCore.token1());
        for (uint256 i; i < watched_.length; ++i) {
            watched.push(watched_[i]);
        }
    }

    /* //////////////////////////////////////////////////////////////
                                 ACTIONS
    ////////////////////////////////////////////////////////////// */

    function plan(uint256 seed, uint256 steps, uint256 trustedSeed, bool land)
        external
        countCall(this.plan.selector)
        advanceBlock
    {
        steps = bound(steps, 1, PLAN_STEPS);
        if (land) _land();
        _startModel();
        focusQueue = seed;
        Plan.Steps memory plan_ = Plan.init();
        Plan.Steps memory others = Plan.init();
        bool paused = ALM_CORE.paused_();
        for (uint256 i; i < steps; ++i) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, i)));
            uint8 command = uint8(Constants.OPCODES[entropy % Constants.OPCODES.length]);
            if (paused && CommandLogic.pausable(command)) {
                command = CommandLogic.CLOSE_RANGE
                    + uint8(entropy % (CommandLogic.EMERGENCY_UNSTAKE - CommandLogic.CLOSE_RANGE + 1));
            }
            if (!_hasStakedRange()) command = _unstakedCounterpart(command);
            bytes memory payload = _payload(command, entropy / Constants.OPCODES.length);
            if (command <= CommandLogic.CANCEL_REQUESTS) plan_ = plan_.add(command, payload);
            else others = others.add(command, payload);
        }
        bool unsettled = plan_.commands.length != 0;
        for (uint256 i; i < others.inputs.length; ++i) {
            uint8 command = uint8(others.commands[i]);
            if (unsettled && command >= CommandLogic.OPEN_RANGE) plan_ = plan_.settleRequests();
            if (command >= CommandLogic.OPEN_RANGE || command == CommandLogic.SETTLE_REQUESTS) unsettled = false;
            plan_ = plan_.add(command, others.inputs[i]);
        }
        if (expectWindowRefusal) ghostWindowAttempts++;
        uint256 forfeited =
            forfeits ? CORE_HANDLER.forfeitOf(CORE_HANDLER.earnedWithoutPenalty(ALM_CORE.stakedTokenIds())) : 0;

        if (_runAt(plan_, this.plan.selector, _trusted(trustedSeed), land)) {
            ghostRandomPlans++;
            ghostForfeited += forfeited;
            if (expectWindowRefusal) ghostWindowTouches++;
        }
        skipPendingCheck = false;
    }

    function openRange(int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1)
        external
        countCall(this.openRange.selector)
        advanceBlock
    {
        (int24 lower, int24 upper) = _ticks(tickLower, tickUpper);
        amount0 = bound(amount0, 0, ALM_CORE.bufferAmount0());
        amount1 = bound(amount1, 0, ALM_CORE.bufferAmount1());
        if (amount0 == 0 && amount1 == 0) return;

        if (_run(Plan.init().openRange(lower, upper, amount0, amount1, 0, 0), this.openRange.selector)) {
            ghostRangesOpened++;
        }
    }

    function closeRange(uint256 indexSeed) external countCall(this.closeRange.selector) advanceBlock {
        uint256 length = ALM_CORE.getRangesLength();
        if (length == 0) return;
        uint256 index = bound(indexSeed, 0, length - 1);

        Range memory range = ALM_CORE.getRange(index);
        bool closed = _run(Plan.init().closeRange(index, range.unstakedTokenId), this.closeRange.selector);
        if (closed) ghostRangesClosed++;
        if (range.stakedTokenId != 0) _countRefusal(closed, RangesLib.RangeStaked.selector, CommandLogic.CLOSE_RANGE);
    }

    function increaseLiquidity(uint256 indexSeed, uint256 amount0, uint256 amount1)
        external
        countCall(this.increaseLiquidity.selector)
        advanceBlock
    {
        uint256 length = ALM_CORE.getRangesLength();
        if (length == 0) return;
        uint256 index = bound(indexSeed, 0, length - 1);
        amount0 = bound(amount0, 0, ALM_CORE.bufferAmount0());
        amount1 = bound(amount1, 0, ALM_CORE.bufferAmount1());
        if (amount0 == 0 && amount1 == 0) return;

        Range memory range = ALM_CORE.getRange(index);
        _run(
            Plan.init().increaseLiquidity(index, range.unstakedTokenId, amount0, amount1, 0, 0),
            this.increaseLiquidity.selector
        );
    }

    function decreaseLiquidity(uint256 indexSeed, uint128 liquidity)
        external
        countCall(this.decreaseLiquidity.selector)
        advanceBlock
    {
        uint256 length = ALM_CORE.getRangesLength();
        if (length == 0) return;
        uint256 index = bound(indexSeed, 0, length - 1);

        Range memory range = ALM_CORE.getRange(index);
        uint128 unstaked =
            IMetadexCLPositionManager(ALM_CORE.POSITION_MANAGER_()).positions(range.unstakedTokenId).liquidity;
        if (unstaked == 0) return;
        liquidity = uint128(bound(liquidity, 1, unstaked));

        _run(
            Plan.init().decreaseLiquidity(index, range.unstakedTokenId, liquidity, 0, 0),
            this.decreaseLiquidity.selector
        );
    }

    function stake(uint256 indexSeed, uint256 amount0, uint256 amount1)
        external
        countCall(this.stake.selector)
        advanceBlock
    {
        uint256 length = ALM_CORE.getRangesLength();
        if (length == 0) return;
        uint256 index = bound(indexSeed, 0, length - 1);
        amount0 = bound(amount0, 0, ALM_CORE.bufferAmount0());
        amount1 = bound(amount1, 0, ALM_CORE.bufferAmount1());
        if (amount0 == 0 && amount1 == 0) return;

        Range memory range = ALM_CORE.getRange(index);
        _land();
        bool windowOpen = range.stakedTokenId != 0 && ALM_CORE.isPenaltyWindowOpen(index);
        if (windowOpen) ghostWindowAttempts++;
        bool staked = _run(
            range.stakedTokenId == 0
                ? Plan.init().stake(index, range.unstakedTokenId, amount0, amount1, 0, 0)
                : Plan.init().increaseStakedLiquidity(index, range.stakedTokenId, amount0, amount1, 0, 0, false),
            this.stake.selector
        );
        if (staked && windowOpen) ghostWindowTouches++;
        if (windowOpen) {
            _countRefusal(staked, RangesLib.PenaltyWindowOpen.selector, CommandLogic.INCREASE_STAKED_LIQUIDITY);
        }
    }

    function stakeStakedRange(uint256 indexSeed, uint256 amount0, uint256 amount1)
        external
        countCall(this.stakeStakedRange.selector)
        advanceBlock
    {
        uint256 length = ALM_CORE.getRangesLength();
        if (length == 0) return;
        uint256 index = bound(indexSeed, 0, length - 1);
        Range memory range = ALM_CORE.getRange(index);
        if (range.stakedTokenId == 0) return;
        amount0 = bound(amount0, 0, ALM_CORE.bufferAmount0());
        amount1 = bound(amount1, 0, ALM_CORE.bufferAmount1());

        bool staked = _run(
            Plan.init().stake(index, range.unstakedTokenId, amount0, amount1, 0, 0), this.stakeStakedRange.selector
        );
        _countRefusal(staked, RangesLib.RangeStaked.selector, CommandLogic.STAKE);
    }

    function unstakeUnstakedRange(uint256 indexSeed, uint128 liquidity)
        external
        countCall(this.unstakeUnstakedRange.selector)
        advanceBlock
    {
        uint256 length = ALM_CORE.getRangesLength();
        if (length == 0) return;
        uint256 index = bound(indexSeed, 0, length - 1);
        if (ALM_CORE.getRange(index).stakedTokenId != 0) return;

        bool unstaked = _run(Plan.init().unstake(index, 0, liquidity, 0, 0, false), this.unstakeUnstakedRange.selector);
        _countRefusal(unstaked, RangesLib.RangeNotStaked.selector, CommandLogic.UNSTAKE);
    }

    function unstake(uint256 indexSeed, uint128 liquidity) external countCall(this.unstake.selector) advanceBlock {
        uint256 length = ALM_CORE.getRangesLength();
        if (length == 0) return;
        uint256 index = bound(indexSeed, 0, length - 1);

        Range memory range = ALM_CORE.getRange(index);
        if (range.stakedLiquidity == 0) return;
        liquidity = uint128(bound(liquidity, 1, range.stakedLiquidity));

        _land();
        bool windowOpen = ALM_CORE.isPenaltyWindowOpen(index);
        if (windowOpen) ghostWindowAttempts++;
        bool unstaked =
            _run(Plan.init().unstake(index, range.stakedTokenId, liquidity, 0, 0, false), this.unstake.selector);
        if (unstaked && windowOpen) ghostWindowTouches++;
        if (windowOpen) _countRefusal(unstaked, RangesLib.PenaltyWindowOpen.selector, CommandLogic.UNSTAKE);
    }

    function decreaseStakedAcceptingPenalty(uint256 indexSeed, uint128 liquidity)
        external
        countCall(this.decreaseStakedAcceptingPenalty.selector)
        advanceBlock
    {
        uint256 length = ALM_CORE.getRangesLength();
        if (length == 0) return;
        uint256 index = bound(indexSeed, 0, length - 1);

        Range memory range = ALM_CORE.getRange(index);
        if (range.stakedLiquidity == 0) return;
        liquidity = uint128(bound(liquidity, 1, range.stakedLiquidity));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = range.stakedTokenId;
        uint256 forfeited = CORE_HANDLER.forfeitOf(CORE_HANDLER.hiddenEmissions(tokenIds));
        Plan.Steps memory plan_ = Plan.init().unstake(index, range.stakedTokenId, liquidity, 0, 0, true);
        if (_run(plan_, this.decreaseStakedAcceptingPenalty.selector)) ghostForfeited += forfeited;
    }

    function emergencyUnstake(uint256 indexSeed) external countCall(this.emergencyUnstake.selector) advanceBlock {
        uint256 length = ALM_CORE.getRangesLength();
        if (length == 0) return;
        uint256 index = bound(indexSeed, 0, length - 1);

        uint256 tokenId = ALM_CORE.getRange(index).stakedTokenId;
        if (tokenId == 0) return;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        uint256 forfeited = CORE_HANDLER.forfeitOf(
            CORE_HANDLER.earnedWithoutPenalty(tokenIds)
                - ICLGauge(ALM_CORE.gauge()).deferredEmissions(address(ALM_CORE))
        );
        Plan.Steps memory plan_ = Plan.init().emergencyUnstake(index, tokenId);
        if (_run(plan_, this.emergencyUnstake.selector)) ghostForfeited += forfeited;
    }

    function collect(uint256 indexSeed) external countCall(this.collect.selector) advanceBlock {
        uint256 length = ALM_CORE.getRangesLength();
        if (length == 0) return;
        uint256 index = bound(indexSeed, 0, length - 1);

        _run(Plan.init().collect(ALM_CORE.getRange(index).unstakedTokenId), this.collect.selector);
    }

    function swap(bool zeroForOne, uint256 amountIn, uint256 kind, uint256 trustedSeed)
        external
        countCall(this.swap.selector)
        advanceBlock
    {
        uint256 buffer = zeroForOne ? ALM_CORE.bufferAmount0() : ALM_CORE.bufferAmount1();
        if (buffer == 0) return;
        amountIn = _swapAmount(amountIn, bound(kind, 0, 2), buffer);

        uint160 sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        _runAt(
            Plan.init().swapViaPool(zeroForOne, amountIn, sqrtPriceLimitX96, 0),
            this.swap.selector,
            _trusted(trustedSeed),
            true
        );
    }

    function clearDeposits(bool isToken0, uint256 controllerSeed, uint256 trustedSeed)
        external
        countCall(this.clearDeposits.selector)
        advanceBlock
    {
        address vault = isToken0 ? ASYNC_VAULT0 : ASYNC_VAULT1;
        address controller = CORE_HANDLER.actorAt(controllerSeed);
        (uint32 pendingDepositEpoch,) = ALM_CORE.pendingEpochs(vault);
        Record memory record = ALM_CORE.depositRecord(vault, controller);
        if (record.amountIn == 0 || record.epoch != pendingDepositEpoch) return;

        Plan.Steps memory plan_ = Plan.init().clearRequests(isToken0, true, Plan.one(controller)).settleRequests();
        _runAt(plan_, this.clearDeposits.selector, _trusted(trustedSeed), true);
    }

    function clearRedeems(bool isToken0, uint256 controllerSeed, uint256 trustedSeed)
        external
        countCall(this.clearRedeems.selector)
        advanceBlock
    {
        address vault = isToken0 ? ASYNC_VAULT0 : ASYNC_VAULT1;
        address controller = CORE_HANDLER.actorAt(controllerSeed);
        (, uint32 pendingRedeemEpoch) = ALM_CORE.pendingEpochs(vault);
        Record memory record = ALM_CORE.redeemRecord(vault, controller);
        if (record.amountIn == 0 || record.epoch != pendingRedeemEpoch) return;

        Plan.Steps memory plan_ = Plan.init().clearRequests(isToken0, false, Plan.one(controller)).settleRequests();
        _runAt(plan_, this.clearRedeems.selector, _trusted(trustedSeed), true);
    }

    function clearAllDeposits(bool isToken0, uint256 trustedSeed)
        external
        countCall(this.clearAllDeposits.selector)
        advanceBlock
    {
        address vault = isToken0 ? ASYNC_VAULT0 : ASYNC_VAULT1;
        (uint32 pendingDepositEpoch,) = ALM_CORE.pendingEpochs(vault);
        if (ALM_CORE.depositEpoch(vault, pendingDepositEpoch).amountIn == 0) return;

        _runAt(
            Plan.init().clearAllRequests(isToken0, true).settleRequests(),
            this.clearAllDeposits.selector,
            _trusted(trustedSeed),
            true
        );
    }

    function clearAllRedeems(bool isToken0, uint256 trustedSeed)
        external
        countCall(this.clearAllRedeems.selector)
        advanceBlock
    {
        address vault = isToken0 ? ASYNC_VAULT0 : ASYNC_VAULT1;
        (, uint32 pendingRedeemEpoch) = ALM_CORE.pendingEpochs(vault);
        if (ALM_CORE.redeemEpoch(vault, pendingRedeemEpoch).amountIn == 0) return;

        _runAt(
            Plan.init().clearAllRequests(isToken0, false).settleRequests(),
            this.clearAllRedeems.selector,
            _trusted(trustedSeed),
            true
        );
    }

    function clearQueues(
        uint256 kindSeed,
        uint256 orderSeed,
        uint256 swapKind,
        bool zeroForOne,
        uint256 amountIn,
        bool swapsFirst,
        uint256 trustedSeed
    ) external countCall(this.clearQueues.selector) advanceBlock {
        Plan.Steps memory clears = _clearSteps(kindSeed);
        if (clears.commands.length == 0) return;
        Plan.Steps memory plan_ = _shuffledWithSwap(clears, orderSeed, swapKind, zeroForOne, amountIn, swapsFirst);

        _runAt(plan_, this.clearQueues.selector, _trusted(trustedSeed), true);
    }

    function cancelDeposits(bool isToken0, uint256 controllerSeed, uint256 trustedSeed)
        external
        countCall(this.cancelDeposits.selector)
        advanceBlock
    {
        address controller = CORE_HANDLER.actorAt(controllerSeed);

        cancelled = controller;
        _runAt(
            Plan.init().cancelRequests(isToken0, true, Plan.one(controller)),
            this.cancelDeposits.selector,
            _trusted(trustedSeed),
            true
        );
        cancelled = address(0);
    }

    function cancelRedeems(bool isToken0, uint256 controllerSeed, uint256 trustedSeed)
        external
        countCall(this.cancelRedeems.selector)
        advanceBlock
    {
        address controller = CORE_HANDLER.actorAt(controllerSeed);

        cancelled = controller;
        _runAt(
            Plan.init().cancelRequests(isToken0, false, Plan.one(controller)),
            this.cancelRedeems.selector,
            _trusted(trustedSeed),
            true
        );
        cancelled = address(0);
    }

    function rebalance(uint256 indexSeed, uint128 liquidity) external countCall(this.rebalance.selector) advanceBlock {
        uint256 length = ALM_CORE.getRangesLength();
        if (length == 0) return;
        uint256 index = bound(indexSeed, 0, length - 1);

        uint256 tokenId = ALM_CORE.getRange(index).unstakedTokenId;
        if (IMetadexCLPositionManager(ALM_CORE.POSITION_MANAGER_()).positions(tokenId).liquidity == 0) return;
        liquidity = uint128(
            bound(liquidity, 1, IMetadexCLPositionManager(ALM_CORE.POSITION_MANAGER_()).positions(tokenId).liquidity)
        );

        Plan.Steps memory plan_ = Plan.init()
            .decreaseLiquidity(index, tokenId, liquidity, 0, 0)
            .increaseLiquidity(
                index,
                tokenId,
                Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                0,
                0
            );
        _run(plan_, this.rebalance.selector);
    }

    function failingPlan(uint256 indexSeed, bool zeroForOne, uint256 amountIn)
        external
        countCall(this.failingPlan.selector)
        advanceBlock
    {
        uint256 length = ALM_CORE.getRangesLength();
        uint256 buffer = zeroForOne ? ALM_CORE.bufferAmount0() : ALM_CORE.bufferAmount1();
        if (length == 0 || buffer == 0) return;
        uint256 index = bound(indexSeed, 0, length - 1);
        amountIn = bound(amountIn, 1, buffer);

        Range memory range = ALM_CORE.getRange(index);
        uint160 sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        Plan.Steps memory plan_ = Plan.init()
            .collect(range.unstakedTokenId)
            .swapViaPool(zeroForOne, amountIn, sqrtPriceLimitX96, type(uint256).max);

        if (_run(plan_, this.failingPlan.selector)) ghostBelowMinimumOutputs++;
        else ghostPlansReverted++;
    }

    function swapViaRouter(bool zeroForOne, uint256 amountIn, uint256 trustedSeed)
        external
        countCall(this.swapViaRouter.selector)
        advanceBlock
    {
        uint256 buffer = zeroForOne ? ALM_CORE.bufferAmount0() : ALM_CORE.bufferAmount1();
        if (buffer == 0) return;
        amountIn = bound(amountIn, 1, buffer);

        Plan.Steps memory plan_ = Plan.init().add(CommandLogic.SWAP_VIA_ROUTER, _routerPayload(zeroForOne, amountIn));
        if (_runAt(plan_, this.swapViaRouter.selector, _trusted(trustedSeed), true)) ghostRouterSwaps++;
    }

    function clearDepositsWhilePaused(bool isToken0, bool named, uint256 controllerSeed, uint256 trustedSeed)
        external
        countCall(this.clearDepositsWhilePaused.selector)
        advanceBlock
    {
        if (!ALM_CORE.paused_()) return;

        Plan.Steps memory plan_ = named
            ? Plan.init().clearRequests(isToken0, true, Plan.one(CORE_HANDLER.actorAt(controllerSeed))).settleRequests()
            : Plan.init().clearAllRequests(isToken0, true).settleRequests();
        bool executed = _runAt(plan_, this.clearDepositsWhilePaused.selector, _trusted(trustedSeed), true);
        _countRefusal(
            executed,
            ALMKeeperExtension.Paused.selector,
            named ? CommandLogic.CLEAR_REQUESTS : CommandLogic.CLEAR_ALL_REQUESTS
        );
    }

    function planAtABandEdge(uint256 edgeSeed, uint256 indexSeed)
        external
        countCall(this.planAtABandEdge.selector)
        advanceBlock
    {
        uint256 length = ALM_CORE.getRangesLength();
        Plan.Steps memory plan_ = length == 0
            ? Plan.init()
            : Plan.init().collect(ALM_CORE.getRange(bound(indexSeed, 0, length - 1)).unstakedTokenId);
        _land();
        _runAt(plan_, this.planAtABandEdge.selector, _edge(edgeSeed), false);
    }

    function settleWithSentinels(
        uint256 actorSeed,
        uint256 assets,
        uint256 shares,
        bool redeemToken0,
        bool zeroForOne,
        uint256 swapSeed,
        uint256 stepSeed
    ) external countCall(this.settleWithSentinels.selector) advanceBlock {
        uint256 buffer = zeroForOne ? ALM_CORE.bufferAmount0() : ALM_CORE.bufferAmount1();
        CORE_HANDLER.requestDeposit(actorSeed, actorSeed, actorSeed, bound(assets, 1, buffer + 1), zeroForOne);
        CORE_HANDLER.mint(actorSeed >> 8, shares);
        CORE_HANDLER.requestRedeem(actorSeed >> 8, actorSeed >> 8, actorSeed >> 8, shares, redeemToken0, false);
        Plan.Steps memory plan_ = _clearSteps(actorSeed >> 16);
        if (plan_.commands.length == 0) return;
        plan_ = plan_.swapViaPool(
                zeroForOne,
                _swapAmount(swapSeed >> 1, (swapSeed & 1) + 1, 1),
                zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1,
                0
            )
            .settleRequests();
        uint256 whole = Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR;
        uint256 length = ALM_CORE.getRangesLength();
        if (length == 0 || stepSeed & 1 == 0) {
            (int24 lower, int24 upper) = _ticks(int24(int256(stepSeed >> 1)), int24(int256(stepSeed >> 25)));
            plan_ = plan_.openRange(lower, upper, whole, whole, 0, 0);
        } else {
            uint256 index = bound(stepSeed >> 1, 0, length - 1);
            plan_ = plan_.increaseLiquidity(index, ALM_CORE.getRange(index).unstakedTokenId, whole, whole, 0, 0);
        }

        _run(plan_, this.settleWithSentinels.selector);
    }

    function buildWhileUnsettled(uint256 queueSeed, uint256 rangeSeed, bool settlesAfter, uint256 trustedSeed)
        external
        countCall(this.buildWhileUnsettled.selector)
        advanceBlock
    {
        (bool isToken0, bool isDeposit) = (queueSeed & 1 == 0, queueSeed & 2 == 0);
        {
            address vault = isToken0 ? ASYNC_VAULT0 : ASYNC_VAULT1;
            (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = ALM_CORE.pendingEpochs(vault);
            uint256 pending = isDeposit
                ? ALM_CORE.depositEpoch(vault, pendingDepositEpoch).amountIn
                : ALM_CORE.redeemEpoch(vault, pendingRedeemEpoch).amountIn;
            if (pending == 0) return;
        }

        uint256 whole = Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR;
        uint256 length = ALM_CORE.getRangesLength();
        Plan.Steps memory plan_ = Plan.init().clearAllRequests(isToken0, isDeposit);
        if (length == 0) {
            (int24 lower, int24 upper) = _ticks(int24(int256(rangeSeed)), int24(int256(rangeSeed >> 24)));
            plan_ = plan_.openRange(lower, upper, whole, whole, 0, 0);
        } else {
            uint256 index = bound(rangeSeed, 0, length - 1);
            plan_ = plan_.increaseLiquidity(index, ALM_CORE.getRange(index).unstakedTokenId, whole, whole, 0, 0);
        }
        if (settlesAfter) plan_ = plan_.settleRequests();

        bool executed = _runAt(plan_, this.buildWhileUnsettled.selector, _trusted(trustedSeed), true);
        _countRefusal(
            executed,
            ALMKeeperExtension.InvalidOrder.selector,
            length == 0 ? CommandLogic.OPEN_RANGE : CommandLogic.INCREASE_LIQUIDITY
        );
    }

    function swapTwice(bool zeroForOne, uint256 amountIn, bool viaRouter)
        external
        countCall(this.swapTwice.selector)
        advanceBlock
    {
        uint256 buffer = zeroForOne ? ALM_CORE.bufferAmount0() : ALM_CORE.bufferAmount1();
        if (buffer < 2) return;
        amountIn = bound(amountIn, 1, buffer / 2);

        uint160 sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        (uint160 trustedSqrtPriceX96,,,,,) = POOL.slot0();
        Plan.Steps memory plan_ = Plan.init().swapViaPool(zeroForOne, amountIn, sqrtPriceLimitX96, 0);
        _land();
        uint256 snapshot = vm.snapshotState();
        bool alone;
        vm.prank(KEEPER);
        try ALM_CORE.execute(plan_.commands, plan_.inputs, trustedSqrtPriceX96) {
            alone = true;
        } catch { }
        vm.revertToStateAndDelete(snapshot);
        if (!alone) return;
        plan_ = viaRouter
            ? plan_.add(CommandLogic.SWAP_VIA_ROUTER, _routerPayload(zeroForOne, amountIn))
            : plan_.swapViaPool(zeroForOne, amountIn, sqrtPriceLimitX96, 0);
        bool executed = _runAt(plan_, this.swapTwice.selector, trustedSqrtPriceX96, true);
        _countRefusal(executed, ALMKeeperExtension.TooManySwaps.selector, CommandLogic.SWAP_VIA_POOL);
    }

    function emptyPlan(uint256 trustedSeed) external countCall(this.emptyPlan.selector) advanceBlock {
        ghostEmptyPlans++;
        if (!_runAt(Plan.init(), this.emptyPlan.selector, _trusted(trustedSeed), true) && lastInBands) {
            ghostEmptyPlanRefusals++;
        }
    }

    /* //////////////////////////////////////////////////////////////
                                RANDOM PLAN
    ////////////////////////////////////////////////////////////// */

    function _startModel() internal {
        delete model;
        delete modelUnstaked;
        (opened, windows, expectWindowRefusal, forfeits) = (0, 0, false, false);
        uint256 length = ALM_CORE.getRangesLength();
        for (uint256 i; i < length; ++i) {
            model.push(ALM_CORE.getRange(i));
            modelUnstaked.push(
                IMetadexCLPositionManager(ALM_CORE.POSITION_MANAGER_())
                .positions(ALM_CORE.getRange(i).unstakedTokenId)
                .liquidity
            );
            if (ALM_CORE.getRange(i).stakedTokenId != 0 && ALM_CORE.isPenaltyWindowOpen(i)) windows |= 1 << i;
        }
    }

    function _payload(uint8 command, uint256 entropy) internal returns (bytes memory payload) {
        if (command == CommandLogic.CLOSE_RANGE) return _closeStep(entropy);
        if (command == CommandLogic.DECREASE_LIQUIDITY) return _decreaseStep(entropy);
        if (command == CommandLogic.COLLECT) return _collectStep(entropy);
        if (command == CommandLogic.UNSTAKE) return _unstakeStep(entropy);
        if (command == CommandLogic.EMERGENCY_UNSTAKE) return _emergencyStep(entropy);
        if (command == CommandLogic.OPEN_RANGE) return _openStep(entropy);
        if (command == CommandLogic.INCREASE_LIQUIDITY) return _increaseStep(entropy, false);
        if (command == CommandLogic.STAKE) return _stakeStep(entropy);
        if (command == CommandLogic.INCREASE_STAKED_LIQUIDITY) return _increaseStep(entropy, true);
        if (command == CommandLogic.SWAP_VIA_POOL) return _swapStep(entropy);
        if (command == CommandLogic.SETTLE_REQUESTS) return "";
        if (command == CommandLogic.SWAP_VIA_ROUTER) {
            bool zeroForOne = entropy & 1 == 0;
            uint256 buffer = zeroForOne ? ALM_CORE.bufferAmount0() : ALM_CORE.bufferAmount1();
            return _routerPayload(zeroForOne, bound(entropy >> 1, 1, FixedPointMathLib.max(buffer, 1)));
        }
        return _queueStep(command, entropy);
    }

    function _closeStep(uint256 entropy) internal returns (bytes memory payload) {
        uint256 length = model.length;
        if (length == 0) return Plan.range(0, 0);
        uint256 index = _unstakedIndex(entropy);
        payload = Plan.range(index, _tokenId(index, false));
        if (model[index].stakedLiquidity != 0) return payload;

        uint256 last = length - 1;
        model[index] = model[last];
        model.pop();
        modelUnstaked[index] = modelUnstaked[last];
        modelUnstaked.pop();
        opened = (opened & ~(1 << index)) | (((opened >> last) & 1) << index);
        opened &= ~(1 << last);
        windows = (windows & ~(1 << index)) | (((windows >> last) & 1) << index);
        windows &= ~(1 << last);
    }

    function _decreaseStep(uint256 entropy) internal returns (bytes memory payload) {
        uint256 index = _index(entropy);
        uint128 liquidity = _liquidity(index, false, entropy >> 8);
        payload = abi.encodePacked(Plan.range(index, _tokenId(index, false)), liquidity, uint256(0), uint256(0));
        if (index < model.length) {
            modelUnstaked[index] = liquidity == Sentinels.RANGE_LIQUIDITY ? 0 : _sub(modelUnstaked[index], liquidity);
        }
    }

    function _unstakeStep(uint256 entropy) internal returns (bytes memory payload) {
        uint256 index = _stakedIndex(entropy);
        uint128 liquidity = _liquidity(index, true, entropy >> 8);
        bool acceptPenalty = (entropy >> 136) & 1 == 1;
        payload = abi.encodePacked(
            Plan.range(index, _tokenId(index, true)), liquidity, uint256(0), uint256(0), acceptPenalty
        );
        _actOnStaked(index, acceptPenalty);
        if (index >= model.length) return payload;
        uint128 left = liquidity == Sentinels.RANGE_LIQUIDITY ? 0 : _sub(model[index].stakedLiquidity, liquidity);
        model[index].stakedLiquidity = left;
        if (left == 0) {
            model[index].stakedTokenId = 0;
            windows &= ~(1 << index);
        }
    }

    function _emergencyStep(uint256 entropy) internal returns (bytes memory payload) {
        uint256 index = _stakedIndex(entropy);
        payload = Plan.range(index, _tokenId(index, true));
        forfeits = true;
        if (index >= model.length) return payload;
        (model[index].stakedLiquidity, model[index].stakedTokenId) = (0, 0);
        windows &= ~(1 << index);
    }

    function _collectStep(uint256 entropy) internal view returns (bytes memory payload) {
        uint256 index = _index(entropy);
        payload = Plan.position(index < model.length ? model[index].unstakedTokenId : 0);
    }

    function _openStep(uint256 entropy) internal returns (bytes memory payload) {
        (int24 lower, int24 upper) = _ticks(int24(int256(entropy)), int24(int256(entropy >> 24)));
        payload = abi.encodePacked(
            lower, upper, _buildAmount(true, entropy >> 48), _buildAmount(false, entropy >> 112), uint256(0), uint256(0)
        );
        opened |= 1 << model.length;
        modelUnstaked.push(type(uint128).max);
        model.push(
            Range({
                stakedLiquidity: 0,
                tickLower: lower,
                tickUpper: upper,
                unstakedTokenId: 0,
                stakedTokenId: 0,
                stakedBlock: 0
            })
        );
    }

    function _increaseStep(uint256 entropy, bool staked) internal returns (bytes memory payload) {
        uint256 index = staked ? _stakedIndex(entropy) : _index(entropy);
        payload = Plan.increase(
            index, _tokenId(index, staked), _buildAmount(true, entropy >> 8), _buildAmount(false, entropy >> 72), 0, 0
        );
        if (!staked) {
            if (index < model.length) modelUnstaked[index] = type(uint128).max;
            return payload;
        }
        bool acceptPenalty = (entropy >> 136) & 1 == 1;
        payload = abi.encodePacked(payload, acceptPenalty);
        _actOnStaked(index, acceptPenalty);
        if (index < model.length && model[index].stakedLiquidity != 0) {
            model[index].stakedLiquidity = type(uint128).max;
        }
    }

    function _stakeStep(uint256 entropy) internal returns (bytes memory payload) {
        uint256 index = _unstakedIndex(entropy);
        payload = Plan.increase(
            index, _tokenId(index, false), _buildAmount(true, entropy >> 8), _buildAmount(false, entropy >> 72), 0, 0
        );
        if (index >= model.length || model[index].stakedLiquidity != 0) return payload;
        model[index].stakedLiquidity = type(uint128).max;
        if (_hasWindow()) windows |= 1 << index;
    }

    function _swapStep(uint256 entropy) internal view returns (bytes memory payload) {
        bool zeroForOne = entropy & 1 == 0;
        uint256 buffer = zeroForOne ? ALM_CORE.bufferAmount0() : ALM_CORE.bufferAmount1();
        uint256 amountIn = _swapAmount(entropy >> 3, (entropy >> 1) % 3, FixedPointMathLib.max(buffer, 1));
        uint160 sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        payload = abi.encodePacked(zeroForOne, amountIn, sqrtPriceLimitX96, uint256(0));
    }

    function _queueStep(uint8 command, uint256 entropy) internal returns (bytes memory payload) {
        uint256 queue = (entropy >> 3) & 1 == 0 ? focusQueue : entropy;
        bool isToken0 = queue & 1 == 0;
        bool isDeposit = queue & 2 == 0;
        if (command == CommandLogic.CLEAR_REQUESTS) focusQueue = queue;
        if (command == CommandLogic.CLEAR_ALL_REQUESTS) return abi.encodePacked(isToken0, isDeposit);
        if (command == CommandLogic.CANCEL_REQUESTS && !isDeposit) skipPendingCheck = true;

        address[] memory controllers = new address[](bound(entropy >> 2, 1, CORE_HANDLER.actorsLength()));
        for (uint256 i; i < controllers.length; ++i) {
            controllers[i] = CORE_HANDLER.actorAt(entropy >> (8 * i + 16));
        }
        payload = Plan.entries(isToken0, isDeposit, controllers);
    }

    function _actOnStaked(uint256 index, bool acceptPenalty) internal {
        if (acceptPenalty) {
            forfeits = true;
        } else if ((windows >> index) & 1 == 1 && index < model.length && model[index].stakedLiquidity != 0) {
            expectWindowRefusal = true;
        }
        if (index < model.length && model[index].stakedLiquidity != 0 && _hasWindow()) windows |= 1 << index;
    }

    function _index(uint256 entropy) internal view returns (uint256 index) {
        index = model.length == 0 ? 0 : entropy % model.length;
    }

    function _hasStakedRange() internal view returns (bool staked) {
        for (uint256 i; i < model.length; ++i) {
            if (model[i].stakedLiquidity != 0) return true;
        }
    }

    function _unstakedCounterpart(uint8 command) internal pure returns (uint8 counterpart) {
        if (command == CommandLogic.UNSTAKE) return CommandLogic.DECREASE_LIQUIDITY;
        if (command == CommandLogic.EMERGENCY_UNSTAKE) return CommandLogic.COLLECT;
        if (command == CommandLogic.INCREASE_STAKED_LIQUIDITY) return CommandLogic.STAKE;
        counterpart = command;
    }

    function _stakedIndex(uint256 entropy) internal view returns (uint256 index) {
        index = _pick(entropy, true);
    }

    function _unstakedIndex(uint256 entropy) internal view returns (uint256 index) {
        index = _pick(entropy, false);
    }

    function _pick(uint256 entropy, bool staked) internal view returns (uint256 index) {
        uint256 count;
        for (uint256 i; i < model.length; ++i) {
            if (_eligible(i, staked)) ++count;
        }
        if (count == 0) return _index(entropy);
        count = entropy % count;
        for (index = 0; index < model.length; ++index) {
            if (!_eligible(index, staked)) continue;
            if (count == 0) return index;
            --count;
        }
    }

    function _eligible(uint256 index, bool staked) internal view returns (bool eligible) {
        Range storage range = model[index];
        if (!staked) return range.stakedLiquidity == 0;
        eligible = range.stakedLiquidity != 0 && (range.stakedTokenId != 0 || (opened >> index) & 1 == 1);
    }

    function _tokenId(uint256 index, bool staked) internal view returns (uint256 tokenId) {
        if (index >= model.length) return 0;
        if ((opened >> index) & 1 == 1) return Sentinels.OPENED;
        tokenId = staked ? model[index].stakedTokenId : model[index].unstakedTokenId;
    }

    function _liquidity(uint256 index, bool staked, uint256 entropy) internal view returns (uint128 liquidity) {
        if (index >= model.length) return Sentinels.RANGE_LIQUIDITY;
        uint128 held = staked ? model[index].stakedLiquidity : modelUnstaked[index];
        if (held == 0 || held == type(uint128).max || entropy & 1 == 0) return Sentinels.RANGE_LIQUIDITY;
        liquidity = uint128(bound(entropy >> 1, 1, held));
    }

    function _buildAmount(bool isToken0, uint256 entropy) internal view returns (uint256 amount) {
        if (entropy & 3 == 1) return Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR;
        if (entropy & 3 != 0) return Sentinels.OPEN_BALANCE | bound(entropy >> 2, 0, ConfigLib.BPS_DENOMINATOR);
        amount = bound(entropy >> 2, 0, isToken0 ? ALM_CORE.bufferAmount0() : ALM_CORE.bufferAmount1());
    }

    function _hasWindow() internal view returns (bool open) {
        ICLGaugeFactory.PenaltyConfig memory config = GAUGE_FACTORY.effectivePenaltyConfig(ALM_CORE.gauge());
        open = config.penaltyRate > 0 && config.minStakeBlocks > 0;
    }

    function _sub(uint128 held, uint128 liquidity) internal pure returns (uint128 left) {
        left = held == type(uint128).max ? held : (held > liquidity ? held - liquidity : 0);
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function _swapAmount(uint256 amountIn, uint256 kind, uint256 buffer) internal pure returns (uint256 amount) {
        if (kind == 0) return bound(amountIn, 1, buffer);
        amount = (kind == 1 ? Sentinels.OPEN_BALANCE : Sentinels.TO_TARGET_RATIO)
            | bound(amountIn, 1, ConfigLib.BPS_DENOMINATOR);
    }

    function _routerPayload(bool zeroForOne, uint256 amountIn) internal view returns (bytes memory payload) {
        (address tokenIn, address tokenOut) =
            zeroForOne ? (ALM_CORE.token0(), ALM_CORE.token1()) : (ALM_CORE.token1(), ALM_CORE.token0());
        bytes memory data = abi.encodeCall(
            IMetadexSwapRouter.exactInput,
            IMetadexSwapRouter.ExactInputParams({
                path: abi.encodePacked(tokenIn, TICK_SPACING, tokenOut),
                recipient: ALM_CORE.ROUTER_TRAMPOLINE_(),
                deadline: type(uint256).max,
                amountIn: amountIn,
                amountOutMinimum: 0
            })
        );
        payload = abi.encodePacked(SWAP_ROUTER, amountIn, zeroForOne, uint256(0), data);
    }

    function _clearSteps(uint256 kindSeed) internal view returns (Plan.Steps memory clears) {
        clears = Plan.init();
        for (uint256 q; q < 4; ++q) {
            address vault = q < 2 ? ASYNC_VAULT0 : ASYNC_VAULT1;
            bool deposits = q % 2 == 0;
            (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = ALM_CORE.pendingEpochs(vault);
            uint32 pendingEpoch = deposits ? pendingDepositEpoch : pendingRedeemEpoch;
            uint256 amount = deposits
                ? ALM_CORE.depositEpoch(vault, pendingEpoch).amountIn
                : ALM_CORE.redeemEpoch(vault, pendingEpoch).amountIn;
            if (amount == 0) continue;
            if ((kindSeed >> q) & 1 == 0) {
                clears = clears.clearAllRequests(q < 2, deposits);
            } else {
                address[] memory controllers = new address[](CORE_HANDLER.actorsLength());
                for (uint256 i; i < controllers.length; ++i) {
                    controllers[i] = CORE_HANDLER.actorAt(i);
                }
                clears = clears.clearRequests(q < 2, deposits, controllers);
            }
        }
    }

    function _shuffledWithSwap(
        Plan.Steps memory clears,
        uint256 orderSeed,
        uint256 swapKind,
        bool zeroForOne,
        uint256 amountIn,
        bool swapsFirst
    ) internal view returns (Plan.Steps memory plan_) {
        plan_ = Plan.init();
        uint256[] memory steps = new uint256[](clears.commands.length);
        for (uint256 i; i < steps.length; ++i) {
            steps[i] = i;
        }
        for (uint256 i = clears.commands.length; i > 0; --i) {
            uint256 pick = orderSeed % i;
            orderSeed /= i;
            plan_ = plan_.add(uint8(clears.commands[steps[pick]]), clears.inputs[steps[pick]]);
            steps[pick] = steps[i - 1];
        }
        swapKind = bound(swapKind, 0, 2);
        if (swapKind != 0 && swapsFirst) plan_ = _addSwap(plan_, swapKind, zeroForOne, amountIn);
        plan_ = plan_.settleRequests();
        if (swapKind != 0 && !swapsFirst) plan_ = _addSwap(plan_, swapKind, zeroForOne, amountIn);
    }

    function _addSwap(Plan.Steps memory plan_, uint256 swapKind, bool zeroForOne, uint256 amountIn)
        internal
        view
        returns (Plan.Steps memory)
    {
        uint256 buffer = zeroForOne ? ALM_CORE.bufferAmount0() : ALM_CORE.bufferAmount1();
        if (buffer == 0) return plan_;
        amountIn = bound(amountIn, 1, buffer);
        if (swapKind == 1) {
            return plan_.swapViaPool(
                zeroForOne, amountIn, zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1, 0
            );
        }
        return plan_.add(CommandLogic.SWAP_VIA_ROUTER, _routerPayload(zeroForOne, amountIn));
    }

    function _refusedWhilePaused(Plan.Steps memory plan_) internal pure returns (bool refused) {
        for (uint256 i; i < plan_.commands.length; ++i) {
            uint8 command = uint8(plan_.commands[i]);
            if (CommandLogic.pausable(command)) return true;
            bool clears = command == CommandLogic.CLEAR_REQUESTS || command == CommandLogic.CLEAR_ALL_REQUESTS;
            if (clears && plan_.inputs[i].length > 1 && plan_.inputs[i][1] != 0) return true;
        }
    }

    function _countCommands(Plan.Steps memory plan_) internal pure returns (bool onlyQueueSteps, bool opens) {
        onlyQueueSteps = true;
        for (uint256 i; i < plan_.commands.length; ++i) {
            uint8 command = uint8(plan_.commands[i]);
            if (command > CommandLogic.CANCEL_REQUESTS && command != CommandLogic.SETTLE_REQUESTS) {
                onlyQueueSteps = false;
            }
            if (command == CommandLogic.OPEN_RANGE) opens = true;
        }
    }

    function _ticks(int24 tickLower, int24 tickUpper) internal view returns (int24 lower, int24 upper) {
        int256 lowerIndex =
            bound(int256(tickLower), TickMath.MIN_TICK / TICK_SPACING, TickMath.MAX_TICK / TICK_SPACING - 1);
        int256 upperIndex = bound(int256(tickUpper), lowerIndex + 1, TickMath.MAX_TICK / TICK_SPACING);
        lower = int24(lowerIndex * TICK_SPACING);
        upper = int24(upperIndex * TICK_SPACING);
    }

    function _land() internal {
        uint256 next = ALM_CORE.lastPlanAt_() + ALM_CORE.minPlanInterval_();
        uint256 timestamp = vm.getBlockTimestamp();
        if (timestamp >= next) return;
        vm.roll(vm.getBlockNumber() + (next - timestamp).divUp(BLOCK_TIME));
        vm.warp(next);
    }

    function _run(Plan.Steps memory plan_, bytes4 selector) internal returns (bool executed) {
        (uint160 sqrtPriceX96,,,,,) = POOL.slot0();
        executed = _runAt(plan_, selector, sqrtPriceX96, true);
    }

    function _runAt(Plan.Steps memory plan_, bytes4 selector, uint160 trustedSqrtPriceX96, bool land)
        internal
        returns (bool executed)
    {
        if (land) _land();
        (uint160 sqrtPriceX96,,,,,) = POOL.slot0();
        _snapshotPlan(trustedSqrtPriceX96);
        lastInBands = _inBands(sqrtPriceX96, trustedSqrtPriceX96);
        if (!lastInBands) ghostTrustedOutsideDraws++;

        bool paused = ALM_CORE.paused_();
        bool sentinelSized = _sentinelSized(plan_);
        if (sentinelSized) ghostSentinelPlans++;
        _measureSettlement(plan_, trustedSqrtPriceX96);
        CORE_HANDLER.trackFairShares();
        CORE_HANDLER.watchPending();
        vm.recordLogs();
        vm.prank(KEEPER);
        try ALM_CORE.execute(plan_.commands, plan_.inputs, trustedSqrtPriceX96) {
            executed = true;
            ghostCheckpoints++;
            if (paused && _refusedWhilePaused(plan_)) ghostPausedAccepts++;
            if (vm.getBlockTimestamp() < earliestPlanAt) ghostPlanSpacingBreaches++;
            if (!lastInBands) ghostTrustedOutsideAccepts++;
        } catch (bytes memory reason) {
            _recordRevert(selector, reason);
            lastRefusal = _selectorOf(reason);
            _classifyRefusal(plan_);
            if (lastInBands && lastRefusal == ConfigLib.PriceDeviation.selector) ghostTrustedInsideRefusals++;
            if (
                sentinelSized && sqrtPriceX96 == trustedSqrtPriceX96
                    && lastRefusal == PoolTokensLib.InsufficientBuffer.selector
                    && _queueStepsPay(plan_, trustedSqrtPriceX96)
            ) ghostSentinelPayoutShortfalls++;
        }
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        if (!skipPendingCheck) CORE_HANDLER.countPendingMoves(cancelled, cancelled);
        if (!executed) return false;
        CORE_HANDLER.noteMove(CORE_HANDLER.MOVE_PLAN());
        CORE_HANDLER.noteSettlements(logs);
        _countSwaps(logs);
        _checkSwapCost(logs, sqrtPriceX96);
        _checkGains();
        _checkRanges(plan_);
        _checkPlan(plan_, trustedSqrtPriceX96);
    }

    function _classifyRefusal(Plan.Steps memory plan_) internal {
        if (lastRefusal == ALMKeeperExtension.TooManySwaps.selector) {
            uint256 swaps;
            for (uint256 i; i < plan_.commands.length; ++i) {
                uint8 command = uint8(plan_.commands[i]);
                if (command == CommandLogic.SWAP_VIA_POOL || command == CommandLogic.SWAP_VIA_ROUTER) ++swaps;
            }
            if (swaps < 2) ghostWrongRefusals++;
            else ghostTooManySwapsRefusals++;
        } else if (lastRefusal == ALMKeeperExtension.InvalidOrder.selector) {
            if (_breaksOrder(plan_)) ghostOrderRefusals++;
            else ghostWrongRefusals++;
        }
    }

    function _breaksOrder(Plan.Steps memory plan_) internal pure returns (bool breaks) {
        bool unsettled;
        bool queueClosed;
        for (uint256 i; i < plan_.commands.length; ++i) {
            uint8 command = uint8(plan_.commands[i]);
            if (command <= CommandLogic.CANCEL_REQUESTS && queueClosed) return true;
            if (command > CommandLogic.CANCEL_REQUESTS) queueClosed = true;
            if (command == CommandLogic.CLEAR_REQUESTS || command == CommandLogic.CLEAR_ALL_REQUESTS) unsettled = true;
            if (command == CommandLogic.SETTLE_REQUESTS) unsettled = false;
            if (command >= CommandLogic.OPEN_RANGE && unsettled) return true;
        }
        breaks = unsettled;
    }

    function _countSwaps(VmSafe.Log[] memory logs) internal {
        uint256 swaps;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(POOL) && logs[i].topics[0] == SWAP_TOPIC) ++swaps;
        }
        ghostSwapsExecuted += swaps;
        if (swaps > 1) ghostMultiSwapPlans++;
    }

    function _sentinelSized(Plan.Steps memory plan_) internal pure returns (bool sized) {
        // 0 before the sentinel steps, 1 after the swap, 2 after an amount step.
        uint256 phase;
        for (uint256 i; i < plan_.commands.length; ++i) {
            uint8 command = uint8(plan_.commands[i]);
            bytes memory input = plan_.inputs[i];
            if (command == CommandLogic.SETTLE_REQUESTS) continue;
            if (command >= CommandLogic.OPEN_RANGE && command <= CommandLogic.INCREASE_STAKED_LIQUIDITY) {
                uint256 offset = command == CommandLogic.OPEN_RANGE ? 6 : 13;
                if (!_isSentinel(_word(input, offset), false) || !_isSentinel(_word(input, offset + 32), false)) {
                    return false;
                }
                phase = 2;
            } else if (command == CommandLogic.SWAP_VIA_POOL) {
                if (phase != 0 || !_isSentinel(_word(input, 1), true)) return false;
                phase = 1;
            } else if (phase != 0 || command == CommandLogic.SWAP_VIA_ROUTER) {
                return false;
            }
        }
        sized = phase != 0;
    }

    function _isSentinel(uint256 amount, bool isSwap) internal pure returns (bool sentinel) {
        sentinel =
            amount == 0 || amount & Sentinels.OPEN_BALANCE != 0 || (isSwap && amount & Sentinels.TO_TARGET_RATIO != 0);
    }

    function _word(bytes memory input, uint256 offset) internal pure returns (uint256 word) {
        assembly {
            word := mload(add(add(input, 32), offset))
        }
    }

    function _queueStepsPay(Plan.Steps memory plan_, uint160 trustedSqrtPriceX96) internal returns (bool paid) {
        Plan.Steps memory queue = Plan.init();
        for (uint256 i; i < plan_.commands.length; ++i) {
            uint8 command = uint8(plan_.commands[i]);
            if (command <= CommandLogic.CANCEL_REQUESTS) queue = queue.add(command, plan_.inputs[i]);
        }
        queue = queue.settleRequests();
        uint256 snapshot = vm.snapshotState();
        vm.prank(KEEPER);
        try ALM_CORE.execute(queue.commands, queue.inputs, trustedSqrtPriceX96) {
            paid = true;
        } catch { }
        vm.revertToStateAndDelete(snapshot);
    }

    function _measureSettlement(Plan.Steps memory plan_, uint160 trustedSqrtPriceX96) internal {
        Plan.Steps memory prefix = Plan.init();
        bool clears;
        swappedBeforeSettlement = false;
        for (uint256 i; i < plan_.commands.length; ++i) {
            uint8 command = uint8(plan_.commands[i]);
            prefix = prefix.add(command, plan_.inputs[i]);
            if (command == CommandLogic.SETTLE_REQUESTS) break;
            if (command == CommandLogic.CLEAR_REQUESTS || command == CommandLogic.CLEAR_ALL_REQUESTS) clears = true;
            if (command == CommandLogic.SWAP_VIA_POOL || command == CommandLogic.SWAP_VIA_ROUTER) {
                swappedBeforeSettlement = true;
            }
        }
        settlesAtTheEnd = prefix.commands.length == plan_.commands.length;
        settlementMeasured = false;
        if (settlesAtTheEnd || !clears) return;

        uint256 snapshot = vm.snapshotState();
        bool measured;
        uint256 value;
        vm.prank(KEEPER);
        try ALM_CORE.execute(prefix.commands, prefix.inputs, trustedSqrtPriceX96) {
            (measured, value) = (true, _value(trustedSqrtPriceX96));
        } catch { }
        vm.revertToStateAndDelete(snapshot);
        (settlementMeasured, settlementValue) = (measured, value);
    }

    function _countRefusal(bool executed, bytes4 expected, uint8 command) internal {
        ghostRefusalsTried++;
        if (executed) {
            ghostRefusedStepsAccepted++;
            return;
        }
        if (lastRefusal == expected || lastRefusal == ConfigLib.PriceDeviation.selector) return;
        if (lastRefusal == ALMKeeperExtension.Paused.selector && CommandLogic.pausable(command)) return;
        ghostWrongRefusals++;
    }

    function _inBands(uint160 sqrtPriceX96, uint160 trustedSqrtPriceX96) internal view returns (bool inside) {
        (uint256 lower, uint256 upper) = CLMath.getBand(trustedSqrtPriceX96, ALM_CORE.maxSpotFromTrusted_());
        inside = sqrtPriceX96 >= lower && sqrtPriceX96 <= upper;
        (lower, upper) = CLMath.getBand(trustedSqrtPriceX96, ALM_CORE.maxTwapFromTrusted_());
        uint256 twapSqrtPriceX96 = ALM_CORE.meanSqrtPriceX96_();
        inside = inside && twapSqrtPriceX96 >= lower && twapSqrtPriceX96 <= upper;
    }

    function _checkSwapCost(VmSafe.Log[] memory logs, uint160 sqrtPriceX96) internal {
        (int256 delta0, int256 delta1) = _swapDelta(logs);
        if (delta0 >= 0 && delta1 >= 0) return;
        ghostSwapsChecked++;
        bool zeroForOne = delta0 < 0;
        int256 bought = zeroForOne ? delta1 : delta0;
        uint256 bps = ALM_CORE.BPS_DENOMINATOR_();
        uint256 floor = CLMath.convert(sqrtPriceX96, zeroForOne, uint256(-(zeroForOne ? delta0 : delta1)), false)
            .fullMulDivUp(bps - ALM_CORE.maxSwapCostBps_(), bps);
        if (bought < 0 || uint256(bought) < floor) ghostSwapCostBreaches++;
    }

    function _swapDelta(VmSafe.Log[] memory logs) internal view returns (int256 delta0, int256 delta1) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(ALM_CORE) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] != IALMCoreEvents.PlanExecuted.selector) continue;
            (,,,,, delta0, delta1) =
                abi.decode(logs[i].data, (uint256, uint160, uint256, uint256, uint256, int256, int256));
        }
    }

    function _checkGains() internal {
        address rewardToken = ALM_CORE.REWARD_TOKEN_();
        bool rewardIsPoolToken = rewardToken == ALM_CORE.token0() || rewardToken == ALM_CORE.token1();
        for (uint256 i; i < watched.length; ++i) {
            uint256[3] memory balances = _balances(watched[i]);
            uint256[3] memory before = watchedBefore[i];
            if (balances[0] != before[0] + _refund(watched[i], ASYNC_VAULT0)) ghostPlanGains++;
            if (balances[1] != before[1] + _refund(watched[i], ASYNC_VAULT1)) ghostPlanGains++;
            if (!rewardIsPoolToken && balances[2] != before[2]) ghostPlanGains++;
        }
    }

    function _refund(address account, address vault) internal view returns (uint256 refund) {
        Record memory before = recordsBefore[vault][true][account];
        if (before.amountIn == 0 || before.epoch != pendingEpochBefore[vault][true]) return 0;
        if (ALM_CORE.depositRecord(vault, account).amountIn == 0) refund = before.amountIn;
    }

    function _balances(address account) internal view returns (uint256[3] memory balances) {
        balances = [
            ERC20Mock(ALM_CORE.token0()).balanceOf(account),
            ERC20Mock(ALM_CORE.token1()).balanceOf(account),
            ERC20Mock(ALM_CORE.REWARD_TOKEN_()).balanceOf(account)
        ];
    }

    function _checkRanges(Plan.Steps memory plan_) internal {
        (bool stakes, bool unstakes, bool restakes, bool closes, uint256 opens) = _rangeCommands(plan_);
        uint256 length = ALM_CORE.getRangesLength();
        uint256 kept;
        for (uint256 i; i < rangesSnapshot.length; ++i) {
            Range memory before = rangesSnapshot[i];
            (bool found, Range memory range) = _findRange(before.unstakedTokenId, length);
            if (!found) {
                if (!closes || (before.stakedTokenId != 0 && !unstakes)) ghostIllegalRangeMoves++;
                continue;
            }
            ++kept;
            if (range.tickLower != before.tickLower || range.tickUpper != before.tickUpper) ghostIllegalRangeMoves++;
            if (range.stakedTokenId == before.stakedTokenId) continue;
            bool legal = before.stakedTokenId == 0
                ? stakes
                : (range.stakedTokenId == 0 ? unstakes : stakes || unstakes || restakes);
            if (!legal) ghostIllegalRangeMoves++;
        }
        if (length - kept > opens) ghostIllegalRangeMoves++;
    }

    function _findRange(uint256 unstakedTokenId, uint256 length)
        internal
        view
        returns (bool found, Range memory range)
    {
        for (uint256 i; i < length; ++i) {
            range = ALM_CORE.getRange(i);
            if (range.unstakedTokenId == unstakedTokenId) return (true, range);
        }
    }

    function _rangeCommands(Plan.Steps memory plan_)
        internal
        pure
        returns (bool stakes, bool unstakes, bool restakes, bool closes, uint256 opens)
    {
        for (uint256 i; i < plan_.commands.length; ++i) {
            uint8 command = uint8(plan_.commands[i]);
            if (command == CommandLogic.STAKE) stakes = true;
            if (command == CommandLogic.UNSTAKE || command == CommandLogic.EMERGENCY_UNSTAKE) unstakes = true;
            if (command == CommandLogic.INCREASE_STAKED_LIQUIDITY) restakes = true;
            if (command == CommandLogic.CLOSE_RANGE) closes = true;
            if (command == CommandLogic.OPEN_RANGE) ++opens;
        }
    }

    function _snapshotPlan(uint160 trustedSqrtPriceX96) internal {
        (supplyBefore, rangesBefore) = (ALM_CORE.totalSupply(), ALM_CORE.getRangesLength());
        valueBefore = _value(trustedSqrtPriceX96);
        uint256 bps = ALM_CORE.BPS_DENOMINATOR_();
        valueFloor = valueBefore.fullMulDiv(bps - ALM_CORE.maxShortfallBps_(), bps);
        earliestPlanAt = ALM_CORE.lastPlanAt_() + ALM_CORE.minPlanInterval_();
        _snapshotQueues();
        delete watchedBefore;
        for (uint256 i; i < watched.length; ++i) {
            watchedBefore.push(_balances(watched[i]));
        }
        delete rangesSnapshot;
        for (uint256 i; i < rangesBefore; ++i) {
            rangesSnapshot.push(ALM_CORE.getRange(i));
        }
    }

    function _checkPlan(Plan.Steps memory plan_, uint160 trustedSqrtPriceX96) internal {
        if (plan_.commands.length > 1) ghostMultiStepPlans++;
        (bool onlyQueueSteps, bool opens) = _countCommands(plan_);
        if (opens && ALM_CORE.getRangesLength() > ALM_CORE.rangeCap_()) ghostRangeCapBreaches++;
        _checkSettlement(trustedSqrtPriceX96, rangesBefore + plan_.commands.length);
        uint256 supplyAfter = ALM_CORE.totalSupply();
        if (supplyAfter == 0) return;
        ghostPlansExecuted++;

        uint256 unit = 3 + CLMath.convert(trustedSqrtPriceX96, true, 1, false);
        uint256 valueAfter = _value(trustedSqrtPriceX96);
        uint256 tolerance = (ALM_CORE.getRangesLength() + 4) * unit;
        if (onlyQueueSteps && (valueAfter + tolerance).fullMulDiv(supplyBefore, supplyAfter) < valueBefore) {
            ghostSettleOnlyLosses++;
        }

        tolerance = (ALM_CORE.getRangesLength() + plan_.commands.length + 2) * unit
            + ((rangesBefore + 1) * unit).fullMulDivUp(supplyAfter, supplyBefore);
        if ((valueAfter + tolerance).fullMulDiv(supplyBefore, supplyAfter) < valueFloor) ghostLossBoundBreaches++;
    }

    function _snapshotQueues() internal {
        escrowedSharesBefore = ALM_CORE.balanceOf(address(ALM_CORE));
        (escrowed0Before, escrowed1Before) = (ALM_CORE.getEscrowed0(), ALM_CORE.getEscrowed1());
        _snapshotQueue(ASYNC_VAULT0);
        _snapshotQueue(ASYNC_VAULT1);
    }

    function _snapshotQueue(address vault) internal {
        (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = ALM_CORE.pendingEpochs(vault);
        (uint32 lastClearedDepositEpoch, uint32 lastClearedRedeemEpoch) = ALM_CORE.lastClearedEpochs(vault);
        (pendingEpochBefore[vault][true], pendingEpochBefore[vault][false]) = (pendingDepositEpoch, pendingRedeemEpoch);
        highestEpochBefore[vault][true] = FixedPointMathLib.max(pendingDepositEpoch, lastClearedDepositEpoch);
        highestEpochBefore[vault][false] = FixedPointMathLib.max(pendingRedeemEpoch, lastClearedRedeemEpoch);
        for (uint256 i; i < CORE_HANDLER.actorsLength(); ++i) {
            address controller = CORE_HANDLER.actorAt(i);
            recordsBefore[vault][true][controller] = ALM_CORE.depositRecord(vault, controller);
            recordsBefore[vault][false][controller] = ALM_CORE.redeemRecord(vault, controller);
        }
    }

    function _settled(address vault, bool isDeposit) internal {
        (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = ALM_CORE.pendingEpochs(vault);
        uint256 pendingEpoch = isDeposit ? pendingDepositEpoch : pendingRedeemEpoch;
        (cleared[vault][isDeposit], cancelledIn[vault][isDeposit]) = (0, 0);
        for (uint256 i; i < CORE_HANDLER.actorsLength(); ++i) {
            address controller = CORE_HANDLER.actorAt(i);
            Record memory before = recordsBefore[vault][isDeposit][controller];
            if (before.amountIn == 0 || before.epoch != pendingEpochBefore[vault][isDeposit]) continue;
            Record memory record =
                isDeposit ? ALM_CORE.depositRecord(vault, controller) : ALM_CORE.redeemRecord(vault, controller);
            if (record.amountIn == 0) {
                cancelledIn[vault][isDeposit] += before.amountIn;
            } else if (record.epoch != pendingEpoch) {
                cleared[vault][isDeposit] += before.amountIn;
                clearedEpoch[vault][isDeposit] = record.epoch;
            }
        }
        if (cleared[vault][isDeposit] == 0) return;
        (uint32 lastClearedDepositEpoch, uint32 lastClearedRedeemEpoch) = ALM_CORE.lastClearedEpochs(vault);
        uint256 highest =
            FixedPointMathLib.max(pendingEpoch, isDeposit ? lastClearedDepositEpoch : lastClearedRedeemEpoch);
        if (highest <= highestEpochBefore[vault][isDeposit]) ghostEpochIdBreaches++;
    }

    function _epochOut(address vault, bool isDeposit) internal view returns (uint256 amountOut) {
        if (cleared[vault][isDeposit] == 0) return 0;
        uint32 epoch = clearedEpoch[vault][isDeposit];
        amountOut =
            isDeposit ? ALM_CORE.depositEpoch(vault, epoch).amountOut : ALM_CORE.redeemEpoch(vault, epoch).amountOut;
    }

    function _checkSettlement(uint160 trustedSqrtPriceX96, uint256 steps) internal {
        _settled(ASYNC_VAULT0, true);
        _settled(ASYNC_VAULT1, true);
        _settled(ASYNC_VAULT0, false);
        _settled(ASYNC_VAULT1, false);

        (bool consistent, uint256 paid0, uint256 paid1) = _checkEscrow();
        if (!consistent) return;
        uint256 deposited1 = cleared[ASYNC_VAULT1][true];
        uint256 depositValue0 = CLMath.convert(trustedSqrtPriceX96, true, cleared[ASYNC_VAULT0][true], false);
        if (depositValue0 + deposited1 + cleared[ASYNC_VAULT0][false] + cleared[ASYNC_VAULT1][false] == 0) return;
        if (!settlesAtTheEnd && !settlementMeasured) {
            ghostSettlementsUnmeasured++;
            return;
        }
        ghostSettlementsChecked++;

        uint256 held = (settlesAtTheEnd ? _value(trustedSqrtPriceX96) : settlementValue)
            + CLMath.convert(trustedSqrtPriceX96, true, paid0, false) + paid1;
        uint256 tolerance =
            (ALM_CORE.getRangesLength() + steps) * (3 + CLMath.convert(trustedSqrtPriceX96, true, 1, false));
        if (held > depositValue0 + deposited1 + tolerance) {
            uint256 value = held - depositValue0 - deposited1 - tolerance;
            if (_epochOut(ASYNC_VAULT0, true).fullMulDiv(value, supplyBefore) > depositValue0) {
                ghostSettlementBreaches++;
            }
            if (_epochOut(ASYNC_VAULT1, true).fullMulDiv(value, supplyBefore) > deposited1) ghostSettlementBreaches++;
        }
        _checkRedeems(
            CLMath.convert(trustedSqrtPriceX96, true, paid0, false),
            paid1,
            held + tolerance - (swappedBeforeSettlement ? 0 : FixedPointMathLib.min(depositValue0 + deposited1, held))
        );
    }

    function _checkRedeems(uint256 paidValue0, uint256 paid1, uint256 ceiling) internal {
        uint256 redeemed0 = cleared[ASYNC_VAULT0][false];
        uint256 redeemed1 = cleared[ASYNC_VAULT1][false];
        if (redeemed0 != 0 && paidValue0.fullMulDiv(supplyBefore, redeemed0) > ceiling) ghostSettlementBreaches++;
        if (redeemed1 != 0 && paid1.fullMulDiv(supplyBefore, redeemed1) > ceiling) ghostSettlementBreaches++;
    }

    function _checkEscrow() internal returns (bool consistent, uint256 paid0, uint256 paid1) {
        uint256 redeemed = cleared[ASYNC_VAULT0][false] + cleared[ASYNC_VAULT1][false];
        uint256 escrowedShares = ALM_CORE.balanceOf(address(ALM_CORE)) + redeemed + cancelledIn[ASYNC_VAULT0][false]
            + cancelledIn[ASYNC_VAULT1][false];
        if (escrowedShares < escrowedSharesBefore) {
            ghostSettlementMismatches++;
            return (false, 0, 0);
        }
        uint256 minted = escrowedShares - escrowedSharesBefore;
        ghostSharesSettledIn += minted;
        ghostSharesSettledOut += redeemed;
        if (minted > 0 && ALM_CORE.totalSupply() > ALM_CORE.totalCap_()) ghostTotalCapBreaches++;
        if (_epochOut(ASYNC_VAULT0, true) + _epochOut(ASYNC_VAULT1, true) != minted) ghostSettlementMismatches++;

        paid0 = ALM_CORE.getEscrowed0() + cleared[ASYNC_VAULT0][true] + cancelledIn[ASYNC_VAULT0][true];
        paid1 = ALM_CORE.getEscrowed1() + cleared[ASYNC_VAULT1][true] + cancelledIn[ASYNC_VAULT1][true];
        if (paid0 < escrowed0Before || paid1 < escrowed1Before) {
            ghostSettlementMismatches++;
            return (false, 0, 0);
        }
        (consistent, paid0, paid1) = (true, paid0 - escrowed0Before, paid1 - escrowed1Before);
        if (paid0 != _epochOut(ASYNC_VAULT0, false)) ghostSettlementMismatches++;
        if (paid1 != _epochOut(ASYNC_VAULT1, false)) ghostSettlementMismatches++;
    }

    function _value(uint160 sqrtPriceX96) internal view returns (uint256 value) {
        (uint256 amount0, uint256 amount1) = _holdings(
            IALMCore(address(ALM_CORE)).getSnapshot(address(POOL), address(this)).ranges,
            sqrtPriceX96,
            ALM_CORE.bufferAmount0(),
            ALM_CORE.bufferAmount1()
        );
        value = amount1 + CLMath.convert(sqrtPriceX96, true, amount0, false);
    }

    function _trusted(uint256 seed) internal view returns (uint160 trustedSqrtPriceX96) {
        (uint160 sqrtPriceX96,,,,,) = POOL.slot0();
        (uint256 sqrtPriceLowerX96, uint256 sqrtPriceUpperX96) =
            CLMath.getBand(sqrtPriceX96, ALM_CORE.maxSpotFromTrusted_());
        (uint256 twapLowerX96, uint256 twapUpperX96) =
            CLMath.getBand(ALM_CORE.meanSqrtPriceX96_(), ALM_CORE.maxTwapFromTrusted_());
        uint256 lower = FixedPointMathLib.max(sqrtPriceLowerX96, twapLowerX96);
        uint256 upper = FixedPointMathLib.min(sqrtPriceUpperX96, twapUpperX96);
        if (lower > upper) (lower, upper) = (sqrtPriceLowerX96, sqrtPriceUpperX96);
        trustedSqrtPriceX96 = uint160(bound(seed, lower, upper));
    }

    function _edge(uint256 seed) internal view returns (uint160 trustedSqrtPriceX96) {
        (uint160 sqrtPriceX96,,,,,) = POOL.slot0();
        (uint256 lower, uint256 upper) = seed & 2 == 0
            ? CLMath.getBand(sqrtPriceX96, ALM_CORE.maxSpotFromTrusted_())
            : CLMath.getBand(ALM_CORE.meanSqrtPriceX96_(), ALM_CORE.maxTwapFromTrusted_());
        trustedSqrtPriceX96 = uint160((seed & 1 == 0 ? lower : upper) + bound(seed >> 2, 0, 2) - 1);
    }

    function _afterAction() internal override {
        CORE_HANDLER.checkMonotone();
    }
}
