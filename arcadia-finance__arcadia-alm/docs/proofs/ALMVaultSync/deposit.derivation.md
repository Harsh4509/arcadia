# ALMVaultSync.deposit: the quote is paid, the asset leg binds at most a token0 ceiling below the split, a few wei of tokenOut stay

Code: `src/vaults/libraries/math/DepositOptimizationMath.sol` `computeSwap` (:58-125), `previewDeposit` (:139-148), `getBalanceIn` (:252-259), `getAmountOut` (:272-316), `getNormalizedParameters` (:423-487), `src/vaults/types/Snapshot.sol` `getRounding` (:213-222), `getMintShares` (:287-326), `src/vaults/types/SwapState.sol` `computeSwapStep` (:126-144), `getStepFees` (:153-166), `accrueFees` (:175-186), `crossTick` (:198-234), `src/vaults/libraries/math/EquivalentPositionMath.sol` `amountsAt` (:109-124), `src/vaults/ALMVaultSync.sol` `_deposit` (:118-130), `_swapAndMint` (:198-254). Pool behaviour: [PoolAxioms.md](../PoolAxioms.md).

Notation. zeroForOne is written out, oneForZero mirrors every inequality. `a` the deposit (`balanceIn`), `x` and `Y` the swap's tokenIn and tokenOut (`amountSwapIn`, `amountSwapOut`), `kept = a − x`, `s0` spot, `S` the end price (`sqrtPriceNew`), `T` the target of the step the walk ends in, `N` the supply, `n` the range count, `m` the shares, `σ = m / N`. `f = fee / 1e6 <= 1/10` (G1), `φ = f / (1 − f) <= 1/9`, `κ = 1 / (1 − f)`. `u_0(p) = ceil(Q / p)`, `u_1(p) = ceil(p / Q)`, `Q = 2^96`, and `r_t(p) = getRounding(p, t) = n (u_t(p) + 2) + 1` (Snapshot.sol:220-221). `c = 2n + 4` (`roundingMargin`, DepositOptimizationMath.sol:71). Per step `k` of the walk, `b_k = a ⊖ (r_in(T_k) + 3)` (`balanceNet`, DepositOptimizationMath.sol:84). `w = feeShare · unstaked / (1e10 · L) <= 1`, the core's part of a step's fee (SwapState.sol:160-164).

Three views of the core's tokens at a price `p`, per token `t`:
- `R_t(p)`: the real amounts: the ranges' exact amounts, the buffer, the fees.
- `D_t(p)`: what the step test and the solve read: `amountsAt` of the walk's position at the step's start, moved exactly along the step, the step's real fee share on tokenIn.
- `K_t(p)`: what `getMintShares` divides by: per range `getAmountsForLiquidityRoundingUp` of its liquidity, plus the idle tokens with the walk's fees, plus `n` on tokenIn (Snapshot.sol:294-316).

## 1. Statement

For every state and every `a`, with `(S, x, Y) = computeSwap(a)` and `m = getMintShares(S, kept, Y)`:

1. `x <= a`, so `kept` does not underflow in `_deposit` (ALMVaultSync.sol:126) and `previewDeposit` (DepositOptimizationMath.sol:147).
2. When `S` differs from spot, `_swapAndMint` asks the pool for an exact output of `max(Y, 1)` with limit `S` (ALMVaultSync.sol:212, :223-228). That swap ends at `S` and takes `x`.
3. For `m` shares at `S` the core pulls at most `kept − n` of tokenIn and `Y − n` of tokenOut. So `_swapAndMint` does not revert `ExcessiveInput` (ALMVaultSync.sol:242) and the core does not revert on its pull, and `deposit(a, receiver, previewDeposit(a))` mints `previewDeposit(a)` shares.
4. The asset leg does not bind below the split, up to token0's ceilings: `(kept − r_in(S)) N / K_in(S) > (1 − g) Y N / D_out(S)`, with `g = 0` for token1 in and `g = G / K_in(S) <= 1 / J(S)` for token0 in (3.5).
5. When the core holds at least `n` wei of tokenOut, the tokenOut left in the vault is at most `2 r_out(S) + ceil(K_out(S) / N) + n (ceil(m / N) + 1) + floor(Y / J(S))`, in both directions, `J(S)` the position manager's least token0 divisor at `S` (3.5, 3.7).
6. The refund is at most `r_in(T) + 3 + c (σ + 1) + K_in(S) / N` plus one price unit of tokenIn.

