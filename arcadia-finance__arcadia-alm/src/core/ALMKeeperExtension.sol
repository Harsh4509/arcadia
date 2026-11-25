/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ALMCore } from "./ALMCore.sol";
import { BaseExtension } from "./abstracts/base/BaseExtension.sol";
import { CalldataLogic } from "./libraries/logic/CalldataLogic.sol";
import { CLMath } from "../shared/libraries/math/CLMath.sol";
import { CommandLogic } from "./libraries/logic/CommandLogic.sol";
import { ConfigLib } from "./libraries/state/ConfigLib.sol";
import { CoreImmutables } from "./types/CoreImmutables.sol";
import { EmissionsLogic } from "./libraries/logic/EmissionsLogic.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMFactory } from "../interfaces/IALMFactory.sol";
import { IMetadexCLGaugeFactory } from "../interfaces/IMetadexCLGaugeFactory.sol";
import { IMetadexCLPool } from "../interfaces/IMetadexCLPool.sol";
import { IMetadexCLPositionManager } from "../interfaces/IMetadexCLPositionManager.sol";
import { IRouterTrampoline } from "../interfaces/IRouterTrampoline.sol";
import { LibTransient } from "@solady/utils/LibTransient.sol";
import { PlanCache, PlanCacheLib } from "./types/PlanCache.sol";
import { PositionManagerLogic } from "./libraries/logic/PositionManagerLogic.sol";
import { Queue, Record, State } from "./types/State.sol";
import { QueueLib } from "./libraries/state/QueueLib.sol";
import { Range } from "./types/Range.sol";
import { RangesLib } from "./libraries/state/RangesLib.sol";
import { RewardCheckpoint } from "./abstracts/mixins/RewardCheckpoint.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { Sentinels } from "./libraries/Sentinels.sol";
import { toTokenDelta, TokenAmounts, TokenDelta } from "./types/TokenDelta.sol";

/**
 * @title ALM Keeper Extension.
 * @author Pragma Labs
 * @notice The keeper plans of a core.
 */
