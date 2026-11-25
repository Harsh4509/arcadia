# ALMVaultSync max views: the plain call of each view's amount fills its swap within the swap-cost band

Code: `src/vaults/ALMSyncExtension.sol` `maxMint` (:112-125), `maxDeposit` (:132-141), `maxRedeem` (:148-157), `maxWithdraw` (:164-173), `_maxShares` (:182-196), `src/vaults/libraries/math/RedeemOptimizationMath.sol` `previewRedeem` (:40-83), `maxRedeem` (:98-130), `src/vaults/libraries/math/WithdrawOptimizationMath.sol` `previewWithdraw` (:44-132), `maxWithdraw` (:146-185), `src/vaults/libraries/math/MintOptimizationMath.sol` `computeSwap` (:42-102), `maxMint` (:141-202), `src/vaults/libraries/math/DepositOptimizationMath.sol` `computeSwap` (:58-125), `maxDeposit` (:167-237), `src/vaults/types/Snapshot.sol` `getSwapCostLimit` (:92-115), `getBurnAmounts` (:342-380), `src/vaults/ALMVaultSync.sol` `_deposit` (:118-130), `_mint` (:170-184), `_swapAndMint` (:198-254), `_withdraw` (:345-356), `_burnAndSwap` (:366-398), `src/core/ALMCore.sol` `_burn` (:278-340), `src/core/libraries/state/RangesLib.sol` `removeLiquidity` (:408). Pool behaviour: [PoolAxioms.md](../PoolAxioms.md).

Notation: `s0` spot, `s_E` the band's edge in the swap's direction (`getSwapCostLimit`), `L` a step's active liquidity, `T` a step's target, `f = fee / 1e6`, `b = maxSwapCostBps / 1e4`, `n` the range count, `N` the supply, `Q = 2^96`. `burnIn(S)`, `burnOut(S)` the tokenIn and tokenOut a burn of `S` shares releases. `E` the exact tokenIn of the whole supply at spot (ranges and idle), `B = getBurnAmounts(s0, N).amountIn` (RedeemOptimizationMath.sol:104). "Fills": an exit's sale consumes the whole `burnIn` (ALMVaultSync.sol:393), an entry's buy delivers the whole `amountSwapOut` (ALMVaultSync.sol:230).

Domain: the pool's `fee()` equals `beforeSwapFee` for the vault and no after-swap fee is charged (the deployed `DynamicSwapFeeHook` answers `getBeforeSwapFee` from the caller and block state of `beforeSwap` and charges no after-swap fee, docs/audit-doc.md 6.4, Fee reads and swap hooks). The band lies inside `(MIN_SQRT_PRICE, MAX_SQRT_PRICE)` (spot within the band of the price bounds is degenerate, docs/audit-doc.md 6.4, Limit views that revert).

## 1. Statement

| View | Statement | Status |
|---|---|---|
| `maxRedeem` | the plain redeem of `maxRedeem(owner)` fills | proven (3.5) |
| `maxWithdraw` | the plain withdraw of `maxWithdraw(owner)` burns at most `maxRedeem(owner)` shares, fills, and pays at least the amount | proven for `A = 0`, `W = 0`, model for `A > 0` or `W > 0` (3.7) |
| `maxMint` | the plain mint of `maxMint(receiver)` fills | model (3.9), the token0 terms derived in the same frame ([MintOptimizationMath/maxMint.derivation.md](../MintOptimizationMath/maxMint.derivation.md)) |
| `maxDeposit` | the plain deposit of `maxDeposit(receiver)` fills | derived given the solve's accuracy, `getRoot`'s guard band open ([DepositOptimizationMath/maxDeposit.derivation.md](../DepositOptimizationMath/maxDeposit.derivation.md)) |
| zero | at a zero view, `deposit(0)` and `mint(0)` return 0, and `withdraw(0)` and `redeem(0)` burn nothing, on a quotable, unpaused vault | proven (3.10) |
| past the band | an entry whose buy passes the band reverts `InsufficientOutput`, an exit whose sale passes it reverts `InsufficientOutput`, and with `maxSwapCostBps * 100 <= fee` a plain call that swaps reverts the pool's `SPL` | proven (3.11) |
| loss | a swap inside the band loses less than `b` of its input's value at spot on every part of it | proven (3.12) |

