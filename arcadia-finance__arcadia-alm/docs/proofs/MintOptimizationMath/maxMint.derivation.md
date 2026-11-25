# MintOptimizationMath.maxMint: the token0-out rounding terms

Code: `src/vaults/libraries/math/MintOptimizationMath.sol` `maxMint` (:141-202), its token0 terms :182-192, `computeSwap` (:42-102), `getMintAmountOut` (:217-229), `src/vaults/types/Snapshot.sol` `getMintAmounts` (:239-276), `getRounding` (:213-223), `src/shared/libraries/math/CLMath.sol` `getAmountsForLiquidityRoundingUp` (:136-151), `getAmount0ForLiquidityRoundingUp` (:160-176). Pool behaviour: [PoolAxioms.md](../PoolAxioms.md). Frame: [ALMVaultSync/maxViews.derivation.md](../ALMVaultSync/maxViews.derivation.md) section 3.9, which this file extends from token1 out to token0 out.

Notation: one for zero, tokenOut token0, the price rises. `s0` spot, `ℓ` the view's limit, `Q = 2^96`, `n` the range count, `N` the supply, `m` the shares, `L` the pool's liquidity on a step, `k = steps` (:166). `J(p) = floor(p^2 / Q)`, `J0 = J(s0)` (:183). `u0 = ceil(Q / s0)`, `r0 = getRounding(s0, token0) = n (u0 + 2) + 1`. Per range `i` with liquidity `L_i` and bounds `lo_i < up_i`: `a_i(p) = max(p, lo_i)`, `q_i(p) = Q (1 / a_i − 1 / up_i)` the exact token0 of one liquidity unit at `p` (0 for `p >= up_i`), `x_i(p) = (up_i − a_i) / J_i`, `J_i = floor(a_i up_i / Q)`, the same with the position manager's divisor (`CLMath.sol:166-174`), `C_i = ceil(L_i m / N)` (`Snapshot.sol:255`). `M(p, m) = Σ_i ceil(C_i x_i(p)) + ceil(idle0 · m / N)` the mint's token0 (`Snapshot.sol:255-272`, the idle carries no margin on tokenOut). `K = Σ C_i` over the ranges in range (`activeLiquidityDelta`, `Snapshot.sol:261-263`), `ω(p1, p2) = Q (1 / p1 − 1 / p2)`.

The code's values: `C_spot = M(s0, N)` (:147), `C_end = M(ℓ, N)` (:175), `A = ceil(C_spot / J0)` (:187), `B_u = ceil(u0 / J0)` (:190), `Ĉ = C_end + 2 A + ceil(A / J0)` (:188), `R = r0 + k + n (2 B_u + ceil(B_u / J0) + 1) + 2 + 2` (:179, :191, :195), `Y_ℓ` the walk's floored output (:165), and `maxMint = floor((Y_ℓ − R) N / (Ĉ + 1))` (:201).

## 1. Statement

For `m <= maxMint` with `J0 >= 1` and the walk reaching `ℓ`, the mint's need at spot satisfies

```
need_0 − K ω(s0, ℓ) + (k − 1) + K / L  <  Y_ℓ − (n + 3 − (n + 1) / J0)  <=  Y_ℓ − 2,
```

`need_0 = getMintAmountOut(s0, m)`. By maxViews.derivation.md 3.9 this is the condition under which `computeSwap(m)` ends at or before `ℓ`, with no core edge between spot and `ℓ`. With a core edge `e` between, the same inequality holds with `e` in place of spot (section 3.3). The token0 terms of :182-192 are sufficient, with at least 2 wei to spare.

`J0 = 0` returns 0 (:185).

## 2. Axioms and bounds used

- A2: the pool's token0 between two prices is the exact amount rounded once. So a step's floored output is `floor(L ω)` and the need's drop over a step is `floor(K ω)` (:67-69).
- 3.2 of maxViews.derivation.md: an exact output fills within a limit iff it is at most the floored output to it.
- `J_i >= J0` for every range that holds token0 at a price `p >= s0`: `a_i >= s0` and `up_i > a_i`.
- `x_i / q_i = a_i up_i / (Q J_i) < 1 + 1 / J_i`, as `J_i > a_i up_i / Q − 1`. So `x_i < q_i (1 + 1 / J0)`.
- `q_i(p) <= Q / a_i <= Q / s0 <= u0` for `p >= s0`.

## 3. Proof

### 3.1 The need at spot

`need_0 = M + n + T1`, `M = M(s0, m)`, `T1 = ceil(M / J0)` (:225-228). Let `e_i = C_i q_i(s0)`, the exact token0 of the mint's liquidity in range `i`, and `Ex = Σ e_i + idle0 · m / N`.

Per range, `ceil(C_i x_i) < e_i (1 + 1 / J0) + 1`. The idle part is below `idle0 · m / N + 1`. So

