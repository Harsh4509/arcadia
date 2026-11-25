# Reward accounting follows the Metadex chain status

Code: `src/core/libraries/state/RewardsLib.sol` `payReward` (:45-75), `checkpoint` (:145-186), `accrueBalanceReward` (:217-244), `getRewardPerShare` (:263-313), `getRewardTotals` (:324-360); `src/core/ALMAdminExtension.sol` `getRewardOwed` (:324-341); `src/core/libraries/logic/EmissionsLogic.sol` `isMintable` (:43-47). Metadex at `node_modules/metadex` (V3) and `node_modules/metadex-slipstream`, the versions pinned in `package.json`.

## 1. What Metadex does per status

Status is one of `Active`, `Paused`, `Suspended`, `Sunset` (`ILeafVoter.ChainStatus`). It is set on each side by its own `CHAIN_STATUS_ROLE` transaction (`metadex/V3/src/voter/Voter.sol:534`, `metadex/V3/src/voter/LeafVoter.sol:409`).

Leaf accrual. The gauge's share of emissions grows with the leaf scalar `emissionsPerVP` (`metadex/V3/src/libraries/LeafAllocationLibrary.sol:1188-1216`, `ceiling += effectiveShare` at :1216). `applyChainStatus` settles at the old rate, stores the status and zeroes the scalar only for `Suspended` and `Sunset` (:475-486). Every later scalar write is masked to zero under those two statuses (:1058-1065), including in-flight root messages. So a `Paused` chain keeps crediting its gauges at the live rate, a `Suspended` or `Sunset` chain credits nothing.

Leaf payout. `mintEmissions` requires `Active` or `Sunset` (`LeafVoter.sol:85-89`, :179) and is bounded by the gauge's settled ceiling (`LeafAllocationLibrary.sol:414-415`). `CLGauge.earned` is a plain view over the pool growth plus the voter's projected share, plus the deferred emissions (`metadex-slipstream/contracts/gauge/CLGauge.sol:237-276`), with no status gate. A claim calls `mintEmissions` without a catch (:418), so it reverts while `Paused` or `Suspended`. An unstake catches the revert and defers the amount (:449-452), which `earned` keeps counting (:276).

Transitions. `Suspended` cannot go to `Paused` and `Sunset` only goes to `Suspended` (`LeafVoter.sol:416-421`, the same matrix on root `Voter.sol:541-549`).

## 2. Root funding of what the leaf credits

Root tracks a per-chain `ceiling` the redeems mint against. `_settleChain` walks the chain's accrual and books it to `ceiling` unless the status is `Suspended` or `Sunset`, where it goes to `cumulativeSuspendedSurplus` instead (`metadex/V3/src/libraries/AllocationLogicLibrary.sol:905-938`, the NatSpec at :900-901 names `Paused` as accruing normally). `setChainStatus` settles under the old status before writing the new one (`Voter.sol:551`), as the leaf settles at the old rate (`LeafAllocationLibrary.sol:477`). Both sides price segments the same way (`AllocationLogicLibrary.sol:941-942`).

`processRedeem` mints up to `ceiling - reportedSurplus - totalRedeemed`, pays any remainder from the donated buffer, and reverts `CeilingExceeded` otherwise so the transport redelivers (`Voter.sol:332-376`). A `Suspended` origin reverts `RouteSuspended` and is redelivered later (:340).

Sequences, each marked Funded when root's `ceiling` holds every amount the leaf credits to the gauge over it:
- `Paused -> Active`: the leaf credited at the live rate and root booked the same period into `ceiling`. Funded.
- `Paused -> Suspended -> Active`: the `Paused` accrual lands in `ceiling` at the suspend-time settle (`Voter.sol:551`) and in the gauge ceiling at the leaf's (`LeafAllocationLibrary.sol:477`). While `Suspended` neither side accrues. On resume the leaf scalar stays zero until the next root dispatch (`LeafAllocationLibrary.sol:481-483`) while root's `ceiling` resumes at once: root ahead of the leaf, never behind. Funded.
- `Paused -> Suspended -> Sunset`: as above, `Sunset` mints and redeems (`LeafVoter.sol:85-89`). `ceiling` is frozen but already holds the `Paused` accrual. Funded.
- `Active -> Sunset`: no accrual on either side after the flip. What was earned before stays claimable. Funded.

With root `Suspended` or `Sunset` while the leaf is `Active` or `Paused`, the leaf credits at the live rate while root books the same period to surplus (`AllocationLogicLibrary.sol:905-938`). The leaf-side claim still pays, bounded by the leaf ceiling (`LeafAllocationLibrary.sol:414-415`), so the ALM receives its reward token. The root redeem of those receipt tokens reverts `CeilingExceeded` (`Voter.sol:332-376`) until accrual covers it or draws the donated buffer. That state lies past the ALM's payout, so it does not change what the ALM counts.

So no status path leaves `earned` accrued while `Paused` unfunded at the leaf. Claims are all-or-nothing against the leaf ceiling (`LeafAllocationLibrary.sol:415`), so they cannot pay less. They can only wait while the chain is not `Active` or `Sunset`.

## 3. What the ALM counts

The ALM counts what the gauge reports regardless of the status and gates only the payout.