## 2. Axioms and bounds used

- A1, A2 (amounts, one rounding each), B1 to B7 (steps), D1, D2 (the loop, its targets), E1 to E3, C4 (the tick), G5.
- `CLMath.getBand` (CLMath.sol:108-121) with the deviation of Snapshot.sol:112: `s_E = ceil(s0 / (1 + δ))` below, `floor(s0 (1 + δ))` above, `δ = (b − f) / 2` floored at 0 ([CLMath/getBand.md](../CLMath/getBand.md), symbolic).
- `ALMCore._burn` with `RangesLib.removeLiquidity`: per range `floor(L_i S / N)` liquidity (RangesLib.sol:433-437), the unstaked side first (RangesLib.sol:449-455), each side's amounts floored, plus `floor((buffer + net fees) S / N)` (ALMCore.sol:325-330). `SnapshotLib.getBurnAmounts` computes the same from the same reads (Snapshot.sol:354-378).
- `DEAD_SHARES` are held by `address(1)` (ALMAdminExtension.sol:415), so every owner's balance is below `N`.
- `previewWithdraw`'s margins and `maxWithdraw`'s: [roundingMargins.derivation.md](roundingMargins.derivation.md) 4.4 to 4.6.

## 3. Proof

### 3.1 Lemma: an exact input fills iff it is at most the band's capacity

Step from `s` to `T` at `L` with `R` left (B1 to B3): `R' = floor(R (1e6 − fee) / 1e6)`, `A_T` the rounded-up input to `T`. If `R' >= A_T` the step reaches `T` and consumes `C_T = A_T + ceil(A_T f / (1 − f))`, and `R >= C_T` (`R >= A_T / (1 − f)`, integers). Else it consumes exactly `R` and ends before `T`.

So an exact input `X` fills with the band as the limit iff `X <= C_E = Σ C_T` over the steps from `s0` to `s_E`: earlier steps consume `C_T` each. On the last, `R <= C_T` is consumed in full (inside, or `R = C_T` at `s_E`), and `R > C_T` reaches `s_E` with `R − C_T` left, where the loop stops (D1).

### 3.2 Lemma: an exact output fills iff it is at most the band's floored output

With `r` left, a step's floored output to `T` is `Y_T` (B4). If `r >= Y_T` the step reaches `T` and pays `Y_T`. Else it ends at `getNextSqrtPriceFromOutput(r)`, which passes the exact price for `r` (B7): `s − ceil(r Q / L)` for token1 out, `ceil(L Q s / (L Q − r s))` for token0 out. The exact output there is at least `r`, and the pool's output is that exact amount rounded down once (A1, A2), so at least `r`, capped at `r` (B5). The end price is at or before `T`, since `r < Y_T` makes the exact price for `r` lie before `T` and `T` is an integer.

So an exact output `y` of either token fills with the band as the limit iff `y <= Y_E = Σ Y_T` over the steps to `s_E`.

### 3.3 The band at execution is the view's

Entries clamp the limit to `snapshot.getSwapCostLimit` (ALMVaultSync.sol:214-218), the view's own function on the same snapshot. Exits use `getSwapCostLimit(spot, fee(), getMaxSwapCostBps(), ·)` (ALMVaultSync.sol:385-389) with `quotable`'s spot (ALMVaultSync.sol:371), the pool's `slot0` price, read in the same transaction before the burn, which does not move the price. The views read the same price, `maxSwapCostBps` and (domain) fee.

### 3.4 The release

