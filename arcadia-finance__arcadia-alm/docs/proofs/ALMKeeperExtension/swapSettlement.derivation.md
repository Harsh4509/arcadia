# ALMKeeperExtension.execute: each cleared epoch settles once, and the shares left keep the start value per share less their part of the swap cost

Code: `src/core/ALMKeeperExtension.sol` `execute` (:72-157), `_dispatch` (:176-225), `_swapViaPool` (:507-531), `_swapViaRouter` (:539-566), `_applySwap` (:578-617), `_clearRequests` (:628-668), `_clearAllRequests` (:676-702), `_settleEpochs` (:709-723), `_settleRedeems` (:735-757), `_settleDeposits` (:766-782), `_cancelRequests` (:789-826), `_amount` (:840-855), `_amountIn` (:865-873), `_amountInToRatio` (:883-911); `src/core/types/PlanCache.sol` `start` (:71-99), `checkShortfall` (:108-121), `applyBufferDelta` (:132-135), `applyLiquidityDelta` (:144-153), `hasUnsettledEpochs` (:203-205), `getValue` (:254-261), `getOwed` (:269-272), `getSettlementAmountsOut` (:282-381), `getLevies` (:396-422); `src/core/libraries/state/QueueLib.sol`; `src/core/libraries/state/PoolTokensLib.sol` `creditCollected`; `src/core/libraries/state/ShareLib.sol` `checkTotalCap` (:36); `src/core/libraries/logic/CommandLogic.sol` (:17-46). Pool behaviour: [PoolAxioms.md](../PoolAxioms.md).

Notation. `t` the trusted sqrt price, `P = t^2 / 2^192` the trusted price, `s` the pool's sqrt price at the plan's start (`cache.spotSqrtPriceX96`). `V(x) = P x0 + x1` the exact value at `t` of a signed token pair. `a = (cache.amount0, cache.amount1)`, `δ = cache.swapDelta`, `d = (depositAssets0, depositAssets1)`, `r = (redeemShares0, redeemShares1)`, `q = r0 + r1`, `S = supplyBefore`, `ρ_i = r_i / S`, all read at the settlement. Then

    E  = a − δ − d          the tokens of the start holders before the swap
    Wb = V(E)               their value before the swap
    c  = −V(δ)              the value the swap lost (negative for a gain)
    W  = Wb − c             their value after the swap
    D  = P d0 + d1          the cleared deposits' value
    Ld, Lr                  the deposit levy and the redeem levy, K = Ld + Lr
    Pd = W + K              the deposits' price (value per S shares)
    Px = min(Wb, W + K)     the redeems' price

`m = maxSwapCostBps / 1e4`, `β = maxSpotFromTrusted / 1e18`, `f` the pool fee as a fraction. Kinds of steps: queue `0x00` to `0x02` (`CLEAR_REQUESTS`, `CLEAR_ALL_REQUESTS`, `CANCEL_REQUESTS`), `SETTLE_REQUESTS = 0x03`, teardown `0x1_`, swap `0x2_`, buildup `0x3_`. "Buildup" below means a step of kind `0x3_`.

## 1. Statement

For every plan that `execute` completes:

1. Order. Every `CLEAR_REQUESTS`, `CLEAR_ALL_REQUESTS` and `CANCEL_REQUESTS` step precedes every other step. No buildup step runs while a cleared epoch is unsettled: a plan that clears a request runs every buildup step after its settlement.
2. One settlement. If the plan clears a request, `_settleEpochs` settles exactly once with effect, at the plan's first `SETTLE_REQUESTS` step, and no request is cleared after it. A plan that clears and never settles reverts `InvalidOrder`. At that settlement `S` is the aLP supply, and each cleared epoch's `amountIn` equals the cache total of its queue.
3. Each epoch's payment. The cleared redeem epoch of vault `i` is paid `assets_i` and the cleared deposit epoch of vault `i` is minted `shares_i`, both from `getSettlementAmountsOut` on the cache at the settlement, with the bounds of section 2 (L1, L2) at the prices `Px` and `Pd`. The payout moves from the buffer to escrow, the aLP is minted to escrow, both are stored as the epoch's `amountOut`, and no later step of the plan changes them. Each request of an epoch is credited `floor(amountIn · epochOut / epochIn)` at the epoch's remaining rate, and the credits never sum above the epoch's output.
4. Swap cost. The settlement reads `δ` of the plan's one swap that moved tokens, if it ran before the settlement, else `δ = 0`. `c` is the same for every step placed between the swap and the settlement. The flows pay `K`, at most their pro rata part of the cost on the part of the swap they needed (L3). The start holders, cleared redeems included, carry `c − K` pro rata. On a gain (`c < 0`) `K = 0`, redeems are paid at `Wb` and the gain stays with the shares left after the settlement, entrants included.
5. Value per share. The exact value at `t` held right after the settlement, per share of the supply after it, is at least `Pd / S = (Wb − (c − K)) / S`. Deposits are minted at most their value less their levy at that price, redeems are paid at most `Px / S` per share less their levy.
6. Swap cost bound. A swap that passes `_applySwap` has `c < (1 − (1 − m) / (1 + β)^2) X + 1` for a sale of token0 and `c < (1 − (1 − m) / (1 + β)^2) X + P` for a sale of token1, `X` the exact value at `t` of the net input, the last term one wei of the output token at `t`. A pool fill starting at a price inside the band gains at most `((1 + β)^2 (1 − f) − 1) X`. A router fill has no bound on its gain.
7. Sentinels. After the settlement `getOwed` is `(0, 0)` and `OPEN_BALANCE | bps` is `floor(buffer_i · bps / 1e4)`. When `SETTLE_REQUESTS` directly follows a swap whose amount `OPEN_BALANCE` or `TO_TARGET_RATIO` resolved, the settled payouts are at most the payouts owed before the swap in both tokens, for every fill (constant 0), and the payout in the swap's input token never reverts `InsufficientBuffer`.
8. Shortfall. The plan's end value per share at `t` is at least `1 − maxShortfallBps / 1e4` of its start value per share, less one wei over `S` (`checkShortfall`).

Statement 5, and the exactness of the prices in 3 and 4, hold when `E >= 0` at the settlement. Lemma (E) of 3.4 proves `E >= 0` at every settlement under assumption (T): no teardown step between a `SWAP_VIA_ROUTER` step and the settlement removes liquidity that the router's callee added to a core position. Without (T), 3.4 bounds the value the settlement computes for the start holders between `V(E)` and the value of the tokens they hold.

Status: 1, 2, 4, 6, 7, 8 derived. 3 derived, its credit bound resting on L7, whose `creditSettled` row is open. 5 derived under (T), given L1 and L2.

## 2. Axioms and bounds used

Pool: B1 to B4 (one step's input, fee and output), C1, C2, C3, C7 (the hook fee only lowers an exact input's output), D6 (the swap returns the input consumed and the output). The pool's price does not move on a mint, burn or collect.

ALM bounds, cited and not re-proved here:

| # | Bound | Source |
|---|---|---|
| L1 | Redeems: `P assets0 ≤ Px r0 / S` and `assets1 ≤ Px r1 / S`, less `Lr` on the vault of the swap's output token. The levied payout does not underflow. | `PlanCacheLib.getSettlementAmountsOut`, [PlanCacheLib/getSettlementAmountsOut.derivation.md](../PlanCacheLib/getSettlementAmountsOut.derivation.md) |
| L2 | Deposits: `shares_i ≤ (D_i − Ld) S / Pd` for the deposit in the swap's input token, `shares_i ≤ D_i S / Pd` for the other, `D_0 = P d0`, `D_1 = d1`. | same |
| L3 | Levies: each levy is the ceiling of its flow's pro rata part of `k`, capped at the flow, `k ≤ ceil(c)` the cost scaled by the part of the swap the flows needed beyond their offsets. `K ≤ k + 1`. `K = 0` when `c ≤ 0`. | `PlanCacheLib.getLevies`, [PlanCache/getLevies.derivation.md](../PlanCache/getLevies.derivation.md) |
| L4 | `getOwed(cache)` is the last two outputs of `getSettlementAmountsOut(cache)`, or `(0, 0)` without a cleared redeem. | `PlanCacheLib.getOwed`, [PlanCacheLib/getOwed.derivation.md](../PlanCacheLib/getOwed.derivation.md) |
| L5 | `getSettlementAmountsOut` values `E` once down (`redeemValue`, so `floor(Wb)` when `E >= 0`) and prices the redeems at `min(redeemValue, value + K)`, with `value` the value after the swap rounded down. With `δ = 0` it has `value = redeemValue` and no levy. | same as L1 |
| L6 | `checkShortfall` reverts iff `floor(valueAfter · S / supplyAfter) < floor(valueBefore · (1e4 − maxShortfallBps) / 1e4)`. | [PlanCacheLib/checkShortfall.md](../PlanCacheLib/checkShortfall.md) |
| L7 | `requestAmountOut(x, X, Y) = floor(x Y / X) ≤ Y` for `x ≤ X`. `creditSettled` takes a record's floored share of the epoch's remaining amounts and lowers both by it. | test/symbolic/libraries/QueueLib.symbolic.t.sol:87 `prove_requestAmountOut_IsTheFlooredProRataShare` and :105 `prove_requestAmountOut_NeverExceedsTheBatch` (symbolic), :234 `prove_creditSettled_MovesTheRecordsProRataOutputIntoTheClaimablePile` (open), [QueueLib/requestAmountOut.md](../QueueLib/requestAmountOut.md), [QueueLib/creditSettled.md](../QueueLib/creditSettled.md) |
| L8 | `startClearedEpoch` sets `lastClearedEpoch` to an id above every id issued, whose epoch is empty. | test/symbolic/libraries/QueueLib.symbolic.t.sol:36 `prove_startClearedEpoch_SucceedsIffTheNextIdFitsUint32` (symbolic), [QueueLib/startClearedEpoch.md](../QueueLib/startClearedEpoch.md) |
| L9 | `maxSwapCostBps ≤ 10_000`, `maxShortfallBps ≤ 10_000`. | `ALMAdminExtension.setPlanLimits`, src/core/ALMAdminExtension.sol:165-166, the only writer of both |
| L10 | Every entry point that mints, burns or records a request (`mint`, `burn`, `trustedBurn`, `seed`, `recordDepositRequest`, `recordRedeemRequest`, the cancels and claims) is `nonReentrant`, and `execute` holds the lock. | `nonReentrant` at `src/core/ALMCore.sol:136` (`mint`), :206 (`burn`), :226 (`trustedBurn`), :367, :394 (the two records), :421, :448 (the two cancels), :476, :500 (the two claims), `src/core/ALMAdminExtension.sol:383` (`seed`), `ALMKeeperExtension.sol:74` (`execute`) |

The unchecked arithmetic of the plan path (`_amount`, `_amountInToRatio`, `_applySwap`, `_swapViaPool`, `_clearRequests`) is bounded in [ALMVaultSync/uncheckedMath.derivation.md](../ALMVaultSync/uncheckedMath.derivation.md) sections 2 and 3.6.

## 3. Proof

### 3.1 The order (statement 1)

`execute` keeps `previous`, the opcode of the step before, and reverts `InvalidOrder` (ALMKeeperExtension.sol:125-127) when `command ≤ CANCEL_REQUESTS` and `previous > CANCEL_REQUESTS`. Let step `j` have an opcode above `0x02` and a later step have one at or below it. The first step after `j` with an opcode at or below `0x02` has a predecessor above `0x02` and reverts. So in a completed plan every step at or below `0x02` precedes every step above it. `SETTLE_REQUESTS = 0x03` is above the threshold: it may follow any step, and no clear or cancel may follow it.

The buildup rule. `_dispatch` reverts `InvalidOrder` (:212) on a step of kind `0x3_` or above while `depositAssets0 | depositAssets1 | redeemShares0 | redeemShares1` is non-zero. The totals are written only by the clear steps and zeroed only by the settlement (3.2). A buildup step has an opcode above `0x02`, so every clear step precedes it, and a total a clear step wrote stays until the settlement. So if a settlement runs with a total above zero, the totals were the same at every buildup step before it, and each of those reverted: no buildup step precedes a settlement with effect. A plan whose totals are zero (no clear, or clears that found nothing pending) runs buildup steps anywhere, and its `SETTLE_REQUESTS` steps return at their first line.

Settlement order. A completed plan that clears a request is: clear and cancel steps, then teardown and swap steps, then the one settlement with effect, then steps of any kind above `0x02`.

### 3.2 One settlement (statement 2)

The four totals `depositAssets0`, `depositAssets1`, `redeemShares0`, `redeemShares1` are written only by `_clearRequests` and `_clearAllRequests` (opcodes `0x00`, `0x01`) and zeroed only by `_settleEpochs`. `_settleEpochs` is reached only through `SETTLE_REQUESTS`. By 3.1 every clear precedes every `SETTLE_REQUESTS` step. The first `SETTLE_REQUESTS` step with a total above zero settles and zeroes all four. Every later one returns at its first line. After the loop `execute` reverts `InvalidOrder` while a total is above zero (:133), so a plan that cleared a request settles it, and a plan whose clears found nothing pending settles nothing.

