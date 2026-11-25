# QueueLib: the sums behind the unchecked subtractions

Code: `src/core/libraries/state/QueueLib.sol` `requestDeposit` (:46-79), `requestRedeem` (:88-101), `cancelDeposit` (:115-135), `cancelRedeem` (:144-159), `clearDeposit` (:181-200), `clearRedeem` (:207-217), `clearAllDeposits` (:227-241), `clearAllRedeems` (:247-252), `creditDeposit` (:295-311), `creditRedeem` (:319-331), `claimDeposit` (:346-365), `record` (:408-425), `cancel` (:433-443), `creditSettled` (:453-473), `settleEpoch` (:484-486), `takeClaimable` (:499-520), `nextEpoch` (:571-573). Callers: `src/core/ALMCore.sol` :367-383, :392-410, :419-437, :446-464, :474-488, :498-512, `src/core/ALMKeeperExtension.sol` `_clearRequests` (:628-668), `_clearAllRequests` (:676-702), `_settleEpochs` (:709-724), `_settleRedeems` (:735-757), `_settleDeposits` (:766-782), `_cancelRequests` (:789-826).

Notation: `v` an asynchronous vault (`ASYNC_VAULT0` or `ASYNC_VAULT1`, the only callers `_requireAsyncVault` admits, `AsyncVaultGuard.sol:53-54`, and the only vaults the keeper names, `ALMKeeperExtension.sol:635`, :682, :792). `dep_v`, `red_v` its deposit and redeem queue (`State.sol:129-132`). `P`, `C` a queue's `pendingEpoch` and `lastClearedEpoch`. `rec(c)` a controller's record in a queue, `pile(c)` its claimable pile. A record is in epoch `e` when `rec.epoch = e`. A record with `amountIn = 0` adds nothing to any sum below.

## 1. Statement

At the end of every call:

- I1. `shareAccounts[c].pendingShares = Σ_v (dep_v.rec(c).pendingShares + red_v.rec(c).amountIn)`.
- I2. For every queue and epoch id `e`, `epochs[e].amountIn = Σ_c rec(c).amountIn` over the records in `e`.
- I3. `shareAccounts[c].claimableShares = Σ_v dep_v.pile(c).amountOut`.
- I4. `balanceOf(core) >= Σ_v (Σ_c dep_v.pile(c).amountOut + Σ_e dep_v.epochs[e].amountOut + red_v.epochs[P].amountIn)`, and the supply is at most `2^128 − 1`.

I2 holds at every point of a plan too, not only at its end.

Consequences, the unchecked operations:

| Site | Operation | From |
|---|---|---|
| `QueueLib.sol:132`, :157, :308, :328 | `pendingShares −=` one record's `pendingShares` or `amountIn` | I1: the subtrahend is one term of the sum |
| `QueueLib.sol:191`, :214, :440 | pending epoch `amountIn −= rec.amountIn` | I2: the record is pending, checked at every caller |
| `QueueLib.sol:192`, :215 | cleared epoch `amountIn += rec.amountIn` | section 3.4: the pending and the cleared epoch sum to at most `2^128 − 1` over a plan |
| `QueueLib.sol:467` | epoch `amountIn −= rec.amountIn` | I2 for the record's epoch |
| `QueueLib.sol:468` | epoch `amountOut −= amountOut` | I2: `rec.amountIn <= epoch.amountIn`, so `floor(rec.amountIn · amountOut / amountIn) <= amountOut` |
| `QueueLib.sol:309` | `claimableShares += shares` | I3, I4: the sum after is at most `balanceOf(core)`, below `2^128` |
| `QueueLib.sol:363` | `claimableShares −= shares` | I3: `shares <= pile.amountOut` of this vault (`QueueLib.sol:510-512`), one term of the sum |

## 2. What the proof rests on