`burnIn(S) = getBurnAmounts(s0, S).amountIn` (section 2). Each term is a floor of a nondecreasing map of `S`, so `burnIn` and `burnOut` are nondecreasing in `S`. Linearity of the exact amounts gives `burnIn(S) <= S E / N`. At `S = N` the liquidity floors are exact and the idle floor is exact, and each range loses under 1 wei on each of its two sides: `E < B + 2n` (`E = B` when `n = 0`).

### 3.5 `maxRedeem`

The view walks the pool's steps to `s_E` with `MetadexSwapMath.computeSwapStep` and an unbounded input, at liquidity `L_k − ceil(W_k H / N)` (RedeemOptimizationMath.sol:110-124), `W_k` the core's liquidity in range on the step and `H` the owner's balance, and returns `min(H, floor(C_walk N / (B + 2n)))` (RedeemOptimizationMath.sol:127-129), or `H` when `B = 0` (RedeemOptimizationMath.sol:105).

- Capacity. A burn of `S <= H` removes `Σ floor(L_i S / N) <= ceil(W_k H / N)` from the step's liquidity, so the real pool has at least the walk's liquidity on every step. As `S < N`, every range keeps liquidity, so no tick of the walk is uninitialized by the burn and the steps coincide. `C_T` rises with `L`, so `C_walk <= C_E` of the real sale.
- Release. For `S = floor(C_walk N / (B + 2n))`: `burnIn(S) <= S E / N <= S (B + 2n) / N <= C_walk`. For `S = H` the smaller: the same chain with `H`.
- `B = 0`: `burnIn(S) <= burnIn(N) = 0` (3.4), no sale.

By 3.1 the sale fills. The walk stops at the first step with zero liquidity (RedeemOptimizationMath.sol:111). The real sale and `previewRedeem` (RedeemOptimizationMath.sol:62) walk through a zero-liquidity gap to the liquidity past it, so behind a gap the real sale has more capacity than `C_walk`, and the view stays on the safe side.

### 3.6 `previewRedeem`

`previewRedeem(S, 0)` releases `getBurnAmounts(s0, S)` (RedeemOptimizationMath.sol:50-51), the core's release (3.4), and sells `burnIn(S)` with the pool's own step function at the pool's liquidity less `Σ floor(L_i S / N)` of the ranges in range (RedeemOptimizationMath.sol:62-71), recomputed at the core's edges (RedeemOptimizationMath.sol:73-78): the pool after the burn, step for step. So when the plain redeem's sale fills, it pays `previewRedeem(S, 0)`. With a margin `previewRedeem(S, k)` sells `burnIn(S) − k` (RedeemOptimizationMath.sol:54).

### 3.7 `maxWithdraw`

`maxWithdraw = previewRedeem(M, marginIn) − marginOut`, `M = maxRedeem(H)` (WithdrawOptimizationMath.sol:152, :183-184, roundingMargins.derivation.md 4.5 for the margins and 4.6 for the step bound). The plain withdraw burns `S' = previewWithdraw(maxWithdraw)` (ALMVaultSync.sol:350-352).

- `S' <= M`: roundingMargins.derivation.md 4.5, given the lemma of its section 5 (the fewest shares of the binding step lie in the candidate pair).
- Fill: `burnIn(S') <= burnIn(M) <= C_E` (3.4, 3.5), so the sale fills (3.1).
- Payout: the plain withdraw requires the payout to cover the amount (ALMVaultSync.sol:355). That is `previewWithdraw`'s guarantee, roundingMargins.derivation.md 4.4.

The candidate pair. In the binding step `previewWithdraw` solves with the target `amountOut − state.amountOut + 1` (WithdrawOptimizationMath.sol:105), one unit of `2^-96` wei over the amount left `a`. With tokenOut token0 and `holdingsOut = 0`, the walk's output to a price `p` is `R − ceil(L 2^192 / p)`, `R = floor(L 2^192 / s)`, `d = L 2^192 mod s`, so it pays `a` iff `p >= x = (s R + d) / (R − a)`. The quadratic's crossing is at `s R / (R − a)`, short of `x` by `d / (R − a)` price units, up to about `P / L` units with `P` the raw price. Solving for `a + 1` puts the crossing at `p̂ = s R / (R − a − 1) >= x`. So the root or its neighbour (WithdrawOptimizationMath.sol:118-121) pays whenever the root's error is under half a price unit, which getRoot.derivation.md section 3 gives away from the quadratic's double root. The double root is degenerate (getRoot.derivation.md section 5).