- `getRewardTotals` always reads `earned`, or `deferredEmissions` without staked ranges (RewardsLib.sol:346-349), and adds it net of the protocol share to the lifetime reward (:352-359).
- `getRewardPerShare` pre-credits the hidden emissions whenever a window may be open (:277-294), with no status input.
- `checkpoint` (:159, :173-174) and `getRewardOwed` (ALMAdminExtension.sol:330-332) read both.
- `payReward` claims from the gauge only when `EmissionsLogic.isMintable(leafVoter)` (RewardsLib.sol:57), `Active` or `Sunset` (EmissionsLogic.sol:46): the gauge claim is the only call that mints, and it is the one that reverts off `Active` and `Sunset`.
- `payProtocolFees` does not claim the gauge (RewardsLib.sol:89-115). `setProtocolFees` claims through `claimGaugeEmissions` only to reject a change with rewards pending (ALMAdminExtension.sol:247).

Per status:
- `Active`: `earned` grows and is claimable.
- `Paused`: `earned` grows (section 1) and is counted at every checkpoint, so credits follow the blocks held. A claim pays `min(rewardOwed, lastRewardBalance)` (RewardsLib.sol:67), and the rest stays owed until the chain mints again. Nothing in `payReward` is skipped beyond the gauge claim, so a holder leaving during the pause keeps its credit.
- `Suspended`: the scalar is zero and `earned` is flat, so counting it credits nothing new, and no jump follows `Suspended -> Active`.
- `Sunset`: counted and claimable.

No status needs excluding: section 2 found no unfunded leaf-side path, and under `Suspended` the counted amount does not move.

Evidence: test/fuzz/ALMCore/Mint.fuzz.t.sol:1410 `testFuzz_Success_mint_CountsTheGaugeEarnedOnAnyChainStatus`, test/fuzz/ALMCore/TrustedBurn.fuzz.t.sol:219 `testFuzz_Success_trustedBurn_CountsTheGaugeEarnedOnAnyChainStatus`, test/fuzz/ALMCore/RecordRedeemRequest.fuzz.t.sol:241 `testFuzz_Success_recordRedeemRequest_CountsTheGaugeOnAnyChainStatus`, test/fuzz/ALMCore/CancelRedeemRequest.fuzz.t.sol:268 `testFuzz_Success_cancelRedeemRequest_CountsTheGaugeOnAnyChainStatus`. The invariants test/invariant/ALMCore.invariant.t.sol:940 `invariant_preCreditEqualsTheHiddenEmissionsAtTheLastCheckpoint` and :968 `invariant_rewardDeficitIsBoundedByForfeitsAndGovernanceMoves` run on every status (the handler sets it at test/invariant/handlers/GaugeHandler.sol:170). The claim-all check of `afterInvariant` (:1325) is gated on a mintable chain (:1380), as it needs the gauge to pay.

## 4. The reward per share wraps

`rewardPerShare`, `rewardPerSharePaid` and `protocolRewardPerSharePaid` are uint128 values modulo 2^128. `getRewardPerShare` adds each step in unchecked uint128 arithmetic (RewardsLib.sol:309-311). `accrueBalanceReward` (:231-233) and `getRewardOwed` (ALMAdminExtension.sol:337-340) subtract a checkpoint from the accumulator in unchecked uint128 arithmetic. No code orders, sums or bounds the absolute value: the only other uses are the two equality tests (`checkpoint` :179, `accrueBalanceReward` :226), the raw state views and the `RewardPerShareUpdated` event (:183).

Notation: step i credits `c_i` over supply `s_i`, `d_i = floor(c_i 1e18 / s_i)` (:310). Between two interactions of one account, `D = sum d_i`, `C = sum c_i`, `s_min = min s_i`.

- Exactness. The account reads `(accumulator - paid) mod 2^128 = D mod 2^128`, which is `D` exactly when `D < 2^128`.
- Bound. `D <= C 1e18 / s_min`, so `D < 2^128` when `C 1e18 < 2^128 s_min`, that is `s_min > C / 3.4028e20`.
- Inputs. `s_min >= DEAD_SHARES = 1e6` (ALMAdminExtension.sol:36, minted to `address(1)` at the seed, :414). A step with zero supply credits nothing (RewardsLib.sol:307). `C` is the rise of `highWater + preCredited` over the span: every checkpoint raises that sum by exactly its credit, and a drop of the hidden emissions keeps it (:289-293). The high water rises to `total` (reward token the core received plus what the gauge reports earned, net of the protocol share, :297-303) or by a dropped pre-credit, the pre-credit to the hidden emissions. So `C` is at most the reward that reached the core or was reported earned over the span plus the hidden emissions pre-credited and then forfeited. Bounding `C` by a token supply `T` assumes no reward token unit reaches the core twice in the span (paid out and transferred back, `received` counts any transfer, :331-339) and that `T` counts the forfeited emissions. The code enforces neither, so `C <= T` is an assumption on the token flows.
- Result. At the floor `s_min = 1e6` the bound holds for `C < 2^128 / 1e12 = 3.4028e26` wei (3.4028e8 tokens of 18 decimals). For `C <= 1e28` wei it holds for every supply above `2.94e7` shares.
- Each step. `d_i <= D < 2^128`, so `SafeCastLib.toUint128(d_i)` (:310) does not revert. A single step of 2^128 or more reverts the checkpoint.
- Equality tests. A step with `0 < d_i < 2^128` changes the accumulator, and `accumulator == paid` holds exactly when `D mod 2^128 = 0`, which under the bound is `D = 0`.