Statements 2 and 3 assume the pool's swap uses the fee the walk reads and adds no after-swap fee (C7, and the deployed `DynamicSwapFeeHook` answers `getBeforeSwapFee` from the caller and block state of `beforeSwap` and charges no after-swap fee, docs/audit-doc.md 6.4, Fee reads and swap hooks). An after-swap fee on the input is caught by `_swapAndMint`'s `ExcessiveInput` check (ALMVaultSync.sol:242). The plain `deposit(a, receiver)` limits the swap to the band (`getSwapCostLimit`, ALMVaultSync.sol:214-218): with `S` past the band it reverts `InsufficientOutput` (ALMVaultSync.sol:230).

## 2. Axioms and bounds used

- Pool: A1, A2, A3, B1, B2, B4, B5, B7, C1, C2, D1, D2, D3, F1, F2, G1, G3, G5.
- `getRounding`'s sufficiency: [roundingMargins.derivation.md](roundingMargins.derivation.md) section 4.1.
- The core's pull for `m` shares at `S`: per range `getAmountsForLiquidityRoundingUp` of `ceil(L_i m / N)`, plus `ceil((idle_t + F + e_t) m / N)`, `F` the walk's fees and `e_t` the core's fees over the snapshot's, with `e_in <= n` and `e_out = 0`: [mint.derivation.md](mint.derivation.md) sections 1 to 3 (F1, F2).
- The solve's root is at most the exact root of the step's equation, short by under `2^-30` of a price unit for `s < 2^160` away from the double root: [QuadraticMath/getRoot.derivation.md](../QuadraticMath/getRoot.derivation.md) sections 3 and 6.
- The step test and the end of a step: [DepositOptimizationMath/stepEndRounding.derivation.md](../DepositOptimizationMath/stepEndRounding.derivation.md).
- Symbolic: test/symbolic/libraries/SnapshotLib.symbolic.t.sol:344 `prove_getRounding_NeverFallsAlongTheSwap` (prices in `[MIN_SQRT_PRICE, MAX_SQRT_PRICE]`, the target on the swap's side), test/symbolic/libraries/SwapStateLib.symbolic.t.sol:230 `prove_computeSwapStep_TheFeeOnAWeiMoreInputRoundedUpExceedsRoundedDownByAtMostTwo` (`fee <= 100_000`), test/symbolic/libraries/DepositOptimizationMath.symbolic.t.sol:90 `prove_getBalanceIn_ABalancePastItHoldsMoreTokenInThanThePositionsRatio` (every amount below `2^120`, `positionAmountOut > 0`), test/symbolic/libraries/SnapshotLib.symbolic.t.sol:301 `prove_getMintShares_WithoutLiquidity_TheMintOfItsSharesIsCoveredWithItsCarriedFee`, test/symbolic/libraries/SnapshotLib.symbolic.t.sol:321 `prove_getMintShares_WithoutRanges_TheTokenOutLegBindsWhenTheTokenInCoversTheRatio`.
- Open symbolic: test/symbolic/libraries/SnapshotLib.symbolic.t.sol:250 `prove_getMintShares_AboveTheRange_TheMintOfItsSharesIsCoveredByTheBalances` (one range, price at most `2^128`, `lower · upper >= 2^96`, supply at most `2^128`), status in [Snapshot/getMintShares.md](../Snapshot/getMintShares.md).

## 3. Proof

### 3.1 The walk is the pool's swap (statement 2)

Each step of `computeSwap` takes the pool's next target (D2, E1 to E3, via `setNextTick`, SwapState.sol:100-117), computes the pool's input rounded up, fee `ceil(input f / (1 − f))` and output rounded down (`computeSwapStep` with `roundUp`, SwapState.sol:132-143, B2, B4), and crosses the tick as the pool does (D3, `crossTick`, SwapState.sol:207-227). For an exact output request the pool takes a step to its target iff the output left is at least the floored output to the target (B5), with the same input and fee (B2). Every full step of the walk adds its floored output to `Y`, so the pool's request covers each full step exactly and its input and fee match.

The last step. When the solve ends inside a step, `getAmountOut` returns `R = s0 − ceil(y Q / L)` (DepositOptimizationMath.sol:312-315, B7 for token1 out), `y` the floored output to the solve's price, and `computeSwap` recomputes the step to `R` (DepositOptimizationMath.sol:113-117). Its output `y' = floor(L (s0 − R) / Q) >= y`, since `s0 − R >= y Q / L`. The pool, asked for `y'`, ends at `s0 − ceil(y' Q / L)`: `y' Q / L <= s0 − R` gives at most `s0 − R`, and `y' >= y` gives at least `ceil(y Q / L) = s0 − R`. So the pool ends at `R`. Token0 out: `R = ceil(L Q s0 / (L Q − y s0))` (B7), `y' = floor` of the exact output to `R` is at least `y`, and the pool's price for `y'` is at least `R` (monotone) and at most `R` (the exact price for `y'` is at most `R`, an integer). When the solve ends on the position's bound the walk takes the step to the bound, a full step. So the pool's swap ends at `S` with input `x` (B5 caps the output at the request).