Thin pool, `A > 0` or `W > 0` (model). The argument, in three steps:

1. Within a step the core's in-range liquidity pays out at most what it holds, `W_out δ <= A_true`: the step ends at or before the core's edge, an initialized tick (SwapState.sol:107-116). The model's `A` is `A_true` less at most `n` wei (WithdrawOptimizationMath.sol:58-59).
2. With `holdingsOut >= 1` wei at a candidate, the rounded evaluation (WithdrawOptimizationMath.sol:246, :248) moves `amountOutLeft` and `holdingsOut` by at most `2 + 2 W / L + 1` units of `2^-96` wei, so the paying shares move by under `N 2^-94 / holdingsOut`: under one share.
3. With `holdingsOut = 0` and `W > 0` the root sits at `α / (1 − σ W / L)` instead of the least paying `α = a / R`, `σ` the burnt fraction. That state exists only within `n` wei of the core's edge, so the extra sale is at most `n σ L / (L − σ W)` wei of tokenOut. It exceeds the margins only when `W^2` is below about `n L` over the range's relative width: a dust core.

An exact integer model of the walk and the pool's swap finds no withdraw of at most `maxWithdraw` that fails to pay or burns more than `maxRedeem`.

### 3.8 `maxDeposit`

The deposit's buy is an exact output of the pool's floored outputs to its end price `P`, with that cost (mint.derivation.md 3.3), so by 3.2 the plain deposit fills iff `P` lies at or before `s_E`.

Branches that are proven: with no pool liquidity the deposit's walk takes no step and no swap runs (DepositOptimizationMath.sol:77, :195-197). When the walk runs out of pool liquidity before its limit (DepositOptimizationMath.sol:226), every deposit's walk ends where the liquidity ends, before `s_E`.

The cap branch: the view walks to `s_E` moved one unit inward (clipped to spot, DepositOptimizationMath.sol:208-210) and caps the assets at `getBalanceIn(cost, output, positionIn − 1, positionOut + 1)` at that limit (DepositOptimizationMath.sol:229-236). That the deposit of at most this cap solves to a price at or before the walk's limit: [DepositOptimizationMath/maxDeposit.derivation.md](../DepositOptimizationMath/maxDeposit.derivation.md), given the solve's accuracy and outside `getRoot`'s guard band. The branch that returns the room's value with no tokenOut at spot swaps nothing (its section 3.6).

Shares: a deposit whose buy fills may still mint 0 shares and revert `ZeroShares` in the states of docs/audit-doc.md 6.4, Limit views that revert: a swap that buys less than one price step, or a swap stopped at the band when one aLP's tokenOut exceeds the tokenOut the pool sells within it ([DepositOptimizationMath/maxDeposit.md](../DepositOptimizationMath/maxDeposit.md) statement 6).

### 3.9 `maxMint`

