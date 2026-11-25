# Arcadia ALM: protocol documentation for the Sherlock audit

Repository `arcadia-finance/arcadia-alm`. In scope: `src/**`, except the vendored Metadex libraries in `src/shared/libraries/vendored/`. Out of scope: the pinned Metadex sources under `node_modules/`, the `RouterTrampoline` (Arcadia `asset-managers` repository), and `test/`.

## 1. Protocol Overview

### 1.1 Summary

Arcadia ALM is an automated liquidity manager for Aero Metadex pools (a Slipstream / Uniswap V3 style concentrated-liquidity AMM with gauges). Cores are deployed only for selected liquid pairs (Section 3.2), one `ALMCore` per pool. The core holds up to 14 ranges in that pool (14 positions, each over a lower and upper tick of any width the keeper picks; ranges may overlap) plus an idle buffer of both pool tokens, and issues an ERC-20 share, aLP, against them. Each range is held as two position NFTs: an unstaked side that earns swap fees and a staked side, deposited in the pool's `CLGauge`, that earns AERO emissions. A trusted keeper (Arcadia bot) rebalances the core through `ALMCore.execute`, a small program of opcodes (open, close, add, remove, stake, swap, settle); on-chain bounds cap what one plan can lose as defense in depth.

Users enter and exit in three ways. In kind on the core (`ALMCore.mint` / `ALMCore.burn`, pro rata in both tokens). With one token through an ERC-4626 style synchronous vault (`ALMVaultSync`, one per pool token), which swaps against the pool in the same transaction. Or with one token through an ERC-7540 asynchronous vault (`ALMVaultAsync`, one per pool token), whose requests the keeper settles at a trusted price inside a plan. aLP holders earn swap fees through the share price and AERO emissions through a reward-per-share accumulator; the protocol takes a capped share of both.

### 1.2 Key Design Changes / Novel Mechanisms

- **Unstaked twin per range.** The Metadex gauge forfeits a position's emissions if it is withdrawn within `minStakeBlocks` of its deposit. User burns take liquidity from each range's unstaked side first and only reach the staked side when the unstaked side is too small. Keeping the unstaked side sized to exit flow is the keeper's job (Section 6).
- **In-kind core, single-token vaults on top.** The core only knows pro-rata in-kind mint and burn. The vaults are ordinary callers of the core (`mint`, `trustedBurn`); they hold no state of their own beyond a pause flag.
- **Keeper plans as bounded programs.** A plan is `execute(commands, inputs, trustedSqrtPriceX96)`. The core values its holdings at the keeper's trusted price before and after the plan and reverts if value per share fell by more than `maxShortfallBps`. It also enforces a price band of the trusted price around spot and TWAP, one swap per plan with a cost of at most `maxSwapCostBps` against plan-start spot, and `minPlanInterval`.
- **Async epochs settled inside the plan.** ERC-7540 requests wait in a pending epoch. A plan clears requests (all, or named controllers) as its first steps and settles them in a `SETTLE_REQUESTS` step of the same plan, at the trusted price. Flows that needed the plan's swap pay its cost as a levy; a swap gain goes to the remaining holders.
- **Lifetime emissions accumulator.** Reward per share is driven by the core's lifetime emissions (claimed, received and still earned at the gauge), not by claim events, with a high-water mark. Emissions the gauge hides behind an open penalty window are credited ahead ("pre-credit").
- **Delegatecall extensions with appended immutables.** `ALMKeeperExtension` and `ALMAdminExtension` run in the core's storage by delegatecall. The core appends nine immutable words (tick spacing, pool, tokens, gauge, async vaults, sync vaults) and their length to the calldata, and the extensions read them from the end of calldata (ERC-3448 style). The sync vaults do the same with `ALMSyncExtension`, by staticcall only (previews, limits and accounting views); the sync vault has no delegatecall.
- **On-chain swap simulation in the sync vault.** Previews and the deposit/mint swap size are computed by walking the pool's ticks with vendored `SwapMath`/`TickBitmap` and solving a quadratic, so the vault's own swap and the core's mint agree to a few wei.
- **Live unstaked liquidity.** The core stores no unstaked liquidity; every reader takes `positions(tokenId).liquidity` from the position manager. Anyone may add liquidity to the core's unstaked NFTs (Metadex allows it for non-gauge-held tokens); that liquidity belongs to aLP holders at once.

### 1.3 Actors

- **Sync user.** Deposits or withdraws one pool token through `ALMVaultSync`. Goal: a one-transaction single-asset entry and exit.
- **Async user (owner, controller, operator).** Requests deposits or redeems through `ALMVaultAsync`, cancels while pending, claims after settlement. Goal: size without paying pool price impact itself.
- **In-kind user / integrator.** Calls `ALMCore.mint` and `ALMCore.burn` directly, or holds and transfers aLP.
- **Keeper (Arcadia bot).** Runs plans: rebalances ranges, stakes and unstakes, compounds fees, swaps, clears and settles async requests.
- **Steward, admin, guardian, factory owner.** Deploy cores and set parameters through `ALMFactory` (Section 4).
- **Anyone (permissionless upkeep).** `claimEmissions(account)`, `payProtocolFees`, `skim`, and the sync vault's `sweep`. Payouts go to fixed recipients only.
- **Fee recipient.** Receives the protocol's share of swap fees and emissions.

### 1.4 Core User Flows

- **Sync deposit / mint.** Entry `ALMVaultSync.deposit` or `mint`. Touches: vault → `SnapshotLib.getSnapshot` reads of the core (extsload) → `CLPool.swap` (part of the asset for the other token, callback pays) → `ALMCore.mint` (TWAP band check, pulls both tokens from the vault, `NonfungiblePositionManager.increaseLiquidity` per range, refunds unused token0) → vault refunds unused asset. Synchronous.
- **Sync redeem / withdraw.** Entry `ALMVaultSync.redeem` or `withdraw`. Touches: vault (`quotable`: spot inside the TWAP band) → `ALMCore.trustedBurn` (per range `decreaseLiquidity` + `collect`, unstaked side first; if needed `CLGauge.withdraw`, decrease, re-`deposit`) → asset to receiver, other token to vault → `CLPool.swap` sells the other token for the asset to the receiver. Synchronous.
- **In-kind mint / burn.** Entry `ALMCore.mint(shares, receiver)` / `ALMCore.burn(shares, receiver, owner)`. Same core steps as above, no swap. Synchronous.
- **Async deposit.** `ALMVaultAsync.requestDeposit` (asset owner → core escrow, `ALMCore.recordDepositRequest`) → later a keeper plan `CLEAR_REQUESTS`/`CLEAR_ALL_REQUESTS` and `SETTLE_REQUESTS` mint aLP into the core's escrow → `ALMVaultAsync.deposit` or `mint` claims aLP to the receiver (`ALMCore.claimDepositRequest`). `cancelDepositRequest` while pending. Asynchronous.
- **Async redeem.** `ALMVaultAsync.requestRedeem` (aLP owner → core escrow, `ALMCore.recordRedeemRequest`) → keeper plan clears and settles (escrowed aLP burned, asset moved from buffer to escrow) → `ALMVaultAsync.redeem` or `withdraw` claims the asset. `cancelRedeemRequest` while pending. Asynchronous.
- **Keeper plan.** `ALMCore.execute` → delegatecall `ALMKeeperExtension.execute`: price checks, fee collection on every range, each command in order (clears and cancels first; then position manager, gauge, pool or `RouterTrampoline` steps and `SETTLE_REQUESTS`), a check that every cleared epoch was settled, solvency check, shortfall check.
- **Emissions.** Every aLP mint, burn and transfer checkpoints the accumulator (`RewardCheckpoint._beforeTokenTransfer`). `ALMCore.claimEmissions(account)` (anyone) claims the core's emissions from the gauge when the chain mints, then pays the account's credited AERO to the account.

## 2. Detailed Breakdown by Component

### 2.1 Core: shares, ranges, buffer (`ALMCore`, `RangesLib`, `PoolTokensLib`, `ShareLib`, `ConfigLib`, `State`, `TokenDelta`, `PositionManagerLogic`)

**Purpose.** Holds one pool's ranges and buffer and issues aLP. All state lives in one ERC-7201 struct (`State`, slot `erc7201("arcadia.alm.core")`). Token ledgers: `buffer` (holders' idle tokens), `protocolFees`, `escrowed` (async requests and settled unclaimed redeems). Anything above those is untracked and `skim` books it to `protocolFees`, except for a pool token that is also the reward token: its excess over the ledgers and `lastRewardBalance` is credited as emissions at the next checkpoint. `checkSolvency` requires balances to cover the ledgers (plus `lastRewardBalance` for a reward pool token).

