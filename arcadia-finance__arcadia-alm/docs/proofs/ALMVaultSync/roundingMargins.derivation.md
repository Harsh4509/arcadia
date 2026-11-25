# The sync walks' rounding margins: each constant on the pool's source

Code: `src/vaults/libraries/math/DepositOptimizationMath.sol`, `MintOptimizationMath.sol`, `WithdrawOptimizationMath.sol`, `RedeemOptimizationMath.sol`, `src/vaults/types/SwapState.sol`, `Snapshot.sol`. Pool behaviour: [PoolAxioms.md](../PoolAxioms.md) (A1 to F2, C1 to C5 refer to it).

Notation: `n` the range count, `N` the supply, `s0` spot, `Q = 2^96`, `f = fee / 1e6`, `φ = f / (1 − f)`, `κ = 1 / (1 − f)`, `u_t(p)` one liquidity unit's amount of token `t` at price `p` rounded up (`ceil(Q / p)` for token0, `ceil(p / Q)` for token1), `r_t(p) = getRounding(p, t) = n (u_t(p) + 2) + 1` (Snapshot.sol:213-222).

No field of `Snapshot`, `SwapState` or `EquivalentPosition` carries a margin. Each margin is a local of the quote function that needs it and enters at the read.

## 1. Status

- Section 5 lists what is open: the withdraw model's own `2^-96` roundings against the margins' slack, and the root's accuracy inside the step where the cost binds.
- `previewWithdraw` returns at most `max(F(p), M(p)) + Δ` for every integer price `p`, `Δ` the shares that fund one more unit of `2^-96` wei of tokenOut and one more price unit of sale: section 5, proven for a core without tokenOut and liquidity on the binding step, model otherwise inside that step.
- Not every wei of every constant has a witness. Section 4 says per constant which wei is pinned by a failing test at one less, section 6 lists them. Every "fails at one less" is a run of the named test with that one constant lowered in src (seed `0x51ab`, default runs unless stated).

## 2. Per walk: the margin, where it is computed, where it enters

| Walk | Margin | Computed | Enters |
|---|---|---|---|
| deposit `computeSwap` | balance: `r_in(T) + 3`, `T` the step's target | per step, `balanceNet` (DepositOptimizationMath.sol:84) | the balance the step test and the solve read (DepositOptimizationMath.sol:92, :98, :109) |
| | position: `2n + 4` on its tokenIn | once, `roundingMargin` (DepositOptimizationMath.sol:71) | step test: `positionAmountIn + feesIn + roundingMargin` (DepositOptimizationMath.sol:97). Solve: `positionAmountIn += roundingMargin` in `getNormalizedParameters` (DepositOptimizationMath.sol:445), passed down `getAmountOut`, `getSqrtPrice`, `getQuadraticCoefficients` |
| `getMintShares` (deposit) | `r_t(S)` off each balance, `n` on the tokenIn cost | Snapshot.sol:295-305 | its own reads |
| mint `computeSwap` | `n`, and for token0 `need / J0`, on the tokenOut need | `getMintAmountOut` (MintOptimizationMath.sol:225-228) | the loop's comparison with the output bought (MintOptimizationMath.sol:58, :72) |
| `getMintAmounts` (mint) | `n` on the idle tokenIn | Snapshot.sol:269-270 | its own read |
| `previewWithdraw` | tokenOut: `r_out(s0)` and 1 per moving step | `amountOut` (WithdrawOptimizationMath.sol:62, :88) | `amountOut − state.amountOut` at each read |
| | tokenIn: `r_in(s0)` and `2 + φ` per moving step | `amountIn` (WithdrawOptimizationMath.sol:72, :86), which also takes each step's cost (:128) | passed to `getSharesForAmounts`, `getSqrtPrice`, `getQuadraticCoefficients`, `getNormalizedParameters`, and the early exit (:96) |
| | holdings: `− n` per token | `holdingsIn`, `holdingsOut` (WithdrawOptimizationMath.sol:58-59) | at the read of `amountsAt` |
| | liquidity: `+ n` | WithdrawOptimizationMath.sol:223 | at each read of `state.liquidity` for a cost |
| `previewRedeem` | none: the pool's own steps at the liquidity the burn leaves | | |
| `maxRedeem` | `2n` on the divisor, the burned liquidity rounded up | RedeemOptimizationMath.sol:118, :128 | at the reads |
| `maxWithdraw` | tokenIn: section 4.5 | `roundingMarginIn` (WithdrawOptimizationMath.sol:171-176) | left unsold: `previewRedeem(..., roundingMarginIn)` takes it off the burn's tokenIn before the sale (RedeemOptimizationMath.sol:54) |
| | tokenOut: section 4.5 | `roundingMarginOut` (WithdrawOptimizationMath.sol:179) | off the redeem's payout (WithdrawOptimizationMath.sol:183-184) |
| `maxMint`, `maxDeposit` | their own, locals | in the function | at their reads ([maxViews.derivation.md](maxViews.derivation.md) 3.8, 3.9) |