The mint's buy is an exact output with the end price `P` of `computeSwap(S)` as its limit, clamped to `s_E` (ALMVaultSync.sol:214-218). If `P` lies at or before the view's limit `ℓ` (the nearer of `s_E` and the TWAP band's edge, ALMSyncExtension.sol:115, MintOptimizationMath.sol:151-153), its output is at most the view's `Y_ℓ`: the full steps coincide and the last step's request is at most its floored output to `P`, at most that to `ℓ` (3.2). So the mint fills when `P` lies at or before `ℓ`, and the core's TWAP check at `P` passes.

Branches that are proven: no tokenOut need at spot returns `type(uint256).max` and the mint buys nothing (MintOptimizationMath.sol:147-148). A walk summing 0 returns 0 (MintOptimizationMath.sol:172). No need at the walk's end, mint.derivation.md 3.4 (MintOptimizationMath.sol:175-176). For token0 out, `J0 = 0` returns 0 (MintOptimizationMath.sol:185).

The general branch returns `floor((Y_ℓ − R) N / (C_ℓ + 1))` (MintOptimizationMath.sol:201) with `R = getRounding(s0, tokenOut) + steps + 2` (MintOptimizationMath.sol:179, :195) plus, for token0 out, `n (2 B_u + ceil(B_u / J0) + 1) + 2` (MintOptimizationMath.sol:190-191), and `C_ℓ` the whole supply's need at the walk's end plus, for token0, `2 A + ceil(A / J0)` (MintOptimizationMath.sol:187-188). Here `J0 = floor(s0^2 / Q)`, `A = ceil(C_0 / J0)` with `C_0` the whole supply's need at spot, and `B_u = ceil(ceil(Q / s0) / J0)`. That `computeSwap` of these shares ends at or before `ℓ` (model, token1 out, no core edge between spot and `ℓ`):

- In the step that holds `ℓ` the mint's request is `ceil((need_j − bought_j) L / (L + K))` (MintOptimizationMath.sol:78-81), `K` the mint's in-range liquidity, and the pool ends at or before `ℓ` iff the request is at most the floored output to `ℓ`, `y_ℓ` (3.2). As `y_ℓ K / L >= K ω_ℓ − K / L`, `ω` the exact tokenOut per unit of liquidity, it suffices that `need_j − K ω_ℓ + K / L <= bought_j + y_ℓ = Y_ℓ`.
- Each earlier step's drop is floored (MintOptimizationMath.sol:63-69, :85): `need_j <= need_0 − Σ exact drops + (k − 1)` over `k` steps. Per range the liquidity ceiling adds under one unit, worth at most `u_out`, and the amount's and the idle's ceilings under 1 each (Snapshot.sol:255-272), so `mintOut(s0, m) − K ω_total <= (m / N) C_ℓ + n (u_out + 1) + 1`.
- `m (C_ℓ + 1) <= (Y_ℓ − R) N` (MintOptimizationMath.sol:201) gives `(m / N) C_ℓ <= Y_ℓ − R − m / N`, and `K <= W m / N + n_in` with `n_in <= W <= L` gives `K / L <= m / N + 1`. So the claim holds when `R >= n (u_out + 2) + 1 + (k − 1) + 1`, and the code's `R = n (u_out + 2) + 1 + k + 2` (MintOptimizationMath.sol:179, :195) leaves 2 wei to spare.
- At a core edge the need is recomputed (MintOptimizationMath.sol:94-99) and the chain restarts with fewer floors. Degenerate exception: a mint that reaches a core edge unfinished buys one more wei past it (MintOptimizationMath.sol:98). If `ℓ` lies within one wei of pool output past that edge, the buy passes `ℓ`. With the swap-cost band as `ℓ` the band's least nonzero width is `5e-7` of the price, so only a TWAP band edge can sit there, and in the exact integer model those states return `maxMint = 0`.

An exact integer model finds no `mint(maxMint)` that fails, and its least slack `Y_ℓ − amountSwapOut` is the 2 wei derived. Token0 out: the `J0` terms are sufficient with at least 2 wei to spare, [MintOptimizationMath/maxMint.derivation.md](../MintOptimizationMath/maxMint.derivation.md). The tokenIn side of the mint is mint.derivation.md.

### 3.10 Zero flows

`_deposit` and `_mint` return 0 for 0 before the snapshot (ALMVaultSync.sol:120, :172). `previewWithdraw` returns 0 for 0 (WithdrawOptimizationMath.sol:50), so `withdraw(0)` runs `_burnAndSwap(0)`: `_burn` has no zero guard, `removeLiquidity` removes nothing (it collects and skips a range whose delta is 0, RangesLib.sol:440-447), the payout is `floor(0) = 0`, and `burnIn = 0` skips the sale (ALMVaultSync.sol:384). `redeem(0)` is the same path. `_burnAndSwap` still checks `quotable` (ALMVaultSync.sol:371-372) and the vault `whenNotPaused`, hence the domain of the statement.

### 3.11 Past the band

Entry: the pool stops at `s_E` with output below the request (3.2) and `_swapAndMint` reverts `InsufficientOutput` right after the swap, before the core's pull (ALMVaultSync.sol:230). Exit: the sale stops at `s_E` with input left (3.1) and `_burnAndSwap` reverts `InsufficientOutput` (ALMVaultSync.sol:393). With `maxSwapCostBps * 100 <= fee` the deviation is 0 (Snapshot.sol:112) and `getBand` returns spot, which the pool rejects as a limit (D1, `SPL`). The views return 0 there (a walk with its target at spot pays and costs nothing).

### 3.12 The loss inside the band

ZeroForOne, a step from `s_a` to `s_b` at any liquidity returns `(1 − f) s_a s_b / s0^2` of its input's value at spot. OneForZero, `(1 − f) s0^2 / (s_a s_b)`. At the edge `s_E = s0 / (1 + δ)` or `s0 (1 + δ)` (rounded inward) the marginal loss is at most `c_E = 1 − (1 − f) / (1 + δ)^2`, and `(1 + δ)^2 (1 − b) = 1 − f − (b − f) b + (b − f)^2 (1 − b) / 4 < 1 − f` since `(b − f)(1 − b) < 4 b`, so `c_E < b`.

## 4. Constants

| Constant | Where | Sufficiency | Witness |
|---|---|---|---|
| `2n` on the divisor | RedeemOptimizationMath.sol:128 | 3.4, 3.5: two sides per range lose under 1 wei each at the full supply, the idle loses nothing there | none (test/fuzz/libraries/RedeemOptimizationMath/MaxRedeem.fuzz.t.sol:61 `testFuzz_Success_maxRedeem_TheSaleToTheRangesEdgeAsThePoolsOnlyLiquidity` pins the value) |
| `ceil(W_k H / N)` | RedeemOptimizationMath.sol:118 | 3.5 | none |
| `marginIn`, `marginOut`, the step bound | WithdrawOptimizationMath.sol:162-179 | roundingMargins.derivation.md 4.5, 4.6 | there |
| `+ 1` on the solve's target | WithdrawOptimizationMath.sol:105 | 3.7 | none |
| one unit inward, `positionIn − 1`, `positionOut + 1` | DepositOptimizationMath.sol:208-210, :235 | [DepositOptimizationMath/maxDeposit.derivation.md](../DepositOptimizationMath/maxDeposit.derivation.md) section 4 | none |
| `R`, `+ 1` on `C_ℓ` | MintOptimizationMath.sol:179, :195-201 | 3.9 (model): 2 wei to spare, token1 out | none |
| the token0 terms | MintOptimizationMath.sol:182-192 | [MintOptimizationMath/maxMint.derivation.md](../MintOptimizationMath/maxMint.derivation.md) section 4: at least 2 wei to spare | none |

Tests asserting the statements:
- test/fuzz/ALMVaultSync/MaxRedeem.fuzz.t.sol:347 `testFuzz_Success_maxRedeem_ItsRedeemSucceedsWithinTheSwapCost`, test/fuzz/ALMVaultSync/Redeem.fuzz.t.sol:481 `testFuzz_Success_redeem_MaxRedeemOfATinyHolder`.
- test/fuzz/ALMVaultSync/MaxWithdraw.fuzz.t.sol:398 `testFuzz_Success_maxWithdraw_ItsWithdrawFillsAndPaysTheAssets`, test/fuzz/ALMVaultSync/Withdraw.fuzz.t.sol:563 `testFuzz_Success_withdraw_MaxWithdrawOfATinyHolder`.
- test/fuzz/ALMVaultSync/MaxMint.fuzz.t.sol:583 `testFuzz_Success_maxMint_ItsMintSucceedsWithinTheSwapCost`, test/fuzz/libraries/MintOptimizationMath/MaxMint.fuzz.t.sol:88 `testFuzz_Success_maxMint_TheBuyEndsAtOrBeforeTheLimit`, test/fuzz/ALMVaultSync/Mint.fuzz.t.sol:745 `testFuzz_Success_mint_MaxMintOfATinyRoom`.
- test/fuzz/ALMVaultSync/MaxDeposit.fuzz.t.sol:291 `testFuzz_Success_maxDeposit_ItsDepositSucceedsWithinTheSwapCost`, test/fuzz/libraries/DepositOptimizationMath/MaxDeposit.fuzz.t.sol:120 `testFuzz_Success_maxDeposit_ItsDepositMintsAtMostTheSharesWithinTheLimit`, test/fuzz/ALMVaultSync/Deposit.fuzz.t.sol:873 `testFuzz_Success_deposit_MaxDepositOfATinyRoom`.
- Zero flows: test/fuzz/libraries/WithdrawOptimizationMath/PreviewWithdraw.fuzz.t.sol:33 `testFuzz_Success_previewWithdraw_ZeroForNothing`, test/fuzz/ALMVaultSync/Withdraw.fuzz.t.sol:529 `testFuzz_Success_withdraw_ZeroBurnsNothing`, test/fuzz/ALMVaultSync/Deposit.fuzz.t.sol:961 `testFuzz_Success_deposit_ZeroMintsNothing`, test/fuzz/ALMVaultSync/Mint.fuzz.t.sol:572 `testFuzz_Success_mint_ZeroTakesNothing`.
- Past the band: test/fuzz/ALMVaultSync/Deposit.fuzz.t.sol:396 `testFuzz_Revert_deposit_InsufficientOutput_BeyondTheSwapCost`, test/fuzz/ALMVaultSync/Mint.fuzz.t.sol:476 `testFuzz_Revert_mint_InsufficientOutput_BeyondTheSwapCost`, test/fuzz/ALMVaultSync/Redeem.fuzz.t.sol:285 `testFuzz_Revert_redeem_InsufficientOutput_BeyondTheSwapCost`, test/fuzz/ALMVaultSync/Withdraw.fuzz.t.sol:198 `testFuzz_Revert_withdraw_InsufficientOutput_BeyondTheSwapCost`, test/fuzz/ALMVaultSync/Mint.fuzz.t.sol:518 `testFuzz_Revert_mint_SPL_TheSwapCostIsWithinTheFee`, test/fuzz/ALMVaultSync/Redeem.fuzz.t.sol:334 `testFuzz_Revert_redeem_SPL_TheSwapCostIsWithinTheFee`.

## 5. Open

- `maxWithdraw`: the thin-pool case `A > 0` or `W > 0` has the model argument of 3.7, not a proof. The lower bound on the quadratic's `q` in terms of `1 − σ W / L` is getRoot.derivation.md section 7: the double root needs the burn and the sale to empty the step's tokenOut reserve.
- `maxMint`: 3.9 is a model argument for either tokenOut. The token0 terms (MintOptimizationMath.sol:182-192) are derived within it ([MintOptimizationMath/maxMint.derivation.md](../MintOptimizationMath/maxMint.derivation.md)).
- `maxDeposit`: `getRoot`'s guard band at the step that holds the walk's limit ([DepositOptimizationMath/maxDeposit.derivation.md](../DepositOptimizationMath/maxDeposit.derivation.md) statement 3 (b)), and the per-floor derivation of the solve's accuracy it takes from stepEndRounding.derivation.md 3.4. An exact integer model finds no `deposit(maxDeposit)` whose swap passes the band (`InsufficientOutput`) or whose mint fails the TWAP check, with the least distance to the walk's limit 1 price unit.
