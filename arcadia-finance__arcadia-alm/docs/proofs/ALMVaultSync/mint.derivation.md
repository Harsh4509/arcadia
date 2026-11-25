# ALMVaultSync.mint: the core's tokenIn pull stays within what the vault holds after its buy

Code: `src/vaults/ALMVaultSync.sol` `_mint` (:170-184), `_deposit` (:118-130), `_swapAndMint` (:198-254), `src/vaults/libraries/math/MintOptimizationMath.sol` `computeSwap` (:42-102), `previewMint` (:116-125), `maxMint` (:141-202), `src/vaults/types/Snapshot.sol` `getMintAmounts` (:239-276), `getMintShares` (:287-326), `src/vaults/types/SwapState.sol` `getStepFees` (:153-166), `accrueFees` (:175-186), `src/core/ALMCore.sol` `mint` (:136), `src/core/libraries/state/RangesLib.sol` `getUnstakedPositions` (:502-528), `src/shared/libraries/vendored/MetadexPositionValue.sol` `fees` (:28-45). Pool behaviour: [PoolAxioms.md](../PoolAxioms.md). Builds on [getStepFees](../SwapState/getStepFees.derivation.md).

Notation: `m` the shares minted, `N` the supply, `n` the range count, `n_u` the core's ranges with unstaked liquidity in range on some step of the buy, `u' = unstakedFee / 1e6`, `b' = protocolSwapFeeBps / 1e4`, `F_k`, `L_k`, `S_k` a step's fee, pool liquidity and staked liquidity, `Lu_k` the core's unstaked liquidity in range on step `k`. Subscript `m` is the model (the vault's quote), `a` the pool and the core at execution. `s` a price, `Q = 2^96`.

Domain: the step fee is `beforeSwapFee` for the vault (Snapshot.sol:63-65) and the pool charges no after-swap fee (the deployed `DynamicSwapFeeHook` answers `getBeforeSwapFee` from the caller and block state of `beforeSwap` and charges no after-swap fee, docs/audit-doc.md 6.4, Fee reads and swap hooks). The buy ends at the quote's end price, which the plain mint needs within the swap-cost band ([maxViews.derivation.md](maxViews.derivation.md) section 3).

## 1. Statement