**Ranges.** `Range { tickLower, tickUpper, unstakedTokenId, stakedLiquidity, stakedTokenId, stakedBlock }`. The unstaked NFT exists from `OPEN_RANGE` to `CLOSE_RANGE` and may hold zero liquidity. The staked NFT exists only while staked; its liquidity is cached in `stakedLiquidity` (only the gauge can change a gauge-held position). Unstaked liquidity is always read live from the position manager. A closed range is swapped with the last range and popped.

**Mechanics.**
- `mint(shares, receiver)`: requires an unpaused core, spot within `maxSpotFromTwap` of the TWAP (`checkTwapDeviation`), the total cap and the receiver's per-user cap. Pays `ceil((buffer + netUncollectedFees) × shares / supply)` of each token plus, per range, the amounts for `ceil(rangeLiquidity × shares / supply)` at spot, rounded up. `rangeLiquidity` counts both sides; the new liquidity goes to the unstaked side. Unused token0 is refunded; `amount1Desired` is the exact rounded-up token1 amount, so token1 is expected to be used in full. No caller minimums: the caller's allowance caps the pull.
- `burn(shares, receiver, owner)` / `trustedBurn(..., caller)` (sync vaults only): per range removes `floor((unstaked + staked) × shares / supply)`, unstaked side first, the rest from the staked side (gauge withdraw, decrease, restake or burn the NFT if drained). Collects the unstaked sides' fees. Pays principal plus `floor((buffer + netFees) × shares / supply)`. No price check: an in-kind burn at a manipulated price pays at least its value at the true price. Spends allowance unless the caller is the owner or its operator.
- Swap fees: the unstaked sides earn the pool's fees net of the pool's `unstakedFee` share; staked sides earn emissions only. The protocol takes `protocolSwapFeeBps` of every collection.
- Caps: `totalCap` on supply; `perUserCap` on `balance + claimableShares + pendingShares`, skipped for the core and exempt accounts. `getPendingShares` estimates a deposit request's aLP at the last plan's exchange rate, valuing the assets at the higher of their values at spot and at the last plan price, rounded up (cap accounting only).

**Expected inputs.** `mint` callers bound their cost with their allowance; the price is bounded only by the TWAP band. `burn` needs no minimums.

**Edge cases and intentional behaviour.**
- `burn` and `trustedBurn` never check the core's pause flag: an in-kind exit is open in every state.
- `seed` mints `DEAD_SHARES = 1e6` to `address(1)`; the steward chooses the initial share count and value.
- Ether sent to the core (including the position manager's `refundETH`) is accepted by `receive()` and stays there. The core never sends native value out (6.1).

**Areas of concern.** Any state that a third party can change and the core reads (position manager liquidity and `tokensOwed`, pool fee growth, token balances); rounding of mint up versus burn down across ranges; `TokenDelta` packing (int128 per token).

### 2.2 Keeper plans (`ALMKeeperExtension`, `PlanCache`, `CommandLogic`, `CalldataLogic`, `Sentinels`, `EmissionsLogic.isPenaltyWindowOpen`)

**Purpose.** Lets an approved keeper (`ALMFactory.isKeeper[core][keeper]`) restructure the core. The keeper is trusted (Section 4.1); the bounds below are defense in depth against a faulty bot or a leaked key.

**Plan lifecycle.** `execute(commands, inputs, trustedSqrtPriceX96)`:
1. Checks the keeper, a non-zero trusted price, one input per command, `minPlanInterval` since `lastPlanAt`, pause (a paused core reverts `Paused` if any command is pausable), spot within `maxSpotFromTrusted` of the trusted price and the TWAP within `maxTwapFromTrusted` of it.
2. Collects the fees of every unstaked side with liquidity into the buffer; values holdings at the trusted price: `valueBefore = amount1 + convert(trusted, amount0)` over buffer plus every range's principal (both sides).
3. Runs each command in order. The clear and cancel steps (0x00 to 0x02) must come before every other step (`InvalidOrder`), and a buildup step (0x30 to 0x33) reverts `InvalidOrder` while a cleared epoch is unsettled, so a plan that clears requests settles them before its first buildup. Teardown, swap and `SETTLE_REQUESTS` steps may otherwise come in any order. Every token movement is mirrored in `PlanCache.amount0/1` (liquidity changes valued at the trusted price), and the swap's buffer delta is kept as `swapDelta`.
4. Requires every cleared epoch to be settled by a `SETTLE_REQUESTS` step (`InvalidOrder` otherwise), then `checkSolvency`.
5. `checkShortfall`: `valueAfter × supplyBefore / supplyAfter >= valueBefore × (10,000 − maxShortfallBps) / 10,000`, else revert.
6. Stores the exchange rate (supply per value at the trusted price, rounded up) for later request estimates.

**Commands** (one byte each, the high nibble the kind: requests, teardown, swaps, buildup; tight-packed payloads, lengths checked; any other byte reverts `UnknownCommand`):

| Op | Command | Notes |
|---|---|---|
| 0x00 | `CLEAR_REQUESTS` | Named controllers of one queue; records not pending are skipped. Deposit clears revert while paused. |
| 0x01 | `CLEAR_ALL_REQUESTS` | Whole pending epoch of one queue, no-op when empty; reverts `AlreadyCleared` if the plan already named controllers of that queue. Deposit clears revert while paused. |
| 0x02 | `CANCEL_REQUESTS` | Named pending requests, refunded to the controller (assets or aLP). |
| 0x03 | `SETTLE_REQUESTS` | Settles every epoch cleared so far at the plan state when it runs (2.3). Does nothing when nothing is cleared or it already ran. No buildup step can precede it in a plan that cleared a request (the buildup step reverts `InvalidOrder`), so it prices on the buffer and the ranges as the teardowns and the swap left them. Reverts `InsufficientBuffer` when the buffer does not hold a redeem payout. |
| 0x10 | `CLOSE_RANGE` | Range must have no staked side. Removes all unstaked liquidity, collects, burns the NFT. |
| 0x11 | `DECREASE_LIQUIDITY` | Unstaked side. |
| 0x12 | `COLLECT` | Any NFT the core owns. |
| 0x13 | `UNSTAKE` | Staked side decrease. Reverts `PenaltyWindowOpen` inside the window unless the payload sets `acceptPenalty`. |
| 0x14 | `EMERGENCY_UNSTAKE` | Whole staked side via `CLGauge.emergencyWithdraw` (only when Metadex enables it), no claim. |
| 0x20 | `SWAP_VIA_POOL` | Pausable. |
| 0x21 | `SWAP_VIA_ROUTER` | Pausable. Input sent to `RouterTrampoline`, which calls a keeper-chosen router and returns both token balances. |
| 0x30 | `OPEN_RANGE` | Pausable. Bounded by `rangeCap`. |
| 0x31 | `INCREASE_LIQUIDITY` | Pausable. Unstaked side. |
| 0x32 | `STAKE` | Pausable. Mints the staked NFT and deposits it; starts a penalty window. |
| 0x33 | `INCREASE_STAKED_LIQUIDITY` | Pausable. Unstake, increase, restake (restarts the window); same window rule as `UNSTAKE`. |

Every range command names the range index and the token id it expects (`RangeMismatch` otherwise), or `OPENED` for a range opened earlier in the same plan.

**Sentinels.** `OPEN_BALANCE | bps`: that share of the buffer above what cleared, not yet settled redeems are owed (`PlanCacheLib.getOwed`, the settlement payout at the current state; zero after `SETTLE_REQUESTS`). `TO_TARGET_RATIO | bps` (swap input only): values the open buffer (buffer less the owed payouts) at the trusted price, splits it at `bps` of token0 by value, and sells what the input side holds above its owed payout and its target. `RANGE_LIQUIDITY`: the whole liquidity of the side.

**Swaps.** At most one swap that moves the buffer per plan (`TooManySwaps`); a swap step that leaves both buffer amounts unchanged does not count. `balanceOut >= minAmountOut` (`InsufficientOutput`) and `balanceOut >= convert(planStartSpot, amountIn − amountReturned) × (10,000 − maxSwapCostBps) / 10,000`, rounded up (`MaxSwapCostExceeded`).

**Expected inputs.** The keeper computes the trusted price off-chain and supplies sensible amounts and step order; a plan that would breach a bound reverts.

**Edge cases.** The shortfall is measured at the trusted price, so at the true price a plan may lose about `maxShortfallBps` plus twice `maxSpotFromTrusted` (documented in `setPlanLimits`). The core holds its reentrancy lock for the whole plan, so the router cannot reenter state-changing core entry points; aLP `transfer`, `transferFrom` and `approve`, and `setOperator` through a vault, are not under the lock.

**Areas of concern.** Bugs an honest plan can hit, or a third party can trigger around one: keeper payload decoding (`CalldataLogic`), the `PlanCache` mirror versus real balances, `OPEN_BALANCE`/`TO_TARGET_RATIO` resolution, the order rules, swap-and-pop index handling.

### 2.3 Async queue and settlement (`ALMVaultAsync`, `ERC7540Deposit`, `ERC7540Redeem`, `ERC7540Operator`, `QueueLib`, `PlanCacheLib.getSettlementAmountsOut`, async parts of `ALMCore`)

**Purpose.** ERC-7540 requests for one pool token per vault. The vault forwards to the core, which owns all queue state: per vault a deposit and a redeem `Queue { pendingEpoch, lastClearedEpoch, epochs, records, claimable }`.

**Mechanics.**
- `requestDeposit(assets, controller, owner)`: owner must be the caller or its operator; assets go from owner to the core's escrow; any controller may be named. Blocked while the vault is paused. `requestRedeem(shares, controller, owner)`: the core moves the owner's aLP to its escrow, spending allowance unless the caller is the owner or its operator. Open while paused.
- A controller has one record per queue; a new request first credits a settled record into its claimable pile, then adds to the pending epoch.
- `cancelDepositRequest` / `cancelRedeemRequest` (controller or operator): only for a record in the pending epoch; refunds the whole record to any receiver (cap-checked for aLP to another receiver).
- Clearing: the plan's first named clear of a queue opens a fresh cleared epoch id and moves each named record into it; `CLEAR_ALL_REQUESTS` closes the pending epoch and opens the next. Cleared deposit assets move from escrow to the buffer.
- Settlement (`SETTLE_REQUESTS`, `getSettlementAmountsOut`), in token1 at the trusted price and the plan state when the step runs, every rounding against the flow:
  - `Wb`, value before the swap: the holdings less the swap's delta and less the cleared deposit tokens (subtracted in tokens, then valued). `W`, value after: `Wb` plus the swap's gain, floored at zero. Swap cost: `Wb − W` when positive.
  - Levy `L` (`getLevies`): when the swap cost something, the flows that needed it (deposits in its input token, redeems paid in its output token), net of offsetting flows and weighted by the holdings' composition after the payouts, pay `swapCost × min(netPart, swapped) / swapped`, rounded up, split pro rata and capped at each flow. Derivation: `docs/proofs/PlanCache/getLevies.derivation.md`.
  - Redeems: `min(Wb, W + L) × shares / supplyBefore` less their own levy (token0 payouts converted at the trusted price, rounded down): they carry a swap's cost but get none of its gain. Deposits: `(depositValue − own levy) × supplyBefore / (W + L)`, with `W` rounded up.
  - Redeem epochs settle first (escrowed aLP burned, assets moved from buffer to escrow, `InsufficientBuffer` otherwise), then deposit epochs mint aLP into escrow (`TotalCapExceeded` otherwise). Deposits against a zero value revert `ZeroValue`.
- Claims (`deposit`, `mint`, `redeem`, `withdraw` on the vault; controller or operator; any receiver): pro rata from the controller's claimable pile, the last claimer receiving the rounding remainder. `requestId` is always 0. `previewDeposit/Mint/Redeem/Withdraw` revert `PreviewNotSupported`.

**Expected inputs.** Users may name any controller; a controller that cannot receive the asset can still cancel to another receiver.

**Edge cases.** `pendingShares` reserves cap room from request to credit. Claims, cancels and redeem requests stay open while paused.

**Areas of concern.** Epoch id handling (named clears, clear-all, lazy credit), sum of claims versus escrow, levy maths, rounding at small epochs.

### 2.4 Emissions (`RewardsLib`, `EmissionsLogic`, `RewardCheckpoint`, `ALMAdminExtension.claimEmissions/payProtocolFees/getRewardOwed`)

**Purpose.** Credits the AERO the staked sides earn to aLP holders pro rata to balance and time held.

**Mechanics.**
- `total = claimedCumulative + netReceivedSinceLastCheckpoint + net(gauge.earned(core, stakedTokenIds))` (or `deferredEmissions` with no staked id), net of `protocolEmissionFeeBps`. Earned is counted on every LeafVoter chain status; `claimEmissions` only claims at the gauge when the chain is Active or Sunset (`setProtocolFees` claims on every status, see 6.3).
- `received = rewardBalance − poolTokenReserves (if the reward token is a pool token) − lastRewardBalance`.
- `credit = total − highWater` when positive; `rewardPerShare += credit × 1e18 / supply`; `highWater = total`. `rewardPerShare` is a `uint128` that wraps, read by each account as a difference against its checkpoint (6.3).
- Pre-credit: while `config.windowEnd != 0`, `getHiddenEmissions` rebuilds `CLGauge.earned` without the penalty for every staked side inside its window; a rise is credited ahead, a drop is folded into `highWater` (credit is never taken back). `windowEnd` is set at stake time when the penalty is on and cleared by the checkpoint after the last window closes.
- Each account's `rewardOwed += balance × (rewardPerShare − paid) / 1e18` at every transfer touching it. The core's own balance (escrowed aLP) accrues to `protocolFees`.
- `claimEmissions(account)` (anyone): claims gauge emissions for staked ids outside their window (plus deferred), checkpoints, pays `min(rewardOwed, lastRewardBalance)` to the account.

**Edge cases.** In-window token ids are skipped by the claim. A shortfall between credited and held reward is paid first come, first served.

**Areas of concern.** Accrual across penalty windows, restakes and closes; equality of `getHiddenEmissions` with the gauge's `earned`; reward token that is also a pool token; any path that makes the checkpoint revert (it runs inside every transfer).

### 2.5 Sync vault (`ALMVaultSync`, `ALMSyncExtension`, `Snapshot`, `SwapState`, `EquivalentPosition`, `DepositOptimizationMath`, `MintOptimizationMath`, `RedeemOptimizationMath`, `WithdrawOptimizationMath`, `QuadraticMath`, `CLMath`, vendored `MetadexSwapMath`, `MetadexTickBitmap`)

**Purpose.** ERC-4626 style single-asset entry and exit, one vault per pool token, sharing the core's aLP as its share (ERC-7575). Holds no balances between transactions; anything left is swept to the protocol by `sweep()` (anyone, non-reentrant: sends the vault's two token balances to the core and calls `skim`).

