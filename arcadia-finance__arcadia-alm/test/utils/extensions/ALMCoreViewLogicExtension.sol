/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic } from "../../../src/core/libraries/logic/ALMCoreViewLogic.sol";
import {
    Config,
    Epoch,
    ExchangeRate,
    PoolTokens,
    Record,
    RewardAccount,
    ShareAccount
} from "../../../src/core/types/State.sol";
import { IALMCore } from "../../../src/interfaces/IALMCore.sol";
import { Range } from "../../../src/core/types/Range.sol";

contract ALMCoreViewLogicExtension {
    using ALMCoreViewLogic for IALMCore;
    using ALMCoreViewLogic for bytes32[];

    function getConfig(address core) external view returns (Config memory config) {
        config = IALMCore(core).getConfig();
    }

    function getTwapWindow(address core) external view returns (uint32 twapWindow) {
        twapWindow = IALMCore(core).getTwapWindow();
    }

    function getMaxSwapCostBps(address core) external view returns (uint16 maxSwapCostBps) {
        maxSwapCostBps = IALMCore(core).getMaxSwapCostBps();
    }

    function quotable(address core, address pool, bool assetIsToken0, bool paused)
        external
        view
        returns (bool isQuotable, uint160 sqrtPriceX96, uint256 sqrtPriceLimitX96)
    {
        (isQuotable, sqrtPriceX96, sqrtPriceLimitX96) = IALMCore(core).quotable(pool, assetIsToken0, paused);
    }

    function getRewards(address core)
        external
        view
        returns (
            uint128 rewardPerShare,
            uint128 highWater,
            uint128 claimedCumulative,
            uint128 lastRewardBalance,
            uint128 protocolFees,
            uint128 protocolRewardPerSharePaid,
            uint128 preCredited
        )
    {
        (
            rewardPerShare,
            highWater,
            claimedCumulative,
            lastRewardBalance,
            protocolFees,
            protocolRewardPerSharePaid,
            preCredited
        ) = IALMCore(core).getRewards();
    }

    function getRewardAccount(address core, address account)
        external
        view
        returns (RewardAccount memory rewardAccount)
    {
        rewardAccount = IALMCore(core).getRewardAccount(account);
    }

    function getLastExchangeRate(address core) external view returns (ExchangeRate memory lastExchangeRate) {
        lastExchangeRate = IALMCore(core).getLastExchangeRate();
    }

    function getShareAccount(address core, address account) external view returns (ShareAccount memory shareAccount) {
        shareAccount = IALMCore(core).getShareAccount(account);
    }

    function isOperator(address core, address controller, address operator) external view returns (bool approved) {
        approved = IALMCore(core).isOperator(controller, operator);
    }

    function isExempt(address core, address account) external view returns (bool exempt) {
        exempt = IALMCore(core).isExempt(account);
    }

    function maxMint(address core, address receiver) external view returns (uint256 shares) {
        shares = IALMCore(core).maxMint(receiver);
    }

    function getPoolTokens(address core) external view returns (PoolTokens memory poolTokens) {
        poolTokens = IALMCore(core).getPoolTokens();
    }

    function getBuffer(address core) external view returns (uint128 amount0, uint128 amount1) {
        (amount0, amount1) = IALMCore(core).getBuffer();
    }

    function readRangeWords(address core) external view returns (bytes32[] memory words) {
        words = IALMCore(core).readRangeWords();
    }

    function decodeRanges(bytes32[] memory words) external pure returns (Range[] memory ranges) {
        ranges = words.decodeRanges();
    }

    function decodeRange(bytes32[] memory words, uint256 index)
        external
        pure
        returns (int24 tickLower, int24 tickUpper, uint128 stakedLiquidity)
    {
        (tickLower, tickUpper, stakedLiquidity) = words.decodeRange(index);
    }

    function decodePauseAndDeviation(uint256 word) external pure returns (bool paused, uint64 maxSpotFromTwap) {
        (paused, maxSpotFromTwap) = ALMCoreViewLogic.decodePauseAndDeviation(word);
    }

    function decodeRecord(bytes32 word) external pure returns (uint32 epoch, uint128 amountIn, uint96 pendingShares) {
        (epoch, amountIn, pendingShares) = ALMCoreViewLogic.decodeRecord(word);
    }

    function decodeWord(bytes32 word) external pure returns (uint128 low, uint128 high) {
        (low, high) = ALMCoreViewLogic.decodeWord(word);
    }

    function memberSlot(uint256 offset) external pure returns (bytes32 slot) {
        slot = ALMCoreViewLogic.memberSlot(offset);
    }

    function mappingSlot(address key, uint256 offset) external pure returns (bytes32 slot) {
        slot = ALMCoreViewLogic.mappingSlot(key, offset);
    }

    function queueSlot(address vault, uint256 offset) external pure returns (bytes32 slot) {
        slot = ALMCoreViewLogic.queueSlot(vault, offset);
    }

    function getPendingDepositEpoch(address core, address vault) external view returns (uint32 pendingEpoch) {
        pendingEpoch = IALMCore(core).getPendingDepositEpoch(vault);
    }

    function getPendingRedeemEpoch(address core, address vault) external view returns (uint32 pendingEpoch) {
        pendingEpoch = IALMCore(core).getPendingRedeemEpoch(vault);
    }

    function getLastClearedDepositEpoch(address core, address vault) external view returns (uint32 lastClearedEpoch) {
        lastClearedEpoch = IALMCore(core).getLastClearedDepositEpoch(vault);
    }

    function getLastClearedRedeemEpoch(address core, address vault) external view returns (uint32 lastClearedEpoch) {
        lastClearedEpoch = IALMCore(core).getLastClearedRedeemEpoch(vault);
    }

    function getDepositEpoch(address core, address vault, uint32 epoch) external view returns (Epoch memory epoch_) {
        epoch_ = IALMCore(core).getDepositEpoch(vault, epoch);
    }

    function getRedeemEpoch(address core, address vault, uint32 epoch) external view returns (Epoch memory epoch_) {
        epoch_ = IALMCore(core).getRedeemEpoch(vault, epoch);
    }

    function getDepositRecord(address core, address vault, address controller)
        external
        view
        returns (Record memory record)
    {
        record = IALMCore(core).getDepositRecord(vault, controller);
    }

    function getRedeemRecord(address core, address vault, address controller)
        external
        view
        returns (Record memory record)
    {
        record = IALMCore(core).getRedeemRecord(vault, controller);
    }

    function getPendingDeposit(address core, address vault, address controller) external view returns (uint256 amount) {
        amount = IALMCore(core).getPendingDeposit(vault, controller);
    }

    function getPendingRedeem(address core, address vault, address controller) external view returns (uint256 amount) {
        amount = IALMCore(core).getPendingRedeem(vault, controller);
    }

    function getClaimableDeposit(address core, address vault, address controller)
        external
        view
        returns (uint128 amountIn, uint128 amountOut)
    {
        (amountIn, amountOut) = IALMCore(core).getClaimableDeposit(vault, controller);
    }

    function getClaimableRedeem(address core, address vault, address controller)
        external
        view
        returns (uint128 amountIn, uint128 amountOut)
    {
        (amountOut, amountIn) = IALMCore(core).getClaimableRedeem(vault, controller);
    }

    function isLocked(address core) external view returns (bool locked) {
        locked = IALMCore(core).isLocked();
    }
}