`state.amountIn` holds the modelled sale's cost alone and the withdraw walk does not read it. The walk's cost with its margin is the running local `amountIn`.

## 3. Axioms used

A1, A2, A3, B1 to B6, C1 to C5, D2, E1 to E3, F1, F2 of [PoolAxioms.md](../PoolAxioms.md), and the core's burn of `floor(L_i shares / N)` liquidity per range (RangesLib.sol:433-437).

## 4. The constants

### 4.1 `getRounding`, the burn's and the mint's rounding of one token

Rests on A3, and on the core's burn of `floor(L_i shares / N)` per range, split over the unstaked and the staked position (RangesLib.sol:433-437, :449-455).

Sufficiency. Per range the burn loses under one liquidity unit, worth at most `u_t`, and each of its two positions' amounts is rounded down once (A3, A1, A2): under 1 wei each. The idle part's floor loses under 1. So a burn releases more than its exact pro rata part less `n (u_t + 2) + 1`, for either token. The mint is the mirror with ceilings.

Witness: none for the last wei. test/fuzz/libraries/SnapshotLib/GetRounding.fuzz.t.sol:22 `testFuzz_Success_getRounding_ABurnReleasesItsPartLessTheRounding` asserts the bound, :48 `testFuzz_Success_getRounding_PerRangeAUnitAndTwoWeiPlusOneForTheIdle` the value. No test fails at one less on a safe-side claim.

### 4.2 Deposit, the balance margin `r_in(T) + 3`

Rests on B2 (C1), A1, A2, and 4.1.

Sufficiency. `getMintShares` takes `r_in(S)` off the tokenIn balance at the end price `S` (Snapshot.sol:301-305), and `r_in(T) >= r_in(S)` since `u_in` does not fall along the swap. The solve is exact in the last step's real amounts and the walk charges the pool's rounded ones: by C1 the step costs under `2 + φ` more than `κ x`. With `fee <= 100,000` (`φ <= 1/9`) that is under 3, and it exceeds 2 when `0 < frac(φ k) < φ`, so 3 is the least integer.

Witness: test/fuzz/libraries/DepositOptimizationMath/PreviewDepositMargins.fuzz.t.sol:145 `test_Success_previewDeposit_OneForZero_TheBalanceMarginCoversTheStepsCeilings` and :161 `test_Success_previewDeposit_OneForZero_TheBalanceMarginCoversTheStepsCeilings_HighFee`: a core out of range on the asset's side with dust of the asset, the step's input and fee both a hair over a whole number. Both fail with 2, with test/fuzz/libraries/DepositOptimizationMath/PreviewDeposit.fuzz.t.sol:282 `testFuzz_Success_previewDeposit_ZeroForOne_EndsInTheStepAtTheDepositEndingAtTheWordStart` and :328 its `_ThinTokenOut` variant.

### 4.3 Deposit, the position margin `2n + 4`