**Mechanics.**
- Deposit: computes the swap of part of the asset into the other token so that the pair matches the core's composition after the swap's price impact (`DepositOptimizationMath.computeSwap`, a tick walk plus a quadratic root per step). The split is solved net of the mint's rounding margins (the balance less `getRounding` at the step's price plus 3, against the position's tokenIn plus `2 × ranges + 4`). Then `shares = min over tokens of (balance − getRounding margin) × supply / costOfWholeSupply`. Swaps exact-output whenever the quote's end price differs from spot, asking the pool for at least 1 wei, so a quote that ends at a range edge without buying tokenOut still moves spot there. Then calls `ALMCore.mint` and refunds unused asset.
- Mint: inverse of the above for a share count. When the walk reaches the edge of the core's ranges it buys at least one wei. Pulls the quoted payment and refunds what is unused.
- Redeem: `trustedBurn`, then sells all of the other token for the asset (exact input, `InsufficientOutput` unless all of it sells). Withdraw: `previewWithdraw` sizes the burn so that the payout covers `assets`, then redeems those shares and reverts if the payout is below `assets`.
- Signatures: the plain ERC-4626 calls (`deposit(a,r)`, `mint(s,r)`, `redeem(s,r,o)`, `withdraw(a,r,o)`) cap the vault's swap at `getSwapCostLimit` (a band around same-transaction spot of half of `maxSwapCostBps − fee` in sqrt price) and revert `InsufficientOutput` unless the swap fills completely; they have no value-loss check. The slippage signatures (`minShares`, `maxAssets`, `minAssets`, `maxShares`) skip that band (entries swap up to the computed end price, exits without a price limit) and check the caller's bound instead.
- Exits require `quotable`: spot within `maxSpotFromTwap` of the TWAP, the core unlocked and its supply non-zero. Entries get the TWAP check inside `ALMCore.mint`.
- Previews and limits run in `ALMSyncExtension` (staticcall with the vault's parameters appended). `previewDeposit`/`previewRedeem` are lower bounds, `previewMint` an upper bound, `previewWithdraw` (on the vault) is what `withdraw` burns. `max*` return 0 when the vault is paused, the core is not quotable, or `pool.fee()` reverts (entries also while the core is paused); otherwise the largest flow whose plain call fills within the band, under the caps (under-reporting allowed). `maxRedeem` divides the band's fill by the whole supply's tokenIn plus 2 wei per range. `maxWithdraw` redeems those shares with `previewWithdraw`'s tokenIn margin unsold, less its tokenOut margin, its tick count to the band floored at zero. `totalAssets` is the lower of the core's holdings valued in the asset at spot and at the TWAP.

**ERC-4626 deviations (intended).** `deposit` refunds unused assets; `withdraw` sells all of the other token and so may pay more than `assets`; previews are bounds as stated, not exact.

**Expected inputs.** Callers who need protection against a price moved before their transaction use the slippage signatures with bounds from an independent price. `minShares = previewDeposit` read in the same block is not such a bound.

**Areas of concern.** Agreement between the vault's simulation (`SwapState`, `getStepFees`) and the pool's execution and the core's charge; rounding direction of each helper versus its caller; the `max*` contract.

### 2.6 Governance and maintenance (`ALMAdminExtension`, `BaseExtension`, `ALMCore._delegate`)

**Purpose.** Setters (factory only), `seed` (factory only, once), `setOperator` (the core's four vaults only, checked against the appended immutables), `skim`, `payProtocolFees`, `claimEmissions`, `getRewardOwed`. Runs by delegatecall; `onlyDelegated` blocks direct calls on the extension. `setProtocolFees` collects fees and claims emissions at the old rates first and reverts `RewardsPending` while a staked side is inside its window.

### 2.7 Factory (`ALMFactory`, `BaseFactory`)

**Purpose.** Deploys and governs cores. Holds the roles (Section 4) and the keeper registry.

**Mechanics.**
- All contracts are deployed by CREATE2 with the factory as deployer, salt from (pool, contract kind), and creation-code hashes pinned at factory construction (`CodeHashes`). No proxies, no upgrades.
- Creation is split across transactions to stay under the EIP-7825 gas cap: `createExtensions` (once per factory: sync, keeper and admin extensions), `createCore` (checks, then any subset of the four vaults), `resumeCore` (the rest; the core last, only after all four vaults).
- `createCore` requires: no core or pending creation for the pool; fee recipient not zero and not the core's address; `observationCardinalityNext >= 300`; `FactoryRegistry.gaugeToTarget(pool.gauge()) == pool`; the gauge's voter and gauge factory equal the factory's.
- `seedCore` (steward) pulls the seed from the steward and calls `ALMCore.seed`. A core is usable only after the admin configured `twapWindow`, `rangeCap`, `totalCap` and `perUserCap` (`checkConfigured` in `seed`).
- `pause(core)` pauses the core and its four vaults; only the steward can `unpause`.

### 2.8 Periphery (`ALMCoreView`, `ALMCoreViewLogic`, `ALMRegistry`)

**Purpose.** Read-only. `ALMCoreViewLogic` decodes core storage through `extsload` (vaults use it for snapshots); `ALMCoreView` is a lens for front ends (accepts only cores of its factory); `ALMRegistry` is an owner-managed list of registered factories and their lenses. Views that price (`getSnapshot`, previews, `totalAssets`, `getPosition`, `getRewardOwed`) revert while the core is locked; plain state reads do not.

### 2.9 Invariants

These hold between transactions (inside a keeper plan the ledgers move step by step). A reachable state that breaks one is a finding, rated by its impact.

- **Solvency.** For each pool token, `balanceOf(core) >= buffer + protocolFees + escrowed`, plus `lastRewardBalance` when that token is the reward token. For a reward token that is not a pool token, `balanceOf(core) >= lastRewardBalance`.
- **Escrow.** Per async vault, the core's `escrowed` amount of the vault's asset covers every pending deposit plus every settled, unclaimed redeem payout, and the core's own aLP balance covers every pending redeem plus every settled, unclaimed deposit.
- **Queue.** A controller has at most one record per queue, and it is either pending or settled. Epoch ids are never reused. A record is credited once.
- **In-kind fairness.** `ALMCore.mint` adds at least the minted shares' pro-rata part of every range's liquidity and of the buffer plus net uncollected fees; `ALMCore.burn` and `trustedBurn` release at most the burned shares' pro-rata part. Neither lowers what a remaining share is owed in kind.
- **Supply.** After `seed` the supply is never below `DEAD_SHARES`. No mint or settlement raises the supply above `totalCap`.
- **Ranges.** At most 14 ranges. A range has a staked token id exactly when `stakedLiquidity > 0`, that NFT is then deposited in the pool's gauge for the core, and `stakedLiquidity` equals its liquidity. The unstaked NFT of every open range is owned by the core.
- **Authorisation.** aLP leaves an account only by that account, its operator or a spender within its allowance. Pool tokens are pulled only from `msg.sender`, or from an owner by its operator (`requestDeposit`). Only the core's own vaults reach `trustedBurn`, `setOperator` and the request, cancel and claim entry points; only an approved keeper reaches `execute`; only the factory reaches the setters and `seed`.
- **Exits.** `ALMCore.burn`, the cancel of a pending request and the claim of a settled one never depend on a pause flag.
- **Plans.** A plan that succeeds made at most one swap that moved the buffer, settled every epoch it cleared, kept the swap within `maxSwapCostBps` of plan-start spot and kept the value per share at the trusted price within `maxShortfallBps`.
- **Rewards.** Credited reward is paid only to the account it was credited to, or to the fee recipient for the protocol's part, and never above `lastRewardBalance`. `highWater` never decreases. An account's `rewardOwed` falls only by a payout to that account.
- **Sync vault.** An entry spends at most the asset it pulled from the caller and at most the other token its own swap bought; an exit sells exactly the other token its own burn released. The vault keeps no claim on what it holds between transactions.

## 3. Deployment Environment

### 3.1 Supported Chains

Base, Optimism, Arbitrum, Robinhood Chain, Arc and Ethereum mainnet. One factory per chain, each against that chain's Metadex deployment with its own `LeafVoter`.

Chain properties that matter:
- **Block numbers.** Gauge penalty windows count blocks, so `minStakeBlocks` is a different time on each chain. On the Arbitrum-stack chains (Arbitrum, Robinhood Chain) the gauges count `ArbSys.arbBlockNumber()` (`ArbCLGauge`); the factory's `arbBlockNumber` flag must match the chain's gauge.
- **Oracle.** `block.timestamp` has one-second resolution, so a pool writes at most one oracle observation per second (one per 12 s block on Ethereum). On Base (200 ms blocks) and the Arbitrum-stack chains several blocks share a timestamp.
- **Mempool.** Ethereum has a public mempool; the keeper submits plans privately there. Front-running is not a valid finding (Section 6).
- **EVM.** Transient storage on every chain (the reentrancy lock and the checkpoint flag use it). The EIP-7825 transaction gas cap is assumed everywhere (core creation is split for it).
- **Arc: native USDC.** Arc's native gas asset is USDC (18 decimals), and the USDC ERC-20 (6 decimals) is a view of the same balance: a contract's native balance and its USDC `balanceOf` are one balance at different decimals, and moving either moves both. The core accepts native value (`ALMCore.receive`, the position manager's `refundETH`) and never sends it out, so on Arc such value only adds to the core's USDC balance, where it is an untracked balance like any other (6.1).

### 3.2 Pools and Tokens

**Liquid pairs only.** Cores are deployed only for a selected set of liquid pairs: deep two-sided liquidity around spot, steady trading, a registered Metadex gauge. Every assumption in this document (price bands, TWAP, swap cost, rounding sizes) is made for such a pair.

**Core versus vaults.** The core must work in every pool state: `ALMCore.mint` and `burn` (within their own checks: pause, caps, TWAP band), keeper plans, and async requests, cancels and claims. A revert or loss there is in scope unless listed in Section 6. The vaults' single-token conversions (sync `deposit`, `mint`, `redeem`, `withdraw`, their previews and `max*` views, `totalAssets`, `convertTo*`, and the single-token side of async settlement) only need to work in normal states of a liquid pair. In degenerate states they may revert, return zero, or give the caller a worse rate than in-kind (a loss to the caller), for example: spot at or near the pool's price bounds, a pool or core holding only one token or the vault's asset only as dust (spot outside every range), no active liquidity at spot. Such reverts and caller losses are accepted. Users can enter and exit in kind through `ALMCore.mint` and `burn` instead.

**Tokens.** Standard ERC-20 pool tokens and reward token only, chosen by the steward per pool (the pool must have a registered Metadex gauge). Decimals 6 to 18. Not supported: fee-on-transfer, rebasing, transfer hooks (ERC-777), non-standard return values. Blocklistable tokens (USDC) are expected as pool tokens; a blocklisted account can only lose its own access. The reward token is what the chain's Metadex emissions handler delivers on a claim: AERO on Base, where the handler redeems in the same transaction, and the chain's Metadex receipt token (redeemable for AERO on Base) on every other chain. It may also be one of the pool tokens.

### 3.3 External Integrations & Dependencies

Pinned in `package.json`: `metadex` at `8b506b4`, `metadex-slipstream` at `f99f209`.

- **Metadex `CLPool`**: spot, TWAP (`observe`), swaps, fee and reward growth, `fee()` / `unstakedFee()`. The swap fee is not a constant: the pool's swap hook (`DynamicSwapFeeHook`) sets it per block at the block's first swap, as a base fee plus a part that grows with the distance between the tick and its TWAP, up to a fee cap. It can charge the first swapping transaction of a block an initial fee outside that cap, grants per-caller discounts and adds an MEV tax. `fee()` returns what a swap by the caller would pay in the current state. Trusted to work as pinned.
- **Metadex `NonfungiblePositionManager`**: all position changes. Note: anyone may `increaseLiquidity` on a non-gauge-held NFT, while `decreaseLiquidity`, `collect` and `burn` require the owner or an approved address.
- **Metadex `CLGauge`**: `deposit`, `withdraw`, `emergencyWithdraw`, `claimEmissions`, `earned`, `deferredEmissions`, `rewardGrowthInside`.
- **Metadex `CLGaugeFactory`**: penalty and referral config. Its penalty admin may change `minStakeBlocks` (up to `maxMinStakeBlocks`) and the penalty rate at any time; we treat such changes as legitimate governance, not as attacks (Section 6). Live Base config on 2026-11-09: penalty rate 100 %, factory `minStakeBlocks` 75, `emergencyWithdrawEnabled` false.
- **Metadex `LeafVoter`**: chain status (Active, Paused, Suspended, Sunset) and the emissions projection used by `earned`.
- **Metadex `FactoryRegistry`**: gauge validation in `createCore`.
- **`RouterTrampoline`** (Arcadia `asset-managers`, out of scope): executes the keeper's router call and returns both token balances to the core. Trusted: the core credits the balances it returns.
- **`ArbSys` (0x64)**: block number on chains with `arbBlockNumber`.

Metadex contracts are not upgradeable proxies; their governance can change fees, swap hooks, penalty config, referral config, chain status and emergency withdraw. Findings that require Metadex to break or to act maliciously are out of scope; findings where an ordinary Metadex parameter change makes the ALM misbehave are in scope unless listed in Section 6.

## 4. Roles, Permissions & Trust Model

### 4.1 Privileged Roles

- **Factory owner** (`Ownable`): fully trusted. Sets admin, guardian and steward.
- **Admin**: fully trusted, a Safe multisig with a timelock. Every setter (Section 4.2) and `addKeeper`.
- **Steward**: fully trusted. Creates extensions and cores, seeds, unpauses, revokes the guardian; can also do everything the guardian can.
- **Guardian**: trusted to act fast, limited to de-risking: `pause`, `lowerTotalCap`, `lowerPerUserCap`, `removeKeeper`. Cannot unpause or raise anything.
- **Keeper**: trusted. Assumed to run plans on time, size the unstaked sides for exit flow, pick a correct trusted price, name only the core's own NFTs, and clear and cancel requests sensibly. Issues that need the keeper to act maliciously or submit a careless plan are out of scope; the bounds in 2.2 are defense in depth, not a trust boundary. Issues where a third party makes an honest plan lose value or revert are in scope unless listed in Section 6.
- **Sync and async vaults**: deployed by the factory; the core trusts only them for `trustedBurn`, `setOperator` and the request, cancel and claim entry points.
- **ALMRegistry owner**: trusted; curates factories for front ends only.
- **Upgrade authority**: none. Cores, vaults, extensions and the factory are immutable. A broken core can only be paused and exited in kind; its pool cannot get a second core from the same factory.

### 4.2 Configurable Parameters & Valid Ranges

| Parameter | Setter (role) | Valid range in code | Production | Controls |
|---|---|---|---|---|
| `rangeCap` | `setRangeCap` (admin) | 0 to 14 | 2 to 4 typically, up to 14 where gas per plan allows | Max open ranges |
| `totalCap` | `setTotalCap` (admin), `lowerTotalCap` (guardian/steward, strictly lower) | uint128 | Per core | Max aLP supply (mint, settlement) |
| `perUserCap` | `setPerUserCap` (admin), `lowerPerUserCap` (guardian/steward, strictly lower) | uint128 | Per core | Max balance + claimable + pending aLP per account |
| `isExempt` | `setCapExempt` (admin) | bool | Per account, as needed | Per-user cap exemption |
| `maxShortfallBps` | `setPlanLimits` (admin) | 0 to 10,000 | Per pool, higher for pools with higher expected fees | Max value-per-share loss per plan at the trusted price |
| `maxSwapCostBps` | `setPlanLimits` (admin) | 0 to 10,000; must exceed the pool's swap fee in bps (`pool.fee() / 100`, a per-block dynamic fee, see 3.3 and 6.4) or the plain sync flows and the keeper's pool swaps revert | Per pool, above its swap fee | Keeper swap cost; sync vault plain-flow band |
| `minPlanInterval` | `setPlanLimits` (admin) | uint32 seconds | Per pool | Min time between plans |
| `twapWindow` | `setDeviation` (admin) | 1 to 2^32−1 seconds; must stay below the pool's observation cardinality (one observation per second at most) | Per pool, below its observation history | TWAP reference |
| `maxSpotFromTwap` | `setDeviation` (admin) | uint64, 1e18-scaled ratio on sqrt price (1e15 = ±0.1 % sqrt price ≈ ±0.2 % price) | Per pair | Spot band for mints and sync exits |
| `maxSpotFromTrusted` | `setDeviation` (admin) | uint64, same scale | Per pair | Spot band around the keeper's price |
| `maxTwapFromTrusted` | `setDeviation` (admin) | uint64, same scale | Per pair | TWAP band around the keeper's price |
| `protocolSwapFeeBps` | `setProtocolFees` (admin) | 0 to 5,000 | 0 at launch | Protocol share of swap fees |
| `protocolEmissionFeeBps` | `setProtocolFees` (admin) | 0 to 5,000 | 0 at launch | Protocol share of emissions |
| `feeRecipient` | `createCore` (steward), `setProtocolFees` (admin) | not zero, not the core | Protocol treasury | Protocol fee payee |
| keepers | `addKeeper` (admin), `removeKeeper` (guardian/steward) | any keeper, on a core of this factory | Arcadia keeper bot | Who may call `execute` |
| seed | `seedCore` (steward) | both amounts > 0, shares > 1e6, within the caps | Small, with a non-dust value per share and a fine-grained share count | Initial supply and exchange rate |

Parameters are assumed to be set within these ranges and with the stated relationships (`twapWindow` below cardinality, `maxSwapCostBps × 100 > fee`, tight bands).

### 4.3 Off-Chain Components & Operational Assumptions

- **Keeper bot** (Arcadia). Runs plans at least every `minPlanInterval` when needed: rebalances, compounds, stakes, keeps each range's unstaked side large enough that ordinary burns do not reach the staked side, settles async queues (named clears when a controller would revert the plan), and cancels requests it cannot settle. Places `SETTLE_REQUESTS` right after the swap, with strategy removals and collects after it (a misplaced settle prices flows at another plan state; keeper trusted). The code itself refuses a buildup step before the settlement (2.2). Combines a `TO_TARGET_RATIO` swap with settlement only when the target leaves the redeems' payouts in the core. On Ethereum it submits plans privately. May go offline; users can always exit in kind with `ALMCore.burn`, and cancel pending requests.
- **Front end**. Computes slippage bounds for the sync vault's slippage signatures from an independent price.
- **Deployment checklist**. Raise the pool's observation cardinality well above `twapWindow` before go-live; create the extensions before any core; configure caps and bands before `seedCore`; seed at a non-dust value per share with a fine-grained share count; keep `maxSwapCostBps` below about 55 bps at tick spacing 1 (6.4).

## 5. Previous Audits

- Several audit rounds by the AI auditing model Claude Mythos (versions 5.1 and 5.2) on earlier commits of this repository.
- Several AI-assisted reviews during development.

Every issue these reviews found that the team acknowledged and did not fix is listed in Section 6.

## 6. Known Issues, Accepted Risks & Design Decisions

Each item names its trigger, impact and why it is accepted. Variants with the same root cause and impact are covered.

**Front-running and transaction ordering.** Front-running, back-running and sandwiching of any transaction (sync flows, async requests, mints, burns, keeper plans) is accepted as for any trade and is not a valid finding. Users bound their price with the slippage signatures; the keeper submits privately on Ethereum.

### 6.1 Core (mint, burn, share token, caps)

- **Burns reaching the staked side (unstaked-twin sizing).** Burns take each range's unstaked side first. A burn larger than a range's unstaked side withdraws the staked NFT from the gauge; inside its penalty window that forfeits the side's accrued emissions (100 % on Base) and the restake reopens the window. Repeated small burns, a twin drained faster than the staked side, the resulting first-come reward deficit, and the keeper's inability to unstake inside the window without `acceptPenalty` are all the same design point. Keeping the unstaked side sized for exits is the keeper's job; the contract does not enforce it.
- **Round trip earns staked emissions.** Mints add only to the unstaked sides and burns take them first, while aLP accrues the whole core's emissions. A mint, hold, burn earns staked-side emissions for the time held, until a plan stakes its part. Repeated around every plan it keeps diluting the holders' emissions, limited by the caps, and it earns less than a holder who stays. Accepted design.
- **Third-party liquidity on the core's unstaked NFTs.** Anyone may `increaseLiquidity` on an unstaked NFT; the liquidity is the holders' at once and is valued and collected like the rest. A mint just before captures part of it, funded by the donor only. Includes reviving a side the core left at zero liquidity.
- **Exits are never paused.** `burn` and `trustedBurn` ignore the core's pause flag; `pause` blocks `ALMCore.mint`, deposit clears and the pausable opcodes. The sync vault's exits use the vault's own pause flag.
- **Core worth zero.** If every holder exits and the dead-share residue values at 0 wei, a plan reverts (`setLastExchangeRate` divides by zero, settlement reverts `ZeroValue`), `mint` prices shares at zero, and the factory refuses a second core for the pool. Degenerate: the 1e6 `DEAD_SHARES` never exit, so a seed that prices them at 1 wei or more never reaches it.
- **Degenerate or coarse seed.** Above 2^96 aLP per wei of value (for example 1 wei of each token for 1e30 aLP), every async deposit request reverts on the per-user cap or the `uint96` pending-share cast in `QueueLib.record` (at one aLP per wei, only past requests of 7.9e28 wei). A share count near `DEAD_SHARES` floors deposits to few shares, leaves up to one aLP's tokenOut in the vault (swept, 2.5), and lets `deposit(maxDeposit)` revert `ZeroShares` (6.4). The steward is trusted to seed fine-grained shares at a non-dust value.
- **Seed rate at spot.** `seed` values the seed and sets the first exchange rate at spot, without a TWAP check, so a spot moved at seed time skews the pending aLP estimates of the first deposit requests: they reserve too much or too little cap room until the first plan resets the rate. No value moves. Only the steward seeds, and the caps are estimates.
- **Untracked balances.** Excess tokens (donations, swept vault leftovers, token1 a mint leaves unused) become protocol fees through `skim`, or emissions for a reward pool token (2.1). Ether sent to the core, including the position manager's `refundETH`, is accepted by `receive()` and stays on the core, with no way out: on Arc the native balance is the USDC balance, so the core never forwards it.
- **aLP sent to the core.** `transfer`, `transferFrom` and `mint(receiver = core)` to the core are accepted; nothing can move those shares again and their emissions go to the protocol. Sender's own loss.
- **Per-user cap is best effort.** A claim of settled aLP to the controller skips the per-user check, as the total cap binds at settlement and the counted sum is unchanged. A deposit's pending estimate (2.1) counts until `QueueLib.creditDeposit` swaps it for the settled shares, and a settled redeem's shares count as `pendingShares` until `QueueLib.creditRedeem` runs on the controller's next request or claim, so the cap is over- or under-restrictive. The `uint96` cast in `record` reverts only past 2^96 pending aLP on one record. Caps are estimates.
- **Filling another account's cap.** Anyone can name any controller in `requestDeposit`. A request's pending aLP is estimated at spot (no TWAP check) and the last plan rate, so a dust request made at a pushed spot can fill the controller's whole per-user cap; transfers, mints and deposits to that account then revert `PerUserCapExceeded` until it cancels (keeping the dust). Cost to the sender is the swap fees of the push, no profit, no funds at risk.
- **One operator registry.** `share.isOperator` is shared by the four vaults and the core: an operator approved on one vault can act on all of them and burn the controller's balance through `ALMCore.burn`. An operator could already move the whole balance through `recordRedeemRequest`.
- **Unlocked plain views mid plan.** `totalSupply`, `getPoolTokens`, `getRanges`, `claimableDepositRequest` and similar plain reads answer while the core is locked and may show cleared-but-unsettled state; only the keeper's router call can observe it. Pricing views revert while locked; integrators should check `isLocked`.
- **Token assumptions.** Only standard ERC-20s (Section 3.2). A pool token with transfer hooks that is also the reward token could reenter `transfer` during `mint` and mis-credit emissions.

### 6.2 Keeper plans and async settlement

- **Plan loss within bounds.** A plan may lose up to `maxShortfallBps` at the trusted price, which is up to `maxSpotFromTrusted` from spot, plus up to `maxSwapCostBps` on its one swap (inside the shortfall). Any loss within these bounds, including MEV around the keeper's swap, is accepted.
- **Settlement at the trusted price.** Async flows convert at the keeper's trusted price, up to `maxSpotFromTrusted` from spot and `maxTwapFromTrusted` from the TWAP, so a flow can settle up to that far off spot in either direction, and a user who predicts the keeper's price can time single-sided requests. By design; bands kept tight.
- **Requests near the total cap.** A mint landing just before a plan, or a standing refundable deposit request larger than the cap room, makes `_settleDeposits` revert `TotalCapExceeded` for any deposit clear of that queue, named or `CLEAR_ALL_REQUESTS`; so does a named controller topping up its pending request before the plan. The keeper answers with named clears or `CANCEL_REQUESTS` first. A controller that cannot receive the asset (blocklisted) cannot be keeper-cancelled, which forces named clears on that queue.
- **Stale plans.** A plan is built off chain against a state that can change before it executes: a request is cancelled, topped up or made again, spot moves, liquidity is added to an unstaked NFT. Such a plan can revert (`InsufficientBuffer`, `InvalidOrder`, `PriceDeviation`, the position manager's or the pool's own errors, including the pool's `AS` when a `TO_TARGET_RATIO` swap resolves to zero input). For example, a plan that pays a redeem from a pending deposit's tokens reverts `InsufficientBuffer` when that deposit is cancelled first. The keeper rebuilds the plan. A revert that a rebuilt plan avoids is not a finding; a state in which no honest plan can execute is.
- **Keeper step order (`SETTLE_REQUESTS` placement).** The code enforces two rules (2.2): clears and cancels first, and no buildup step while a cleared epoch is unsettled. Within them the keeper places `SETTLE_REQUESTS` right after the swap, with strategy removals and collects after it. Placed before the swap it settles without a levy and the swap's cost or gain goes to the remaining shares, and a teardown or collect between the swap and it enters the value redeems are priced at. If the callee of a `SWAP_VIA_ROUTER` step adds liquidity to one of the core's unstaked positions and a teardown removes it before `SETTLE_REQUESTS`, the settlement values the start holders at no less than their value without that liquidity and at no more than the tokens they then hold, so part of the added liquidity (the donor's own funds) can be credited to the plan's flows. Beyond the two rules, placement is keeper responsibility. Derivation: `docs/proofs/ALMKeeperExtension/swapSettlement.derivation.md`.
- **`TO_TARGET_RATIO` with settlement.** A `TO_TARGET_RATIO` swap in a settling plan reverts it (`InsufficientBuffer`) unless the target leaves the redeems' payouts in the output token in the core. The keeper combines them only then, and only its own plan's liveness is affected.
- **Deposit under one aLP.** A request worth less than one aLP settles at zero shares. Two floors apply: the epoch's shares are floored once, and each record's credit is floored against what is left of the epoch, the epoch's last credited record taking the remainder. A request loses less than two aLP's value, and the record credited last can receive up to one aLP above its part. The steward's `seed` sets one aLP's value.
- **Swap gains go to the remaining shares.** Redeems paid at `min(Wb, W + levies)` (2.3) bear their share of a swap cost but get no gain, which goes to the shares left after settlement, same-plan deposits included (at price 1, a redeem gets 500 instead of 505 and a deposit of 100 gets shares worth 100.82). The gain is bounded by `(1 + maxSpotFromTrusted)^2 × (1 − fee) − 1` of the sale on a pool fill, and not on-chain on a router fill (`maxSwapCostBps` bounds only the cost). Accepted: sharing gains with redeems would need a pre-swap reserve for the largest possible gain.
- **Own swap fees left out of settlement.** Fees the plan's own swap pays to the core's unstaked liquidity (a `SWAP_VIA_POOL`, or a router route through this pool) accrue after the opening collect, so settlement excludes them and the next plan collects them. Same-plan redeems miss their share of those fees and same-plan deposits gain it: as a fraction of a payout, at most the pool fee times the swap's input over the core's value, reached when the core is the pool's whole active liquidity on the swap's path. The swap cost that the levy charges to the flows that needed the swap (2.3) includes that fee in full, although the core's liquidity earns it back for the remaining shares. Zero when no part of the swap trades against a range of the core: a route outside this pool, or every range on the swap's path closed first. Accepted.
- **Keeper `COLLECT` on foreign NFTs.** `COLLECT` accepts any NFT the core owns, including one a third party transferred in; its tokens are booked as fees. Keeper trusted to name only the core's own ids.
- **Reward-token pool token and the router call.** When the reward token is a pool token and the plan's router swap sells it, an aLP transfer made from inside the router call reverts (checked underflow in `getRewardTotals`: the input has left the core while the buffer still counts it). Only that call fails.
- **`RouterTrampoline` allowances.** Anyone can make the trampoline approve any spender (router = token, calldata = `approve`). A spender on the keeper's route could take input the router leaves in the trampoline; the core's balance-based swap cost check bounds the loss. Dependency, out of scope.
- **TWAP window versus oracle history.** If `twapWindow` is at least the pool's populated observation count, the TWAP read reverts `OLD` (anyone can write one observation per second, keeping the history at the ring length). That reverts `ALMCore.mint`, keeper plans, sync entries and exits, the `max*` views, `totalAssets` and `convertToShares`/`convertToAssets`; previews still answer and `ALMCore.burn` still works. Anyone can raise the cardinality, which ends it for good. `createCore` checks only `observationCardinalityNext >= 300` and `setDeviation` only rejects a zero window. Deployment parameter (Section 4.3).

### 6.3 Emissions

- **Every transfer reads Metadex.** The checkpoint in every aLP transfer, mint and burn calls `CLGauge.earned` (which reads the LeafVoter and the gauge factory) and, while a penalty window is open, the pool, gauge factory and LeafVoter, all unwrapped. A revert there blocks transfers, mints and burns until fixed. Gas per transfer is accordingly high. No unprivileged trigger.
- **Penalty config changed after staking.** If the Metadex penalty admin turns the penalty on or raises `minStakeBlocks` while a side is staked past its old window and `config.windowEnd` is zero, the core does not pre-credit the new window; its emissions are credited when it closes, to that block's holders (a newcomer minting just before takes its pro-rata part). Redistribution of up to one window of a side's unclaimed emissions; no protocol loss. An in-kind mint held over the block in which the window closes pays no fee, so a newcomer with cap room can take most of that amount. A rate or referral-share raise mid-window lowers what the core will receive below what was pre-credited, repaid from later emissions. Governance-triggered; the guard would cost about 3.9k gas per transfer and 2k per claim.
- **Credited above held.** Credit can exceed the reward balance after penalty forfeits following pre-credit, an `EMERGENCY_UNSTAKE` abandoning credited emissions, a referral-share raise mid-window, or other governance moves. `payReward` pays `min(rewardOwed, lastRewardBalance)` and `payProtocolFees` caps the same way, first come, first served, until later emissions refill the gap (2.4). The protocol counts as a holder.
- **Reward per share wraps.** `rewardPerShare` is a `uint128` read as a difference against each account's checkpoint (modulo 2^128). One checkpoint step adding 2^128 or more per share reverts every transfer until the step fits, and steps summing past 2^128 between two checkpoints of one account lose multiples of 2^128 of its reward. Needs about 3.4e26 wei of emissions credited between two checkpoints at the 1e6 `DEAD_SHARES` floor, proportionally more at any larger supply.
- **Escrowed aLP earns for the protocol.** The core's own balance (pending redeems, settled unclaimed deposits) accrues to `protocolFees`, so escrowed aLP earns no emissions for its controllers. By design: controller credit is left out to keep the reward accounting simple.
- **Reward token from outside the gauge.** Reward token sent to the core by anyone (a donation, an airdrop, a claim made for the core) is credited at the next checkpoint to the holders of that block, like liquidity donated to an unstaked NFT (6.1). A mint just before it captures part of it, funded by the sender only.
- **`setProtocolFees` liveness.** Reverts `RewardsPending` while a staked side is inside its penalty window, and reverts `ChainNotActiveOrSunset` while the chain is Paused or Suspended with claimable emissions (`claimGaugeEmissions` claims without the `isMintable` check of `payReward`). On Base it also reverts `RouteSuspended` while the root `Voter` has the chain Suspended, or with a mismatched orchestrator adapter. Admin waits, no value moves.
- **Claims wait on the gauge's mint.** While the chain mints, `claimEmissions` claims at the gauge before it pays, and `setProtocolFees` claims too, so a revert on the gauge's mint path reverts both, even for reward the core already holds. `payProtocolFees` does not claim and keeps paying from the held balance. On Base, the Metadex root chain, a claim redeems through `Voter.processRedeem`, which reverts `RouteSuspended` while the root `Voter` has the chain Suspended; `payReward` gates its claim on the `LeafVoter` status alone, so a blocked `claimEmissions` needs the root Suspended with the leaf Active or Sunset, or a mismatched orchestrator adapter (`setProtocolFees` claims on every status, see the bullet above). Metadex suspends the leaf before the root and resumes the root before the leaf, so this needs Metadex governance to break that order. The same holds for any other revert of that path (the root ceiling, the Minter's cap or minimum mint). Claims wait until the mint works again. No funds are lost and exits stay open.

### 6.4 Sync vault

- **Plain flows: band at same-transaction spot.** The plain signatures take the swap-cost band around same-transaction spot as their swap's price limit and have no value-loss check. A searcher can move spot within `maxSpotFromTwap` first, so a plain flow can be sandwiched for up to that band plus `maxSwapCostBps`. A flow whose swap does not fill within the band reverts (`InsufficientOutput`, or the pool's `SPL` when `maxSwapCostBps × 100 <= fee`, or near the pool's price bounds). Callers who need a bound use the slippage signatures.
- **Rounding borne by the caller.** Pool rounding, the share floor and the entry's leftover tokenOut (`amountSwapOut − amountMintOut`, swept to the protocol) cost a few wei per call and a few hundred wei of the asset per withdraw at tick spacing 1, not growing with the amount, plus up to one aLP's tokenOut per deposit (the core's tokenOut over the supply, a few wei when one aLP is worth a few wei of each token). `getStepFees` is a few wei off the pool's fee credit, in the safe direction at every call site. An integer exact end price can stop the deposit swap one sqrt price unit short, leaving under 1 wei of tokenIn unsold unless the step's liquidity exceeds 7.9e28 at price 1.
- **Limit views that revert.** `deposit(maxDeposit)` can revert `ZeroShares` when the swap buys under one price step or stops at the band because one aLP's tokenOut exceeds the pool's sale within it, which needs a dust leg or a coarse seed (6.1) and a full deposit simulation in the view to cover. The exits' band is not clamped to the pool's price bounds, so within `maxSwapCostBps` of `MIN_SQRT_PRICE` or `MAX_SQRT_PRICE` plain exits revert `SPL` with non-zero `maxRedeem` and `maxWithdraw`, and a max view can return a reverting flow above the core's int128 token delta (1.7e38 wei in one flow) or the pool's per-tick liquidity limit (1.9e32 at tick spacing 1). No funds are lost and `ALMCore.burn` stays open.
- **Gas.** Plain exits cross at most `(maxSwapCostBps − fee / 100) / tickSpacing + 1` initialized ticks, and about 50 exceed the EIP-7825 cap of 16.8M gas, so the admin keeps `maxSwapCostBps` below 55 bps at tick spacing 1 (4.3). Bounded exits (`minAssets`, `maxShares`) sell up to the pool's price bound, so a large holder's full exit can exceed the cap and goes in parts, plain or in kind (`ALMCore.burn` stays under the cap). `previewRedeem` walks every empty bitmap word to the pool's price bound at zero active liquidity (about 6.9k cold words at tick spacing 1, over 14.5M gas, as a view).
- **Fee reads and swap hooks.** Every snapshot reads the fee as `pool.beforeSwapFee` with the vault as the swap's caller (the value `pool.fee()` returns to the vault), in the flows and, through `ALMSyncExtension`, in the previews and max views, so a per-caller discount is quoted as it is charged. Previews, `totalAssets` and the flows revert if that read reverts, and the plain exits also on their unwrapped `pool.fee()` read (max views first probe `pool.fee()` with `tryFee` and return 0). The entries price their swap at that fee: a hook whose fee depends on the swap's amount or direction, or that charges an after-swap fee, makes the swap cost more than the quote, and the entry reverts when the excess passes what the quote leaves unspent. The deployed `DynamicSwapFeeHook` answers `getBeforeSwapFee` from the same caller and block state as `beforeSwap` and charges no after-swap fee; another hook needs Metadex governance. The fee is dynamic (3.3): in a block where it reaches `maxSwapCostBps`, through volatility or because someone left the tick away from its TWAP at the end of the previous block, the plain sync flows revert, the `max*` views shrink to what the band allows and a keeper `SWAP_VIA_POOL` reverts `MaxSwapCostExceeded`; the slippage signatures, the in-kind flows and router swaps keep working.
- **Extreme prices and amounts.** `QuadraticMath.getRoot` with `a = 0` and `b` of 2 or 3 (units of 2^-192) returns 1.0 (`1 << 192`, the full step) instead of `c / b`. The deposit solve never produces that input, the withdraw solve at most for a dust position in a pool without liquidity. The token1 vault's `previewMint` and `mint` revert `DivFailed` below raw sqrt price 2^48 (a price of 1.3e-29 wei of token1 per wei of token0), while `maxMint` returns 0. From there up to a raw sqrt price of about 2^55 the mint's token0 margin (its token0 over the floored raw price) is a visible part of its token0 leg (6 % at 2^50, below 0.01 % from 2^55): the vault buys it, `previewMint` quotes it, and it stays in the vault for `sweep`. `DepositOptimizationMath.getNormalizedParameters` reverts `FullMulDivFailed` instead of `AmountInTooLarge` at a balance of 2^64 units of the step's liquidity (1.8e37 wei at liquidity 1e18 and price 1), reachable only by buying through all liquidity near spot into a step of almost none. Above a raw sqrt price of about 2^137 (a price above 1e24 wei of token1 per wei of token0) `previewWithdraw` can return `type(uint256).max` for a core that holds none of the vault's asset, while `maxWithdraw` is positive: the solve's root has 127 bits, less than the price needs there. `withdraw` then reverts, `redeem` and `ALMCore.burn` stay open. `maxDeposit` and `maxMint` do not cap at the pool's `maxLiquidityPerTick` or the core's `int128` holdings, so a deposit or mint of that amount reverts (`LO` or `Overflow`) above about 1e35 wei.
- **`previewWithdraw` near a double root.** Near the double root of the withdraw quadratic, the guard in `QuadraticMath.getRoot` (`floor(ac / b) >= floor(b / 4)`) returns the full step `1 << 192` although a real root exists. Only the quote's optimality suffers: every finite candidate is priced by `getSharesForAmounts`, so the withdraw still pays the amount. With idle tokenOut the double root needs the burnt fraction of the supply to reach 1 with the core as the step's whole liquidity, which the 1e6 `DEAD_SHARES` exclude. Without idle tokenOut it needs a core holding at most `n` wei of tokenOut over its whole range, `n` the range count.
- **Withdraw at a liquidity cliff.** Where the core is the pool's only liquidity in the sale's direction, a `withdraw` with a `maxShares` bound for an amount above `maxWithdraw` can revert `InsufficientOutput` with a few wei of tokenIn unsold: the quote's tokenIn margins are extra tokenIn the sale must sell, and past the last liquidity it cannot. No funds are lost, and `maxWithdraw` and smaller amounts succeed. It needs the amount within `previewWithdraw`'s tokenIn margin of the pool's whole capacity in that direction, with no other LP past the core's range.
- **`previewWithdraw` across a zero-liquidity gap.** Behind a gap with no liquidity between initialized ticks next to spot, `previewWithdraw` stops its walk at the gap while the pool sells through it, so it quotes the least of the burn alone and the step ends before the gap, or `type(uint256).max`. The quote overstates the shares the withdraw needs: the withdraw pays the amount or reverts (at a `type(uint256).max` quote, or `InsufficientOutput` when the extra tokenIn does not sell within the band), never less. It needs an interval on the sale's path that no liquidity provider covers.
- **Deployment order.** A sync vault deployed before the sync extension answers previews and limits with empty data until the extension exists. Steward deploys extensions first.

### 6.5 Factory and governance

- **No timelock or sanity caps in code.** `setPlanLimits` accepts up to 10,000 bps, `setDeviation` any `uint64` band and any non-zero window; admin plus keeper could drain a core in one plan. The admin is a Safe multisig with a timelock, and the guardian and steward de-risk without delay.
- **Pool not checked against the CL factory.** `createCore` ties the pool to its registered gauge, voter and gauge factory but does not check `CLFactory.getPool`. Steward-only.
- **No ALM-side escape from a broken gauge.** Burns into the staked side and `UNSTAKE` go through `CLGauge.withdraw`; `EMERGENCY_UNSTAKE` needs Metadex's `emergencyWithdrawEnabled`. If the gauge's withdraw path breaks, staked liquidity waits for Metadex.

### 6.6 Standards

The vaults follow ERC-4626, ERC-7540 and ERC-7575 as interface conventions. The deviations we know are stated in 2.3 and 2.5 and in the NatSpec. A deviation that is not listed there is a finding only through its impact (a loss of funds, or a flow that breaks in a normal state), rated under the usual severity rules. Non-compliance by itself is not a finding.

## 7. Build, Test & PoC Setup

Requirements: Node 22+, Foundry 1.8.1 or later. `src/` declares `pragma solidity ^0.8.34` (checked arithmetic outside explicit `unchecked` blocks); Metadex is `0.7.6` (wrapping arithmetic, as deployed). Every `unchecked` block states its bound in a comment, except the four vendored libraries under `src/shared/libraries/vendored/`, whose blocks are marked as vendored and keep the arithmetic of their source (Metadex under solc 0.7.6, Uniswap v4's tick bitmap). Bounds that are not a guard in the same statement are derived in `docs/proofs/ALMVaultSync/uncheckedMath.derivation.md`, from the pool's types and caps in `docs/proofs/PoolAxioms.md` (section 7). A reachable state that breaks a stated bound is a finding, rated by its impact.

Build

```bash
npm ci --ignore-scripts
forge build
```

Run the test suite (fork tests excluded by `foundry.toml`)

```bash
forge test
```

Fork tests against live Base Metadex (`test/fork/base/`). Set `RPC_URL_BASE` to a Base RPC URL in your shell or `.env`:

```bash
forge test --match-path 'test/fork/**' --no-match-path 'script/**'
```

Symbolic tests (optional, local): `FOUNDRY_TEST=test/symbolic forge test --symbolic --match-path 'test/symbolic/*' --symbolic-timeout 120`.

Where to put a PoC: `test/poc/` (plain `forge test` runs it; a fork PoC needs `RPC_URL_BASE` and runs with `forge test --match-path 'test/poc/**'`). Prefer the fork base, which deploys the factory, extensions and core through their test subclasses (`ALMFactoryExtension`, `ALMCoreExtension`, ...) with the real vaults, on the live WETH/USDC CL50 pool and its gauge:

```solidity
// test/fork/base/_Base.fork.t.sol sets up: factory (owner, steward), extensions, a core with its four vaults on
// the live pool, a keeper (test-only setIsKeeper), and wide plan limits and bands set by pranking the factory
// (tighten them to realistic values). Its seedCore calls ALMCore.seed directly.
import { Base_Fork_Test } from "../fork/base/_Base.fork.t.sol";
import { Plan } from "../utils/Plan.sol";

contract PoC is Base_Fork_Test {
    using Plan for Plan.Steps;

    function test_PoC() public {
        // seedCore(amount0, amount1): seed the core.
        // openRange(tickLower, tickUpper), runPlan(Plan.init()....): keeper plans (see test/utils/Plan.sol);
        // clears and cancels go first, and a plan that clears requests needs .settleRequests().
        // deposit(syncVault0, assets): sync deposit helper; asyncVault0/1 and syncVault0/1 are available.
        // deal(...) for balances.
    }
}
```

The unit fixture `ALMCore_Fuzz_Test` (`test/fuzz/ALMCore/_ALMCore.fuzz.t.sol`) and the vault bases (`test/fuzz/ALMVaultSync/_ALMVaultSync.fuzz.t.sol`, `test/fuzz/ALMVaultAsync/_ALMVaultAsync.fuzz.t.sol`) run on a local Metadex deployment (`test/utils/fixtures/metadex/`) and offer `setPoolState`, `setCoreState`, `setRangeState`, `runPlan` and `swapInPool`. Their state setters write core storage directly through the test extension `ALMCoreExtension`. For any PoC, on either base, state set through test-only helpers must be shown reachable through real calls.