Zero output. With `Y = 0` and `S` off spot the request is 1 wei (ALMVaultSync.sol:223-228). Every walk step's floored output is 0 (B4), so with 1 wei left each pool step reaches its target (B5) and the pool loops until the price is `S` (D1). Its input and fee per step are the walk's (B2): it ends on `S`, takes `x` and pays 0, and the core mints at `S`.

### 3.2 `x` is within the balance (statement 1)

A step taken in full had its first step test false (DepositOptimizationMath.sol:92): `state.amountIn + step.amountIn + step.feeAmount <= b_k`. In the solved step, with `r = b_k ⊖ state.amountIn` (DepositOptimizationMath.sol:109), `getAmountOut` caps the price where `a' = floor(r (1 − f))` moves it (DepositOptimizationMath.sol:286-308). The step's input to `R` is at most `a'`: `R` is at or before that price, and the exact input to that price is at most `a'`. Its fee is at most `ceil(a' φ)`, and `a' + ceil(a' φ) = ceil(a' / (1 − f)) <= r`. So `x <= max_k b_k <= a`.

When a later step's `b_k` is below `state.amountIn` (`r_in(T_k)` grows along the swap), `zeroFloorSub` gives `r = 0`, the solve moves nothing and the swap ends at the step's start. In every case `kept >= r_in(S) + 3` once `a >= r_in(T_1) + 3`, and a deposit of at most `r_in(T_1) + 3` swaps nothing.

### 3.3 The core's pull (statement 3)

Per range, `ceil(L_i σ) < L_i σ + 1`, and one liquidity unit holds at most `u_t(S)` of either token at `S` (in range and out of range alike), so the range's pull is under `up_i(S) σ + u_t(S) + 1`, `up_i` its rounded-up amount of the whole liquidity. The idle part pulls under `(idle_t + F + e_t) σ + 1 <= (idle_t + F + [t = in] n) σ + 1`. With `K_t = idle_t + F + [t = in] n + Σ up_i`:

    pull_t < K_t σ + n (u_t(S) + 1) + 1 = K_t σ + r_t(S) − n.

`getMintShares` returns `m <= (amount_t − r_t(S)) N / K_t` for each token with `K_t > 0` (Snapshot.sol:301-305, :323-325), so `pull_t < amount_t − n`, for every share count, above the supply too. With 3.1 the vault holds `kept` and `Y` when the core pulls. Symbolic for the idle part with the carry and for one range on the tokenOut side (section 2).

### 3.4 The balance margin `r_in(T) + 3`

`getMintShares` takes `r_in(S)` off the tokenIn balance (Snapshot.sol:301-305). `T` is known before the solve and `r_in(T) >= r_in(S)` for every `S` of the step: `u_0` grows as the price falls and `u_1` as it rises (symbolic, section 2).

The solve is exact in the step's real amounts and the walk charges the pool's rounded ones (C1). With `k = step.amountIn` and `α = k − in ∈ [0, 1)`, `in` the exact input, the step costs `α (1 + φ) + (ceil(φ k) − φ k)` over its exact cost `κ in`: under `2 + φ`, under 3 for `φ <= 1/9`. It exceeds 2 when `0 < frac(φ k) < φ`, which fees with `φ = 1/q`, `q` an integer, never reach and a fee of 3,000 does: 3 is the least integer over the fees a pool can set. The steps before the last are in `state.amountIn`, which the solve subtracts, so one step's rounding suffices.

### 3.5 The position margin `2n + 4`

At the end price, with the same accrued fees in both, the cost exceeds the position read by, per term:

| Term | Bound | Why |
|---|---|---|
| fee carry | exactly `n` | `getMintShares` adds `n` to the tokenIn cost (Snapshot.sol:295-297, 3.3) |
| ranges in range, `n_i` of them | under `n_i + 1` | `Σ ceil(a_i)` against one floored liquidity term of `amountsAt` and floored constants that only raise the position |
| ranges holding tokenIn alone, `n_0` | at most `n_0` | a ceiling against a floor (token1) or a difference of two floors (token0): an integer under 2 |
| the last step's fee share | under `1 + w (1 + φ)` | `getStepFees(step, true)` is `ceil(w · feeAmount)`, `feeAmount` a ceiling on a ceiled input (SwapState.sol:137-138, :160-162) |

`K_in(S) − (D_in(S) + Φ(S)) < 2n + 2 + w (1 + φ)`, `Φ` the step's exact fee share, with `n_i + n_0 <= n`. Above `2n + 3` only when `1 − f < w < 1`: with `w = 1` the fee share is the whole fee, its ceiling adds nothing and the term is under `1 + φ`. So `2n + 4` is the least integer over all states, `2n + 3` over `w <= 1 − f` or `w = 1`. In a step taken in full the fee share is the accrued one and the last row is absent.

Token0's divisor. A range holding token0 at `S` (`S < upper_i`) costs `up_i = ceil(L_i Δ_i / J_i(S))`, `Δ_i = upper_i − max(S, lower_i)` and `J_i(S) = floor(max(S, lower_i) · upper_i / 2^96)` (CLMath.sol:143-146, :166, :174), against the exact `e_i = L_i Δ_i 2^96 / (max(S, lower_i) · upper_i)`. With `max(S, lower_i) · upper_i / 2^96 − J_i(S) < 1`:

    up_i < e_i (1 + 1 / J_i(S)) + 1.

The `+ 1` is the table's ceiling. The rest, `G = Σ e_i / J_i(S)`, is in the cost alone: `amountsAt` divides by the prices themselves (EquivalentPositionMath.sol:78, :86, :115), so the position does not carry it and `c` does not cover it. With `J(S) = min_i J_i(S) >= min_i floor(lower_i · upper_i / 2^96)` and the ranges' token0 at most `K_0(S)`, `G <= K_0(S) / J(S)`. So for token0 in

    K_in(S) − (D_in(S) + Φ(S)) < 2n + 2 + w (1 + φ) + G,   G / K_in(S) <= 1 / J(S),

and for token0 out `K_out(S) − R_out(S) < n + G` with `G / K_out(S) <= 1 / J(S)`. Token1's ceilings divide by `2^96` and add nothing.

The margin enters at the two reads of the position's tokenIn and nowhere else: the step test reads `amountsAt(T) + feesIn + c` (DepositOptimizationMath.sol:95-97), the solve reads `amountsAt(s0) + c` in `getNormalizedParameters` (DepositOptimizationMath.sol:443-445). `accrueFees`, `crossTick` and `getMintShares` see the core's real holdings. The position's liquidities, its bound and the fee term do not carry `c`.

### 3.6 The asset leg (statement 4)

The walk ends in one of two ways.

Solved step. The walk ends in a step whose solve ran, at a price `S` at or before the exact root `P*` of `(b − x*(s)) D_out(s) = (O + y*(s)) (D_in(s) + c + Φ(s))`, `b = b_k − state.amountIn`, `O = state.amountOut`, `x*` and `y*` the step's exact cost and output: either the solve returned `S` inside the step, or it returned a price at or past `T` and the walk ended at `T` (`P*` past `T` up to `2^-32` of a unit, stepEndRounding.derivation.md 3.4 and 3.5). Before the root the left side is the larger, so `b − x*(S) >= (O + y*(S)) (D_in + c + Φ) / D_out`. The charged cost of the last step is under `x*(S) + 3` (3.4), so `kept − r_in(T) − 3 > b − x*(S) − 3`, and `Y <= O + y*(S)` (B4). With 3.5, `D_in + Φ + c > K_in − G`, `G = 0` for token1 in. With `r_in(T) >= r_in(S)`:

    kept − r_in(S) > Y (K_in(S) − G) / D_out(S).

Full step. The walk ends at the target of a step whose step test was false: the pool runs out of liquidity, the next step's net balance is below the cost so far, or the next step buys nothing. Then `b_k > getBalanceIn(cost, Y, D_in(T) + feesIn + c, D_out(T))` (DepositOptimizationMath.sol:98-104), so `(b_k − cost) D_out > Y (D_in + feesIn + c)` (symbolic, section 2), `b_k − cost = kept − r_in(T) − 3` and 3.5 holds without the fee row.

Either way `(kept − r_in(S)) N / K_in > (1 − g) Y N / D_out`, `g = G / K_in <= 1 / J(S)`. For token1 in `g = 0` and the floors keep the order: `floor((kept − r_in(S)) N / K_in) >= floor(Y N / D_out)`. For token0 in the asset leg can bind below the split by the relative `g`: the mint's token0 ceilings, which the core refunds (ALMCore.sol:179-183). `D_out` is the position the split reads, not `amountsAt(S)`: the two differ by under a wei either way, and `D_out` can exceed `K_out` by under `n` (in range ranges for token1 out, plus the token0 ranges' floor differences for token0 out). With `amountsAt(S)` in place of `D_out` the inequality does not hold.