// forge-lint: disable-next-item(block-timestamp, calls-loop, reentrancy-events, require-revert-in-loop, uninitialized-local, unsafe-typecast)
contract ALMKeeperExtension is BaseExtension {
    using FixedPointMathLib for uint256;
    using LibTransient for LibTransient.TBool;
    using SafeTransferLib for address;

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error AlreadyCleared();
    error InsufficientOutput();
    error InvalidOrder();
    error InvalidPrice();
    error LengthMismatch();
    error MaxSwapCostExceeded();
    error OnlyKeeper();
    error Paused();
    error PlanTooSoon();
    error RangeMismatch(uint256 index);
    error TooManySwaps();
    error UnknownCommand();

    /* //////////////////////////////////////////////////////////////
                              PLAN EXECUTION
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Runs one keeper plan, bounded by the price it was computed against and by its shortfall at that price.
     * @param commands One byte per step, each an opcode.
     * @param inputs The tight-packed payload of each step.
     * @param trustedSqrtPriceX96 The sqrt price the plan was computed against.
     */
    function execute(bytes calldata commands, bytes[] calldata inputs, uint160 trustedSqrtPriceX96)
        external
        nonReentrant
        onlyDelegated
    {
        // Checks.
        if (!IALMFactory(FACTORY).isKeeper(address(this), msg.sender)) revert OnlyKeeper();
        if (trustedSqrtPriceX96 == 0) revert InvalidPrice();
        if (commands.length != inputs.length) revert LengthMismatch();
        State storage state = _state();
        // Unchecked: both terms are uint32 values.
        unchecked {
            if (block.timestamp < uint256(state.config.lastPlanAt) + state.config.minPlanInterval) {
                revert PlanTooSoon();
            }
        }
        if (state.config.paused) {
            for (uint256 i; i < commands.length; ++i) {
                if (CommandLogic.pausable(uint8(commands[i]))) revert Paused();
            }
        }

        // Cache the core immutables.
        CoreImmutables memory immutables = CalldataLogic.decodeCoreImmutables();

        PlanCache memory cache;
        {
            // Check that the trusted price is within the deviation from the pool price.
            uint160 spotSqrtPriceX96 = state.config.checkTrustedDeviation(immutables.pool, trustedSqrtPriceX96);

            // Update State.
            state.config.lastPlanAt = SafeCastLib.toUint32(block.timestamp);

            // Collect the fees and calculate the principal of all ranges.
            (TokenDelta fees, uint256 amount0, uint256 amount1) =
                state.collectFees(POSITION_MANAGER, trustedSqrtPriceX96);

            // Update State.
            state.creditCollected(TokenDelta.wrap(0), fees);

            // Cache the plan.
            cache = PlanCacheLib.start(
                state, immutables, trustedSqrtPriceX96, spotSqrtPriceX96, totalSupply(), amount0, amount1
            );
        }

        // Reset the emissions checkpoint flag.
        _checkpointed().set(false);

        // Run every command of the plan, the clear and cancel steps first.
        uint8 previous;
        for (uint256 i; i < commands.length; ++i) {
            uint8 command = uint8(commands[i]);
            if (command <= CommandLogic.CANCEL_REQUESTS && previous > CommandLogic.CANCEL_REQUESTS) {
                revert InvalidOrder();
            }
            _dispatch(state, cache, command, inputs[i]);
            previous = command;
        }

        // Check that every cleared epoch is settled.
        if (cache.hasUnsettledEpochs()) revert InvalidOrder();

        // Check solvency.
        state.checkSolvency(immutables.token0, immutables.token1);

        // Cache the value and supply after the plan.
        uint256 valueAfter = cache.getValueAfter();
        uint256 supplyAfter = totalSupply();

        // Check that the shortfall stays within the max shortfall.
        cache.checkShortfall(state.config, valueAfter, supplyAfter);

        // Update State.
        state.share.setLastExchangeRate(trustedSqrtPriceX96, supplyAfter, valueAfter);

        emit PlanExecuted(
            commands.length,
            trustedSqrtPriceX96,
            cache.valueBefore,
            valueAfter,
            supplyAfter,
            cache.swapDelta.amount0(),
            cache.swapDelta.amount1()
        );
    }

    /**
     * @inheritdoc RewardCheckpoint
     */
    function _checkpoint() internal override {
        if (!_checkpointed().get()) {
            _checkpointed().set(true);
            ALMCore(payable(address(this))).checkpoint();
        }
    }

    /**
     * @notice Runs one step of a plan.
     * @param state The core state.
     * @param cache The plan cache.
     * @param command The opcode.
     * @param payload The tight-packed payload of this step.
     */
    function _dispatch(State storage state, PlanCache memory cache, uint8 command, bytes calldata payload) internal {
        uint8 kind = command >> 4;
        if (kind == 0) {
            if (command == CommandLogic.CLEAR_REQUESTS) {
                _clearRequests(cache, payload);
            } else if (command == CommandLogic.CLEAR_ALL_REQUESTS) {
                _clearAllRequests(state, cache, payload);
            } else if (command == CommandLogic.CANCEL_REQUESTS) {
                _cancelRequests(cache, payload);
            } else if (command == CommandLogic.SETTLE_REQUESTS) {
                _settleEpochs(state, cache);
            } else {
                revert UnknownCommand();
            }
        } else if (kind == 1) {
            if (command == CommandLogic.CLOSE_RANGE) {
                _closeRange(state, cache, payload);
            } else if (command == CommandLogic.DECREASE_LIQUIDITY || command == CommandLogic.UNSTAKE) {
                _decreaseLiquidity(state, cache, payload, command == CommandLogic.UNSTAKE);
            } else if (command == CommandLogic.COLLECT) {
                _collect(state, cache, payload);
            } else if (command == CommandLogic.EMERGENCY_UNSTAKE) {
                _emergencyUnstake(state, cache, payload);
            } else {
                revert UnknownCommand();
            }
        } else if (kind == 2) {
            if (command == CommandLogic.SWAP_VIA_POOL) {
                _swapViaPool(state, cache, payload);
            } else if (command == CommandLogic.SWAP_VIA_ROUTER) {
                _swapViaRouter(state, cache, payload);
            } else {
                revert UnknownCommand();
            }
        } else {
            // Check that every cleared epoch is settled.
            if (cache.hasUnsettledEpochs()) revert InvalidOrder();

            if (command == CommandLogic.OPEN_RANGE) {
                _openRange(state, cache, payload);
            } else if (command == CommandLogic.INCREASE_LIQUIDITY || command == CommandLogic.INCREASE_STAKED_LIQUIDITY)
            {
                _increaseLiquidity(state, cache, payload, command == CommandLogic.INCREASE_STAKED_LIQUIDITY);
            } else if (command == CommandLogic.STAKE) {
                _stake(state, cache, payload);
            } else {
                revert UnknownCommand();
            }
        }
    }

    /* //////////////////////////////////////////////////////////////
                                TEARDOWN
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Closes a range, releasing its unstaked side into the buffer and burning it.
     * @param state The core state.
     * @param cache The plan cache.
     * @param payload The tight-packed payload of this step.
     */
    function _closeRange(State storage state, PlanCache memory cache, bytes calldata payload) internal {
        // Decode payload.
        (uint256 index, uint256 tokenId) = CalldataLogic.decodeRange(payload);

        // Checks.
        _rangeAt(cache, index, tokenId, false);

        // Remove the unstaked side's liquidity, collect its fees and burn its position.
        uint256 lastIndex;
        // Unchecked: _rangeAt found a range at the index.
        unchecked {
            lastIndex = state.ranges.length - 1;
        }
        (int24 tickLower, int24 tickUpper, uint128 liquidity, TokenDelta principal, TokenDelta fees) =
            state.closeRange(POSITION_MANAGER, index, lastIndex);

        // Update State.
        TokenDelta delta = state.creditCollected(principal, fees);

        // Update Plan Cache.
        cache.closeRange(index, lastIndex);
        // Unchecked: the liquidity is a uint128.
        unchecked {
            cache.applyLiquidityDelta(tickLower, tickUpper, -int256(uint256(liquidity)));
        }
        cache.applyBufferDelta(delta);
    }

    /**
     * @notice Removes liquidity from one side of a range into the buffer.
     * @param state The core state.
     * @param cache The plan cache.
     * @param payload The tight-packed payload of this step.
     * @param staked True for the staked side.
     */
    function _decreaseLiquidity(State storage state, PlanCache memory cache, bytes calldata payload, bool staked)
        internal
    {
        // Decode payload.
        (uint256 index, IMetadexCLPositionManager.DecreaseLiquidityParams memory params, bool acceptPenalty) =
            CalldataLogic.decodeDecrease(payload, staked);

        // Get the range the step names.
        Range storage range = _rangeAt(cache, index, params.tokenId, staked);

        // If the payload asks for the side's whole liquidity, set it to the side's liquidity.
        if (params.liquidity == Sentinels.RANGE_LIQUIDITY) {
            params.liquidity = staked
                ? range.stakedLiquidity
                : IMetadexCLPositionManager(POSITION_MANAGER).positions(range.unstakedTokenId).liquidity;
        }

        // Remove the liquidity from the range's side and collect its fees.
        TokenDelta principal;
        TokenDelta fees;
        if (staked) {
            IMetadexCLGaugeFactory.PenaltyConfig memory config =
                IMetadexCLGaugeFactory(GAUGE_FACTORY).effectivePenaltyConfig(cache.immutables.gauge);
            bool windowOpen =
                !acceptPenalty && EmissionsLogic.isPenaltyWindowOpen(range.stakedBlock, config, cache.blockNumber);
            (principal, fees) = RangesLib.decreaseStakedLiquidity(
                state, POSITION_MANAGER, index, cache.immutables.gauge, params, windowOpen, false, config
            );
        } else {
            params.tokenId = range.unstakedTokenId;
            (principal, fees) = PositionManagerLogic.decreaseLiquidityAndCollect(POSITION_MANAGER, params);
        }

        // Update State and Plan Cache.
        _applyDecrease(state, cache, range, params.liquidity, principal, fees);
    }

    /**
     * @notice Takes a range's whole staked side out of the gauge through its emergency withdraw, without a claim.
     * @param state The core state.
     * @param cache The plan cache.
     * @param payload The tight-packed payload of this step.
     */
    function _emergencyUnstake(State storage state, PlanCache memory cache, bytes calldata payload) internal {
        // Decode payload.
        (uint256 index, uint256 tokenId) = CalldataLogic.decodeRange(payload);

        // Get the range the step names.
        Range storage range = _rangeAt(cache, index, tokenId, true);

        // Remove the whole staked side through the gauge's emergency withdraw and collect its fees.
        IMetadexCLPositionManager.DecreaseLiquidityParams memory params;
        IMetadexCLGaugeFactory.PenaltyConfig memory config;
        (TokenDelta principal, TokenDelta fees) = RangesLib.decreaseStakedLiquidity(
            state, POSITION_MANAGER, index, cache.immutables.gauge, params, false, true, config
        );

        // Update State and Plan Cache.
        _applyDecrease(state, cache, range, params.liquidity, principal, fees);
    }

    /**
     * @notice Collects the accrued fees of one position into the buffer.
     * @param state The core state.
     * @param cache The plan cache.
     * @param payload The tight-packed payload of this step.
     * @dev Only collects the fees generated during the plan.
     */
    function _collect(State storage state, PlanCache memory cache, bytes calldata payload) internal {
        // Decode payload.
        IMetadexCLPositionManager.CollectParams memory params = CalldataLogic.decodePosition(payload);

        // Collect the position's fees.
        TokenDelta fees = PositionManagerLogic.collect(POSITION_MANAGER, params);

        // Update State.
        TokenDelta delta = state.creditCollected(TokenDelta.wrap(0), fees);

        // Update Plan Cache.
        cache.applyBufferDelta(delta);
    }

    /**
     * @notice Applies a decrease of one side of a range to the buffer and the plan cache.
     * @param state The core state.
     * @param cache The plan cache.
     * @param range The range.
     * @param liquidity The liquidity removed.
     * @param principal The principal released.
     * @param fees The fees collected.
     */
    function _applyDecrease(
        State storage state,
        PlanCache memory cache,
        Range storage range,
        uint128 liquidity,
        TokenDelta principal,
        TokenDelta fees
    ) internal {
        // Update State.
        TokenDelta delta = state.creditCollected(principal, fees);

        // Update Plan Cache.
        // Unchecked: the liquidity is a uint128.
        unchecked {
            cache.applyLiquidityDelta(range.tickLower, range.tickUpper, -int256(uint256(liquidity)));
        }
        cache.applyBufferDelta(delta);
    }

    /* //////////////////////////////////////////////////////////////
                                 BUILDUP
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Opens a range out of the buffer.
     * @param state The core state.
     * @param cache The plan cache.
     * @param payload The tight-packed payload of this step.
     */
    function _openRange(State storage state, PlanCache memory cache, bytes calldata payload) internal {
        // Decode payload.
        IMetadexCLPositionManager.MintParams memory params = CalldataLogic.decodeOpen(payload);
        params.amount0Desired = _amount(state, cache, true, params.amount0Desired);
        params.amount1Desired = _amount(state, cache, false, params.amount1Desired);

        // Set the pool tokens and the tick spacing of the position.
        (params.token0, params.token1, params.tickSpacing) =
        (cache.immutables.token0, cache.immutables.token1, cache.immutables.tickSpacing);

        // Mint the new range's unstaked position from the buffer.
        (uint128 liquidity, TokenDelta delta) = state.openRange(POSITION_MANAGER, params);

        // Update State.
        state.poolTokens.buffer.applyDelta(delta);

        // Update Plan Cache.
        // Unchecked: openRange pushed a range.
        unchecked {
            cache.openRange(state.ranges.length - 1);
        }
        cache.applyLiquidityDelta(params.tickLower, params.tickUpper, int256(uint256(liquidity)));
        cache.applyBufferDelta(delta);
    }

    /**
     * @notice Adds liquidity to one side of a range out of the buffer.
     * @param state The core state.
     * @param cache The plan cache.
     * @param payload The tight-packed payload of this step.
     * @param staked True for the staked side.
     */
    function _increaseLiquidity(State storage state, PlanCache memory cache, bytes calldata payload, bool staked)
        internal
    {
        // Decode payload.
        (uint256 index, IMetadexCLPositionManager.IncreaseLiquidityParams memory params, bool acceptPenalty) =
            CalldataLogic.decodeIncrease(payload, staked);
        params.amount0Desired = _amount(state, cache, true, params.amount0Desired);
        params.amount1Desired = _amount(state, cache, false, params.amount1Desired);

        // Get the range the step names.
        Range storage range = _rangeAt(cache, index, params.tokenId, staked);

        // Add liquidity to the range's side from the buffer.
        uint128 liquidity;
        TokenDelta delta;
        if (staked) {
            IMetadexCLGaugeFactory.PenaltyConfig memory config =
                IMetadexCLGaugeFactory(GAUGE_FACTORY).effectivePenaltyConfig(cache.immutables.gauge);
            bool windowOpen =
                !acceptPenalty && EmissionsLogic.isPenaltyWindowOpen(range.stakedBlock, config, cache.blockNumber);
            (liquidity, delta) = RangesLib.increaseStakedLiquidity(
                state, POSITION_MANAGER, index, cache.immutables.gauge, params, windowOpen, config
            );
        } else {
            params.tokenId = range.unstakedTokenId;
            (liquidity, delta) = PositionManagerLogic.increaseLiquidity(POSITION_MANAGER, params);
        }

        // Update State.
        state.poolTokens.buffer.applyDelta(delta);

        // Update Plan Cache.
        cache.applyLiquidityDelta(range.tickLower, range.tickUpper, int256(uint256(liquidity)));
        cache.applyBufferDelta(delta);
    }

    /**
     * @notice Mints the staked side of a range out of the buffer and stakes it.
     * @param state The core state.
     * @param cache The plan cache.
     * @param payload The tight-packed payload of this step.
     */
    function _stake(State storage state, PlanCache memory cache, bytes calldata payload) internal {
        // Decode payload.
        (uint256 index, uint256 tokenId, IMetadexCLPositionManager.MintParams memory params) =
            CalldataLogic.decodeStake(payload);
        params.amount0Desired = _amount(state, cache, true, params.amount0Desired);
        params.amount1Desired = _amount(state, cache, false, params.amount1Desired);

        // Get the range the step names.
        Range storage range = _rangeAt(cache, index, tokenId, false);

        // Set the pool tokens and the tick spacing of the position.
        (params.token0, params.token1, params.tickSpacing) =
        (cache.immutables.token0, cache.immutables.token1, cache.immutables.tickSpacing);

        // Mint the range's staked position from the buffer and deposit it in the gauge.
        (uint128 liquidity, TokenDelta delta) = state.mintStaked(
            POSITION_MANAGER,
            index,
            cache.immutables.gauge,
            params,
            IMetadexCLGaugeFactory(GAUGE_FACTORY).effectivePenaltyConfig(cache.immutables.gauge)
        );

        // Update State.
        state.poolTokens.buffer.applyDelta(delta);

        // Update Plan Cache.
        cache.applyLiquidityDelta(range.tickLower, range.tickUpper, int256(uint256(liquidity)));
        cache.applyBufferDelta(delta);
    }

    /* //////////////////////////////////////////////////////////////
                                  SWAPS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Swaps one buffer token for the other against the pool.
     * @param state The core state.
     * @param cache The plan cache.
     * @param payload The tight-packed payload of this step.
     */
    function _swapViaPool(State storage state, PlanCache memory cache, bytes calldata payload) internal {
        // Decode payload.
        (bool zeroForOne, uint256 amountIn, uint160 sqrtPriceLimitX96, uint256 minAmountOut) =
            CalldataLogic.decodeSwapViaPool(payload);
        amountIn = _amountIn(state, cache, zeroForOne, amountIn);

        // Checks.
        if (cache.swapDelta != TokenDelta.wrap(0)) revert TooManySwaps();

        // Swap in the pool.
        (int256 amount0, int256 amount1) = IMetadexCLPool(cache.immutables.pool)
            .swap(address(this), zeroForOne, SafeCastLib.toInt256(amountIn), sqrtPriceLimitX96, "");

        // Get the amounts in and out.
        uint256 amountInUsed;
        uint256 amountOut;
        // Unchecked: a swap's output is below 2^214.
        unchecked {
            (amountInUsed, amountOut) =
                zeroForOne ? (uint256(amount0), uint256(-amount1)) : (uint256(amount1), uint256(-amount0));
        }

        // Update State and Plan Cache.
        _applySwap(state, cache, zeroForOne, amountInUsed, 0, amountOut, minAmountOut);
    }

    /**
     * @notice Swaps one buffer token for the other on a router.
     * @param state The core state.
     * @param cache The plan cache.
     * @param payload The tight-packed payload of this step.
     */
    function _swapViaRouter(State storage state, PlanCache memory cache, bytes calldata payload) internal {
        // Decode payload.
        address router;
        bool zeroForOne;
        uint256 minAmountOut;
        bytes calldata data;
        uint256 amountIn;
        (router, amountIn, zeroForOne, minAmountOut, data) = CalldataLogic.decodeSwapViaRouter(payload);
        amountIn = _amountIn(state, cache, zeroForOne, amountIn);

        // Checks.
        if (cache.swapDelta != TokenDelta.wrap(0)) revert TooManySwaps();

        // Get the input and the output token of the swap.
        (address tokenIn, address tokenOut) = zeroForOne
            ? (cache.immutables.token0, cache.immutables.token1)
            : (cache.immutables.token1, cache.immutables.token0);

        // Transfer the input from the buffer to the router trampoline.
        tokenIn.safeTransfer(ROUTER_TRAMPOLINE, amountIn);

        // Swap via the router.
        (uint256 balanceIn, uint256 balanceOut) =
            IRouterTrampoline(ROUTER_TRAMPOLINE).execute(router, data, tokenIn, tokenOut, amountIn);

        // Update State and Plan Cache.
        _applySwap(state, cache, zeroForOne, amountIn, balanceIn, balanceOut, minAmountOut);
    }

    /**
     * @notice Applies a swap to the buffer and the plan cache.
     * @param state The core state.
     * @param cache The plan cache.
     * @param zeroForOne True when the swap sells token0 for token1.
     * @param amountIn The input token sent.
     * @param balanceIn The input token returned.
     * @param balanceOut The output token received.
     * @param minAmountOut The minimum amount of the output token.
     */
    function _applySwap(
        State storage state,
        PlanCache memory cache,
        bool zeroForOne,
        uint256 amountIn,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 minAmountOut
    ) internal {
        // Check that the swap returns at least the minimum output.
        if (balanceOut < minAmountOut) revert InsufficientOutput();

        // Check that the swap stays within the max swap cost.
        // Unchecked: maxSwapCostBps is at most BPS_DENOMINATOR.
        unchecked {
            if (
                balanceOut
                    < CLMath.convert(cache.spotSqrtPriceX96, zeroForOne, amountIn.zeroFloorSub(balanceIn), false)
                        .fullMulDivUp(
                            ConfigLib.BPS_DENOMINATOR - state.config.maxSwapCostBps, ConfigLib.BPS_DENOMINATOR
                        )
            ) revert MaxSwapCostExceeded();
        }

        // Calculate the buffer delta of the swap.
        int128 deltaIn;
        // Unchecked: both terms are non-negative int128 values.
        unchecked {
            deltaIn = SafeCastLib.toInt128(balanceIn) - SafeCastLib.toInt128(amountIn);
        }
        int128 deltaOut = SafeCastLib.toInt128(balanceOut);
        TokenDelta delta = zeroForOne ? toTokenDelta(deltaIn, deltaOut) : toTokenDelta(deltaOut, deltaIn);

        // Update State.
        state.poolTokens.buffer.applyDelta(delta);

        // Update Plan Cache.
        cache.applyBufferDelta(delta);
        cache.swapDelta = delta;
    }

    /* //////////////////////////////////////////////////////////////
                           REQUESTS SETTLEMENT
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Clears the named pending requests of a vault's queue into the plan's settlement.
     * @param cache The plan cache.
     * @param payload The vault side and the queue, then the controllers.
     */
    function _clearRequests(PlanCache memory cache, bytes calldata payload) internal {
        // Decode payload.
        (bool isToken0, bool isDeposit, uint256 count) = CalldataLogic.decodeControllers(payload);

        // Checks.
        State storage state = _state();
        if (isDeposit && state.config.paused) revert Paused();
        address vault = isToken0 ? cache.immutables.asyncVault0 : cache.immutables.asyncVault1;

        // Cache the queue and the amount the plan cleared of it.
        Queue storage queue = isDeposit ? state.vaultQueues[vault].deposits : state.vaultQueues[vault].redeems;
        uint256 cleared = cache.getCleared(isDeposit, isToken0);

        // Clear each named request.
        for (uint256 i; i < count; ++i) {
            // Get the controller of the entry.
            address controller = CalldataLogic.readController(payload, i);

            // If the request is not pending, skip it.
            Record storage record = queue.records[controller];
            uint256 amountIn = record.amountIn;
            if (!QueueLib.isPending(record.epoch, queue.pendingEpoch, amountIn)) continue;

            // If the plan cleared no request of the queue yet, start its cleared epoch.
            if (cleared == 0) QueueLib.startClearedEpoch(queue);

            // Update State and Plan Cache.
            if (isDeposit) cache.applyBufferDelta(QueueLib.clearDeposit(state, queue, record, isToken0));
            else QueueLib.clearRedeem(queue, record);
            // Unchecked: the cleared requests are part of the pending epoch's uint128 amount.
            unchecked {
                cleared += amountIn;
            }

            if (isDeposit) emit DepositCleared(vault, controller, amountIn);
            else emit RedeemCleared(vault, controller, amountIn);
        }

        // Update Plan Cache.
        cache.setCleared(isDeposit, isToken0, cleared);
    }

    /**
     * @notice Clears every pending request of a vault's queue into the plan's settlement.
     * @param state The core state.
     * @param cache The plan cache.
     * @param payload The vault side and the queue.
     */
    function _clearAllRequests(State storage state, PlanCache memory cache, bytes calldata payload) internal {
        // Decode payload.
        (bool isToken0, bool isDeposit) = CalldataLogic.decodeQueue(payload);

        // Checks.
        if (isDeposit && state.config.paused) revert Paused();
        address vault = isToken0 ? cache.immutables.asyncVault0 : cache.immutables.asyncVault1;

        // Cache the queue and the amount of its pending epoch.
        Queue storage queue = isDeposit ? state.vaultQueues[vault].deposits : state.vaultQueues[vault].redeems;
        uint256 amountIn = queue.epochs[queue.pendingEpoch].amountIn;

        // If the epoch holds nothing, return.
        if (amountIn == 0) return;

        // Check that the plan cleared no named request of the queue.
        if (cache.getCleared(isDeposit, isToken0) != 0) revert AlreadyCleared();

        // Update State.
        TokenDelta delta;
        if (isDeposit) delta = state.clearAllDeposits(queue, isToken0, amountIn);
        else QueueLib.clearAllRedeems(queue);

        // Update Plan Cache.
        cache.applyBufferDelta(delta);
        cache.setCleared(isDeposit, isToken0, amountIn);
    }

    /**
     * @notice Settles the epochs the plan cleared.
     * @param state The core state.
     * @param cache The plan cache.
     */
    function _settleEpochs(State storage state, PlanCache memory cache) internal {
        // If the plan cleared no request, return.
        if (!cache.hasUnsettledEpochs()) return;

        // Calculate the aLP and assets of every cleared epoch.
        (uint256 shares0, uint256 shares1, uint256 assets0, uint256 assets1) = cache.getSettlementAmountsOut();

        // Settle the cleared redeem epochs, then the cleared deposit epochs.
        _settleRedeems(state, cache, cache.immutables.asyncVault0, true, assets0, cache.redeemShares0);
        _settleRedeems(state, cache, cache.immutables.asyncVault1, false, assets1, cache.redeemShares1);
        _settleDeposits(state, cache.immutables.asyncVault0, cache.depositAssets0, shares0);
        _settleDeposits(state, cache.immutables.asyncVault1, cache.depositAssets1, shares1);

        // Update Plan Cache.
        (cache.depositAssets0, cache.depositAssets1, cache.redeemShares0, cache.redeemShares1) = (0, 0, 0, 0);
    }

    /**
     * @notice Settles a vault's cleared redeem epoch, burning its aLP out of escrow and moving its assets into escrow.
     * @param state The core state.
     * @param cache The plan cache.
     * @param vault The vault.
     * @param isToken0 True when the vault's asset is token0.
     * @param assets The asset amount the epoch is paid.
     * @param shares The aLP the epoch redeems.
     */
    function _settleRedeems(
        State storage state,
        PlanCache memory cache,
        address vault,
        bool isToken0,
        uint256 assets,
        uint256 shares
    ) internal {
        // If the plan cleared no redeem of the vault, return.
        if (shares == 0) return;

        // Burn the shares from the core's escrow.
        _burn(address(this), shares);

        // Update State.
        Queue storage redeems = state.vaultQueues[vault].redeems;
        TokenDelta delta = state.settleRedeems(redeems, isToken0, assets);

        // Update Plan Cache.
        cache.applyBufferDelta(delta);

        emit RedeemEpochSettled(vault, redeems.lastClearedEpoch, assets, shares);
    }

    /**
     * @notice Settles a vault's cleared deposit epoch, minting its aLP into escrow.
     * @param state The core state.
     * @param vault The vault.
     * @param assets The asset amount the epoch deposits.
     * @param shares The aLP the epoch is minted.
     */
    function _settleDeposits(State storage state, address vault, uint256 assets, uint256 shares) internal {
        // If the plan cleared no deposit of the vault, return.
        if (assets == 0) return;

        // Check that the minted shares stay within the total cap.
        state.checkTotalCap(totalSupply() + shares);

        // Mint the shares to the core's escrow.
        _mint(address(this), shares);

        // Settle the cleared epoch at the minted shares.
        Queue storage deposits = state.vaultQueues[vault].deposits;
        uint32 lastClearedEpoch = deposits.lastClearedEpoch;
        QueueLib.settleEpoch(deposits.epochs[lastClearedEpoch], shares);

        emit DepositEpochSettled(vault, lastClearedEpoch, assets, shares);
    }

    /**
     * @notice Cancels named pending requests of a vault's queue and returns what they paid in to their controllers.
     * @param cache The plan cache.
     * @param payload The vault side and the queue, then the controllers.
     */
    function _cancelRequests(PlanCache memory cache, bytes calldata payload) internal {
        // Decode payload.
        (bool isToken0, bool isDeposit, uint256 count) = CalldataLogic.decodeControllers(payload);
        address vault = isToken0 ? cache.immutables.asyncVault0 : cache.immutables.asyncVault1;

        // Cache the queue.
        State storage state = _state();
        Queue storage queue = isDeposit ? state.vaultQueues[vault].deposits : state.vaultQueues[vault].redeems;

        // Cancel each named request.
        for (uint256 i; i < count; ++i) {
            // Get the controller of the entry.
            address controller = CalldataLogic.readController(payload, i);

            // If the request is not pending, skip it.
            Record storage record = queue.records[controller];
            uint256 amountIn = record.amountIn;
            if (!QueueLib.isPending(record.epoch, queue.pendingEpoch, amountIn)) continue;

            if (isDeposit) {
                // Update State.
                QueueLib.cancelDeposit(state, queue, record, controller, isToken0);

                // Transfer the assets from escrow to the controller.
                (isToken0 ? cache.immutables.token0 : cache.immutables.token1).safeTransfer(controller, amountIn);

                emit DepositCanceled(vault, controller, amountIn);
            } else {
                // Transfer the shares from escrow to the controller.
                _transfer(address(this), controller, amountIn);

                // Update State.
                state.cancelRedeem(queue, record, controller);

                emit RedeemCanceled(vault, controller, amountIn);
            }
        }
    }

    /* //////////////////////////////////////////////////////////////
                                SENTINELS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Resolves the OPEN_BALANCE sentinel of an amount.
     * @param state The core state.
     * @param cache The plan cache.
     * @param isToken0 True when the amount is in token0.
     * @param amount The amount of the payload.
     * @return amount_ The amount resolved.
     */
    function _amount(State storage state, PlanCache memory cache, bool isToken0, uint256 amount)
        internal
        view
        returns (uint256 amount_)
    {
        if (amount & Sentinels.OPEN_BALANCE == 0) return amount;
        uint256 bps = amount ^ Sentinels.OPEN_BALANCE;
        if (bps > ConfigLib.BPS_DENOMINATOR) revert CalldataLogic.InvalidPayload();
        TokenAmounts storage buffer = state.poolTokens.buffer;
        (uint256 owed0, uint256 owed1) = cache.getOwed();
        uint256 open = uint256(isToken0 ? buffer.amount0 : buffer.amount1).zeroFloorSub(isToken0 ? owed0 : owed1);
        // Unchecked: the open balance is a uint128 and bps at most BPS_DENOMINATOR.
        unchecked {
            amount_ = open * bps / ConfigLib.BPS_DENOMINATOR;
        }
    }

    /**
     * @notice Resolves the sentinels of a swap's input amount.
     * @param state The core state.
     * @param cache The plan cache.
     * @param zeroForOne True when the swap sells token0.
     * @param amountIn The input amount of the payload.
     * @return amountIn_ The input amount resolved.
     */
    function _amountIn(State storage state, PlanCache memory cache, bool zeroForOne, uint256 amountIn)
        internal
        view
        returns (uint256 amountIn_)
    {
        amountIn_ = amountIn & Sentinels.TO_TARGET_RATIO != 0
            ? _amountInToRatio(state, cache, zeroForOne, amountIn)
            : _amount(state, cache, zeroForOne, amountIn);
    }

    /**
     * @notice Resolves the TO_TARGET_RATIO sentinel of a swap's input amount.
     * @param state The core state.
     * @param cache The plan cache.
     * @param zeroForOne True when the swap sells token0.
     * @param amountIn The input amount of the payload.
     * @return amountIn_ The input amount resolved.
     */
    function _amountInToRatio(State storage state, PlanCache memory cache, bool zeroForOne, uint256 amountIn)
        internal
        view
        returns (uint256 amountIn_)
    {
        // Checks.
        uint256 targetRatio = amountIn ^ Sentinels.TO_TARGET_RATIO;
        if (targetRatio > ConfigLib.BPS_DENOMINATOR) revert CalldataLogic.InvalidPayload();

        // Value the open buffer in token1.
        TokenAmounts storage buffer = state.poolTokens.buffer;
        (uint256 owed0, uint256 owed1) = cache.getOwed();
        uint160 trusted = cache.trustedSqrtPriceX96;
        uint256 open = (CLMath.convert(trusted, true, buffer.amount0, false) + buffer.amount1)
        .zeroFloorSub(CLMath.convert(trusted, true, owed0, false) + owed1);

        // Split it at the target ratio.
        uint256 target0 = open.fullMulDiv(targetRatio, ConfigLib.BPS_DENOMINATOR);
        uint256 target1;
        // Unchecked: targetRatio is at most BPS_DENOMINATOR.
        unchecked {
            target1 = open - target0;
        }

        // Sell what the input side holds above its payout and its target.
        amountIn_ = zeroForOne
            ? uint256(buffer.amount0).zeroFloorSub(owed0 + CLMath.convert(trusted, false, target0, false))
            : uint256(buffer.amount1).zeroFloorSub(owed1 + target1);
    }

    /* //////////////////////////////////////////////////////////////
                                 HELPERS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The range at an index, checking it still holds the token id the step expects.
     * @param cache The plan cache.
     * @param index The index of the range.
     * @param tokenId The token id the step expects on the side it acts on, or the opened sentinel.
     * @param staked True when the step acts on the staked side.
     * @return range The range.
     */
    function _rangeAt(PlanCache memory cache, uint256 index, uint256 tokenId, bool staked)
        internal
        view
        returns (Range storage range)
    {
        Range[] storage ranges = _state().ranges;
        range = RangesLib.unsafeAccess(ranges, index);
        if (
            index >= ranges.length
                || (tokenId == Sentinels.OPENED
                        ? !cache.isOpenedRange(index)
                        : (staked ? range.stakedTokenId : range.unstakedTokenId) != tokenId)
        ) revert RangeMismatch(index);
    }
}
