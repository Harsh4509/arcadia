# RewardsLib.checkpoint: the three uint128 sums

Code: `src/core/libraries/state/RewardsLib.sol` `checkpoint` (:145-186), its unchecked block :164-168, `getRewardTotals` (:324-360), `getRewardPerShare` (:263-313), `accrueBalanceReward` (:217-244), `pay` (:124-130), `src/core/abstracts/mixins/RewardCheckpoint.sol` `_beforeTokenTransfer` (:36-42).

Notation: `rec` the `received` of one checkpoint, `fee = floor(rec · bps / 10_000)` its protocol share (:343), `lrb`, `pf`, `cc`, `hw`, `pc` the stored `lastRewardBalance`, `protocolFees`, `claimedCumulative`, `highWater`, `preCredited` (`State.sol:66-71`), each a `uint128`. A primed value is the value after the checkpoint, taken as an integer without the wrap.

## 1. Statement

In a checkpoint that does not revert:

1. `cc' = cc + rec − fee < 2^128`: the sum at :167 does not wrap. Derived from src alone.
2. `lrb' = lrb + rec` is the core's reward token balance less the pool token reserve (:331-339). The sum at :165 does not wrap iff that balance is below `2^128`. No line of src bounds it: it holds for a reward token whose total supply is below `2^128`.
3. `pf' = pf + fee <= 2 hw' + pc`. The sum at :166 does not wrap when `2 hw' + pc < 2^128`. No line of src bounds it: it holds while the lifetime credit stays below `2^126`.

`rec − fee` (:167) does not underflow: `bps <= 5000` (H2, `ConfigLib.sol:24`, `ALMAdminExtension.sol:235`).

## 2. Proof

### 2.1 `claimedCumulative`

`getRewardTotals` returns `total = cc + (rec − fee) + earned` in checked arithmetic, `earned >= 0` the gauge's part net of the fee (:352-359), read before the sums of :165-167 (:159). `getRewardPerShare` returns a high water of at least `total` (:297-303: it is raised to `total` when below it). `checkpoint` stores a changed high water through `SafeCastLib.toUint128` (:185), and an unchanged one is the stored `uint128`. So a checkpoint that does not revert has `cc + rec − fee <= total <= hw' <= 2^128 − 1`. A wrap at :167 would need `cc + rec − fee >= 2^128`, which reverts at :185 and is rolled back.

### 2.2 `lastRewardBalance`

`rec = balance − reserve − lrb` in checked arithmetic (:331-339), so `lrb + rec = balance − reserve`. `toUint128(rec)` (:165) bounds `rec` alone. `pay` lowers `lrb` by what it transfers (:126-129), which keeps `lrb = balance − reserve` at the last checkpoint less the payouts since. So the sum wraps iff `balance − reserve >= 2^128`.

State where it wraps, a reward token with a supply of `2^128` or more: `bps = 5000`, an aLP supply of `1e18`, no staked range, no payout. Checkpoint 1 with `rec = 2^128 − 1`: `fee = 2^127 − 1`, `cc' = 2^127`, `lrb' = 2^128 − 1`, `hw' = 2^127`. One more wei reaches the core. Checkpoint 2: `rec = 1`, `fee = 0`, `cc' = 2^127 + 1`, `hw' = 2^127 + 1`, no revert, and `lrb' = 2^128` is stored as 0. Every later checkpoint computes `rec = 2^128` and reverts at `toUint128` (:165), and every share transfer, mint and burn checkpoints first (`RewardCheckpoint.sol:37`).

### 2.3 `protocolFees`

`pf` has three writers: the fee of a checkpoint (:166), the reward on the core's own balance (:237, a checked sum behind `toUint128`), and the payout (:110, a subtraction). So `pf <= F + A`, `F` the sum of the fees so far and `A` the sum of the rewards credited to the core.

- `F <= cc`. Each checkpoint adds `fee` to `F` and `rec − fee` to `cc`, and `fee <= rec − fee` as `bps <= 5000`.
- `A <= hw + pc`. Every checkpoint raises `hw + pc` by exactly its credit: a rise of the hidden emissions credits `hidden − pc` and sets `pc = hidden` (:291-293), a drop moves `pc − hidden` from `pc` to `hw` with no credit (:290, :293), and a lifetime reward above the high water credits the excess and raises `hw` by it (:297-303). A credit `c` at supply `S` raises the reward per share by `floor(c · 1e18 / S)` (:310). The core's balance `b` is constant between two of its accruals, as every transfer, mint and burn accrues both sides before the balance moves (`RewardCheckpoint.sol:36-42`), and `b <= S` at each checkpoint between them. So an accrual credits the core `floor(b · Δ / 1e18) <= Σ c` over those checkpoints (:232), given the accumulator's difference is exact ([chainStatus.derivation.md](chainStatus.derivation.md) section 4).

With 2.1, `pf + fee <= F' + A <= cc' + hw + pc <= 2 hw' + pc`.

`hw'` and `pc` are each stored through `toUint128` (:177, :185), so src bounds `pf + fee` by `3 (2^128 − 1)` only. Stored values at which :166 wraps: `pf = 2^128 − 1`, `bps = 5000`, `rec = 2`: `fee = 1` and `pf'` is stored as 0. By the bound above that state needs `2 hw + pc >= 2^128 − 1`.

## 3. Constants

None. The two bounds of statements 2 and 3 are on the reward token, as the bound `accrued < 2^236` of [EmissionsLogic/getHiddenEmissions.derivation.md](../EmissionsLogic/getHiddenEmissions.derivation.md) is.