### 3.7 Stranded tokenOut (statement 5)

The core takes at least `R_out σ` of tokenOut: per range the amounts of `ceil(L_i σ)` rounded up, and the idle part rounded up (RangesLib.sol:559-571, CLMath.sol:266-270, ALMCore.sol:159-160), with token1 used in full and token0 up to the position manager's own amount for that liquidity (ALMCore.sol:179-183). A range is one position to the mint, its staked and unstaked liquidity summed (RangesLib.sol:559), so there is one ceiling per range. The vault keeps at most `Y − R_out σ`. `D_out − R_out <= n` (subtracted floors), and `K_out − R_out < n + G`, `G = 0` for token1 out (3.5).

- tokenOut leg binds, `m > (Y − r_out) N / K_out − 1`: left `< r_out + K_out / N + (K_out − R_out) Y / K_out <= 2 r_out + K_out / N + n (m + 1) / N + G Y / K_out`, using `Y / K_out < (m + 1) / N + r_out / K_out` and `K_out >= n`. For token0 out `G Y / K_out <= Y / J(S)`.
- asset leg binds, `m + 1 > (1 − g) Y N / D_out` (3.6): `Y < (m + 1) D_out / N + g Y`, so left `< g Y + ((D_out − R_out) m + D_out) / N <= g Y + n (m + 1) / N + K_out / N`. For token0 in `g Y <= Y / J(S)`, for token1 in `g = 0`.

