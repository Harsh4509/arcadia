/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import {
    Claimable,
    Epoch,
    PoolTokens,
    Queue,
    Record,
    ShareAccount,
    State,
    VaultQueue
} from "../../../src/core/types/State.sol";
import { QueueLib } from "../../../src/core/libraries/state/QueueLib.sol";
import { TokenDelta } from "../../../src/core/types/TokenDelta.sol";

contract QueueLibExtension {
    mapping(uint256 index => Record record) internal records;
    Epoch internal epoch;
    Claimable internal claimable;
    State internal state;

    function setRecord(uint256 index, Record memory record_) external {
        records[index] = record_;
    }

    function getRecord(uint256 index) external view returns (Record memory record_) {
        record_ = records[index];
    }

    function setEpoch(Epoch memory epoch_) external {
        epoch = epoch_;
    }

    function getEpoch() external view returns (Epoch memory epoch_) {
        epoch_ = epoch;
    }

    function setClaimable(Claimable memory claimable_) external {
        claimable = claimable_;
    }

    function getClaimable() external view returns (Claimable memory claimable_) {
        claimable_ = claimable;
    }

    function setPendingEpochs(address vault, uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) external {
        VaultQueue storage vaultQueue = state.vaultQueues[vault];
        (vaultQueue.deposits.pendingEpoch, vaultQueue.redeems.pendingEpoch) = (pendingDepositEpoch, pendingRedeemEpoch);
    }

    function getPendingDepositEpoch(address vault) external view returns (uint32 pendingEpoch) {
        pendingEpoch = state.vaultQueues[vault].deposits.pendingEpoch;
    }

    function getPendingRedeemEpoch(address vault) external view returns (uint32 pendingEpoch) {
        pendingEpoch = state.vaultQueues[vault].redeems.pendingEpoch;
    }

    function setLastClearedEpochs(address vault, uint32 lastClearedDepositEpoch, uint32 lastClearedRedeemEpoch)
        external
    {
        VaultQueue storage vaultQueue = state.vaultQueues[vault];
        (vaultQueue.deposits.lastClearedEpoch, vaultQueue.redeems.lastClearedEpoch) =
        (lastClearedDepositEpoch, lastClearedRedeemEpoch);
    }

    function getLastClearedDepositEpoch(address vault) external view returns (uint32 lastClearedEpoch) {
        lastClearedEpoch = state.vaultQueues[vault].deposits.lastClearedEpoch;
    }

    function getLastClearedRedeemEpoch(address vault) external view returns (uint32 lastClearedEpoch) {
        lastClearedEpoch = state.vaultQueues[vault].redeems.lastClearedEpoch;
    }

    function setDepositRecord(address vault, address controller, Record memory record_) external {
        state.vaultQueues[vault].deposits.records[controller] = record_;
    }

    function getDepositRecord(address vault, address controller) external view returns (Record memory record_) {
        record_ = state.vaultQueues[vault].deposits.records[controller];
    }

    function setRedeemRecord(address vault, address controller, Record memory record_) external {
        state.vaultQueues[vault].redeems.records[controller] = record_;
    }

    function getRedeemRecord(address vault, address controller) external view returns (Record memory record_) {
        record_ = state.vaultQueues[vault].redeems.records[controller];
    }

    function setDepositEpoch(address vault, uint32 id, Epoch memory epoch_) external {
        state.vaultQueues[vault].deposits.epochs[id] = epoch_;
    }

    function getDepositEpoch(address vault, uint32 id) external view returns (Epoch memory epoch_) {
        epoch_ = state.vaultQueues[vault].deposits.epochs[id];
    }

    function setRedeemEpoch(address vault, uint32 id, Epoch memory epoch_) external {
        state.vaultQueues[vault].redeems.epochs[id] = epoch_;
    }

    function getRedeemEpoch(address vault, uint32 id) external view returns (Epoch memory epoch_) {
        epoch_ = state.vaultQueues[vault].redeems.epochs[id];
    }

    function setClaimableDeposit(address vault, address controller, Claimable memory claimable_) external {
        state.vaultQueues[vault].deposits.claimable[controller] = claimable_;
    }

    function getClaimableDeposit(address vault, address controller)
        external
        view
        returns (Claimable memory claimable_)
    {
        claimable_ = state.vaultQueues[vault].deposits.claimable[controller];
    }

    function setClaimableRedeem(address vault, address controller, Claimable memory claimable_) external {
        state.vaultQueues[vault].redeems.claimable[controller] = claimable_;
    }

    function getClaimableRedeem(address vault, address controller) external view returns (Claimable memory claimable_) {
        claimable_ = state.vaultQueues[vault].redeems.claimable[controller];
    }

    function setBuffers(uint128 buffer0, uint128 buffer1) external {
        (state.poolTokens.buffer.amount0, state.poolTokens.buffer.amount1) = (buffer0, buffer1);
    }

    function setEscrowed(uint128 escrowed0, uint128 escrowed1) external {
        (state.poolTokens.escrowed.amount0, state.poolTokens.escrowed.amount1) = (escrowed0, escrowed1);
    }

    function getPoolTokens() external view returns (PoolTokens memory poolTokens) {
        poolTokens = state.poolTokens;
    }

    function setShareAccount(address account, ShareAccount memory shareAccount) external {
        state.share.shareAccounts[account] = shareAccount;
    }

    function getShareAccount(address account) external view returns (ShareAccount memory shareAccount) {
        shareAccount = state.share.shareAccounts[account];
    }

    function requestDeposit(address vault, address controller, bool isToken0, uint256 assets, uint160 sqrtPriceX96)
        external
    {
        state.requestDeposit(state.vaultQueues[vault].deposits, controller, isToken0, assets, sqrtPriceX96);
    }

    function requestRedeem(address vault, address controller, uint256 shares) external {
        state.requestRedeem(state.vaultQueues[vault].redeems, controller, shares);
    }

    function cancelDeposit(address vault, address controller, bool isToken0) external {
        Queue storage deposits = state.vaultQueues[vault].deposits;
        state.cancelDeposit(deposits, deposits.records[controller], controller, isToken0);
    }

    function cancelRedeem(address vault, address controller) external {
        Queue storage redeems = state.vaultQueues[vault].redeems;
        state.cancelRedeem(redeems, redeems.records[controller], controller);
    }

    function startClearedEpoch(address vault, bool deposits) external {
        VaultQueue storage vaultQueue = state.vaultQueues[vault];
        QueueLib.startClearedEpoch(deposits ? vaultQueue.deposits : vaultQueue.redeems);
    }

    function clearDeposit(address vault, address controller, bool isToken0) external returns (TokenDelta delta) {
        Queue storage deposits = state.vaultQueues[vault].deposits;
        delta = state.clearDeposit(deposits, deposits.records[controller], isToken0);
    }

    function clearRedeem(address vault, address controller) external {
        Queue storage redeems = state.vaultQueues[vault].redeems;
        QueueLib.clearRedeem(redeems, redeems.records[controller]);
    }

    function clearAllDeposits(address vault, bool isToken0, uint256 assets) external returns (TokenDelta delta) {
        delta = state.clearAllDeposits(state.vaultQueues[vault].deposits, isToken0, assets);
    }

    function clearAllRedeems(address vault) external {
        QueueLib.clearAllRedeems(state.vaultQueues[vault].redeems);
    }

    function settleRedeems(address vault, bool isToken0, uint256 assets) external returns (TokenDelta delta) {
        delta = state.settleRedeems(state.vaultQueues[vault].redeems, isToken0, assets);
    }

    function creditDeposit(address vault, address controller) external {
        state.creditDeposit(state.vaultQueues[vault].deposits, controller);
    }

    function creditRedeem(address vault, address controller) external {
        state.creditRedeem(state.vaultQueues[vault].redeems, controller);
    }

    function claimDeposit(address vault, address controller, uint256 assets, uint256 maxShares)
        external
        returns (uint256 shares)
    {
        shares = state.claimDeposit(state.vaultQueues[vault].deposits, controller, assets, maxShares);
    }

    function claimRedeem(address vault, address controller, bool isToken0, uint256 shares, uint256 maxAssets)
        external
        returns (uint256 assets)
    {
        assets = state.claimRedeem(state.vaultQueues[vault].redeems, controller, isToken0, shares, maxAssets);
    }

    function isPending(uint256 recordEpoch, uint256 pendingEpoch, uint256 amount) external pure returns (bool pending) {
        pending = QueueLib.isPending(recordEpoch, pendingEpoch, amount);
    }

    function isSettled(uint256 recordEpoch, uint256 pendingEpoch, uint256 amount) external pure returns (bool settled) {
        settled = QueueLib.isSettled(recordEpoch, pendingEpoch, amount);
    }

    function record(uint256 index, uint32 pendingEpoch, address controller, uint256 amount, uint256 pendingShares)
        external
    {
        records[index].record(epoch, pendingEpoch, controller, amount, pendingShares);
    }

    function cancel(uint256 index) external returns (uint256 shares) {
        shares = records[index].cancel(epoch);
    }

    function creditSettled(uint256 index) external returns (uint256 amountOut, uint256 pendingShares) {
        (amountOut, pendingShares) = records[index].creditSettled(epoch, claimable);
    }

    function takeClaimable(uint256 amountIn, uint256 maxAmountOut) external returns (uint256 amountOut) {
        amountOut = claimable.takeClaimable(amountIn, maxAmountOut);
    }

    function requestAmountIn(uint256 amountOut, uint256 batchAmountIn, uint256 batchAmountOut)
        external
        pure
        returns (uint256 amountIn)
    {
        amountIn = QueueLib.requestAmountIn(amountOut, batchAmountIn, batchAmountOut);
    }

    function requestAmountOut(uint256 amountIn, uint256 batchAmountIn, uint256 batchAmountOut)
        external
        pure
        returns (uint256 amountOut)
    {
        amountOut = QueueLib.requestAmountOut(amountIn, batchAmountIn, batchAmountOut);
    }

    function requirePending(uint256 recordEpoch, uint256 pendingEpoch, uint256 amount) external pure {
        QueueLib.requirePending(recordEpoch, pendingEpoch, amount);
    }

    function nextEpoch(address vault, bool deposits) external view returns (uint32 epoch_) {
        VaultQueue storage vaultQueue = state.vaultQueues[vault];
        epoch_ = QueueLib.nextEpoch(deposits ? vaultQueue.deposits : vaultQueue.redeems);
    }

    function settleEpoch(uint256 amountOut) external {
        epoch.settleEpoch(amountOut);
    }

    function setLastExchangeRate(uint160 lastSqrtPriceX96, uint256 supply, uint256 value) external {
        state.share.setLastExchangeRate(lastSqrtPriceX96, supply, value);
    }

    function getPendingShares(bool isToken0, uint256 assets, uint160 sqrtPriceX96)
        external
        view
        returns (uint256 shares)
    {
        shares = state.share.getPendingShares(isToken0, assets, sqrtPriceX96);
    }
}