The supply. aLP is minted or burned in the plan only by `_settleRedeems` and `_settleDeposits`, which run inside the one settlement. Every other entry point that mints or burns is locked out (L10). A redeem cancel moves aLP out of escrow without changing the supply. So the supply at the settlement is the supply `execute` read into `supplyBefore`.

The epochs. For a queue, `_clearAllRequests` requires the cache total to be zero (`AlreadyCleared`), declares the pending epoch cleared and writes its `amountIn` into the total. `_clearRequests` starts a fresh cleared epoch (L8, empty) when the total is zero and otherwise adds to the epoch `lastClearedEpoch` names. Each named record it takes is pending and moves its `amountIn` from the pending epoch to the cleared one, and the same amount into `cleared`. So after every clear step the cleared epoch's `amountIn` equals the cache total. A record cleared once is no longer pending, so it is never counted twice, and a cancel only acts on pending records. Deposits move `amountIn` from escrow into the buffer, and the cache receives the same delta.

### 3.3 The settled amounts are final (statement 3)

`_settleRedeems` burns `redeemShares_i` from escrow and calls `QueueLib.settleRedeems` (QueueLib.sol:266-283), which reverts `InsufficientBuffer` (:272-274) unless the buffer holds `assets_i`, moves `assets_i` from the buffer to escrow and stores it as the epoch's `amountOut`. `_settleDeposits` checks `totalSupply() + shares_i` against the total cap (after the redeem burns), mints `shares_i` to escrow and stores it as the epoch's `amountOut`. Escrow changes in a plan only through a clear, a cancel and the settlement. By 3.1 no clear or cancel follows the settlement, so nothing later in the plan touches what was put in escrow. With 3.2 each epoch's `amountIn` is the total the settlement priced, so the credits of L7, a floored pro rata share of the remaining amounts each, sum to at most the epoch's output.

### 3.4 What the settlement reads

The cache tracks the buffer and a book. Every step applies the same buffer delta to `state.poolTokens.buffer` and to the cache (`applyBufferDelta`), and every liquidity change also books, through `applyLiquidityDelta`, the floor at `t` of the principal of the liquidity added, or its negative for the liquidity removed. `start` books, per range, the floor at `t` of the principal of the range's whole liquidity. So at every step

    a_i = buffer_i + book_i

with `buffer_i >= 0` (a `uint128` in state). Each booked amount is the floor of a real linear in the liquidity: token1 is one floor (A1's form) and token0 two nested floors, which equal one floor of the exact amount (A2's identity).