```
M  <  Ex + Ex / J0 + n + 1.                                                    (1)
```

The exact amounts at `ℓ`. A range in range loses `C_i ω(s0, ℓ)` between spot and `ℓ`, the others nothing, so `Σ e_i − K ω(s0, ℓ) = Σ C_i q_i(ℓ)`. `C_i < L_i m / N + 1` and `q_i(ℓ) <= u0`, and `C_end >= Σ L_i q_i(ℓ) + idle0` (a mint of the supply takes `L_i` per range, rounded up, and the whole idle, `Snapshot.sol:255`, :271). So

```
Ex − K ω(s0, ℓ)  <  (m / N) C_end + n u0.                                      (2)
```

The same way `Ex < (m / N) C_spot + n u0`, hence

```
Ex / J0    <=  (m / N) A + n B_u,
Ex / J0^2  <=  (m / N) ceil(A / J0) + n ceil(B_u / J0).                        (3)
```

`T1 < M / J0 + 1 < Ex / J0 + Ex / J0^2 + (n + 1) / J0 + 1` by (1). With (1), (2), (3):

```
need_0 − K ω(s0, ℓ)
  <  (m / N) C_end + n u0 + Ex / J0 + n + 1  +  n  +  Ex / J0 + Ex / J0^2 + (n + 1) / J0 + 1
  <= (m / N) Ĉ + r0 + n (2 B_u + ceil(B_u / J0)) + (n + 1) / J0 + 1.
```

### 3.2 The view's shares

`m (Ĉ + 1) <= (Y_ℓ − R) N` (:201) gives `(m / N) Ĉ <= Y_ℓ − R − m / N`. `K / L <= m / N + 1` (maxViews.derivation.md 3.9). So

```
need_0 − K ω(s0, ℓ) + (k − 1) + K / L
  <  Y_ℓ − R + r0 + n (2 B_u + ceil(B_u / J0)) + (n + 1) / J0 + k + 1
  =  Y_ℓ − (n + 3 − (n + 1) / J0).
```

`(n + 1) / J0 <= n + 1` for `J0 >= 1`, so the right side is at most `Y_ℓ − 2`.

The step `j` that holds `ℓ` then covers the mint. `need_j <= need_0 − Σ floor(K ω_i)` over the earlier steps `i` (:85), at most `k − 1` of them, each floor losing under 1. With `ω_j` the exact output per unit of liquidity from the step's start to `ℓ` and `y_ℓ` the pool's floored output to `ℓ`, the display gives `need_j − K ω_j + K / L < bought_j + y_ℓ`. The step's own amounts to its target are at least those to `ℓ`, and `floor(K ω_j) > K ω_j − 1`, so `bought_j + step.amountOut + amountMintOutDelta >= need_j` (:72). The request `ceil((need_j − bought_j) L / (L + K))` (:78-81) is at most `y_ℓ`, as `y_ℓ K / L >= K ω_j − K / L`.

### 3.3 A core edge between spot and the limit

At an edge `e` the need is recomputed as `getMintAmountOut(e, m)` (:94-96). Each quantity of 3.1 at `e` is at most its value at spot: `J(e) >= J0`, `u0(e) <= u0`, and `M(e, N) <= M(s0, N)`, since per range the numerator `up_i − a_i` does not rise and the divisor `J_i` does not fall as the price rises (`CLMath.sol:143-150`, :166-174). So `A`, `B_u`, `r0` and the step count from `e` are at most the view's, and 3.1 and 3.2 hold from `e` with the view's `R` and `Ĉ`. The extra wei of :98 is the degenerate exception of maxViews.derivation.md 3.9.

## 4. Constants

| Constant | Where | Sufficiency | Witness |
|---|---|---|---|
| `2 A` in `Ĉ` | :188 | 3.1: `Ex / J0` twice, once in the mint's ceilings over `J_i` (1), once in the need's own `ceil(M / J0)` (:227) | none |
| `ceil(A / J0)` in `Ĉ` | :188 | 3.1: `Ex / J0^2`, the need's `ceil(M / J0)` taken on amounts already `1 / J0` over exact | none |
| `n (2 B_u + ceil(B_u / J0))` | :190-191 | 3.1 (3): the same three terms on the `n` liquidity units the mint's ceilings add | none |
| `n + 2` | :191 | 3.2: covers `(n + 1) / J0 + 1`, the ceilings of (1) over `J0` and the ceiling of `T1` | none: `n + 1 − (n + 1) / J0` wei to spare |
| `+ 2` | :195 | maxViews.derivation.md 3.9: 2 wei to spare, as for token1 | none |

No constant of this row set is the least: the proof leaves `n + 3 − (n + 1) / J0 >= 2` wei, so no state needs the last wei of any of them.

## 5. Scope

The statement is the inequality of section 1. That it implies the fill is maxViews.derivation.md 3.9, whose status there is model. That step is not re-derived here.
