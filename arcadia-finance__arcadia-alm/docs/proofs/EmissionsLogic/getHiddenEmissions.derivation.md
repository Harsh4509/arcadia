# EmissionsLogic.getHiddenEmissions: the bound on `accrued`

Code: `src/core/libraries/logic/EmissionsLogic.sol` `getHiddenEmissions` (:102-159), its unchecked blocks :146-150 and :154-157. Gauge: `node_modules/metadex-slipstream/contracts/gauge/CLGauge.sol` `earned` (:237-277), `_earned` (:515-523), `Gauge.sol` `_applyPenalty` (:157-166), `_applyReferral` (:176-180), `CLGaugeFactory.sol` :265, :329, :421. Pool: `node_modules/metadex-slipstream/contracts/core/CLPool.sol:780`.

Notation: `g` the growth of the reward per unit of staked liquidity inside the range since the staked side's snapshot, times `2^128`, modulo `2^256` (:147-148). `l = range.stakedLiquidity`, a `uint128` (`Range.sol:10-17`). `a = accrued = floor(g l / 2^128)` (:149). `r = penaltyRate`, `h = share`, `M = MAX_PIPS = 1e6`.

## 1. Statement

1. src bounds `a` by `a < 2^256` only: `fullMulDiv` reverts on a larger quotient (:149), and `g < 2^256`, `l < 2^128` give no smaller bound.
2. The block :154-157 is exact iff `a · max(r, h) < 2^256`. With `r, h <= M < 2^20` (the gauge factory's `'MR'`, `CLGaugeFactory.sol:329`, and `maxShareCap <= MAX_PIPS`, :265, :421), `a < 2^236` suffices. This is the bound [ALMVaultSync/uncheckedMath.derivation.md](../ALMVaultSync/uncheckedMath.derivation.md) section 5.2 starts from.
3. `a < 2^236` is not enforced by src. It holds when the reward token emitted to the gauge since the snapshot is below `2^236` wei: `a` is at most the emissions the staked liquidity earned.

## 2. Proof

1. `g` is a difference of two `uint256` readings in unchecked arithmetic (:146-148), any value below `2^256`. `l` is any `uint128`. `fullMulDiv(g, l, 2^128)` returns `floor(g l / 2^128) < 2^256 · 2^128 / 2^128` and reverts only past `2^256 − 1`. Nothing else reads `g` or `a` before :155.

2. `a · r` and `a · h` are unchecked products (:155-156). `visible = a − floor(a r / M) <= a`, so `visible · h <= a · h`. With both products exact, the four subtractions and the sum are those of uncheckedMath.derivation.md section 5.2.

3. The pool raises its reward growth by `floor(reward · 2^128 / stakedLiquidity)` per settlement (`CLPool.sol:780`), and `getHiddenEmissions` adds the projected part the same way (:124). The growth inside a range is at most the global growth over the same span, and `l` is at most the staked position's liquidity (H4), which is part of the pool's staked liquidity while in range. So `g l / 2^128 <= Σ reward`, the reward token emitted to the gauge over the span, while that growth is below `2^256` (uncheckedMath.derivation.md section 5.1). The gauge takes the same products on the same amount in 0.7.6, unchecked (`Gauge.sol:164`, :179, `_reward` from `CLGauge.sol:520`), so it has the same domain.

Values at which the block is wrong: `g = 2^255`, `l = 2^127`, `r = 4`, `h = 0`. Then `a = 2^254`, `a · r = 2^256` wraps to 0, `visible = a`, and the side adds 0 to `hidden` where the exact value is `floor(4 · 2^254 / 1e6) = 115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129`. The state needs `2^254` wei of reward token emitted to one gauge.

## 3. Constants

| Constant | Where | Sufficiency | Witness |
|---|---|---|---|
| `2^236` | the bound the block's comment states as "a real emission amount" (:153) | statement 2: `2^236 · 1e6 < 2^256` | the values above, at `a = 2^254`. Not a constant of the code |