So `Y / J(S)` enters in both directions: for token0 out through the tokenOut leg's cost, for token0 in through the asset leg's cost, where the shares the ceilings cost leave their token1 unbought by the mint. It is under a wei unless the buy exceeds `J(S)` wei of tokenOut. The sum of the reals is under `floor(Y / J(S))` plus the ceilings of the other terms. The bound has no term in `a`, `K_in` or the core's value.

### 3.8 Refund (statement 6)

The deposit keeps `r_in(T) + 3` and `c σ'` (`σ' = Y / D_out`) of tokenIn above the split, and the solve's floors leave up to one price unit of tokenIn unsold (`L Q / S^2` for token0 in, `L / Q` for token1 in). The core takes its share. `r_in(T) / r_in(s0)` is at most the ratio of the square root prices over one step, and a step is at most a bitmap word, `256 · tickSpacing` ticks: `1.013` at spacing 1, `3.6` at 100, `12.9` at 200. A step that long needs no initialized tick ahead within the word, so no range of the core holding tokenOut in range.

## 4. Constants

| Constant | Where | Sufficiency | Witness |
|---|---|---|---|
| `3` in `getRounding(T) + 3` | DepositOptimizationMath.sol:84 | 3.4 | test/fuzz/libraries/DepositOptimizationMath/PreviewDepositMargins.fuzz.t.sol:145 `test_Success_previewDeposit_OneForZero_TheBalanceMarginCoversTheStepsCeilings` and :161 `test_Success_previewDeposit_OneForZero_TheBalanceMarginCoversTheStepsCeilings_HighFee` fail at 2 ([roundingMargins.derivation.md](roundingMargins.derivation.md) 4.2) |
| `getRounding` at the step's target | DepositOptimizationMath.sol:84 | 3.4: `r_in(T) >= r_in(S)`, symbolic | none (a bound taken before the solve, not a counted constant) |
| `2n + 4` | DepositOptimizationMath.sol:71 | 3.5 | token1 in: PreviewDepositMargins.fuzz.t.sol:177 `test_Success_previewDeposit_OneForZero_ThePositionMarginCoversTheStepsFeeShare_OneRange` and :181 `..._TwoRanges` fail at `2n + 3`, :209 `test_Success_previewDeposit_OneForZero_ThePositionMarginCoversTheCostsCeilings_OneRange` and :213 `..._TwoRanges` fail at `2n + 2` (roundingMargins 4.3). Token0 in: none |
| `c` at the step test's read | DepositOptimizationMath.sol:97 | 3.5 | test/fuzz/libraries/DepositOptimizationMath/PreviewDeposit.fuzz.t.sol:328 `testFuzz_Success_previewDeposit_ZeroForOne_EndsInTheStepAtTheDepositEndingAtTheWordStart_ThinTokenOut` fails without it or one lower, :303 `testFuzz_Success_previewDeposit_ZeroForOne_PassesTheWordStartAWeiOverTheDepositEndingThere_ThinTokenOut` one higher (roundingMargins 4.3) |
| `c` at the solve's read | DepositOptimizationMath.sol:445 | 3.5 | test/fuzz/libraries/DepositOptimizationMath/GetNormalizedParameters.fuzz.t.sol:174 `testFuzz_Success_getNormalizedParameters_TheMarginAddsToThePositionsTokenIn` fails without it, one lower or one higher (roundingMargins 4.3) |
| `+ n` on the tokenIn cost | Snapshot.sol:295-297 | 3.3: covers the carry `e_in <= n` for every share count | none |
| `r_t(S)` off each balance | Snapshot.sol:301-305 | 3.3, roundingMargins 4.1 | none |

