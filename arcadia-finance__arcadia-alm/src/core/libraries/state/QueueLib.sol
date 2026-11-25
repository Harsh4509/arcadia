/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { Claimable, Epoch, PoolTokens, Queue, Record, ShareAccount, State } from "../../types/State.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { PoolTokensLib } from "./PoolTokensLib.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { TokenDelta, TokenDeltaLib } from "../../types/TokenDelta.sol";

/**
 * @title Queue Library.
 * @author Pragma Labs
 * @notice The requests of the asynchronous vaults: their epochs, records and claimable piles.
 */
// forge-lint: disable-next-item(require-revert-in-loop, unsafe-typecast)
library QueueLib {
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;
    using TokenDeltaLib for TokenDelta;

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error InsufficientClaimable();
    error RequestNotPending();
    error ZeroAddress();
    error ZeroAmount();

    /* //////////////////////////////////////////////////////////////
                                REQUESTS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Records assets the vault has already moved to the core as a pending deposit.
     * @param state The core state.
     * @param deposits The vault's deposit queue.
     * @param controller The account the request is held for.
     * @param isToken0 True when the vault's asset is token0.
     * @param assets The asset amount requested.
     * @param sqrtPriceX96 The pool's spot price.
     */
    function requestDeposit(
        State storage state,
        Queue storage deposits,
        address controller,
        bool isToken0,
        uint256 assets,
        uint160 sqrtPriceX96
    ) internal {
        // Calculate the pending shares of the requested assets.
        uint256 pendingShares = state.share.getPendingShares(isToken0, assets, sqrtPriceX96);

        // Credit the controller's settled deposit, if any, to its claimable pile.
        creditDeposit(state, deposits, controller);

        // Cache the pending epoch.
        {
            uint32 pendingEpoch = deposits.pendingEpoch;

            // Add the request to the controller's record in the pending epoch.
            record(
                deposits.records[controller],
                deposits.epochs[pendingEpoch],
                pendingEpoch,
                controller,
                assets,
                pendingShares
            );
        }

        // Update State.
        ShareAccount storage shareAccount = state.share.shareAccounts[controller];
        shareAccount.pendingShares += SafeCastLib.toUint128(pendingShares);
        state.poolTokens.escrowed.applyDelta(TokenDeltaLib.single(isToken0, assets.toInt128()));
    }

    /**
     * @notice Records aLP the core has already taken into escrow as a pending redeem.
     * @param state The core state.
     * @param redeems The vault's redeem queue.
     * @param controller The account the request is held for.
     * @param shares The aLP shares requested.
     */
    function requestRedeem(State storage state, Queue storage redeems, address controller, uint256 shares) internal {
        // Credit the controller's settled redeem, if any, to its claimable pile.
        creditRedeem(state, redeems, controller);

        // Cache the pending epoch.
        uint32 pendingEpoch = redeems.pendingEpoch;

        // Add the request to the controller's record in the pending epoch.
        record(redeems.records[controller], redeems.epochs[pendingEpoch], pendingEpoch, controller, shares, 0);

        // Update State.
        ShareAccount storage shareAccount = state.share.shareAccounts[controller];
        shareAccount.pendingShares += uint128(shares);
    }

    /* //////////////////////////////////////////////////////////////
                                 CANCELS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Takes a controller's pending deposit back out of the pending epoch and out of escrow.
     * @param state The core state.
     * @param deposits The vault's deposit queue.
     * @param record_ The controller's record in the deposit queue.
     * @param controller The account the request is held for.
     * @param isToken0 True when the vault's asset is token0.
     */
    function cancelDeposit(
        State storage state,
        Queue storage deposits,
        Record storage record_,
        address controller,
        bool isToken0
    ) internal {
        // Cache the record's assets.
        uint256 assets = record_.amountIn;

        // Take the request back out of the controller's record and the pending epoch.
        uint256 shares = cancel(record_, deposits.epochs[deposits.pendingEpoch]);

        // Update State.
        ShareAccount storage shareAccount = state.share.shareAccounts[controller];
        // Unchecked: the pending shares cover the record's.
        unchecked {
            shareAccount.pendingShares -= uint128(shares);
            state.poolTokens.escrowed.applyDelta(TokenDeltaLib.single(isToken0, -assets.toInt128()));
        }
    }

    /**
     * @notice Takes a controller's pending redeem back out of the pending epoch, after the core returned its aLP.
     * @param state The core state.
     * @param redeems The vault's redeem queue.
     * @param record_ The controller's record in the redeem queue.
     * @param controller The account the request is held for.
     */
    function cancelRedeem(State storage state, Queue storage redeems, Record storage record_, address controller)
        internal
    {
        // Cache the record's shares.
        uint256 shares = record_.amountIn;

        // Take the request back out of the controller's record and the pending epoch.
        cancel(record_, redeems.epochs[redeems.pendingEpoch]);

        // Update State.
        ShareAccount storage shareAccount = state.share.shareAccounts[controller];
        // Unchecked: the pending shares cover the record's.
        unchecked {
            shareAccount.pendingShares -= uint128(shares);
        }
    }

    /* //////////////////////////////////////////////////////////////
                                 CLEARS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Starts the epoch a plan clears named requests into, under a fresh id.
     * @param queue The vault's deposit or redeem queue.
     */
    function startClearedEpoch(Queue storage queue) internal {
        queue.lastClearedEpoch = nextEpoch(queue);
    }

    /**
     * @notice Moves a controller's pending deposit into the cleared epoch and its assets from escrow into the buffer.
     * @param state The core state.
     * @param deposits The vault's deposit queue.
     * @param record_ The controller's record in the deposit queue.
     * @param isToken0 True when the vault's asset is token0.
     * @return delta The token amounts moved from escrow into the buffer.
     */
    function clearDeposit(State storage state, Queue storage deposits, Record storage record_, bool isToken0)
        internal
        returns (TokenDelta delta)
    {
        // Move the request from the pending epoch into the cleared epoch.
        uint128 assets = record_.amountIn;
        uint32 lastClearedEpoch = deposits.lastClearedEpoch;
        record_.epoch = lastClearedEpoch;
        // Unchecked: the record is part of the pending epoch, whose uint128 amount bounds both the subtraction and the cleared epoch's sum.
        unchecked {
            deposits.epochs[deposits.pendingEpoch].amountIn -= assets;
            deposits.epochs[lastClearedEpoch].amountIn += assets;
        }

        // Move the cleared assets from escrow into the buffer.
        PoolTokens storage poolTokens = state.poolTokens;
        delta = TokenDeltaLib.single(isToken0, uint256(assets).toInt128());
        poolTokens.buffer.applyDelta(delta);
        poolTokens.escrowed.applyDelta(delta.neg());
    }

    /**
     * @notice Moves a controller's pending redeem into the cleared epoch, its aLP staying in escrow.
     * @param redeems The vault's redeem queue.
     * @param record_ The controller's record in the redeem queue.
     */
    function clearRedeem(Queue storage redeems, Record storage record_) internal {
        // Move the request from the pending epoch into the cleared epoch.
        uint128 shares = record_.amountIn;
        uint32 lastClearedEpoch = redeems.lastClearedEpoch;
        record_.epoch = lastClearedEpoch;
        // Unchecked: the record is part of the pending epoch, whose uint128 amount bounds both the subtraction and the cleared epoch's sum.
        unchecked {
            redeems.epochs[redeems.pendingEpoch].amountIn -= shares;
            redeems.epochs[lastClearedEpoch].amountIn += shares;
        }
    }

    /**
     * @notice Clears every pending deposit of the vault, moving their assets from escrow into the buffer.
     * @param state The core state.
     * @param deposits The vault's deposit queue.
     * @param isToken0 True when the vault's asset is token0.
     * @param assets The asset amount the epoch holds.
     * @return delta The token amounts moved from escrow into the buffer.
     */
    function clearAllDeposits(State storage state, Queue storage deposits, bool isToken0, uint256 assets)
        internal
        returns (TokenDelta delta)
    {
        // Move the deposited assets from escrow into the buffer.
        PoolTokens storage poolTokens = state.poolTokens;
        delta = TokenDeltaLib.single(isToken0, assets.toInt128());
        poolTokens.buffer.applyDelta(delta);
        poolTokens.escrowed.applyDelta(delta.neg());

        // Clear the pending epoch and start the next one.
        uint32 pendingEpoch = nextEpoch(deposits);
        deposits.lastClearedEpoch = deposits.pendingEpoch;
        deposits.pendingEpoch = pendingEpoch;
    }

    /**
     * @notice Clears every pending redeem of the vault.
     * @param redeems The vault's redeem queue.
     */
    function clearAllRedeems(Queue storage redeems) internal {
        // Clear the pending epoch and start the next one.
        uint32 pendingEpoch = nextEpoch(redeems);
        redeems.lastClearedEpoch = redeems.pendingEpoch;
        redeems.pendingEpoch = pendingEpoch;
    }

    /* //////////////////////////////////////////////////////////////
                               SETTLEMENTS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Settles a vault's cleared redeem epoch, after the core burned its aLP out of escrow.
     * @param state The core state.
     * @param redeems The vault's redeem queue.
     * @param isToken0 True when the vault's asset is token0.
     * @param assets The asset amount the epoch redeems.
     * @return delta The buffer delta of the payout.
     */
    function settleRedeems(State storage state, Queue storage redeems, bool isToken0, uint256 assets)
        internal
        returns (TokenDelta delta)
    {
        // Checks.
        PoolTokens storage poolTokens = state.poolTokens;
        if (assets > (isToken0 ? poolTokens.buffer.amount0 : poolTokens.buffer.amount1)) {
            revert PoolTokensLib.InsufficientBuffer();
        }

        // Move the redeemed assets from the buffer into escrow.
        delta = TokenDeltaLib.single(isToken0, -assets.toInt128());
        poolTokens.buffer.applyDelta(delta);
        poolTokens.escrowed.applyDelta(delta.neg());

        // Settle the cleared epoch at the redeemed assets.
        settleEpoch(redeems.epochs[redeems.lastClearedEpoch], assets);
    }

    /* //////////////////////////////////////////////////////////////
                                 CREDITS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Credits a controller's settled deposit record into its claimable pile and its claimable aLP.
     * @param state The core state.
     * @param deposits The vault's deposit queue.
     * @param controller The account the record is held for.
     */
    function creditDeposit(State storage state, Queue storage deposits, address controller) internal {
        // Checks.
        Record storage record_ = deposits.records[controller];
        if (!isSettled(record_.epoch, deposits.pendingEpoch, record_.amountIn)) return;

        // Move the settled record into the controller's claimable pile, releasing its pending shares.
        (uint256 shares, uint256 pendingShares) =
            creditSettled(record_, deposits.epochs[record_.epoch], deposits.claimable[controller]);

        // Update State.
        ShareAccount storage shareAccount = state.share.shareAccounts[controller];
        // Unchecked: the pending shares cover the record's, the claimable shares are held in escrow.
        unchecked {
            shareAccount.pendingShares -= uint128(pendingShares);
            shareAccount.claimableShares += uint128(shares);
        }
    }

    /**
     * @notice Credits a controller's settled redeem record to its claimable pile.
     * @param state The core state.
     * @param redeems The vault's redeem queue.
     * @param controller The account the record is held for.
     */
    function creditRedeem(State storage state, Queue storage redeems, address controller) internal {
        // Checks.
        Record storage record_ = redeems.records[controller];
        if (!isSettled(record_.epoch, redeems.pendingEpoch, record_.amountIn)) return;

        // Move the settled record into the controller's claimable pile, releasing its pending shares.
        ShareAccount storage shareAccount = state.share.shareAccounts[controller];
        // Unchecked: the pending shares cover the record's.
        unchecked {
            shareAccount.pendingShares -= uint128(record_.amountIn);
        }
        creditSettled(record_, redeems.epochs[record_.epoch], redeems.claimable[controller]);
    }

    /* //////////////////////////////////////////////////////////////
                                 CLAIMS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Takes part of a filled deposit's claim out of the controller's claimable aLP.
     * @param state The core state.
     * @param deposits The vault's deposit queue.
     * @param controller The account the request is held for.
     * @param assets The settled asset amount claimed.
     * @param maxShares The most aLP shares taken.
     * @return shares The aLP shares taken.
     */
    function claimDeposit(
        State storage state,
        Queue storage deposits,
        address controller,
        uint256 assets,
        uint256 maxShares
    ) internal returns (uint256 shares) {
        // Credit the controller's settled deposit, if any, to its claimable pile.
        creditDeposit(state, deposits, controller);

        // Take the claim out of the controller's claimable pile.
        shares = takeClaimable(deposits.claimable[controller], assets, maxShares);

        // Update State.
        ShareAccount storage shareAccount = state.share.shareAccounts[controller];
        // Unchecked: the claimed shares came out of the claimable shares.
        unchecked {
            shareAccount.claimableShares -= uint128(shares);
        }
    }

    /**
     * @notice Takes part of a filled redeem's claim out of escrow, before the core pays it.
     * @param state The core state.
     * @param redeems The vault's redeem queue.
     * @param controller The account the request is held for.
     * @param isToken0 True when the vault's asset is token0.
     * @param shares The settled aLP shares claimed.
     * @param maxAssets The most assets taken.
     * @return assets The asset amount taken.
     */
    function claimRedeem(
        State storage state,
        Queue storage redeems,
        address controller,
        bool isToken0,
        uint256 shares,
        uint256 maxAssets
    ) internal returns (uint256 assets) {
        // Credit the controller's settled redeem, if any, to its claimable pile.
        creditRedeem(state, redeems, controller);

        // Take the claim out of the controller's claimable pile.
        assets = takeClaimable(redeems.claimable[controller], shares, maxAssets);

        // Update State.
        state.poolTokens.escrowed.applyDelta(TokenDeltaLib.single(isToken0, -assets.toInt128()));
    }

    /* //////////////////////////////////////////////////////////////
                                 RECORDS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Adds a request to a controller's record in the pending epoch.
     * @param record_ The controller's record in one queue.
     * @param epoch The pending epoch in that queue.
     * @param pendingEpoch The id of the pending epoch.
     * @param controller The account the request is held for.
     * @param amountIn The amount requested.
     * @param pendingShares The pending aLP of a deposit, zero for a redeem.
     */
    function record(
        Record storage record_,
        Epoch storage epoch,
        uint32 pendingEpoch,
        address controller,
        uint256 amountIn,
        uint256 pendingShares
    ) internal {
        // Checks.
        if (controller == address(0)) revert ZeroAddress();
        if (amountIn == 0) revert ZeroAmount();

        // Update State.
        record_.epoch = pendingEpoch;
        record_.amountIn = SafeCastLib.toUint128(record_.amountIn + amountIn);
        record_.pendingShares = SafeCastLib.toUint96(record_.pendingShares + pendingShares);
        epoch.amountIn = SafeCastLib.toUint128(epoch.amountIn + amountIn);
    }

    /**
     * @notice Takes a pending record back out of the pending epoch and empties it.
     * @param record_ The controller's record in one queue.
     * @param epoch The pending epoch in that queue.
     * @return shares The record's pending aLP, released.
     */
    function cancel(Record storage record_, Epoch storage epoch) internal returns (uint256 shares) {
        // Cache the record's pending shares.
        shares = record_.pendingShares;

        // Update State.
        // Unchecked: the record is part of the pending epoch.
        unchecked {
            epoch.amountIn -= record_.amountIn;
        }
        (record_.epoch, record_.amountIn, record_.pendingShares) = (0, 0, 0);
    }

    /**
     * @notice Moves a settled record into the controller's claimable pile at the epoch's remaining rate.
     * @param record_ The controller's settled record in one queue.
     * @param epoch The epoch the record settled in.
     * @param claimable The controller's claimable pile in that queue.
     * @return amountOut The output credited.
     * @return pendingShares The pending aLP the record cleared.
     */
    function creditSettled(Record storage record_, Epoch storage epoch, Claimable storage claimable)
        internal
        returns (uint256 amountOut, uint256 pendingShares)
    {
        // Cache the record.
        uint256 amountIn = record_.amountIn;
        pendingShares = record_.pendingShares;

        // Calculate the record's share of the epoch's remaining output.
        amountOut = requestAmountOut(amountIn, epoch.amountIn, epoch.amountOut);

        // Update State.
        // Unchecked: the epoch sums cover the record's amount and its share of the output.
        unchecked {
            epoch.amountIn -= uint128(amountIn);
            epoch.amountOut -= uint128(amountOut);
        }
        (claimable.amountIn, claimable.amountOut) =
        (claimable.amountIn + uint128(amountIn), claimable.amountOut + uint128(amountOut));
        (record_.epoch, record_.amountIn, record_.pendingShares) = (0, 0, 0);
    }

    /* //////////////////////////////////////////////////////////////
                                 EPOCHS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Stores the output of an epoch.
     * @param epoch The epoch.
     * @param amountOut The epoch's output.
     */
    function settleEpoch(Epoch storage epoch, uint256 amountOut) internal {
        epoch.amountOut = SafeCastLib.toUint128(amountOut);
    }

    /* //////////////////////////////////////////////////////////////
                                CLAIMABLE
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Takes part of a claimable pile at its fill rate, capping the output.
     * @param claimable The controller's claimable pile.
     * @param amountIn The claimable input taken.
     * @param maxAmountOut The most output taken.
     * @return amountOut The output taken, rounded down.
     */
    function takeClaimable(Claimable storage claimable, uint256 amountIn, uint256 maxAmountOut)
        internal
        returns (uint256 amountOut)
    {
        // Cache the claimable pile.
        (uint256 claimableIn, uint256 claimableOut) = (claimable.amountIn, claimable.amountOut);

        // Checks.
        if (amountIn > claimableIn || claimableIn == 0 && claimableOut == 0) revert InsufficientClaimable();

        // Calculate the output for the claimed input (capped at the most output taken).
        amountOut = FixedPointMathLib.min(
            claimableIn == 0 ? claimableOut : requestAmountOut(amountIn, claimableIn, claimableOut), maxAmountOut
        );

        // Update State.
        // Unchecked: amountIn is at most claimableIn, so amountOut is at most claimableOut.
        unchecked {
            (claimable.amountIn, claimable.amountOut) =
            (SafeCastLib.toUint128(claimableIn - amountIn), SafeCastLib.toUint128(claimableOut - amountOut));
        }
    }

    /* //////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Whether a record is pending.
     * @param recordEpoch The epoch the record sits in.
     * @param pendingEpoch The id of the pending epoch.
     * @param amountIn The record's amount.
     * @return pending True when the record holds an amount in the pending epoch.
     */
    function isPending(uint256 recordEpoch, uint256 pendingEpoch, uint256 amountIn)
        internal
        pure
        returns (bool pending)
    {
        pending = amountIn != 0 && recordEpoch == pendingEpoch;
    }

    /**
     * @notice Whether a record is settled and not yet credited.
     * @param recordEpoch The epoch the record sits in.
     * @param pendingEpoch The id of the pending epoch.
     * @param amountIn The record's amount.
     * @return settled True when the record holds an amount in an epoch other than the pending one.
     */
    function isSettled(uint256 recordEpoch, uint256 pendingEpoch, uint256 amountIn)
        internal
        pure
        returns (bool settled)
    {
        settled = amountIn != 0 && recordEpoch != pendingEpoch;
    }

    /**
     * @notice Reverts unless a record is pending.
     * @param recordEpoch The epoch the record sits in.
     * @param pendingEpoch The id of the pending epoch.
     * @param amountIn The record's amount.
     */
    function requirePending(uint256 recordEpoch, uint256 pendingEpoch, uint256 amountIn) internal pure {
        if (!isPending(recordEpoch, pendingEpoch, amountIn)) revert RequestNotPending();
    }

    /**
     * @notice The id of a queue's next epoch.
     * @param queue The vault's deposit or redeem queue.
     * @return epoch The highest id issued, plus one.
     */
    function nextEpoch(Queue storage queue) internal view returns (uint32 epoch) {
        epoch = uint32(FixedPointMathLib.max(queue.pendingEpoch, queue.lastClearedEpoch)) + 1;
    }

    /**
     * @notice Splits a batch's output to one request, pro rata to its input.
     * @param amountIn The request's input.
     * @param batchAmountIn The batch's input.
     * @param batchAmountOut The batch's output.
     * @return amountOut The output of the request, rounded down.
     */
    function requestAmountOut(uint256 amountIn, uint256 batchAmountIn, uint256 batchAmountOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        amountOut = amountIn.fullMulDiv(batchAmountOut, batchAmountIn);
    }

    /**
     * @notice The input a batch's output costs, pro rata to the batch.
     * @param amountOut The output taken.
     * @param batchAmountIn The batch's input.
     * @param batchAmountOut The batch's output.
     * @return amountIn The input for the output, rounded up.
     */
    function requestAmountIn(uint256 amountOut, uint256 batchAmountIn, uint256 batchAmountOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        amountIn = amountOut.fullMulDivUp(batchAmountIn, batchAmountOut);
    }
}
