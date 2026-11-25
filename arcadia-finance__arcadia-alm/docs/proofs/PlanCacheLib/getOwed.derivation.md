# PlanCacheLib.getOwed: the payout a settlement at the current cache pays

Code: `src/core/types/PlanCache.sol` `getOwed` (:269-272), `getSettlementAmountsOut` (:282-381); `src/core/ALMKeeperExtension.sol` `_dispatch` (:176-225), `_swapViaPool` (:507-531), `_swapViaRouter` (:539-566), `_applySwap` (:578-617), `_settleEpochs` (:709-724), `_amount` (:840-855), `_amountInToRatio` (:883-911); `src/core/libraries/state/QueueLib.sol` `settleRedeems` (:266-283).

Notation of [getSettlementAmountsOut.derivation.md](getSettlementAmountsOut.derivation.md): `t` the trusted sqrt price, `P` its price, `b` the existing aLP's tokens before the swap, `R` their value rounded down (`redeemValue`), `v` the value after the swap, `C = R ⊖ v` the swap's cost, `Lv = dL + rL` the levies, `F` the floored `fullMulDiv`, `c0` the conversion to token0, `S = supplyBefore`, `r_i <= S` the redeem shares of vault `i`. Assumption B0: `b >= 0` at the cache read, which [ALMKeeperExtension/swapSettlement.derivation.md](../ALMKeeperExtension/swapSettlement.derivation.md) Lemma (E) proves under its assumption (T).

## 1. What it computes

`getOwed(cache)` is `(0, 0)` when `redeemShares0 | redeemShares1 == 0` (:270), else the last two outputs of `getSettlementAmountsOut(cache)` (:271): the token0 and token1 a settlement at that cache would pay the cleared redeem epochs. Same function, same inputs, so the equality is exact.

## 2. Where a non-zero value is read

`getOwed` is read by `_amount` (:849) and `_amountInToRatio` (:894) only. Their callers are the buildup steps `_openRange`, `_increaseLiquidity`, `_stake` (:395-396, :430-431, :470-471) and the two swap steps (:511, :547).

- Buildup steps. `_dispatch` reverts `InvalidOrder` on a step of kind `0x3_` while `cache.hasUnsettledEpochs()` (:212, PlanCache.sol:203-205), and `_settleEpochs` zeroes the four totals (ALMKeeperExtension.sol:723). So at every buildup step `redeemShares0 = redeemShares1 = 0` and `getOwed = (0, 0)` by :270. `OPEN_BALANCE | bps` then resolves to `floor(buffer_i bps / 1e4)` (:850-854).
- Swap steps. At a swap step's sentinel `swapDelta = 0`: a moving swap before it would make the step revert `TooManySwaps` (:514, :550). With `swapDelta = 0`, `swapped = 0`, `gain = 0` and `v = R` (PlanCache.sol:305-316), `getLevies` returns `(0, 0)` (:407), and the owed value of redeem `i` is `F(R_k, r_i, S)`, token0 through `c0` (:366-367, :380). This is the redeem's part of the existing value before the swap.

## 3. The payout after the sentinel

(P) At every cache the payout value of redeem `i` is at most `F(R, r_i, S)`: [getSettlementAmountsOut.derivation.md](getSettlementAmountsOut.derivation.md) section 3.

(S) The swap does not move `R`: `_applySwap` adds the swap's delta to the cache amounts (:615) and stores the same delta as `swapDelta` (:616), so `b = amounts - swapDelta - deposits` and `R` are unchanged, for every fill.

So when `SETTLE_REQUESTS` follows the sentinel swap with no teardown between them, the settled payout is at most the owed value at the sentinel in both tokens: `F(R_settle, r_i, S) = F(R_k, r_i, S)`. This is Theorem S of [ALMKeeperExtension/swapSettlement.derivation.md](../ALMKeeperExtension/swapSettlement.derivation.md) section 3.7, where the input-token consequence (the input token's payout never reverts `InsufficientBuffer`) and the output token's condition (section 3.8) are derived.

A teardown between the sentinel swap and the settlement. A removal of liquidity `L` at pool sqrt price `x` returns the pool's rounded-down amounts at `x` plus fees, and the cache debits the rounded-down amounts at `t` (`applyLiquidityDelta`, PlanCache.sol:144-153, `CLMath.getPrincipalAmounts`, CLMath.sol:232-239, the same `SqrtPriceMath.getAmount*Delta(..., false)` at CLMath.sol:213-220). With `f(y)` the exact value at `t` of the range's amounts at sqrt price `y`, `f(x) - f(t) = L (t - x)^2 / x >= 0` with both prices inside the range (`f'(y) = L (1 - P / y^2)` vanishes at `y = t`, `f'' > 0`), and `f` is constant outside the range. So `R` rises by `L (t - x)^2 / x` plus the fees' value, and is unchanged at `x = t` up to the fees (the same floors on the same inputs). The payout of token `i` rises by about `r_i / S` of that rise while the buffer gains the removal's token `i`. The buffer of token `i` ends short of the payout when the removal returns none of token `i` (spot past the range's edge on that side) or when the fees are in the other token, and the settlement then reverts `InsufficientBuffer` (QueueLib.sol:272-274).

## 4. Reverts reachable from `getOwed`

- `ZeroSupply` (PlanCache.sol:321): `redeemShares_i != 0` means the cleared redeems' aLP sits in the core's escrow, so `supplyBefore = totalSupply()` read at the plan's start (ALMKeeperExtension.sol:114) is at least `redeemShares_i > 0`. Unreachable from a sentinel.
- `ZeroValue` (PlanCache.sol:320): at a sentinel `v = R_k` (section 2), so it needs a cleared deposit with `R_k = 0`, an existing aLP of no value at `t`.

## Claims

| Claim | Status | Evidence |
|---|---|---|
| `getOwed` equals the settlement's payouts at the same cache | derived | section 1; test/fuzz/libraries/PlanCacheLib/GetOwed.fuzz.t.sol:76 `testFuzz_Success_getOwed_RedeemSharesAtPriceOne`, :100 `testFuzz_Success_getOwed_Token0AtATrustedPrice`, :136 `testFuzz_Success_getOwed_Token1AtATrustedPrice` |
| without a cleared redeem it is `(0, 0)` | derived | :270; test/fuzz/libraries/PlanCacheLib/GetOwed.fuzz.t.sol:23 `testFuzz_Success_getOwed_ZeroWithoutARedeem`, :48 `testFuzz_Success_getOwed_ZeroWithoutARedeemOnAnEmptySupply` |
| at every buildup step it is `(0, 0)` | derived | section 2 |
| at a swap sentinel it is the redeems' floored part of the existing value before the swap | derived | section 2 |
| the swap between the sentinel and the settlement does not raise the payout, for every fill | derived | section 3 (P) and (S), under B0; test/fuzz/ALMCore/SwapViaRouter.fuzz.t.sol:532 `testFuzz_Success_swapViaRouter_OpenBalanceFilledAboveTheTrustedPricePaysTheValueBefore`, :671 `testFuzz_Success_swapViaRouter_TargetRatioFilledAboveTheTrustedPricePaysTheValueBefore`, test/fuzz/ALMCore/SwapViaPool.fuzz.t.sol:1889 `testFuzz_Success_swapViaPool_TargetRatioWithRedeemsInBothVaultsSettles` |
| a teardown between the sentinel swap and the settlement raises the payout by about `r_i / S` of `L (t - x)^2 / x` plus fees | derived | section 3 |
| `ZeroSupply` is unreachable from a sentinel, `ZeroValue` needs a cleared deposit and `R_k = 0` | derived | section 4 |