Rests on A3 (the mint's ceilings), F1 and F2 (the fee carry), and the walk's own `getStepFees` (SwapState.sol:160-164).

Sufficiency, per term of the mint's cost of tokenIn over the position's:
- `n`: the core's fees after the swap exceed the model's by at most one wei per range with unstaked liquidity in range (F1: the split never credits more than the exact share. F2: one floor per position over its whole uncounted growth, so the swap can carry at most one wei per position), and `getMintShares` carries `n` in its cost (Snapshot.sol:295-297).
- under `n_i + 1`: the per range ceilings of the cost (A3) against the position's one floored liquidity term.
- at most `n_0`: a range holding tokenIn alone, a ceiling against a floor.
- under `1 + w (1 + φ)`: the walk's fee share, a ceiling on a fee that is a ceiling (B2), `w <= 1` the core's part.

The supremum is `2n + 2 + w (1 + φ)`, above `2n + 3` when `1 − f < w < 1`, so `2n + 4` is the least integer.

Witness: PreviewDepositMargins.fuzz.t.sol:177 `test_Success_previewDeposit_OneForZero_ThePositionMarginCoversTheStepsFeeShare_OneRange` and :181 `..._TwoRanges` fail at `2n + 3`, :209 `test_Success_previewDeposit_OneForZero_ThePositionMarginCoversTheCostsCeilings_OneRange` and :213 `..._TwoRanges` fail at `2n + 2`. Token1 in only: the token0 mirror has no witness.

The two reads are pinned separately. Step test (DepositOptimizationMath.sol:97) without the margin or one lower: PreviewDeposit.fuzz.t.sol:328 `testFuzz_Success_previewDeposit_ZeroForOne_EndsInTheStepAtTheDepositEndingAtTheWordStart_ThinTokenOut` fails. One higher: :303 `testFuzz_Success_previewDeposit_ZeroForOne_PassesTheWordStartAWeiOverTheDepositEndingThere_ThinTokenOut` fails. Solve read (DepositOptimizationMath.sol:445) missing, one lower or one higher: test/fuzz/libraries/DepositOptimizationMath/GetNormalizedParameters.fuzz.t.sol:174 `testFuzz_Success_getNormalizedParameters_TheMarginAddsToThePositionsTokenIn` fails.

### 4.4 `previewWithdraw`

Rests on 4.1 (burn), B2, B3 (C1) and B4 (C2).

| Term | Code | Why | Axiom |
|---|---|---|---|
| `r_out(s0)` on the amount | WithdrawOptimizationMath.sol:62 | the burn releases its exact part less under `r_out` | 4.1 |
| `r_in(s0)` on the cost | WithdrawOptimizationMath.sol:72 | the same for the tokenIn the sale is funded with | 4.1 |
| `2 + φ` per moving step on the cost | WithdrawOptimizationMath.sol:86 | the pool's step costs under `κ x + 2 + φ` | C1 |
| 1 per moving step on the amount | WithdrawOptimizationMath.sol:88 | the pool's step pays over `y − 1` | C2 |
| `− n` on each holding | WithdrawOptimizationMath.sol:58-59 | `amountsAt` exceeds the exact holdings by under `n` (its subtracted floors) | none of the pool's |
| `+ n` on the liquidity for a cost | WithdrawOptimizationMath.sol:223 | the burn's liquidity floors leave under `n` more liquidity in the pool than the model's | RangesLib.sol:433-437 |

A step that does not move adds nothing (WithdrawOptimizationMath.sol:81-83): the pool's amounts between equal prices are zero (A1, A2).

Witness: the terms are pinned in value by tests of test/fuzz/libraries/WithdrawOptimizationMath/PreviewWithdraw.fuzz.t.sol that rebuild the walk's shares: the burn's rounding one lower, `2 + φ` one lower and the step's wei removed each fail four of them. A safe-side failure at one less exists for the two per-step terms through `maxWithdraw` (4.5). The others have none.

Reads. With the cost read from the state instead of the parameter: test/fuzz/libraries/WithdrawOptimizationMath/GetSharesForAmounts.fuzz.t.sol:26 `testFuzz_Success_getSharesForAmounts_TheStepsCostAndOutputAndTheSharesPayingBoth` fails, either term of `getNormalizedParameters` fails test/fuzz/libraries/WithdrawOptimizationMath/GetNormalizedParameters.fuzz.t.sol:26 `testFuzz_Success_getNormalizedParameters_TheTermsOverTheLargest` and test/fuzz/libraries/WithdrawOptimizationMath/GetQuadraticCoefficients.fuzz.t.sol:26 `testFuzz_Success_getQuadraticCoefficients_FromTheNormalizedTerms`, the solve's argument fails PreviewWithdraw.fuzz.t.sol:425 `testFuzz_Success_previewWithdraw_TheFewestSharesAtTheFirstStepsRootAndNeighbour`. Without the step's cost added to the local (WithdrawOptimizationMath.sol:128): PreviewWithdraw.fuzz.t.sol:80 `testFuzz_Success_previewWithdraw_TheBurnAndThePoolsSalePayTheAmount` fails. The early exit's read (`amountIn > holdingsIn`, WithdrawOptimizationMath.sol:96) is separated by no test.

### 4.5 `maxWithdraw`

```
M           = maxRedeem(shares)                                                                       (WithdrawOptimizationMath.sol:152)
marginIn    = r_in(s0) + 2n + ceil(κ ceil(band's input at liquidity n)) + ceil((2 + φ) steps)         (:171-176)
marginOut   = r_out(s0) + 2n + steps                                                                  (:179)
maxWithdraw = burnOut(M) + saleOut(burnIn(M) − marginIn) − marginOut      (0 when negative)           (:183-184)
```

`saleOut` is the pool's own exact input sale (`previewRedeem`: B1 to B4) of the burn's tokenIn less `marginIn`, at the liquidity the burn leaves. Let `p` be the integer price that sale ends on (B6), `k` the moving steps the model walk takes to `p`, `σ = M / N`, `L_j`, `W_j` the pool's and the core's liquidity on step `j`, `γ_j` and `ω_j` the exact tokenIn (without fee) and tokenOut per unit of liquidity over the part of step `j` up to `p`, `B0` and `A0` the model's holdings (`amountsAt − n`), `E_in`, `E_out` the supply's exact holdings at spot.

Three facts about the core, not the pool: `burnIn(M) <= σ E_in` and `burnOut(M) <= σ E_out` (floors only), and `E_t <= amountsAt_t + n = (B0 or A0) + 2n`.

Claim: `previewWithdraw(maxWithdraw) <= M`. By the lemma of section 5, `previewWithdraw(maxWithdraw) <= max(F(p), M(p)) + Δ`. The two parts below show `F(p) <= M` and `M(p) <= M`, each with the slack of its margin. The claim follows when the funding slack also holds `Δ`: section 5 states that slack in wei, and it is open in the same state as the `2^-96` roundings.

Funding. The reduced sale ends at `p` having consumed its whole input (C3. It cannot reach the band, since `maxRedeem` sizes `M` so that the full sale of `burnIn(M)` fills inside it: its walk charges each step at a liquidity no higher than the burn leaves, and divides by the supply's tokenIn plus `2n`. B6 moves the price monotonically in the input). Its liquidity on step `j` is at least `L_j − σ W_j`, and by B2 and B3 each step's charge is at least `κ` times its exact input. So

```
Σ κ (L_j − σ W_j) γ_j  <=  burnIn(M) − marginIn  <=  σ (B0 + 2n) − marginIn.
```

The model's cost at `p` is `r_in + k (2 + φ) + Σ κ (L_j + n) γ_j` and its budget `σ (B0 + Σ κ W_j γ_j)`, each to within `3 * 2^-96` wei per step. Cost less budget is at most

```
r_in + k (2 + φ) + n κ Σ γ_j + 2n σ − marginIn  <=  0
```

because `Σ γ_j` up to `p` is at most the band's exact input per unit of liquidity, `σ <= 1` and `k <= steps` (4.6). So the funding shares are at most `M`.

Payout. By B4 the real sale pays at most `Σ l_j ω_j` with `l_j <= L_j − σ W_j + e_j`, `e_j` the liquidity the burn's floors left in the pool on step `j`. That liquidity was not burned, so the burn released at least `e_j ω_j` less than `σ E_out` on the same ranges (a range in range on step `j` holds at least `ω_j` of tokenOut per unit at spot). Hence the real payout is at most `σ (A0 + 2n) + Σ (L_j − σ W_j) ω_j`. The model at `p` pays `σ A0 + Σ (L_j − σ W_j) ω_j`, to within `5 * 2^-96` wei per step, and asks for `maxWithdraw + r_out + k`. So the paying shares are at most `M` when

```
marginOut  >=  r_out + k + 2n σ,
```

which `r_out + steps + 2n` meets.

The per-step coefficient of `marginOut` is 1: the model adds one wei per moving step to the amount (4.4) and that is all `marginOut` has to mirror. The model's other per-step terms on the tokenOut side (`step.amountOut + 2` and the ceiling of the core's part, WithdrawOptimizationMath.sol:244-248) are in units of `2^-96` wei, since the walk's amounts carry 96 binary digits. They are covered by the slack of section 5, not by a wei per step. These bounds are in wei, not in price units: one unit of `2^-96` wei of token0 is `P / L` price units, `P` the raw price (section 5).

The solve's target `amountOut − state.amountOut + 1` (WithdrawOptimizationMath.sol:105) enters `getSqrtPrice` only. Every `getSharesForAmounts` evaluation and the early exit read the amount without it, so what the model asks at `p` is unchanged.

Nothing is converted at spot, so no term depends on what one price unit trades.

Witness: test/fuzz/libraries/WithdrawOptimizationMath/MaxWithdraw.fuzz.t.sol:82 `testFuzz_Success_maxWithdraw_ItsWithdrawBurnsExactlyTheSharesOverTheMostSteps`. Token0 in, no ranges, pool liquidity a multiple of `2^96` (each step's token1 output is a whole number, A1), half the supply redeemed out of even buffers (the burn loses nothing), a sale of two steps. There `previewWithdraw(maxWithdraw)` equals the shares. It fails with `marginOut` one wei lower and with the step bound one lower. With `2 + φ` lowered to `1 + φ` in `marginIn` it fails at 1,000 runs and passes at the default runs: that term's pin depends on the fuzzed remainder of the sale. No failing test at one less: either `2n`, `r_in`, the band's input at liquidity `n`, and the last wei of `marginIn`.

### 4.6 The step bound `ceil(d / spacing) + 1`

`d = slot0.tick − T(limit)` for zeroForOne and `T(limit) − slot0.tick` for the other direction, `T(x) = getTickAtSqrtRatio(x)`, `limit` the swap cost limit. Code: `ticks = max(d, 0)`, `steps = ticks.divUp(tickSpacing) + 1` (WithdrawOptimizationMath.sol:162-166).

Rests on C4 (the pool's tick), C5 and E1 to E3 (stops on the spacing grid), D2.

Sufficiency. A moving step of the model walk to a price `p` at or inside the limit ends on a spaced tick `c` whose price lies strictly between spot and `p`, or is the step that holds `p`. ZeroForOne: `sqrt(c) > limit >= sqrt(T(limit))` gives `c >= T(limit) + 1`, and `sqrt(c) < spot` gives `c <= slot0.tick` in both cases of C4 (when the tick is `T(spot) − 1`, `c = T(spot)` has the price of spot and the step does not move). OneForZero: `sqrt(c) > spot` gives `c >= slot0.tick + 1` (E3 returns a tick above the pool's), and `sqrt(c) < limit` gives `c <= T(limit)`. Either way the spaced ticks lie in an interval of `d` consecutive integers: at most `ceil(d / spacing)` of them, plus the step that holds `p`. A burn can only remove initialized ticks, so the real sale takes no more steps than the model.

`d >= −1` always, and `−1` only with an empty band on a tick reached from above: `d = −1` needs the pool's tick one below spot's (C4) and the limit at spot, which `getSwapCostLimit` gives only for a zero deviation. There `max(d, 0)` gives 1 step where no step moves (test/fuzz/libraries/WithdrawOptimizationMath/MaxWithdraw.fuzz.t.sol:180 `testFuzz_Success_maxWithdraw_OnATickReachedFromAboveWithAnEmptyBand`).

Exactness. The count is reached whenever every spaced tick of the interval is a stop. Word ends are spaced ticks (E2, E3), so they add no step of their own.

Witness: the test of 4.5. Tick spacing 10, spot in tick 3, the limit 7 to 8 ticks below: `d` is 7 or 8, `ceil(d / 10) + 1 = 2`, and the sale takes two steps (to the word end at tick 0, then inside). With the bound one lower the test fails. One higher passes: the safe side.

## 5. What the constants do not cover

- Token0's double rounding is not a residue. A2 shows `ceil(ceil(N / b) / a) = ceil(N / (a b))` and the same for floors: the pool's token0 amounts are the exact amounts rounded once, so every place that counts 1 wei for a token0 rounding (the `2 + φ` per step for token0 in, the wei per step for token0 out, `getRounding` for token0) counts enough, on the integer results.
- The withdraw model's own step amounts carry 96 binary digits and round there: the cost of a step is up to 2 units of `2^-96` wei over exact (a ceiling less a floor, WithdrawOptimizationMath.sol:228-229), the per-step margin up to 1, the core's credits up to 3 under. The proof of 4.5 needs the margins' slack to hold `6 k * 2^-96` wei. That slack is zero only when every one of these is exact at once: `(2 + φ) steps` a whole number (a fee of zero does it), the burn's amounts whole, the band's input at liquidity `n` whole and reached, `M` the whole supply. No such state is constructed, and it is not proven unreachable. Open.
- The lemma of 4.5. Let `G(p) = max(F(p), M(p))` be the shares `getSharesForAmounts` returns at an integer price `p` (`F` when the cost binds, `M` when it does not, `type(uint256).max` when neither the cost binds within the supply nor the holdings left cover the amount left, WithdrawOptimizationMath.sol:259-261). `previewWithdraw` evaluates `G` at every step end up to the step where the cost binds at the end, and at two prices inside that step: the solve's price `r` for the target `a + 1` (`a` the amount left at the step's start, in units of `2^-96` wei) and one neighbour (WithdrawOptimizationMath.sol:101-125). It returns the least of them.

  Before and past the binding step. `M` falls along a step while the amount is payable (`W amountOutLeft <= L holdingsOut`), `F` rises while the cost is fundable (`holdingsIn >= cost W / (L + n)`). For `p` in a step before the binding one, that step's end is no worse than `p`. For `p` past the binding step, the binding step's end is no worse.

  Inside the binding step, a core without tokenOut and without liquidity on the step (`A = 0`, `W = 0`). `G(p)` is `type(uint256).max` below the least paying price and `F(p)` from it on, with `F` rising. For token0 out the least paying price is `ceil(x)`, `x = (s R + d) / (R − a)`, `R = floor(L 2^192 / s)`, `d = L 2^192 mod s`. The quadratic's crossing for the target `a` is `s R / (R − a) = x − d / (R − a)`: `d / (R − a)` price units short of `x`, up to about `P / (L (1 − a / R))`, so a pair around it can miss `x`. The crossing for `a + 1` is `p̂ = s R / (R − a − 1) >= x`, and the root or its neighbour is a paying price `c` with `ceil(x) <= c < p̂ + 1`, given the root within half a price unit ([QuadraticMath/getRoot.derivation.md](../QuadraticMath/getRoot.derivation.md) section 6). So for every `p`

  ```
  previewWithdraw  <=  F(c)  <=  G(p) + Δ,      Δ = F(c) − F(ceil(x)),
  ```

  and `Δ` is the shares funding at most `p̂ + 1 − x <= 1 + s R / ((R − a) (R − a − 1))` price units of sale: under `κ (L + n) (1 + s R / ((R − a) (R − a − 1)))` units of `2^-96` wei of tokenIn, which is the cost of one unit of `2^-96` wei of token0 at the end price plus one price unit. For token1 out the output `L (s − p)` is exact, the least paying price is `floor(s − a / L)`, `p̂ = s − (a + 1) / L`, and `Δ` funds under `1 + 1 / L` price units.

  So the claim of 4.5 needs the funding inequality to hold with `Δ`'s cost to spare:

  ```
  marginIn − (r_in + k (2 + φ) + n κ Σ γ_j + 2n σ)  >=  κ (L + n) (1 + s R / ((R − a) (R − a − 1))) 2^-96  +  6 k 2^-96      wei.
  ```

  The right side is under one wei unless `L + n` or the end's raw price exceeds `2^96 / κ`. The left side is zero only in the state of the previous point. Open in that state, proven elsewhere for `A = 0`, `W = 0`.

  Inside the binding step, the other cores (`A > 0` or `W > 0`). `G` is finite on both sides of the crossing where the holdings left cover the amount left, and the pair around the root holds the integer optimum of the real curves or the price next to it. Model: the pair's rounded evaluation (`step.amountIn − 2` floored and `step.amountOut + 2` ceiled for the core's parts, WithdrawOptimizationMath.sol:244-248) moves the paying shares by under one share while `holdingsOut >= 1` wei, and the `holdingsOut = 0`, `W > 0` state exceeds `Δ` only for a dust core (getRoot.derivation.md section 5). Near the quadratic's double root (`a + 1` near `R`) the state is degenerate (getRoot.derivation.md section 5). Open: the normalization's accuracy ([WithdrawOptimizationMath/getNormalizedParameters.derivation.md](../WithdrawOptimizationMath/getNormalizedParameters.derivation.md)).

- The constant `+ 1` on the solve's target (WithdrawOptimizationMath.sol:105). Sufficiency: the display `p̂ >= x` above. Least: amounts are integers in units of `2^-96` wei, and with the target `a` both candidates miss whenever `d / (R − a) > 3/2`. No witness.

## 6. Failing tests at one less

Seed `0x51ab`, default runs.

| Constant lowered | Failing tests |
|---|---|
| deposit balance margin 3 to 2 | PreviewDepositMargins.fuzz.t.sol:145, :161, PreviewDeposit.fuzz.t.sol:282, :328 |
| deposit position margin to `2n + 3` | PreviewDepositMargins.fuzz.t.sol:177, :181, PreviewDeposit.fuzz.t.sol:328 |
| deposit position margin to `2n + 2` | the three above and PreviewDepositMargins.fuzz.t.sol:209, :213 |
| deposit step test's read one lower | PreviewDeposit.fuzz.t.sol:328 |
| deposit solve's read one lower | GetNormalizedParameters.fuzz.t.sol:174 (deposit), PreviewDepositMargins.fuzz.t.sol:177, :181 |
| `previewWithdraw` burn rounding one lower | four tests of PreviewWithdraw.fuzz.t.sol (4.4) |
| `previewWithdraw` `2 + φ` to `1 + φ` | the same four |
| `previewWithdraw` wei per step removed | the same four and PreviewWithdraw.fuzz.t.sol:80 |
| `maxWithdraw` step bound one lower | MaxWithdraw.fuzz.t.sol:82 and two tests that rebuild the margins |
| `maxWithdraw` `marginOut` one lower | the same three |
| `maxWithdraw` `marginIn` `2 + φ` to `1 + φ` | none at default runs, MaxWithdraw.fuzz.t.sol:82 at 1,000 runs |

Without a failing test at one less: `getRounding`'s last wei, either `2n` of `maxWithdraw`, its `r_in` and the band's input at liquidity `n`, the token0 side of the deposit's position margin, `previewWithdraw`'s `− n` and `+ n`, the early exit's read.