End to end: test/fuzz/ALMVaultSync/Deposit.fuzz.t.sol:772 `testFuzz_Success_deposit_MintsItsPreviewWithUncountedFees` asserts statements 3 and 5 with a fuzzed protocol fee and uncounted fee growth. test/fuzz/libraries/DepositOptimizationMath/PreviewDeposit.fuzz.t.sol:501 `testFuzz_Success_previewDeposit_OneForZero_KeepsTheMintsCostOfAThinAssetLeg` asserts statement 4 at library level.

## 5. Open

- 3.5 for token0 in is derived, not symbolic: test/symbolic/libraries/SnapshotLib.symbolic.t.sol:363 `prove_getMintAmounts_OfTheSupply_Token1InExceedsThePositionByAtMostThree` (token1 in, one range, no fee term) does not finish.
- 3.3 for one range on the tokenIn side with the carry: test/symbolic/libraries/SnapshotLib.symbolic.t.sol:275 `prove_getMintShares_BelowTheRange_TheMintOfItsSharesIsCoveredByTheBalances` does not finish. Derived in 3.3.
- 3.3 bounds one liquidity unit's token0 by `u_0(S)` on the exact amount. With the divisor `J` the rounded-up amount of a unit is up to a relative `1 / J` more. That this stays within the `+ 2` per range of `r_in` is not derived.
- 3.6 inherits the root's accuracy: the solve's price can pass the exact root by under `2^-32` of a unit, that is `ν / 2^32` wei of tokenIn with `ν` one price unit's input. The `3` of 3.4 has `1 − φ >= 0.88` wei of slack, which covers it while `ν < 0.88 · 2^32`: always for token1 in (`L < 2^128`), for token0 in while `L 2^64 < 0.88 S^2`. Beyond that the asset leg can be short by `ν / 2^32` wei. Not derived either way.
- The same slack must hold the floor of the position's tokenIn in `getNormalizedParameters` (DepositOptimizationMath.sol:447-453), `2^32 / S` wei for token0 in and `S / 2^160` for token1 in. Under a wei except at the extreme prices. At those prices not derived.
