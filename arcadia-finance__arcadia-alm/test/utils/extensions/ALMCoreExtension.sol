/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore } from "../../../src/core/ALMCore.sol";
import { Claimable, Config, Epoch, Queue, Record, State, VaultQueue } from "../../../src/core/types/State.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../Constants.sol";
import { CoreParameters } from "../../../src/core/types/CoreParameters.sol";
import { LibTransient } from "@solady/utils/LibTransient.sol";
import { MetadexOracle } from "../../../src/shared/libraries/vendored/MetadexOracle.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { RangesLib } from "../../../src/core/libraries/state/RangesLib.sol";
import { EmissionsLogic } from "../../../src/core/libraries/logic/EmissionsLogic.sol";
import { IMetadexCLGaugeFactory } from "../../../src/interfaces/IMetadexCLGaugeFactory.sol";
import { ImmutablesExtension } from "./ImmutablesExtension.sol";
import { QueueLib } from "../../../src/core/libraries/state/QueueLib.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { TokenDeltaLib } from "../../../src/core/types/TokenDelta.sol";
import { TRANSIENT_SLOT } from "../../../src/core/abstracts/storage/Storage.sol";
import { Vaults } from "../../../src/core/types/Vaults.sol";

// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract ALMCoreExtension is ALMCore, ImmutablesExtension {
    using LibTransient for LibTransient.TBool;

    function lock_() external {
        _lock();
    }

    function getPendingReward(address account) external view returns (uint256 amount) {
        amount = _state().rewards.rewardAccounts[account].rewardOwed;
    }

    function bufferAmount0() external view returns (uint256 amount) {
        amount = _state().poolTokens.buffer.amount0;
    }

    function bufferAmount1() external view returns (uint256 amount) {
        amount = _state().poolTokens.buffer.amount1;
    }

    function asyncVault_(address asset) external view returns (address vault_) {
        if (asset == TOKEN0) vault_ = ASYNC_VAULT0;
        else if (asset == TOKEN1) vault_ = ASYNC_VAULT1;
    }

    function paused_() external view returns (bool paused) {
        paused = _state().config.paused;
    }

    function BPS_DENOMINATOR_() external pure returns (uint256 denominator) {
        denominator = ConfigLib.BPS_DENOMINATOR;
    }

    function claimableDeposit(address vault, address controller) external view returns (Claimable memory claimable) {
        claimable = _state().vaultQueues[vault].deposits.claimable[controller];
    }

    function claimableRedeem(address vault, address controller) external view returns (Claimable memory claimable) {
        claimable = _state().vaultQueues[vault].redeems.claimable[controller];
    }

    function pendingEpochs(address vault)
        external
        view
        returns (uint32 pendingDepositEpoch_, uint32 pendingRedeemEpoch_)
    {
        VaultQueue storage vaultQueue = _state().vaultQueues[vault];
        (pendingDepositEpoch_, pendingRedeemEpoch_) =
        (vaultQueue.deposits.pendingEpoch, vaultQueue.redeems.pendingEpoch);
    }

    function lastClearedEpochs(address vault)
        external
        view
        returns (uint32 lastClearedDepositEpoch_, uint32 lastClearedRedeemEpoch_)
    {
        VaultQueue storage vaultQueue = _state().vaultQueues[vault];
        (lastClearedDepositEpoch_, lastClearedRedeemEpoch_) =
        (vaultQueue.deposits.lastClearedEpoch, vaultQueue.redeems.lastClearedEpoch);
    }

    function depositRecord(address vault, address controller) external view returns (Record memory record) {
        record = _state().vaultQueues[vault].deposits.records[controller];
    }

    function redeemRecord(address vault, address controller) external view returns (Record memory record) {
        record = _state().vaultQueues[vault].redeems.records[controller];
    }

    function depositEpoch(address vault, uint32 id) external view returns (Epoch memory epoch) {
        epoch = _state().vaultQueues[vault].deposits.epochs[id];
    }

    function redeemEpoch(address vault, uint32 id) external view returns (Epoch memory epoch) {
        epoch = _state().vaultQueues[vault].redeems.epochs[id];
    }

    function isPenaltyWindowOpen(uint256 index) external view returns (bool open) {
        open = EmissionsLogic.isPenaltyWindowOpen(
            _state().ranges[index].stakedBlock,
            IMetadexCLGaugeFactory(GAUGE_FACTORY).effectivePenaltyConfig(GAUGE),
            EmissionsLogic.getBlockNumber(_state().config.arbBlockNumber)
        );
    }

    function getRange(uint256 index) external view returns (Range memory range) {
        range = _state().ranges[index];
    }

    function getRangesLength() external view returns (uint256 length) {
        length = _state().ranges.length;
    }

    function stakedTokenIds() external view returns (uint256[] memory tokenIds) {
        tokenIds = RangesLib.stakedTokenIds(_state().ranges);
    }

    function setConfig(Config memory config) external {
        _state().config = config;
    }

    function setPendingEpochs(address vault, uint32 pendingDepositEpoch_, uint32 pendingRedeemEpoch_) external {
        VaultQueue storage vaultQueue = _state().vaultQueues[vault];
        (vaultQueue.deposits.pendingEpoch, vaultQueue.redeems.pendingEpoch) =
        (pendingDepositEpoch_, pendingRedeemEpoch_);
    }

    function setLastClearedEpochs(address vault, uint32 lastClearedDepositEpoch_, uint32 lastClearedRedeemEpoch_)
        external
    {
        VaultQueue storage vaultQueue = _state().vaultQueues[vault];
        (vaultQueue.deposits.lastClearedEpoch, vaultQueue.redeems.lastClearedEpoch) =
        (lastClearedDepositEpoch_, lastClearedRedeemEpoch_);
    }

    function setDepositRecord(address vault, address controller, Record memory record) external {
        _state().vaultQueues[vault].deposits.records[controller] = record;
    }

    function setRedeemRecord(address vault, address controller, Record memory record) external {
        _state().vaultQueues[vault].redeems.records[controller] = record;
    }

    function setDepositEpoch(address vault, uint32 id, Epoch memory epoch) external {
        _state().vaultQueues[vault].deposits.epochs[id] = epoch;
    }

    function setRedeemEpoch(address vault, uint32 id, Epoch memory epoch) external {
        _state().vaultQueues[vault].redeems.epochs[id] = epoch;
    }

    function setMetadata(string memory name_, string memory symbol_) external {
        _state().share.name = name_;
        _state().share.symbol = symbol_;
    }

    function setPendingShares(address account, uint256 shares) external {
        _state().share.shareAccounts[account].pendingShares = uint128(shares);
    }

    function setLastExchangeRate(uint256 supplyPerValueX128, uint160 sqrtPriceX96) external {
        (_state().share.lastExchangeRate.supplyPerValueX128, _state().share.lastExchangeRate.sqrtPriceX96) =
        (supplyPerValueX128, sqrtPriceX96);
    }

    function setRewardPoolToken(uint8 rewardPoolToken) external {
        _state().config.rewardPoolToken = rewardPoolToken;
    }

    function setLastPlanAt(uint32 timestamp) external {
        _state().config.lastPlanAt = timestamp;
    }

    function writeCheckpointed() external returns (bytes32 word) {
        _checkpointed().set(true);
        bytes32 slot = TRANSIENT_SLOT;
        assembly ("memory-safe") {
            word := tload(slot)
        }
    }

    function pushRange(Range memory range) external {
        _state().ranges.push(range);
    }

    function setBuffers(uint256 amount0, uint256 amount1) external {
        _state().poolTokens.buffer.amount0 = uint128(amount0);
        _state().poolTokens.buffer.amount1 = uint128(amount1);
    }

    function setClaimableDeposit(address vault, address controller, Claimable memory claimable) external {
        _state().vaultQueues[vault].deposits.claimable[controller] = claimable;
    }

    function setClaimableRedeem(address vault, address controller, Claimable memory claimable) external {
        _state().vaultQueues[vault].redeems.claimable[controller] = claimable;
    }

    function setEscrowed(uint256 amount0, uint256 amount1) external {
        _state().poolTokens.escrowed.amount0 = uint128(amount0);
        _state().poolTokens.escrowed.amount1 = uint128(amount1);
    }

    function setFeesOwed(uint256 amount0, uint256 amount1, uint256 amountReward) external {
        _state().poolTokens.protocolFees.amount0 = uint128(amount0);
        _state().poolTokens.protocolFees.amount1 = uint128(amount1);
        _state().rewards.protocolFees = uint128(amountReward);
    }

    function getEscrowed0() external view returns (uint256 amount) {
        amount = _state().poolTokens.escrowed.amount0;
    }

    function getEscrowed1() external view returns (uint256 amount) {
        amount = _state().poolTokens.escrowed.amount1;
    }

    function getProtocolFees0() external view returns (uint256 amount) {
        amount = _state().poolTokens.protocolFees.amount0;
    }

    function getProtocolFees1() external view returns (uint256 amount) {
        amount = _state().poolTokens.protocolFees.amount1;
    }

    function getProtocolFeesReward() external view returns (uint256 amount) {
        amount = _state().rewards.protocolFees;
    }

    function getRewardHighWater() external view returns (uint256 amount) {
        amount = _state().rewards.highWater;
    }

    function getClaimedCumulative() external view returns (uint256 amount) {
        amount = _state().rewards.claimedCumulative;
    }

    function getLastRewardBalance() external view returns (uint256 amount) {
        amount = _state().rewards.lastRewardBalance;
    }

    function getRewardSnapshot(address account) external view returns (uint256 amount) {
        amount = _state().rewards.rewardAccounts[account].rewardPerSharePaid;
    }

    function getPreCredited() external view returns (uint128 preCredited) {
        preCredited = _state().rewards.preCredited;
    }

    function getWindowEnd() external view returns (uint48 windowEnd) {
        windowEnd = _state().config.windowEnd;
    }

    function setPreCredited(uint128 preCredited) external {
        _state().rewards.preCredited = preCredited;
    }

    function setWindowEnd(uint48 windowEnd) external {
        _state().config.windowEnd = windowEnd;
    }

    function setProtocolRewardSnapshot(uint256 amount) external {
        _state().rewards.protocolRewardPerSharePaid = uint128(amount);
    }

    function getProtocolRewardSnapshot() external view returns (uint256 amount) {
        amount = _state().rewards.protocolRewardPerSharePaid;
    }

    function setRewardSnapshot(address account, uint256 amount) external {
        _state().rewards.rewardAccounts[account].rewardPerSharePaid = uint128(amount);
    }

    function setRewardAccounting(
        uint256 newRewardPerShare,
        uint256 rewardHighWater_,
        uint256 claimedCumulative_,
        uint256 lastRewardBalance_
    ) external {
        _state().rewards.rewardPerShare = uint128(newRewardPerShare);
        _state().rewards.highWater = uint128(rewardHighWater_);
        _state().rewards.claimedCumulative = uint128(claimedCumulative_);
        _state().rewards.lastRewardBalance = uint128(lastRewardBalance_);
    }

    function setPendingReward(address account, uint256 amount) external {
        _state().rewards.rewardAccounts[account].rewardOwed = uint128(amount);
    }

    function claimableSharesOf_(address controller) external view returns (uint256 shares) {
        shares = _state().share.shareAccounts[controller].claimableShares;
    }

    function setClaimableShares(address controller, uint256 shares) external {
        _state().share.shareAccounts[controller].claimableShares = uint128(shares);
    }

    function mintShares(address account, uint256 shares) external {
        _mint(account, shares);
    }

    function stageSettledDeposit(address vault, address controller, Record memory record, Epoch memory epoch) external {
        State storage state = _state();
        _mint(address(this), epoch.amountOut);
        Queue storage deposits = state.vaultQueues[vault].deposits;
        deposits.records[controller] = record;
        state.share.shareAccounts[controller].pendingShares += record.pendingShares;
        deposits.epochs[record.epoch] = epoch;
        deposits.pendingEpoch = record.epoch;
        (deposits.pendingEpoch, deposits.lastClearedEpoch) = (QueueLib.nextEpoch(deposits), record.epoch);
    }

    function stageSettledRedeem(address vault, address controller, Record memory record, Epoch memory epoch) external {
        State storage state = _state();
        state.poolTokens.escrowed.applyDelta(TokenDeltaLib.single(vault == ASYNC_VAULT0, int128(epoch.amountOut)));
        record.pendingShares = 0;
        Queue storage redeems = state.vaultQueues[vault].redeems;
        redeems.records[controller] = record;
        state.share.shareAccounts[controller].pendingShares += record.amountIn;
        redeems.epochs[record.epoch] = epoch;
        redeems.pendingEpoch = record.epoch;
        (redeems.pendingEpoch, redeems.lastClearedEpoch) = (QueueLib.nextEpoch(redeems), record.epoch);
    }

    function stageClaimableDeposit(address vault, address controller, uint128 claimableIn, uint128 claimableOut)
        external
    {
        State storage state = _state();
        _mint(address(this), claimableOut);
        state.share.shareAccounts[controller].claimableShares += claimableOut;
        state.vaultQueues[vault].deposits.claimable[controller] = Claimable(claimableIn, claimableOut);
    }

    function stageClaimableRedeem(address vault, address controller, uint128 claimableIn, uint128 claimableOut)
        external
    {
        State storage state = _state();
        state.poolTokens.escrowed.applyDelta(TokenDeltaLib.single(vault == ASYNC_VAULT0, int128(claimableOut)));
        state.vaultQueues[vault].redeems.claimable[controller] = Claimable(claimableIn, claimableOut);
    }

    function burnShares(address account, uint256 shares) external {
        _burn(account, shares);
    }

    function checkpoint_() external {
        _checkpoint();
    }

    function updateRewards(address account) external {
        _checkpoint();
        _state().accrueBalanceReward(account, balanceOf(account));
    }

    function accrueBalanceReward(address account) external {
        _state().accrueBalanceReward(account, balanceOf(account));
    }

    function claimGaugeEmissions_() external {
        _state().claimGaugeEmissions(GAUGE, GAUGE_FACTORY);
    }

    function getRewardTotals() external view returns (uint256 received, uint256 protocolFee, uint256 total) {
        State storage state = _state();
        (received, protocolFee, total) = state.getRewardTotals(REWARD_TOKEN, GAUGE);
    }

    function token0() external view returns (address token0_) {
        token0_ = TOKEN0;
    }

    function token1() external view returns (address token1_) {
        token1_ = TOKEN1;
    }

    function gauge() external view returns (address gauge_) {
        gauge_ = GAUGE;
    }

    function tickSpacing() external view returns (int24 tickSpacing_) {
        tickSpacing_ = TICK_SPACING;
    }

    function DEAD_SHARES_() external pure returns (uint256 shares) {
        shares = Constants.DEAD_SHARES;
    }

    function MAX_FEE_BPS_() external pure returns (uint256 bps) {
        bps = ConfigLib.MAX_FEE_BPS;
    }

    function totalCap_() external view returns (uint256 cap) {
        cap = _state().config.totalCap;
    }

    function perUserCap_() external view returns (uint256 cap) {
        cap = _state().config.perUserCap;
    }

    function rangeCap_() external view returns (uint256 cap) {
        cap = _state().config.rangeCap;
    }

    function maxSpotFromTrusted_() external view returns (uint256 deviation) {
        deviation = _state().config.maxSpotFromTrusted;
    }

    function maxTwapFromTrusted_() external view returns (uint256 deviation) {
        deviation = _state().config.maxTwapFromTrusted;
    }

    function maxShortfallBps_() external view returns (uint256 bps) {
        bps = _state().config.maxShortfallBps;
    }

    function maxSwapCostBps_() external view returns (uint256 bps) {
        bps = _state().config.maxSwapCostBps;
    }

    function minPlanInterval_() external view returns (uint256 interval) {
        interval = _state().config.minPlanInterval;
    }

    function lastPlanAt_() external view returns (uint256 timestamp) {
        timestamp = _state().config.lastPlanAt;
    }

    function protocolEmissionFeeBps_() external view returns (uint16 bps) {
        bps = _state().config.protocolEmissionFeeBps;
    }

    function protocolSwapFeeBps_() external view returns (uint16 bps) {
        bps = _state().config.protocolSwapFeeBps;
    }

    function feeRecipient_() external view returns (address recipient) {
        recipient = _state().config.feeRecipient;
    }

    function twapWindow_() external view returns (uint32 window) {
        window = _state().config.twapWindow;
    }

    function maxSpotFromTwap_() external view returns (uint256 deviation) {
        deviation = _state().config.maxSpotFromTwap;
    }

    function meanSqrtPriceX96_() external view returns (uint160 sqrtPriceX96) {
        sqrtPriceX96 = TickMath.getSqrtPriceAtTick(MetadexOracle.consult(POOL, _state().config.twapWindow));
    }

    function pendingShares_(address account) external view returns (uint256 shares) {
        shares = _state().share.shareAccounts[account].pendingShares;
    }

    function isExempt_(address account) external view returns (bool exempt) {
        exempt = _state().share.isExempt[account];
    }

    function lastExchangeRate_() external view returns (uint256 supplyPerValueX128, uint160 sqrtPriceX96) {
        (supplyPerValueX128, sqrtPriceX96) =
        (_state().share.lastExchangeRate.supplyPerValueX128, _state().share.lastExchangeRate.sqrtPriceX96);
    }

    function rewardPerShare_() external view returns (uint256 accumulator) {
        accumulator = _state().rewards.rewardPerShare;
    }

    function POSITION_MANAGER_() external view returns (address positionManager) {
        positionManager = POSITION_MANAGER;
    }

    function ROUTER_TRAMPOLINE_() external view returns (address routerTrampoline) {
        routerTrampoline = ROUTER_TRAMPOLINE;
    }

    function LEAF_VOTER_() external view returns (address leafVoter) {
        leafVoter = LEAF_VOTER;
    }

    function GAUGE_FACTORY_() external view returns (address gaugeFactory) {
        gaugeFactory = GAUGE_FACTORY;
    }

    function REWARD_TOKEN_() external view returns (address rewardToken) {
        rewardToken = REWARD_TOKEN;
    }

    function factory_() external view returns (address factory__) {
        factory__ = FACTORY;
    }

    function pool_() external view returns (address pool__) {
        pool__ = POOL;
    }

    function KEEPER_EXTENSION_() external view returns (address keeperExtension) {
        keeperExtension = KEEPER_EXTENSION;
    }

    function ADMIN_EXTENSION_() external view returns (address adminExtension) {
        adminExtension = ADMIN_EXTENSION;
    }

    function coreParameters_(address feeRecipient) external view returns (CoreParameters memory params) {
        params.tickSpacing = TICK_SPACING;
        params.positionManager = POSITION_MANAGER;
        params.routerTrampoline = ROUTER_TRAMPOLINE;
        params.leafVoter = LEAF_VOTER;
        params.gaugeFactory = GAUGE_FACTORY;
        params.rewardToken = REWARD_TOKEN;
        params.arbBlockNumber = _state().config.arbBlockNumber;
        params.pool = POOL;
        params.token0 = TOKEN0;
        params.token1 = TOKEN1;
        params.gauge = GAUGE;
        params.feeRecipient = feeRecipient;
        params.keeperExtension = KEEPER_EXTENSION;
        params.adminExtension = ADMIN_EXTENSION;
        params.vaults = Vaults(SYNC_VAULT0, SYNC_VAULT1, ASYNC_VAULT0, ASYNC_VAULT1);
    }
}
