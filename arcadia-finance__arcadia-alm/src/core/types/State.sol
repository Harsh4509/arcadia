/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ConfigLib } from "../libraries/state/ConfigLib.sol";
import { PoolTokensLib } from "../libraries/state/PoolTokensLib.sol";
import { QueueLib } from "../libraries/state/QueueLib.sol";
import { Range } from "./Range.sol";
import { RangesLib } from "../libraries/state/RangesLib.sol";
import { RewardsLib } from "../libraries/state/RewardsLib.sol";
import { ShareLib } from "../libraries/state/ShareLib.sol";
import { TokenAmounts } from "./TokenDelta.sol";

/**
 * @notice Every persistent state variable of a core.
 * @custom:storage-location erc7201:arcadia.alm.core
 */
struct State {
    Config config; //         B+0  .. B+3
    Rewards rewards; //       B+4  .. B+8
    Share share; //           B+9  .. B+15
    PoolTokens poolTokens; // B+16 .. B+18
    Range[] ranges; //        B+19, elements at keccak256(B+19) + 2i
    mapping(address vault => VaultQueue vaultQueue) vaultQueues; // B+20
}

using PoolTokensLib for State global;
using QueueLib for State global;
using RangesLib for State global;
using RewardsLib for State global;
using ShareLib for State global;

/**
 * @notice The governance parameters of a core.
 */
struct Config {
    uint128 totalCap; // B+0
    uint128 perUserCap;
    bool paused; // B+1
    uint16 protocolEmissionFeeBps;
    uint16 protocolSwapFeeBps;
    uint32 twapWindow;
    uint64 maxSpotFromTwap;
    uint64 maxSpotFromTrusted;
    uint48 windowEnd;
    uint8 rewardPoolToken; // 1 when the reward token is token0, 2 when token1, else 0.
    uint64 maxTwapFromTrusted; // B+2
    uint16 maxShortfallBps;
    uint16 maxSwapCostBps;
    uint32 minPlanInterval;
    uint8 rangeCap;
    uint32 lastPlanAt;
    bool arbBlockNumber; // True when the gauges count blocks with ArbSys.arbBlockNumber.
    address feeRecipient; // B+3
}

using ConfigLib for Config global;

/**
 * @notice The emissions accumulator and every holder's position in it.
 */
struct Rewards {
    uint128 rewardPerShare; // B+4
    uint128 highWater;
    uint128 claimedCumulative; // B+5
    uint128 lastRewardBalance;
    uint128 protocolFees; // B+6
    uint128 protocolRewardPerSharePaid;
    uint128 preCredited; // B+7
    mapping(address account => RewardAccount rewardAccount) rewardAccounts; // B+8
}

using RewardsLib for Rewards global;

/**
 * @notice The per-holder record of emissions.
 */
struct RewardAccount {
    uint128 rewardPerSharePaid;
    uint128 rewardOwed;
}

/**
 * @notice The share token's metadata, aLP ledger, exchange rate, operator approvals and per user cap exemptions.
 */
struct Share {
    ExchangeRate lastExchangeRate; // B+9 .. B+10
    string name; //   B+11
    string symbol; // B+12
    mapping(address account => ShareAccount shareAccount) shareAccounts; // B+13
    mapping(address controller => mapping(address operator => bool approved)) isOperator; // B+14
    mapping(address account => bool exempt) isExempt; // B+15
}

using ShareLib for Share global;

/**
 * @notice The aLP per value and the trusted price at the last execution's close, for pending deposits.
 */
struct ExchangeRate {
    uint256 supplyPerValueX128;
    uint160 sqrtPriceX96;
}

/**
 * @notice The per-account record of claimable and pending aLP.
 */
struct ShareAccount {
    uint128 claimableShares;
    uint128 pendingShares;
}

/**
 * @notice The tokens held as buffer, owed to the protocol and escrowed for the requests.
 */
struct PoolTokens {
    TokenAmounts buffer; // B+16
    TokenAmounts protocolFees; // B+17
    TokenAmounts escrowed; // B+18
}

using PoolTokensLib for PoolTokens global;

/**
 * @notice One asynchronous vault's deposit queue and redeem queue.
 */
struct VaultQueue {
    Queue deposits; // +0 .. +3
    Queue redeems; // +4 .. +7
}

/**
 * @notice The epoch ids, epochs, records and claimable piles of a vault's deposit or redeem queue.
 */
struct Queue {
    uint32 pendingEpoch; // +0
    uint32 lastClearedEpoch;
    mapping(uint32 id => Epoch epoch) epochs; // +1
    mapping(address controller => Record record) records; // +2
    mapping(address controller => Claimable claimable) claimable; // +3
}

/**
 * @notice The input and output of one epoch.
 */
struct Epoch {
    uint128 amountIn;
    uint128 amountOut;
}

using QueueLib for Epoch global;

/**
 * @notice A controller's request in one queue, and the epoch it sits in.
 */
struct Record {
    uint32 epoch;
    uint128 amountIn;
    uint96 pendingShares;
}

using QueueLib for Record global;

/**
 * @notice A controller's claimable amounts.
 */
struct Claimable {
    uint128 amountIn;
    uint128 amountOut;
}

using QueueLib for Claimable global;