(a) For every state, `mint(m, receiver, previewMint(m))` and the plain `mint(m, receiver)` whose buy fills do not revert on the core's tokenIn pull: with `e = fees_a − fees_m` the core's tokenIn fees at the pull less the model's, `e <= ceil(n_u (1 − b'))` when `b' > 0` and `e <= n_u − 1` when `b' = 0`, and the quote carries `n >= n_u` wei of tokenIn on the idle before its ceiling (Snapshot.sol:269-271).

(b) The deposit carries the same margin in `getMintShares` (Snapshot.sol:295-297), so the core's tokenIn pull for the shares `previewDeposit` returns stays within the deposit's tokenIn after its swap, for every `m`, also above the supply.

(c) At the core's edge with no tokenOut need, the mint walk buys at least 1 wei (MintOptimizationMath.sol:94-99), and `mint(maxMint)` then fills.

(d) A mint with spot at or below a single range and no idle token1 needs no swap and charges at most `(held + B0 + F0) m / N + Q / s + 3` of token0.

The tokenOut side of the pull (the need `getMintAmountOut` covers) is in [MintOptimizationMath/getMintAmountOut.md](../MintOptimizationMath/getMintAmountOut.md), open.

## 2. Axioms and bounds used

- B2, B5, B7: the pool's exact output steps. C2 (from B4): a step pays under 1 wei short of exact.
- F1: every rounding of the fee split is against the unstaked side. F2: a position's owed fees are one floor over the whole uncounted growth (MetadexPositionValue.sol:38-43).
- A1 to A3, D1, D2 for section 3.4.
- `RangesLib.getUnstakedPositions`: the protocol share is `floor(P b')` of the gross total `P`, once (RangesLib.sol:525-526).
- `SwapStateLib.getStepFees(step, true)`: the model accrues `ceil(Φ_k)` per step, `Φ_k = F_k (1 − u') (1 − b') Lu_k / L_k` (SwapState.sol:160-162, with `feeShare` from Snapshot.sol:80-81).
- `ALMCore.mint`: pulls `ceil((buffer_in + fees_in) m / N) + desired_in` (ALMCore.sol:159-160, :163-171), `desired` from `RangesLib.getMintAmounts` (RangesLib.sol:541-580) at the live price with `ceil(L_i m / N)` per range and `CLMath.getAmountsForLiquidityRoundingUp` (CLMath.sol:266-270), and refunds the unused token0 (ALMCore.sol:181-185).

## 3. Proof

### 3.1 The pull reduces to the idle term

`_mint` reads the snapshot, runs `computeSwap(m)` (accruing `ceil(Φ_k)` per step into `snapshot.fees`, MintOptimizationMath.sol:89) and `getMintAmounts(sqrtPriceNew, m)` (ALMVaultSync.sol:176-178), and pulls `balanceIn = amountSwapIn_m + amountMintIn_m` (ALMVaultSync.sol:181-183, :208). `previewMint(m)` is the same sum on the same state (MintOptimizationMath.sol:122-124), so `balanceIn = previewMint(m)`. The vault then swaps exact output `amountSwapOut_m` with the limit `sqrtPriceNew` (or the band, which the domain puts at or past it, ALMVaultSync.sol:214-229), and `ALMCore.mint` pulls from what the vault holds. No revert iff

```
amountSwapIn_a + idle_a + desired_a <= amountSwapIn_m + idle_m + desired_m      (1)
```

Three terms are equal:

- `amountSwapIn_a = amountSwapIn_m`, and the pool ends at `sqrtPriceNew`. The model's full steps are `computeSwapStep(roundUp = true)` (SwapState.sol:126-144): input rounded up, fee `ceil(input f / (1e6 − f))`, output floored, which is the pool's full exact output step (B2, B5), and the pool reaches each such target as the output left includes the later steps'. On the last step the model calls `MetadexSwapMath.computeSwapStep` with the request `r` (MintOptimizationMath.sol:72-83). It either reaches the tick with the floored output `<= r`, or ends at `P = getNextSqrtPriceFromOutput(r)` with output `r`. The pool's last step has the limit `P` (or the tick) as its target and the model's step output as the output left. At `P` the floored output is at least `r` (B7): if equal, the pool reaches `P`, if above, it ends at `getNextSqrtPriceFromOutput(r) = P` with the output capped at `r` (B5). Either way the same price, the same rounded-up input and fee.
- `desired_a = desired_m`: both are `ceil(L_i m / N)` and the rounded-up amounts at the same price per range (Snapshot.sol:255-258 and CLMath.sol:266-270), with `L_i` the same unstaked plus staked liquidity (Snapshot.sol:135, RangesLib.sol:559).
- The tokenOut fees and buffer are untouched by a buy that pays its fee in tokenIn.

So (1) is `ceil((buffer + fees_a) m / N) <= ceil((buffer + fees_m + n) m / N)` on tokenIn, the `+ n` being `getMintAmounts`' margin (Snapshot.sol:269-271). It holds when `e <= n`.

### 3.2 The pool's fees against the model's

Per step the unstaked growth is `g_k = floor(U_k 2^128 / (L_k − S_k))` with `U_k` the fee after the staked share (rounded up) and the levy (rounded up) (F1). So the growth the core's positions earn, `y_k = g_k Lu_k / 2^128` (real), satisfies `Σ_k y_k <= Ψ = Σ_k F_k (1 − u') Lu_k / L_k`, and `Φ = (1 − b') Ψ`.

Per position `i` the core reads `owed_i = tokensOwed_i + floor(G_i Lu_i / 2^128)` (F2, MetadexPositionValue.sol:38-43). With `x_i` the uncounted growth before the buy and `y_i` the buy's, the read moves by `Δ_i = floor(frac(x_i) + y_i)`, so `Δ_i <= ceil(y_i)`. The protocol share moves by `D = floor(P_1 b') − floor(P_0 b') >= floor(Δ b')`, `Δ = Σ_i Δ_i` (RangesLib.sol:525-526). Hence `e = Δ − D − Σ_k ceil(Φ_k)`.

Bound. `Σ_i ceil(y_i) <= ceil(Σ_i y_i) + n_u − 1 < Ψ + n_u`, so `Δ (1 − b') < Φ + n_u (1 − b')`, and `Δ − D <= ceil(Δ (1 − b'))`. With `Σ_k ceil(Φ_k) >= ceil(Φ)`:

```
e <= ceil(Φ + n_u (1 − b')) − ceil(Φ) <= ceil(n_u (1 − b')) <= n_u <= n.
```

For `b' = 0`: `D = 0` and `e <= ceil(Ψ) + n_u − 1 − ceil(Ψ) = n_u − 1`. The bound does not depend on the step count: the growth accumulates unrounded over the steps and the two floors happen once per swap.

Attained (so the margin is needed): `n_u = 1`, `b' > 0`, one step, with a carry `frac(x) >= 1 − frac(y)`, an integer in `(Φ, (floor(y) + 1)(1 − b')]`, and no carry of the protocol floor. `n_u = 2`, `b' = 0.3`, `Ψ = 11.2`, `y = (5.1, 6.1)` both carrying gives `e = 2`.

Lower side: `e < 0` only lowers the pull. The vault refunds `balanceIn − assets` (ALMVaultSync.sol:247-250).

So (1) holds in every state, and `assets <= previewMint(m)`: `previewMint` is an upper bound on what the mint takes. The over-quote is at most `ceil(n m / N)` wei of tokenIn, refunded.

### 3.3 The deposit

`_deposit` mints `m = getMintShares(sqrtPriceNew, A_in, A_out)` with `A_in = assets − amountSwapIn` (ALMVaultSync.sol:126). `getMintShares` sets `cost_in = idle_in + n + Σ_i a_i`, `a_i` the rounded-up amounts of `L_i` (Snapshot.sol:295-317), and `m <= (A_in − r_in) N / cost_in` with `r_in = n (u + 2) + 1` (`getRounding`, Snapshot.sol:220-221, `u` one liquidity unit's tokenIn rounded up, at least the exact tokenIn of one unit at that price for any range). The deposit walk accrues `ceil(Φ_k)` per step (`getStepFees(step, true)` on every step, DepositOptimizationMath.sol:88, :116), so section 3.2's bound holds for it. The core pulls

```
pull_in < (idle_m + e) m / N + 1 + Σ_i (a_i m / N + u + 1)
```

(the amount of `ceil(L_i m / N)` liquidity rounded up is at most the exact amount of `L_i m / N` plus one unit's plus 1). Then

```
A_in − pull_in > m (n − e) / N + n (u + 2) + 1 − n (u + 1) − 1 = m (n − e) / N + n >= 0
```

for every `m`, as `e <= n`.

The deposit's swap costs what its quote does. `DepositOptimizationMath.computeSwap` books every step with `computeSwapStep(roundUp = true)` to the step's target (DepositOptimizationMath.sol:80), and a solved step has its target moved to the solved price `P` first (DepositOptimizationMath.sol:113-117), so the quote's output is the sum of the pool's floored outputs to `P` and its cost the sum of the rounded-up inputs and fees. The vault asks for that output with the limit `P` (ALMVaultSync.sol:223-228): every target is reached (B5, the output left equals the floored output to the last target), so the pool ends on `P` with the same input and fee (B2).

### 3.4 At the core's edge

Notation: `e_c` the core's nearest edge in the buy's direction (`state.position.sqrtPriceBound`), `need(p)` the tokenOut `getMintAmountOut` returns at `p` (MintOptimizationMath.sol:217-229), `B` the walk's bought tokenOut.

How `computeSwap` ends: it loops while `need > B` and the pool has liquidity (MintOptimizationMath.sol:58). The solve runs when `B + step.amountOut + δ >= need` (`δ` the need's drop over the step, MintOptimizationMath.sol:63-72) and requests `ceil((need − B) L / (L + K)) >= 1` (`K` the mint's liquidity in range, MintOptimizationMath.sol:78-81), which the pool pays exactly (B5, B7). Without the solve the need stays above `B` after the step. So `need <= B` is first met only at an edge, where the need is recomputed (MintOptimizationMath.sol:94-96).

At `e_c` with `need(e_c) <= B`: if `B >= 1`, the vault's exact output `B` with the limit `e_c` reaches every target (B5) and ends on `e_c` (D1, D2), where the core takes at most `need(e_c) <= B`. If `B = 0` and `need(e_c) = 0`, `computeSwap` sets the need to 1 there (MintOptimizationMath.sol:98), so the walk goes on past `e_c` as below.

A quote with `B = 0` and its end price `S` off spot (the walk out of pool liquidity or at the pool's price limit, MintOptimizationMath.sol:58, :93) still executes as quoted. `_swapAndMint` swaps whenever the quote's end price differs from spot (ALMVaultSync.sol:212), asking the pool for `max(B, 1)` with `S` as the limit (ALMVaultSync.sol:223-228). Every walk step's floored output is 0 (B4), so with 1 wei left each pool step reaches its target (B5) and the pool loops until the price is `S` (D1): it ends on `S`, takes the walk's input and fee per step (B2) and pays 0. The core mints at `S`.

With the need at 1 the walk goes on past `e_c`: steps paying 0 are booked at their cost, the first step paying a wei is solved for a request of `ceil(L / (L + 0)) = 1` (no core liquidity is in range past an edge with `need(e_c) = 0`), and the walk ends with `B = 1`. The vault's exact output of 1 takes the same steps (B5) and ends at or past the exact price (B7), past `e_c`. There the core takes 0 tokenOut.

The state is reachable: a plan that deploys the whole buffer with tokenOut binding leaves 0 of it when one liquidity unit is worth under a wei (A3), tokenOut fees are 0 after a plan's collection until a swap pays tokenOut in, and a swap with a limit beside `e_c` leaves a gap whose step pays 0 (A1, A2: `g <= (Q − 1) / L` for token1, `g <= (e_c^2 − 1) / (L Q + e_c)` for token0).

`maxMint` agrees: a walk to the limit summing 0 returns 0 (MintOptimizationMath.sol:172). A sum of at least 1 means a step inside the limit pays a wei, the 1 wei buy ends at or before the limit, and with no need at the walk's end it returns `type(uint256).max` (MintOptimizationMath.sol:175-176). A pool without liquidity past `e_c` ends the walk with `B = 0` and `maxMint` returns 0.

### 3.5 A mint without a swap

With spot `s <= s_a` of a single range `[s_a, s_b]` and no idle token1, the core charges token0 only and the vault buys nothing. With `L_m = ceil(L m / N)` and `held = getAmount0Delta(s_a, s_b, L, true) >= L Q (1/s_a − 1/s_b)`:

```
getAmount0Delta(s_a, s_b, L_m, true) <= (L m / N + 1) Q (1/s_a − 1/s_b) + 1 <= held m / N + Q / s_a + 1
```

(A2), and the idle adds `ceil((B0 + F0) m / N)`. The total is at most `(held + B0 + F0) m / N + Q / s + 3` since `s <= s_a`. So `m <= (M − ceil(Q / s) − 3) N / (held + F0 + B0)` keeps the charge, and the position manager's amounts, within `M = type(int128).max`. The bound is at the spot the mint executes at: spot must be at or below the range then, not only when `m` is sized.

## 4. Constants

| Constant | Where | Sufficiency | Witness |
|---|---|---|---|
| `n` wei on the idle tokenIn | Snapshot.sol:269-271 | 3.2: `e <= ceil(n_u (1 − b')) <= n_u <= n` | test/fuzz/ALMVaultSync/Mint.fuzz.t.sol:1481 `test_Success_mint_FillsAtTheQuoteWhenTheBuyCarriesAFeeWei` (one range, `e = 1`): with the margin at 0 the mint at the quote reverts `TransferFromFailed` |
| `n` wei on the tokenIn cost | Snapshot.sol:295-297 | 3.3 | none |
| need set to 1 at an edge | MintOptimizationMath.sol:98 | 3.4 | test/fuzz/ALMVaultSync/Mint.fuzz.t.sol:1395 `testFuzz_Success_mint_FillsBesideTheRangeEdgeWithoutIdleNonAsset`: at 0 the mint reverts at the core's tokenOut pull |
| `ceil(Q / s) + 3` | the bound of 3.5 | 3.5 | none |

test/fuzz/ALMVaultSync/Deposit.fuzz.t.sol:1710 `test_Success_deposit_FillsAtThePreviewAboveTheSupplyWhenTheBuyCarriesAFeeWei` and :1722 `test_Success_deposit_FillsAtThePreviewAboveTheSupplyWithoutAFeeCarry` assert 3.3 on states with and without a carry.
