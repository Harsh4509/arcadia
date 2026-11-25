/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { CLMath } from "../../../shared/libraries/math/CLMath.sol";
import { Config, Epoch, ExchangeRate, PoolTokens, Record, RewardAccount, ShareAccount } from "../../types/State.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { GUARD_SLOT } from "../../../shared/abstracts/mixins/ReentrancyLock.sol";
import { IALMCore } from "../../../interfaces/IALMCore.sol";
import { MetadexOracle } from "../../../shared/libraries/vendored/MetadexOracle.sol";
import { PoolLogic } from "../../../shared/libraries/logic/PoolLogic.sol";
import { QueueLib } from "../state/QueueLib.sol";
import { Range } from "../../types/Range.sol";
import { SlotDerivation } from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import { STATE_SLOT } from "../../abstracts/storage/Storage.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @title ALM Core View Logic.
 * @author Pragma Labs
 * @notice Reads a core's state through its extsload.
 */
// forge-lint: disable-next-item(calls-loop, unsafe-typecast)
library ALMCoreViewLogic {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // totalCap and perUserCap.
    uint256 internal constant CAPS_OFFSET = 0;
    // paused, both fees, twapWindow, maxSpotFromTwap, maxSpotFromTrusted, windowEnd and rewardPoolToken.
    uint256 internal constant PAUSE_AND_FEES_OFFSET = 1;
    // maxTwapFromTrusted, maxShortfallBps, maxSwapCostBps, minPlanInterval, rangeCap, lastPlanAt and arbBlockNumber.
    uint256 internal constant PLAN_BOUNDS_OFFSET = 2;
    // feeRecipient.
    uint256 internal constant FEE_RECIPIENT_OFFSET = 3;
    // rewardPerShare and highWater.
    uint256 internal constant REWARD_PER_SHARE_OFFSET = 4;
    // claimedCumulative and lastRewardBalance.
    uint256 internal constant CLAIMED_CUMULATIVE_OFFSET = 5;
    // The protocol's reward token fee and the reward per share it was paid at.
    uint256 internal constant PROTOCOL_REWARD_OFFSET = 6;
    // preCredited.
    uint256 internal constant PRE_CREDITED_OFFSET = 7;
    // The mapping of every holder's record, one word each.
    uint256 internal constant REWARD_ACCOUNTS_OFFSET = 8;
    // supplyPerValueX128 and sqrtPriceX96 of lastExchangeRate.
    uint256 internal constant LAST_EXCHANGE_RATE_OFFSET = 9;
    // The mapping of every account's claimable and pending aLP, one word each.
    uint256 internal constant SHARE_ACCOUNTS_OFFSET = 13;
    // The mapping of every controller's operator approvals.
    uint256 internal constant IS_OPERATOR_OFFSET = 14;
    // The mapping of every account's per user cap exemption.
    uint256 internal constant IS_EXEMPT_OFFSET = 15;
    // buffer.
    uint256 internal constant BUFFER_OFFSET = 16;
    // protocolFees.
    uint256 internal constant PROTOCOL_FEES_OFFSET = 17;
    // escrowed.
    uint256 internal constant ESCROWED_OFFSET = 18;
    // The length of ranges, whose elements sit two words each from its hash.
    uint256 internal constant RANGES_OFFSET = 19;
    // The mapping of every vault's queue.
    uint256 internal constant VAULT_QUEUES_OFFSET = 20;
    // The base of the deposit queue, from the base of a vault's queues.
    uint256 internal constant DEPOSITS_OFFSET = 0;
    // The base of the redeem queue, from the base of a vault's queues.
    uint256 internal constant REDEEMS_OFFSET = 4;
    // pendingEpoch and lastClearedEpoch, from a queue base.
    uint256 internal constant PENDING_EPOCH_OFFSET = 0;
    // The epochs mapping, from a queue base.
    uint256 internal constant EPOCHS_OFFSET = 1;
    // The records mapping, from a queue base.
    uint256 internal constant RECORDS_OFFSET = 2;
    // The claimable mapping, from a queue base.
    uint256 internal constant CLAIMABLE_OFFSET = 3;
    // The first bit of protocolEmissionFeeBps in the word at PAUSE_AND_FEES_OFFSET.
    uint256 internal constant EMISSION_FEE_BPS_SHIFT = 8;
    // The first bit of protocolSwapFeeBps in the word at PAUSE_AND_FEES_OFFSET.
    uint256 internal constant SWAP_FEE_BPS_SHIFT = 24;
    // The first bit of twapWindow in the word at PAUSE_AND_FEES_OFFSET.
    uint256 internal constant TWAP_WINDOW_SHIFT = 40;
    // The first bit of maxSpotFromTwap in the word at PAUSE_AND_FEES_OFFSET.
    uint256 internal constant MAX_SPOT_FROM_TWAP_SHIFT = 72;
    // The first bit of maxSpotFromTrusted in the word at PAUSE_AND_FEES_OFFSET.
    uint256 internal constant MAX_SPOT_FROM_TRUSTED_SHIFT = 136;
    // The first bit of windowEnd in the word at PAUSE_AND_FEES_OFFSET.
    uint256 internal constant WINDOW_END_SHIFT = 200;
    // The first bit of rewardPoolToken in the word at PAUSE_AND_FEES_OFFSET.
    uint256 internal constant REWARD_POOL_TOKEN_SHIFT = 248;
    // The first bit of maxShortfallBps in the word at PLAN_BOUNDS_OFFSET.
    uint256 internal constant MAX_SHORTFALL_BPS_SHIFT = 64;
    // The first bit of maxSwapCostBps in the word at PLAN_BOUNDS_OFFSET.
    uint256 internal constant MAX_SWAP_COST_BPS_SHIFT = 80;
    // The first bit of minPlanInterval in the word at PLAN_BOUNDS_OFFSET.
    uint256 internal constant MIN_PLAN_INTERVAL_SHIFT = 96;
    // The first bit of rangeCap in the word at PLAN_BOUNDS_OFFSET.
    uint256 internal constant RANGE_CAP_SHIFT = 128;
    // The first bit of lastPlanAt in the word at PLAN_BOUNDS_OFFSET.
    uint256 internal constant LAST_PLAN_AT_SHIFT = 136;
    // The first bit of arbBlockNumber in the word at PLAN_BOUNDS_OFFSET.
    uint256 internal constant ARB_BLOCK_NUMBER_SHIFT = 168;
    // The first bit of tickUpper in the first word of a range.
    uint256 internal constant TICK_UPPER_SHIFT = 24;
    // The first bit of unstakedTokenId in the first word of a range.
    uint256 internal constant UNSTAKED_TOKEN_ID_SHIFT = 48;
    // The first bit of stakedLiquidity in the first word of a range.
    uint256 internal constant STAKED_LIQUIDITY_SHIFT = 128;
    // The first bit of stakedBlock in the second word of a range.
    uint256 internal constant STAKED_BLOCK_SHIFT = 80;
    // The first bit of lastClearedEpoch in the word at PENDING_EPOCH_OFFSET from a queue base.
    uint256 internal constant LAST_CLEARED_EPOCH_SHIFT = 32;
    // The first bit of amountIn in a record.
    uint256 internal constant RECORD_AMOUNT_IN_SHIFT = 32;
    // The first bit of pendingShares in a record.
    uint256 internal constant RECORD_PENDING_SHARES_SHIFT = 160;

    /* //////////////////////////////////////////////////////////////
                                 CONFIG
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The core's governance parameters.
     * @param core The core.
     * @return config The governance parameters.
     */
    function getConfig(IALMCore core) internal view returns (Config memory config) {
        bytes32[] memory words = core.extsload(memberSlot(CAPS_OFFSET), 4);
        (config.totalCap, config.perUserCap) = decodeWord(words[0]);

        uint256 pauseAndFees = uint256(words[PAUSE_AND_FEES_OFFSET - CAPS_OFFSET]);
        (config.paused, config.maxSpotFromTwap) = decodePauseAndDeviation(pauseAndFees);
        config.protocolEmissionFeeBps = uint16(pauseAndFees >> EMISSION_FEE_BPS_SHIFT);
        config.protocolSwapFeeBps = uint16(pauseAndFees >> SWAP_FEE_BPS_SHIFT);
        config.twapWindow = uint32(pauseAndFees >> TWAP_WINDOW_SHIFT);
        config.maxSpotFromTrusted = uint64(pauseAndFees >> MAX_SPOT_FROM_TRUSTED_SHIFT);
        config.windowEnd = uint48(pauseAndFees >> WINDOW_END_SHIFT);
        config.rewardPoolToken = uint8(pauseAndFees >> REWARD_POOL_TOKEN_SHIFT);

        uint256 planBounds = uint256(words[PLAN_BOUNDS_OFFSET - CAPS_OFFSET]);
        config.maxTwapFromTrusted = uint64(planBounds);
        config.maxShortfallBps = uint16(planBounds >> MAX_SHORTFALL_BPS_SHIFT);
        config.maxSwapCostBps = uint16(planBounds >> MAX_SWAP_COST_BPS_SHIFT);
        config.minPlanInterval = uint32(planBounds >> MIN_PLAN_INTERVAL_SHIFT);
        config.rangeCap = uint8(planBounds >> RANGE_CAP_SHIFT);
        config.lastPlanAt = uint32(planBounds >> LAST_PLAN_AT_SHIFT);
        config.arbBlockNumber = uint8(planBounds >> ARB_BLOCK_NUMBER_SHIFT) != 0;

        config.feeRecipient = address(uint160(uint256(words[FEE_RECIPIENT_OFFSET - CAPS_OFFSET])));
    }

    /**
     * @notice The window the core's TWAP is taken over.
     * @param core The core.
     * @return twapWindow The window, in seconds.
     */
    function getTwapWindow(IALMCore core) internal view returns (uint32 twapWindow) {
        twapWindow = uint32(uint256(core.extsload(memberSlot(PAUSE_AND_FEES_OFFSET))) >> TWAP_WINDOW_SHIFT);
    }

    /**
     * @notice The value a swap may lose against the pool's spot price.
     * @param core The core.
     * @return maxSwapCostBps The max swap cost, in basis points.
     */
    function getMaxSwapCostBps(IALMCore core) internal view returns (uint16 maxSwapCostBps) {
        maxSwapCostBps = uint16(uint256(core.extsload(memberSlot(PLAN_BOUNDS_OFFSET))) >> MAX_SWAP_COST_BPS_SHIFT);
    }

    /**
     * @notice The pause flag and the spot band around the TWAP in the config's pause and fees word.
     * @param word The config's pause and fees word.
     * @return paused True while the core is paused.
     * @return maxSpotFromTwap The 1e18-scaled ratio band of the spot sqrt price around the TWAP.
     */
    function decodePauseAndDeviation(uint256 word) internal pure returns (bool paused, uint64 maxSpotFromTwap) {
        paused = uint8(word) != 0;
        maxSpotFromTwap = uint64(word >> MAX_SPOT_FROM_TWAP_SHIFT);
    }

    /* //////////////////////////////////////////////////////////////
                                 REWARDS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The core's emissions accumulator.
     * @param core The core.
     * @return rewardPerShare The reward per share accrued.
     * @return highWater The lifetime reward the accumulator last reached, raised by folded pre-credits.
     * @return claimedCumulative The reward token claimed in total.
     * @return lastRewardBalance The reward token balance at the last accrual.
     * @return protocolFees The reward token owed to the protocol.
     * @return protocolRewardPerSharePaid The reward per share the protocol's fee was paid at.
     * @return preCredited The emissions credited to holders that a penalty window still hides.
     */
    function getRewards(IALMCore core)
        internal
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
        bytes32[] memory words = core.extsload(memberSlot(REWARD_PER_SHARE_OFFSET), 4);
        (rewardPerShare, highWater) = decodeWord(words[0]);
        (claimedCumulative, lastRewardBalance) = decodeWord(words[CLAIMED_CUMULATIVE_OFFSET - REWARD_PER_SHARE_OFFSET]);
        (protocolFees, protocolRewardPerSharePaid) = decodeWord(words[PROTOCOL_REWARD_OFFSET - REWARD_PER_SHARE_OFFSET]);
        (preCredited,) = decodeWord(words[PRE_CREDITED_OFFSET - REWARD_PER_SHARE_OFFSET]);
    }

    /**
     * @notice A holder's reward accounting.
     * @param core The core.
     * @param account The holder.
     * @return rewardAccount The reward per share paid and the reward owed.
     */
    function getRewardAccount(IALMCore core, address account)
        internal
        view
        returns (RewardAccount memory rewardAccount)
    {
        (rewardAccount.rewardPerSharePaid, rewardAccount.rewardOwed) =
            decodeWord(core.extsload(mappingSlot(account, REWARD_ACCOUNTS_OFFSET)));
    }

    /* //////////////////////////////////////////////////////////////
                                  SHARE
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The exchange rate the last execution stored.
     * @param core The core.
     * @return lastExchangeRate The supply per unit of value and the price it was taken at.
     */
    function getLastExchangeRate(IALMCore core) internal view returns (ExchangeRate memory lastExchangeRate) {
        bytes32[] memory words = core.extsload(memberSlot(LAST_EXCHANGE_RATE_OFFSET), 2);
        lastExchangeRate.supplyPerValueX128 = uint256(words[0]);
        lastExchangeRate.sqrtPriceX96 = uint160(uint256(words[1]));
    }

    /**
     * @notice One account's claimable and pending aLP.
     * @param core The core.
     * @param account The account.
     * @return shareAccount The claimable and the pending aLP.
     */
    function getShareAccount(IALMCore core, address account) internal view returns (ShareAccount memory shareAccount) {
        (shareAccount.claimableShares, shareAccount.pendingShares) =
            decodeWord(core.extsload(mappingSlot(account, SHARE_ACCOUNTS_OFFSET)));
    }

    /**
     * @notice Whether an operator may act for a controller.
     * @param core The core.
     * @param controller The account the operator acts for.
     * @param operator The operator.
     * @return approved True when approved.
     */
    function isOperator(IALMCore core, address controller, address operator) internal view returns (bool approved) {
        bytes32 slot = SlotDerivation.deriveMapping(mappingSlot(controller, IS_OPERATOR_OFFSET), operator);
        approved = uint8(uint256(core.extsload(slot))) != 0;
    }

    /**
     * @notice Whether governance exempted an account from the per user cap.
     * @param core The core.
     * @param account The account.
     * @return exempt True when exempted.
     */
    function isExempt(IALMCore core, address account) internal view returns (bool exempt) {
        exempt = uint8(uint256(core.extsload(mappingSlot(account, IS_EXEMPT_OFFSET)))) != 0;
    }

    /**
     * @notice The most aLP a receiver may be minted, before the vault's spot band check.
     * @param core The core.
     * @param receiver The account the shares would be minted to.
     * @return shares The room under the total cap and the per user cap, zero while paused or for the core.
     */
    function maxMint(IALMCore core, address receiver) internal view returns (uint256 shares) {
        // Get the caps and the pause flag.
        bytes32[] memory words = core.extsload(memberSlot(CAPS_OFFSET), 2);
        (uint128 totalCap, uint128 perUserCap) = decodeWord(words[0]);
        (bool paused,) = decodePauseAndDeviation(uint256(words[PAUSE_AND_FEES_OFFSET - CAPS_OFFSET]));

        // Checks.
        if (paused || receiver == address(core)) return 0;

        // Calculate the room under the total cap.
        shares = uint256(totalCap).zeroFloorSub(core.totalSupply());

        // If the receiver is not exempt, cap the room at the room under the per user cap.
        if (!isExempt(core, receiver)) {
            ShareAccount memory shareAccount = getShareAccount(core, receiver);
            shares = FixedPointMathLib.min(
                shares,
                uint256(perUserCap)
                    .zeroFloorSub(core.balanceOf(receiver) + shareAccount.claimableShares + shareAccount.pendingShares)
            );
        }
    }

    /* //////////////////////////////////////////////////////////////
                               POOL TOKENS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The core's buffer, the pool tokens it owes the protocol and the escrow of the requests.
     * @param core The core.
     * @return poolTokens The buffer, the fees owed and the escrow.
     */
    function getPoolTokens(IALMCore core) internal view returns (PoolTokens memory poolTokens) {
        bytes32[] memory words = core.extsload(memberSlot(BUFFER_OFFSET), 3);
        (poolTokens.buffer.amount0, poolTokens.buffer.amount1) = decodeWord(words[0]);
        (poolTokens.protocolFees.amount0, poolTokens.protocolFees.amount1) =
            decodeWord(words[PROTOCOL_FEES_OFFSET - BUFFER_OFFSET]);
        (poolTokens.escrowed.amount0, poolTokens.escrowed.amount1) = decodeWord(words[ESCROWED_OFFSET - BUFFER_OFFSET]);
    }

    /**
     * @notice The core's buffer.
     * @param core The core.
     * @return amount0 The token0 in the buffer.
     * @return amount1 The token1 in the buffer.
     */
    function getBuffer(IALMCore core) internal view returns (uint128 amount0, uint128 amount1) {
        (amount0, amount1) = decodeWord(core.extsload(memberSlot(BUFFER_OFFSET)));
    }

    /* //////////////////////////////////////////////////////////////
                                 RANGES
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The two storage words of every range of the core.
     * @param core The core.
     * @return words The words, two per range in order.
     */
    function readRangeWords(IALMCore core) internal view returns (bytes32[] memory words) {
        bytes32 slot = memberSlot(RANGES_OFFSET);
        uint256 count = uint256(core.extsload(slot));
        // Unchecked: the core holds at most MAX_RANGE_CAP ranges.
        unchecked {
            words = core.extsload(SlotDerivation.deriveArray(slot), 2 * count);
        }
    }

    /**
     * @notice Decodes each range from its two storage words.
     * @param words The two storage words of every range, in order.
     * @return ranges The ranges.
     */
    function decodeRanges(bytes32[] memory words) internal pure returns (Range[] memory ranges) {
        uint256 length = words.length / 2;
        assembly ("memory-safe") {
            ranges := mload(0x40)
            mstore(ranges, length)
            let source := add(words, 0x20)
            let pointers := add(ranges, 0x20)
            let range := add(pointers, shl(5, length))
            for { let i := 0 } lt(i, length) { i := add(i, 1) } {
                mstore(add(pointers, shl(5, i)), range)
                let unstaked := mload(add(source, shl(6, i)))
                let staked := mload(add(source, add(shl(6, i), 0x20)))
                mstore(range, signextend(2, unstaked))
                mstore(add(range, 0x20), signextend(2, shr(TICK_UPPER_SHIFT, unstaked)))
                mstore(add(range, 0x40), and(shr(UNSTAKED_TOKEN_ID_SHIFT, unstaked), 0xffffffffffffffffffff))
                mstore(add(range, 0x60), shr(STAKED_LIQUIDITY_SHIFT, unstaked))
                mstore(add(range, 0x80), and(staked, 0xffffffffffffffffffff))
                mstore(add(range, 0xa0), shr(STAKED_BLOCK_SHIFT, staked))
                range := add(range, 0xc0)
            }
            mstore(0x40, range)
        }
    }

    /**
     * @notice Decodes one range's ticks and staked liquidity from its first storage word.
     * @param words The two storage words of every range, in order.
     * @param index The index of the range.
     * @return tickLower The lower tick of the range.
     * @return tickUpper The upper tick of the range.
     * @return stakedLiquidity The staked liquidity of the range.
     */
    function decodeRange(bytes32[] memory words, uint256 index)
        internal
        pure
        returns (int24 tickLower, int24 tickUpper, uint128 stakedLiquidity)
    {
        uint256 word;
        // Unchecked: the index is below half the words' length at every caller.
        unchecked {
            word = uint256(words[2 * index]);
        }
        tickLower = int24(uint24(word));
        tickUpper = int24(uint24(word >> TICK_UPPER_SHIFT));
        stakedLiquidity = uint128(word >> STAKED_LIQUIDITY_SHIFT);
    }

    /* //////////////////////////////////////////////////////////////
                                 QUEUES
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice A vault's pending deposit epoch.
     * @param core The core.
     * @param vault The vault.
     * @return pendingEpoch The id of the pending deposit epoch.
     */
    function getPendingDepositEpoch(IALMCore core, address vault) internal view returns (uint32 pendingEpoch) {
        pendingEpoch = getPendingEpoch(core, DEPOSITS_OFFSET, vault);
    }

    /**
     * @notice A vault's pending redeem epoch.
     * @param core The core.
     * @param vault The vault.
     * @return pendingEpoch The id of the pending redeem epoch.
     */
    function getPendingRedeemEpoch(IALMCore core, address vault) internal view returns (uint32 pendingEpoch) {
        pendingEpoch = getPendingEpoch(core, REDEEMS_OFFSET, vault);
    }

    /**
     * @notice A vault's last cleared deposit epoch.
     * @param core The core.
     * @param vault The vault.
     * @return lastClearedEpoch The id of the deposit epoch the last clear moved requests into.
     */
    function getLastClearedDepositEpoch(IALMCore core, address vault) internal view returns (uint32 lastClearedEpoch) {
        lastClearedEpoch = getLastClearedEpoch(core, DEPOSITS_OFFSET, vault);
    }

    /**
     * @notice A vault's last cleared redeem epoch.
     * @param core The core.
     * @param vault The vault.
     * @return lastClearedEpoch The id of the redeem epoch the last clear moved requests into.
     */
    function getLastClearedRedeemEpoch(IALMCore core, address vault) internal view returns (uint32 lastClearedEpoch) {
        lastClearedEpoch = getLastClearedEpoch(core, REDEEMS_OFFSET, vault);
    }

    /**
     * @notice A vault's deposit epoch.
     * @param core The core.
     * @param vault The vault.
     * @param epoch The epoch id.
     * @return epoch_ The input and the output.
     */
    function getDepositEpoch(IALMCore core, address vault, uint32 epoch) internal view returns (Epoch memory epoch_) {
        epoch_ = getEpoch(core, DEPOSITS_OFFSET, vault, epoch);
    }

    /**
     * @notice A vault's redeem epoch.
     * @param core The core.
     * @param vault The vault.
     * @param epoch The epoch id.
     * @return epoch_ The input and the output.
     */
    function getRedeemEpoch(IALMCore core, address vault, uint32 epoch) internal view returns (Epoch memory epoch_) {
        epoch_ = getEpoch(core, REDEEMS_OFFSET, vault, epoch);
    }

    /**
     * @notice A controller's deposit record on a vault.
     * @param core The core.
     * @param vault The vault.
     * @param controller The controller.
     * @return record The epoch, the amount in and the pending aLP.
     */
    function getDepositRecord(IALMCore core, address vault, address controller)
        internal
        view
        returns (Record memory record)
    {
        record = getRecord(core, DEPOSITS_OFFSET, vault, controller);
    }

    /**
     * @notice A controller's redeem record on a vault.
     * @param core The core.
     * @param vault The vault.
     * @param controller The controller.
     * @return record The epoch, the amount in and the pending aLP.
     */
    function getRedeemRecord(IALMCore core, address vault, address controller)
        internal
        view
        returns (Record memory record)
    {
        record = getRecord(core, REDEEMS_OFFSET, vault, controller);
    }

    /**
     * @notice The asset amount a controller's deposit record holds in the pending epoch.
     * @param core The core.
     * @param vault The vault.
     * @param controller The controller.
     * @return assets The asset amount, zero unless the record is pending.
     */
    function getPendingDeposit(IALMCore core, address vault, address controller)
        internal
        view
        returns (uint256 assets)
    {
        assets = getPending(core, DEPOSITS_OFFSET, vault, controller);
    }

    /**
     * @notice The aLP a controller's redeem record holds in the pending epoch.
     * @param core The core.
     * @param vault The vault.
     * @param controller The controller.
     * @return shares The aLP, zero unless the record is pending.
     */
    function getPendingRedeem(IALMCore core, address vault, address controller) internal view returns (uint256 shares) {
        shares = getPending(core, REDEEMS_OFFSET, vault, controller);
    }

    /**
     * @notice A controller's claimable deposits on a vault, counting a settled record.
     * @param core The core.
     * @param vault The vault.
     * @param controller The controller.
     * @return assets The settled input.
     * @return shares The settled output.
     */
    function getClaimableDeposit(IALMCore core, address vault, address controller)
        internal
        view
        returns (uint128 assets, uint128 shares)
    {
        (assets, shares) = getClaimable(core, DEPOSITS_OFFSET, vault, controller);
    }

    /**
     * @notice A controller's claimable redeems on a vault, counting a settled record.
     * @param core The core.
     * @param vault The vault.
     * @param controller The controller.
     * @return assets The settled output.
     * @return shares The settled input.
     */
    function getClaimableRedeem(IALMCore core, address vault, address controller)
        internal
        view
        returns (uint128 assets, uint128 shares)
    {
        (shares, assets) = getClaimable(core, REDEEMS_OFFSET, vault, controller);
    }

    /**
     * @notice The pending epoch of one queue of a vault.
     * @param core The core.
     * @param queueOffset The base of the deposit or redeem queue.
     * @param vault The vault.
     * @return pendingEpoch The id of the pending epoch.
     */
    function getPendingEpoch(IALMCore core, uint256 queueOffset, address vault)
        internal
        view
        returns (uint32 pendingEpoch)
    {
        pendingEpoch = uint32(uint256(core.extsload(queueSlot(vault, queueOffset + PENDING_EPOCH_OFFSET))));
    }

    /**
     * @notice The last cleared epoch of one queue of a vault.
     * @param core The core.
     * @param queueOffset The base of the deposit or redeem queue.
     * @param vault The vault.
     * @return lastClearedEpoch The id of the epoch the last clear moved requests into.
     */
    function getLastClearedEpoch(IALMCore core, uint256 queueOffset, address vault)
        internal
        view
        returns (uint32 lastClearedEpoch)
    {
        lastClearedEpoch = uint32(
            uint256(core.extsload(queueSlot(vault, queueOffset + PENDING_EPOCH_OFFSET))) >> LAST_CLEARED_EPOCH_SHIFT
        );
    }

    /**
     * @notice A controller's record in one queue of a vault.
     * @param core The core.
     * @param queueOffset The base of the deposit or redeem queue.
     * @param vault The vault.
     * @param controller The controller.
     * @return record The epoch, the amount in and the pending aLP.
     */
    function getRecord(IALMCore core, uint256 queueOffset, address vault, address controller)
        internal
        view
        returns (Record memory record)
    {
        (record.epoch, record.amountIn, record.pendingShares) = decodeRecord(
            core.extsload(SlotDerivation.deriveMapping(queueSlot(vault, queueOffset + RECORDS_OFFSET), controller))
        );
    }

    /**
     * @notice An epoch by its queue, vault and id.
     * @param core The core.
     * @param queueOffset The base of the deposit or redeem queue.
     * @param vault The vault.
     * @param epoch The epoch id.
     * @return epoch_ The input and the output.
     */
    function getEpoch(IALMCore core, uint256 queueOffset, address vault, uint32 epoch)
        internal
        view
        returns (Epoch memory epoch_)
    {
        (epoch_.amountIn, epoch_.amountOut) = decodeWord(
            core.extsload(SlotDerivation.deriveMapping(queueSlot(vault, queueOffset + EPOCHS_OFFSET), uint256(epoch)))
        );
    }

    /**
     * @notice The amount a record holds in its queue's pending epoch.
     * @param core The core.
     * @param queueOffset The base of the deposit or redeem queue.
     * @param vault The vault.
     * @param controller The controller.
     * @return amountIn The amount, zero unless the record is pending.
     */
    function getPending(IALMCore core, uint256 queueOffset, address vault, address controller)
        internal
        view
        returns (uint256 amountIn)
    {
        bytes32[] memory slots = new bytes32[](2);
        slots[0] = queueSlot(vault, queueOffset + PENDING_EPOCH_OFFSET);
        slots[1] = SlotDerivation.deriveMapping(
            SlotDerivation.offset(slots[0], RECORDS_OFFSET - PENDING_EPOCH_OFFSET), controller
        );
        bytes32[] memory words = core.extsload(slots);
        uint32 recordEpoch;
        (recordEpoch, amountIn,) = decodeRecord(words[1]);
        amountIn = QueueLib.isPending(recordEpoch, uint32(uint256(words[0])), amountIn) ? amountIn : 0;
    }

    /**
     * @notice A controller's claimable amounts in one queue of a vault, including a settled record.
     * @param core The core.
     * @param queueOffset The base of the deposit or redeem queue.
     * @param vault The vault.
     * @param controller The controller.
     * @return amountIn The settled input.
     * @return amountOut The settled output.
     */
    function getClaimable(IALMCore core, uint256 queueOffset, address vault, address controller)
        internal
        view
        returns (uint128 amountIn, uint128 amountOut)
    {
        bytes32[] memory slots = new bytes32[](3);
        slots[0] = queueSlot(vault, queueOffset + PENDING_EPOCH_OFFSET);
        slots[1] = SlotDerivation.deriveMapping(
            SlotDerivation.offset(slots[0], RECORDS_OFFSET - PENDING_EPOCH_OFFSET), controller
        );
        slots[2] = SlotDerivation.deriveMapping(
            SlotDerivation.offset(slots[0], CLAIMABLE_OFFSET - PENDING_EPOCH_OFFSET), controller
        );
        bytes32[] memory words = core.extsload(slots);
        (uint32 recordEpoch, uint128 recordAmountIn,) = decodeRecord(words[1]);
        (amountIn, amountOut) = decodeWord(words[2]);
        if (QueueLib.isSettled(recordEpoch, uint32(uint256(words[0])), recordAmountIn)) {
            (uint128 batchAmountIn, uint128 batchAmountOut) = decodeWord(
                core.extsload(
                    SlotDerivation.deriveMapping(
                        SlotDerivation.offset(slots[0], EPOCHS_OFFSET - PENDING_EPOCH_OFFSET), uint256(recordEpoch)
                    )
                )
            );
            amountIn += recordAmountIn;
            amountOut += uint128(QueueLib.requestAmountOut(recordAmountIn, batchAmountIn, batchAmountOut));
        }
    }

    /**
     * @notice The epoch, the amount in and the pending aLP in a record's word.
     * @param word The word.
     * @return epoch The epoch the record sits in.
     * @return amountIn The record's amount in.
     * @return pendingShares The aLP the record reserves.
     */
    function decodeRecord(bytes32 word) internal pure returns (uint32 epoch, uint128 amountIn, uint96 pendingShares) {
        epoch = uint32(uint256(word));
        amountIn = uint128(uint256(word) >> RECORD_AMOUNT_IN_SHIFT);
        pendingShares = uint96(uint256(word) >> RECORD_PENDING_SHARES_SHIFT);
    }

    /**
     * @notice The two uint128 halves of a word.
     * @param word The word.
     * @return low The low half.
     * @return high The high half.
     */
    function decodeWord(bytes32 word) internal pure returns (uint128 low, uint128 high) {
        low = uint128(uint256(word));
        high = uint128(uint256(word) >> 128);
    }

    /* //////////////////////////////////////////////////////////////
                                  LOCK
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Whether the core's reentrancy lock is set.
     * @param core The core.
     * @return locked True while the lock is set.
     */
    function isLocked(IALMCore core) internal view returns (bool locked) {
        locked = core.exttload(bytes32(GUARD_SLOT)) != bytes32(0);
    }

    /* //////////////////////////////////////////////////////////////
                                 QUOTES
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Whether a vault can quote a limit, the price it quotes against and the band's limit for a buy.
     * @param core The core.
     * @param pool The Metadex CL pool.
     * @param assetIsToken0 True when the vault's asset is token0.
     * @param paused True when the vault is paused.
     * @return isQuotable True when the vault can quote a limit, with spot inside the band.
     * @return sqrtPriceX96 The spot price, zero when the vault is paused or the core is locked or has no supply.
     * @return sqrtPriceLimitX96 The band's limit in the direction a buy of the non-asset moves the price.
     */
    function quotable(IALMCore core, address pool, bool assetIsToken0, bool paused)
        internal
        view
        returns (bool isQuotable, uint160 sqrtPriceX96, uint256 sqrtPriceLimitX96)
    {
        if (paused || isLocked(core) || core.totalSupply() == 0) {
            return (false, 0, 0);
        }

        uint256 word = uint256(core.extsload(memberSlot(PAUSE_AND_FEES_OFFSET)));
        uint160 twapSqrtPriceX96 =
            TickMath.getSqrtPriceAtTick(MetadexOracle.consult(pool, uint32(word >> TWAP_WINDOW_SHIFT)));
        sqrtPriceX96 = PoolLogic.sqrtPriceX96(pool);
        (uint256 sqrtPriceLowerX96, uint256 sqrtPriceUpperX96) =
            CLMath.getBand(twapSqrtPriceX96, uint64(word >> MAX_SPOT_FROM_TWAP_SHIFT));
        isQuotable = sqrtPriceX96 >= sqrtPriceLowerX96 && sqrtPriceX96 <= sqrtPriceUpperX96;
        sqrtPriceLimitX96 = assetIsToken0 ? sqrtPriceLowerX96 : sqrtPriceUpperX96;
    }

    /* //////////////////////////////////////////////////////////////
                              STORAGE SLOTS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The slot of a member of the core's state.
     * @param offset The member offset.
     * @return slot The slot.
     */
    function memberSlot(uint256 offset) internal pure returns (bytes32 slot) {
        // Unchecked: STATE_SLOT ends in a zero byte and every offset is below 256.
        unchecked {
            slot = bytes32(uint256(STATE_SLOT) + offset);
        }
    }

    /**
     * @notice The slot of an entry of a mapping member of the core's state.
     * @param key The key.
     * @param offset The member offset of the mapping.
     * @return slot The slot.
     */
    function mappingSlot(address key, uint256 offset) internal pure returns (bytes32 slot) {
        slot = SlotDerivation.deriveMapping(memberSlot(offset), key);
    }

    /**
     * @notice The slot of a member of a vault's queue.
     * @param vault The vault.
     * @param offset The queue offset.
     * @return slot The slot.
     */
    function queueSlot(address vault, uint256 offset) internal pure returns (bytes32 slot) {
        slot = SlotDerivation.offset(mappingSlot(vault, VAULT_QUEUES_OFFSET), offset);
    }
}