Per range write `Λ` for its liquidity at the start (the unstaked position's liquidity read from the position manager plus `stakedLiquidity`, which `collectFees` sums and `start` books in one floor), `l_j` for the parts the plan removes before the settlement, and `X` for the liquidity a third party adds to its unstaked position during the plan before the settlement.

Lemma (E). At every settlement with effect, if `Σ l_j ≤ Λ` in every range, then `E_i >= 0`, `a_i − δ_i >= 0` and `a_i >= 0` in both tokens.

Proof. By 3.1 no buildup step ran before the settlement: only queue, teardown and swap steps did. A swap step books no liquidity, a queue step none, a teardown step books `−floor(p(l_j))`. So the book of a range is `floor(p(Λ)) − Σ floor(p(l_j))`. As `floor(u + v) >= floor(u) + floor(v)` and `p` is linear, the book is at least `floor(p(Λ − Σ l_j)) >= 0`. The buffer at the settlement is the buffer at the start, plus the cleared deposits `d_i`, plus the teardown proceeds and fees (non-negative), plus `δ_i`. So `E_i = a_i − δ_i − d_i >= buffer_i(start) + book_i >= 0`, then `a_i − δ_i = E_i + d_i >= 0`, and `a_i >= 0` from `buffer_i >= 0` and `book_i >= 0`. ∎

With `E >= 0` and `a >= 0` no clamp of `getValue` or of `held0`, `held1` in `getSettlementAmountsOut` is reached, so the library computes the exact quantities of the notation, each rounded once as its document states. `_settleEpochs` needs no check of its own for it.

When `Σ l_j ≤ Λ` holds. The staked side: `decreaseStakedLiquidity` (RangesLib.sol:233) subtracts each removal from `stakedLiquidity` in checked arithmetic, so the staked removals of a range sum to at most its `stakedLiquidity` at the start. The unstaked side: the position manager reverts a decrease above the position's liquidity, and the sentinel `RANGE_LIQUIDITY` and `CLOSE_RANGE` remove the position's liquidity at the step. That liquidity is the unstaked liquidity at the start, less the earlier removals, plus `X`: the core adds none before the settlement (3.1). So `Σ l_j ≤ Λ + X`, and `Σ l_j ≤ Λ` in every plan with `X = 0`.

When `X > 0` is reachable. `execute` holds the lock (L10). Between two steps the code that runs is the core's, the position manager's, the pool's, the gauge's, the tokens' and the callee of a `SWAP_VIA_ROUTER` step, which the keeper names in the payload. Only that callee is arbitrary code, and `increaseLiquidity` on a core-owned unstaked position is open to any caller, who pays the tokens ([RangesLib/donatedLiquidity.derivation.md](../RangesLib/donatedLiquidity.derivation.md) 8.1). A gauge-owned position accepts additions from the gauge only. So `X > 0` needs a router step before the settlement whose callee adds to an unstaked position, and `Σ l_j > Λ` needs in addition a teardown step on that range between that router step and the settlement. Assumption (T) excludes exactly that pair. The buildup rule does not: a teardown is no buildup. (T) holds in every plan with no router step before the settlement, and in every plan with no teardown step between its router step and the settlement, which is the placement of the settlement right after the swap.

Without (T). Let `Y = Σ l_j − Λ`, `0 < Y ≤ X`, be the added liquidity a range's teardown removed, and `T` the tokens the start holders hold before the swap: the buffer less `δ` and `d`, plus each range's remaining liquidity at `t`. Per token, to within one wei per range:

    book_i >= floor(p_i(Λ)) − floor(p_i(Λ + Y)) >= −ceil(p_i(Y))
    E_i    >= buffer_i(start) + proceeds_i − Σ ceil(p_i(Y))
    T_i     = E_i + Σ p_i(X) >= E_i⁺,   E_i⁺ = max(E_i, 0)

the sums over the ranges. `E_i < 0` needs the added liquidity's principal at `t` in token `i` to exceed the buffer at the start plus every teardown's proceeds in that token, which a removal at a spot away from `t` allows in one token. The removal's proceeds are worth at `t` at least the principal at `t` of the liquidity removed (3.9), so `V(E) >= V(a_start)` plus the fees. `getValue` then computes `V(E⁺)`, and

    V(a_start) ≤ V(E) ≤ V(E⁺) ≤ V(T)

The value the settlement computes for the start holders is at least their value without the addition and at most the value of the tokens they hold with it. The difference `V(E⁺) − V(E) ≤ Σ V(p(Y))` is part of what the third party paid in. The bounds L1 to L3 and statement 5 are derived for `E >= 0` and are not extended to this case.

The cost is the swap's alone. `V` is linear on signed pairs, so for any `a`, `V(a − δ) − V(a) = −V(δ) = c`: teardown steps between the swap and the settlement move `Wb` and `W` by the same amount and leave `c`. `cache.swapDelta` is written only by `_applySwap`, and a swap step reverts `TooManySwaps` when it is already non-zero (:514, :550), so `δ` is the plan's one moving swap if that ran before the settlement, else zero. A swap step whose delta is zero leaves `δ = 0`, and a later swap may then move tokens.

### 3.5 Value per share (statements 4 and 5)

Right after the settlement the cache holds `a' = a − (assets0, assets1)` and the supply is `S' = S − q + shares0 + shares1`. Since `V(a) = V(E) + V(δ) + V(d) = W + D`,

    V(a') = W + D − (P assets0 + assets1) >= W + D − Px q / S + Lr        (L1)
    (Pd / S) S' = Pd − Pd q / S + Pd (shares0 + shares1) / S <= Pd − Pd q / S + D − Ld        (L2)
    V(a') − (Pd / S) S' >= (W + K − Pd) + (Pd − Px) q / S = (Pd − Px) q / S >= 0

as `Px ≤ W + K = Pd`. So every share after the settlement, entrants' included, is worth at least `Pd / S = (Wb − (c − K)) / S`: the start holders lose `c − K` of the swap and nothing of a flow's part. The surplus `(Pd − Px) q / S` is zero on a loss and `−c q / S` on a gain, which is how the redeems' part of a gain stays with the shares after the settlement: an entrant minted `shares` holds `(−c) (q / S) shares / S'` of it.

Example of the gain, price 1: `S = 1000`, 600 token0 and 400 token1, a token1 deposit of 100, a token0 redeem of 500 aLP, a sale of 100 token0 for 110. `Wb = 1000`, `W = 1010`, `K = 0`. The redeem is paid 500. The deposit is minted `100 · 1000 / 1010 = 99.0` aLP. After the settlement `V(a') = 1010 + 100 − 500 = 610` on `S' = 599.0`, so the deposit's aLP is worth `100.8`.

### 3.6 Bounds on the swap (statement 6)

Cost. `_applySwap` reverts `MaxSwapCostExceeded` (:592-600) when `balanceOut < ceil(floor(conv_s(n)) (1e4 − maxSwapCostBps) / 1e4)`, `n = amountIn ⊖ balanceIn` the net input and `conv_s` the conversion at `s`, the start spot. Selling token0, a passing swap has `out >= (1 − m)(P_s n − 1)`, so `c = P n − out < n (P − (1 − m) P_s) + 1`. The band check of `execute` (`ConfigLib.checkTrustedDeviation`, ConfigLib.sol:73-86) gives `t / (1 + β) ≤ sqrt-spot ≤ t (1 + β)`, so `P_s >= P / (1 + β)^2` and `c < (1 − (1 − m) / (1 + β)^2) X + 1` with `X = P n`. Selling token1, `out >= (1 − m)(n / P_s − 1)` and `c = n − P out < n (1 − (1 − m) P / P_s) + (1 − m) P`, with `P / P_s >= 1 / (1 + β)^2`. A router refund above the input gives `n = 0` and both deltas non-negative: `c ≤ 0`.

Gain on a pool fill. Selling token0, each step's input to its end price is at most `1 − f` of what the step consumes (B1 to B3: the fee is the ceiling of `input · f / (1 − f)` on a full step, and a partial step's input is at most `floor(R (1 − f))`), its output is at most the exact amount between its prices (B4, C2), and the exact token1 per exact token0 between sqrt prices `u < v` is `u v / 2^192 ≤ v^2 / 2^192`, the price where the step starts. The price only falls, so `out ≤ P_spot (1 − f) n` with `P_spot` the pool's price at the swap, and the hook fee only lowers `out` (C7). So `−c = out − P n ≤ ((P_spot / P)(1 − f) − 1) X ≤ ((1 + β)^2 (1 − f) − 1) X` when the pool's price at the swap is in the band. Selling token1 is the mirror: `out ≤ (1 − f) n / P_spot` and `P / P_spot ≤ (1 + β)^2`. Mints, burns and collects do not move the pool's price, so the pool's price at the swap is the start spot unless an earlier swap step of the plan (a router swap whose delta was zero) moved it.

### 3.7 The sentinels (statement 7)

After the settlement the totals are zero, `getOwed` returns `(0, 0)` (PlanCache.sol:270) and `_amount` returns `floor(buffer_i · bps / 1e4)`: the payouts are in escrow, the whole buffer is free.

Before the settlement, `getOwed` is read on the cache at that step (L4): the payouts a settlement at that cache would pay.

Theorem S. Let a swap step resolve its input by `OPEN_BALANCE` or `TO_TARGET_RATIO` before the settlement, with `owed = getOwed` on the cache at that step, let `SETTLE_REQUESTS` be the next step, and let Lemma (E) hold. Then `assets_i ≤ owed_i` for both vaults, for every fill.

Proof. At the sentinel `δ = 0` (a non-zero delta reverts `TooManySwaps`), so by L5 `owed_i` is the payout at `redeemValue = floor(V(E))` with no levy. Between the sentinel and the settlement only the swap ran, which adds `δ` to `a`. So `E = a − δ − d` at the settlement is the same pair of integers, and `redeemValue` is the same integer. The settlement prices the redeems at `min(redeemValue, value + K) ≤ redeemValue` (L5) and only subtracts a levy (L1). The floors and the token0 conversion are monotone. ∎

Input side. `OPEN_BALANCE | bps` sells `floor((buffer_in ⊖ owed_in) bps / 1e4) ≤ buffer_in ⊖ owed_in`, and `TO_TARGET_RATIO` sells `buffer_in ⊖ (owed_in + target_in) ≤ buffer_in ⊖ owed_in`. The pool consumes at most the amount specified (D6) and a router's refund only returns input. So if `buffer_in >= owed_in` before the swap, `buffer_in >= owed_in >= assets_in` at the settlement and the input token's payout never reverts. If `buffer_in < owed_in`, the sentinel sells nothing of the input token.

The constant is 0: the sentinel subtracts `owed_in` and nothing more. It is attained whenever `Px = Wb`, which holds on a fill at or above the trusted price and when the flows pay the whole cost: test/fuzz/ALMCore/SwapViaRouter.fuzz.t.sol:532 `testFuzz_Success_swapViaRouter_OpenBalanceFilledAboveTheTrustedPricePaysTheValueBefore` ends with the token0 buffer at 0 and the epoch paid exactly `owed0`.

Residue. When `Px < Wb` (a loss the flows do not pay in full), a 100 % input sentinel leaves `owed_in − assets_in`, in value `(c − K) ρ_in` up to the floors, in the buffer. No amount fixed before the fill removes it. An `OPEN_BALANCE` buildup after the settlement takes it.

If a teardown runs between the swap and the settlement, `Wb` rises by `L (t − x)^2 / x` per removal at pool sqrt price `x` plus the fees, and the payouts can exceed `owed`. The token the removal returns none of, or the one the fees are not in, can end short, and the settlement then reverts `InsufficientBuffer`, no value moves ([PlanCacheLib/getOwed.derivation.md](../PlanCacheLib/getOwed.derivation.md) section 3).

### 3.8 The swap's output token

In exact values at `t`, with the settlement right after the swap and `c >= 0`. Write `B` the buffer before the swap, `O` the owed payouts in value, `open = V(B) − V(O)`, `target_in + target_out = open`. `TO_TARGET_RATIO` sells the value `target_out + O_out − B_out`, so after the fill `B_out' = O_out + target_out − c`. The settlement pays `Px ρ_out − Lr = O_out − (c − K) ρ_out − Lr` (as `Px = Wb − (c − K)`, `O_out = Wb ρ_out`). So the output payout is covered iff

    target_out >= (c − K)(1 − ρ_out) + Ld

and otherwise the settlement reverts `InsufficientBuffer`. With `TO_TARGET_RATIO | 1e4` on a sale of token0 (or `| 0` on a sale of token1), `target_out = 0`, so a positive cost settles only with `K = c` and `Ld = 0`. For any input amount the buffer covers both payouts only if the value it holds after the fill, `V(B) − c`, is at least `V(O) − (c − K)(ρ_in + ρ_out) − Lr`:

    open >= (c − K)(1 − ρ_in − ρ_out) + Ld

The integer form of both conditions is not derived (section 5).

### 3.9 Placement: who carries what

The settlement prices on the cache when `SETTLE_REQUESTS` runs. By 3.4 the steps before it enter `Wb` and `W` alike and leave `c`, so each placement assigns a step's result to a set of holders. None credits value that is not held (3.5).

| Step, relative to the settlement | Carried by |
|---|---|
| The swap before it | flows `K`, start holders `c − K` (3.5) |
| The swap after it, or no swap before it | no levy: the shares after the settlement, entrants included, carry the whole swap. Against a settlement right after the swap the start holders give the entrants the flows' part `K`, e.g. `c D / (Wb + D)` when the flows would pay the whole cost |
| A teardown or `COLLECT` before it | the start holders, cleared redeems included: a removal at spot `x` books at least the value at `t` it books at `x = t` (the position's tokens at `x` are what it holds after trading along its curve at prices between `t` and `x`, each favourable at `t`), `L (t − x)^2 / x` more with both prices inside the range. After the plan's pool swap this includes the fees and the price impact the swap paid the core's own liquidity |
| A teardown or `COLLECT` after it | the shares after the settlement |
| A buildup after it | the shares after the settlement |
| A buildup before it | none: the step reverts `InvalidOrder` (3.1) |

### 3.10 Shortfall (statement 8)

`valueBefore = floor(V(a_start))` with `a_start >= 0` (PlanCache.sol:85-89). `valueAfter = getValueAfter()`, `V` of the end cache rounded down with each token below zero counted as zero. By L6 a completed plan has `valueAfter · S / supplyAfter >= floor(valueBefore (1 − maxShortfallBps / 1e4)) > valueBefore (1 − maxShortfallBps / 1e4) − 1`. So the end value per share is at least `1 − maxShortfallBps / 1e4` of the start value per share less `1 / S` per share. This bounds, on the holders' side, every loss of the plan together: `c − K`, the valuation of buildups at a spot away from `t`, and the roundings.

The end cache can hold a token below zero only by the floors of the book: `n` adds booked on one range and then one removal of their sum book `Σ floor(p(l_j)) − floor(p(Σ l_j)) >= −(n − 1)`. With the token's buffer at zero and no other range booking it, `valueAfter` is that many wei of the token above the exact value.

### 3.11 The reward checkpoint

`_checkpointed` is reset at the start of `execute` (:119), and the first aLP movement of the plan (a redeem cancel, else the settlement's first burn or mint) runs the core's checkpoint once. It precedes every supply change of the plan. The checkpoint reads balances and writes the reward ledger only, so its position changes no token amount any later step reads. A forfeit of hidden emissions in a step after it is folded at the next checkpoint: the ledger keeps credited reward equal to the high water plus the pre-credit, so the emissions accrued since the last checkpoint before the plan are credited over `S` and withheld from the next credits of the same amount ([RewardsLib/getRewardPerShare.md](../RewardsLib/getRewardPerShare.md)).

## 4. Constants

| Constant | Where | Sufficiency | Witness |
|---|---|---|---|
| Order threshold `CANCEL_REQUESTS = 0x02`, `SETTLE_REQUESTS = 0x03` above it | `execute` | 3.1, 3.2: every step that writes a total or escrow before the settlement precedes the settlement, and the settlement may follow any step | no witness |
| Totals zero at the end | `execute` | 3.2: no cleared epoch is left unsettled | no witness |
| Sentinel reserve 0 (`owed_in` subtracted, no margin) | `_amount`, `_amountInToRatio` | Theorem S, 3.7. Attained by test/fuzz/ALMCore/SwapViaRouter.fuzz.t.sol:532 `testFuzz_Success_swapViaRouter_OpenBalanceFilledAboveTheTrustedPricePaysTheValueBefore` | no witness |
| Buildup rule: a step of kind `0x3_` or above reverts while a total is above zero | `_dispatch` | 3.1: no buildup step precedes a settlement with effect. 3.4: `E >= 0`, `a − δ >= 0` and `a >= 0` at that settlement under (T), so no clamp of `getValue` is reached | Price 1 (`t = 1` in sqrt), no swap: `S = 1000` on 1000 token1, a cleared token0 deposit of 100, then `OPEN_RANGE` on sqrt prices `[0.9, 1.1]` at spot sqrt `0.99` spends 100 token0 and 89.1 token1 for `L = 990`, booked at `t` as 90.0 token0 and 99.0 token1. A settlement after it reads `a = (90, 1009.9)`, `E = (−10, 1009.9)`: `Wb = 999.9` exact, `1009.9` as `getValue` computes it, and the deposit is minted `100 · 1000 / 1009.9 = 99.0` aLP in place of `100.0`. The rule reverts the `OPEN_RANGE` step. Test: test/fuzz/ALMCore/SettleAfterBuildup.fuzz.t.sol:41 `testFuzz_Revert_settleEpochs_InvalidOrder_ABuildupBeforeTheSettlement` |
| `bps ≤ 10_000`, `targetRatio ≤ 10_000` | `_amount`, `_amountInToRatio` | the resolved amount is at most the open balance, `target0 ≤ open` | no witness |
| Swap cost floor: `convert` down, then `fullMulDivUp` by `1e4 − maxSwapCostBps` | `_applySwap` | 3.6: `c < (1 − (1 − m) / (1 + β)^2) X` plus one wei of the output token | no witness |

## 5. Open

1. Without (T) (3.4): L1 to L3 and statement 5 for a settlement that follows a teardown of liquidity a router's callee added. 3.4 bounds the computed value of the start holders, not the levies and the payouts derived from it.
2. The integer form of 3.8: how many wei of floors (sentinel, conversions, payouts) separate the exact conditions from the code's.
3. Statement 5 rests on L1 and L2. The redeem bound of L1 for the levied vault uses Lemma R of [PlanCacheLib/getSettlementAmountsOut.derivation.md](../PlanCacheLib/getSettlementAmountsOut.derivation.md) section 3, derived and not machine-checked.
4. Statement 3's credit bound rests on `creditSettled` (L7), open in [QueueLib/creditSettled.md](../QueueLib/creditSettled.md).