- N1. Every entry point that writes a queue is `nonReentrant` on the core's one lock: `recordDepositRequest`, `recordRedeemRequest`, `cancelDepositRequest`, `cancelRedeemRequest`, `claimDepositRequest`, `claimRedeemRequest` (`ALMCore.sol:367`, :394, :421, :448, :476, :500) and `execute` (`ALMKeeperExtension.sol:74`, delegated, so the lock is the core's, `ReentrancyLock.sol:39-44`). So no request, cancel or claim runs inside a plan.
- N2. `QueueLib` is the only writer of `shareAccounts`, `records`, `epochs`, `claimable`, `pendingEpoch` and `lastClearedEpoch`: the other uses in `src` are reads (`ShareLib.sol:55`, `ALMCoreViewLogic.sol`).
- N3. Epoch ids are issued once. `nextEpoch` is `max(P, C) + 1` in checked `uint32` (`QueueLib.sol:572`). `startClearedEpoch` sets `C` to it (:170), `clearAllDeposits` and `clearAllRedeems` set `C = P` and `P` to it (:238-240, :249-251). So `max(P, C)` rises at every issue and an issued id was never `P` or `C` before. Only `record` writes `rec.epoch = P` (:421) and only the clears write `rec.epoch = C` (:188, :211), so an id not yet issued holds no record, and its `Epoch` is zero: `epochs[e]` is written only at `e = P` (:424, :191, :214, :440), at `e = C` (:192, :215, `settleEpoch` from `ALMKeeperExtension.sol:779` and `QueueLib.sol:282`), and at a record's own epoch (:467-468).
- N4. A plan settles every epoch it cleared before it ends and before any range grows: `execute` reverts while `hasUnsettledEpochs` (`ALMKeeperExtension.sol:133`, :212, `PlanCache.sol:203-205`). `_settleEpochs` zeroes the plan's cleared amounts (`ALMKeeperExtension.sol:723`), and a clear or cancel after another command reverts `InvalidOrder` (:125-127). [ALMKeeperExtension/swapSettlement.derivation.md](../ALMKeeperExtension/swapSettlement.derivation.md) derives that each cleared epoch settles once.
- N5. The supply is at most the `uint128` `totalCap`: every mint is behind `checkTotalCap` (`ALMCore.sol:144` for :189, `ALMAdminExtension.sol:392` for :415 and :420, `ALMKeeperExtension.sol:771` for :774, `ShareLib.sol:36-39`, `State.sol:39`).

## 3. Proof

Each invariant holds in the empty state. Below, every writer keeps it.

### 3.1 I1

Writers of `pendingShares` (N2): `QueueLib.sol:77`, :100, :132, :157, :308, :328. Writers of `rec.pendingShares` and `rec.amountIn`: `record` (:422-423), `cancel` (:442), `creditSettled` (:472).

- `requestDeposit`. `creditDeposit` runs first (:58, below). `record` adds `assets` and `pendingShares` to the record (:422-423, checked, `toUint96` bounds the shares) and `pendingShares` rises by the same `pendingShares` in a checked sum (:77).
- `requestRedeem`. `creditRedeem` first (:90). `record` adds `shares` to `rec.amountIn` behind `toUint128` (:422), so `shares < 2^128` and `uint128(shares)` (:100) is exact. Both sides rise by `shares`.
- `cancelDeposit`. `cancel` returns `rec.pendingShares` and zeroes the record (:435, :442). `pendingShares` falls by the returned value (:132).
- `cancelRedeem`. `shares = rec.amountIn` is read before `cancel` zeroes the record (:148, :151), and `pendingShares` falls by it (:157).
- `creditDeposit`. `creditSettled` returns `rec.pendingShares` and zeroes the record (:459, :472). `pendingShares` falls by it (:308).
- `creditRedeem`. `pendingShares` falls by `rec.amountIn` (:328), then `creditSettled` zeroes the record (:330, :472).
- `clearDeposit`, `clearRedeem` write `rec.epoch` only (:188, :211).

Each subtraction removes exactly the term the record held, so I1 is kept and no subtraction wraps.

### 3.2 I2

- `record` (:421-424). The record is zero or in `P`: `requestDeposit` and `requestRedeem` call `creditDeposit` or `creditRedeem` first (:58, :90), which empties a record with `amountIn != 0` in an epoch other than `P` (`isSettled`, :298, :322, :553). The record and `epochs[P]` rise by `amountIn`, both checked (:422, :424), and `rec.epoch = P`.
- `cancel` (:440-442). Every caller checks the record pending first: `requirePending` (`ALMCore.sol:430`, :457) and `isPending` (`ALMKeeperExtension.sol:806`), and passes `epochs[P]` (`QueueLib.sol:126`, :151). `epochs[P].amountIn` falls by the record's amount, at most the sum, and the record is zeroed.
- `clearDeposit`, `clearRedeem` (:186-193, :209-216). The caller checks the record pending (`ALMKeeperExtension.sol:649`). The record moves from `P` to `C`, `epochs[P].amountIn` falls by its amount and `epochs[C].amountIn` rises by it. With `C != P` both sums stay exact. `C != P` here: the plan cleared nothing of the queue yet and `startClearedEpoch` issued a fresh `C` (`ALMKeeperExtension.sol:652`), or it cleared before, by name (`C` fresh) or in full (`C` the old `P`, and `P` fresh).
- `clearAllDeposits`, `clearAllRedeems` change ids only: the records keep their epoch.
- `creditSettled` (:458-472). The record is in `rec.epoch` with `amountIn != 0`, and the caller passes `epochs[rec.epoch]` (:302, :330). The epoch falls by the record's amount and the record is zeroed.
- `settleEpoch` writes `amountOut` only (:485).

### 3.3 I3 and I4

I3. Writers of `claimableShares`: `QueueLib.sol:309`, :363. Writers of a deposit pile's `amountOut`: `creditSettled` through `creditDeposit` (:470-471), `takeClaimable` through `claimDeposit` (:517-518). `creditDeposit` adds the `amountOut` that `creditSettled` added to the pile (:301-302, :309). `claimDeposit` subtracts the `shares` that `takeClaimable` took off the pile (:357, :363). `uint128(amountOut)` (:468, :471) is exact: `amountOut <= epoch.amountOut`.

I4. Let `X` be the right side.

- `_settleDeposits` mints `shares` to the core, then stores them as the cleared epoch's `amountOut` (`ALMKeeperExtension.sol:774`, :779). The epoch's `amountOut` was zero: its id is fresh or the former `P` (N3), and an epoch settles once (N4). Both sides rise by `shares`.
- `creditSettled` on a deposit record moves `amountOut` from the epoch to the pile (:468, :470-471): `X` is unchanged.
- `claimDepositRequest` takes `shares` off the pile and transfers them out of escrow (`ALMCore.sol:484`, :487): both sides fall by `shares`.
- `recordRedeemRequest` moves `shares` into the core, then `record` adds them to `red_v.epochs[P]` (`ALMCore.sol:403`, :406, `QueueLib.sol:424`): both sides rise by `shares`.
- A redeem cancel returns the record's shares and takes them off `red_v.epochs[P]` (`ALMCore.sol:460`, :463, `ALMKeeperExtension.sol:818`, :821, `QueueLib.sol:440`): both sides fall by them.
- A plan that clears redeems takes their amounts off `red_v.epochs[P]` (`QueueLib.sol:214`, or the id change of :249-251) and burns the same sum before it ends (N4, `cache.redeemShares`, `ALMKeeperExtension.sol:659`, :667, :701, :747): at the plan's end both sides fell by it.
- The core's balance falls nowhere else: `_transfer(address(this), …)` and `_burn(address(this), …)` appear at `ALMCore.sol:529`, `ALMKeeperExtension.sol:747` and :818 only.

`creditDeposit` runs only from `requestDeposit` and `claimDeposit` (`QueueLib.sol:58`, :354), outside a plan (N1), where I4 holds as the previous call left it. So `claimableShares[c] <= X <= balanceOf(core) <= supply < 2^128` (N5) after the sum at :309.

### 3.4 The cleared epoch's sum

Claim: over a plan, `epochs[P].amountIn + epochs[C].amountIn` of a queue it clears by name does not rise, so `epochs[C].amountIn += assets` (`QueueLib.sol:192`, :215) stays below `2^128`.

Cleared by name first: `C` is fresh with `amountIn = 0` (N3), and `epochs[P].amountIn <= 2^128 − 1` (a `uint128`, the sum of its records by I2). Each clear moves one record's amount from `P` to `C`. `P` gains nothing during the plan (N1). Cleared in full first: `C` is the old `P` with its `uint128` amount and the new `P` is fresh and stays empty (N1, N3), so no record is pending and the named clear skips every entry (`ALMKeeperExtension.sol:649`). `_clearRequests`' own counter `cleared` (`ALMKeeperExtension.sol:658-660`) is bounded the same way ([ALMVaultSync/uncheckedMath.derivation.md](../ALMVaultSync/uncheckedMath.derivation.md) section 3.6).

## 4. Constants

None.
