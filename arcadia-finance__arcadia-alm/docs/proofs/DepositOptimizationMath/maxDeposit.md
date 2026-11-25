# DepositOptimizationMath.maxDeposit: its deposit mints at most the shares and swaps within the limit, and can mint none

Code: `src/vaults/libraries/math/DepositOptimizationMath.sol` `maxDeposit` (:167-237), `previewDeposit` (:139-148), `getBalanceIn` (:252-259), `src/vaults/types/Snapshot.sol` `getMintAmounts` (:239-276), `getMintShares` (:287-326), `src/vaults/libraries/math/EquivalentPositionMath.sol` `amountsAt` (:109-124), `src/shared/libraries/math/CLMath.sol` `convert` (:39-68). Pool behaviour: [PoolAxioms.md](../PoolAxioms.md).

Notation as [ALMVaultSync/deposit.derivation.md](../ALMVaultSync/deposit.derivation.md). `A_t` the core's `amountsAt` at spot (DepositOptimizationMath.sol:184), `R_t(p)` its exact amounts at `p` with the idle tokens, `p0` the exact price of tokenOut in tokenIn at spot, `V0 = (A_in − n)⁺ + convert(s0, (A_out − n)⁺)` rounded down (DepositOptimizationMath.sol:187-192), `E` the walk's limit: the band and the pool's limit, moved one unit toward spot (DepositOptimizationMath.sol:205-210).

## 1. Statement

1. `maxDeposit <= floor(shares · V0 / N)`.
2. Every deposit of `a <= shares · V0 / N` mints at most `shares`: `previewDeposit(a) <= shares`.
3. With no pool liquidity or no tokenOut at spot, `maxDeposit` is the bound of 1 when the mint of the whole supply at spot takes no tokenOut, else 0.
4. `maxDeposit` is 0 when `getMintShares(s0, floor(shares · V0 / N), A_out · shares / N)` is 0.
5. When the walk reaches `E`, `maxDeposit <= getBalanceIn(cost(E), out(E), D_in(E) − 1, D_out(E) + 1)`. The swap of a deposit of at most that cap then ends at or before `E`, given the solve's accuracy and outside `getRoot`'s guard band: [maxDeposit.derivation.md](maxDeposit.derivation.md). The guard band is open.
6. A positive `maxDeposit` can be a deposit that mints no share: `deposit(maxDeposit)` then reverts `ZeroShares` in the core (ALMCore.sol:140).

## 2. Axioms and bounds used

C1, C2, B4, B5, B7 (the walk is the pool's swap, deposit.derivation.md 3.1). `amountsAt` exceeds the exact holdings by under `n` per token (subtracted floors, [roundingMargins.derivation.md](../ALMVaultSync/roundingMargins.derivation.md) 4.4). `getMintShares` returns `m <= (amount_t − r_t) N / K_t` per token with `K_t > 0` (Snapshot.sol:301-305, :323-325).

## 3. Proof

1, 3, 4 and the bound in 5 are the code's `min`, branch and guard: DepositOptimizationMath.sol:187-192 and :233-236 (1, 5), :195-197 (3), :201-202 (4).

2. Let `m = previewDeposit(a)`, `(S, x, Y)` its swap. For each token with `K_t > 0`, `m K_t <= N amount_t`, and the inequality holds trivially when `K_t = 0`. Weighted by `1` and `p0`:

    m (K_in(S) + p0 K_out(S)) <= N (kept + p0 Y).

The swap buys tokenOut at a price that rises from `p0` and pays at least the exact input (C1, C2), so `x >= p0 Y` and `kept + p0 Y <= a`. The cost is at least the exact holdings, `K_t(S) >= R_t(S)`, and the walk's fees only add. A range's holdings valued at the fixed price `p0` are least at spot: in range, `d/ds (L Q / s + p0 L s / Q)` vanishes at `s0` and changes sign there, and out of range the holdings are constant. So `K_in(S) + p0 K_out(S) >= R_in(s0) + p0 R_out(s0) >= V0`, the last since `A_t − n < R_t` and `convert` rounds down. Hence `m <= N a / V0 <= shares`.

5. The deposit's walk reads the balance `a ⊖ (r_in(T) + 3) <= a` (DepositOptimizationMath.sol:84) and the position's tokenIn plus `2n + 4 >= D_in − 1` (DepositOptimizationMath.sol:97). `getBalanceIn` does not fall as the position's tokenIn grows, so each step test turns true no later than with the cap's position, and the exact root moves toward spot as the balance falls and as the position's tokenIn grows. That the deposit's solve then ends at or before `E`: [maxDeposit.derivation.md](maxDeposit.derivation.md) sections 3.3 to 3.5, with `getRoot`'s guard band open.

6. Take a state whose walk reaches `E` with `out(E) < r_out(S) + K_out(S) / N` for every `S` of the band, a moved band (`cost(E) > 0`) and `shares` large enough that the guard of 4 passes. Then `maxDeposit >= min(floor(shares · V0 / N), cost(E)) > 0`. Given 5, its deposit ends at or before `E`, so `Y <= out(E)` and `m <= (Y − r_out(S)) N / K_out(S) < 1`. Its `previewDeposit` is 0 and `_swapAndMint` calls the core's mint with 0 shares (ALMVaultSync.sol:236). The guard prices the value bound at spot, not the capped amount, so it does not exclude the state. The other case of the same class: a non-asset leg worth under one price unit's output, where the solve buys nothing. Both are docs/audit-doc.md 6.4, Limit views that revert: `maxDeposit` is non-zero and the deposit reverts `ZeroShares`.

Tests: test/fuzz/libraries/DepositOptimizationMath/MaxDeposit.fuzz.t.sol:120 `testFuzz_Success_maxDeposit_ItsDepositMintsAtMostTheSharesWithinTheLimit`, :204 `testFuzz_Success_maxDeposit_ItsDepositMintsAtMostTheSharesWithoutTokenOut` (library, 2 and 5). test/fuzz/ALMVaultSync/MaxDeposit.fuzz.t.sol:291 `testFuzz_Success_maxDeposit_ItsDepositSucceedsWithinTheSwapCost`, :335 `testFuzz_Success_maxDeposit_ZeroWithADustNonAssetLegWithinTheRounding`, :459 `testFuzz_Success_maxDeposit_ZeroWhenTheSwapCostIsWithinTheFee`, :382 `testFuzz_Success_maxDeposit_ItsDepositMintsWithADustAssetLeg` (vault).

## 4. Constants

| Constant | Where | Sufficiency | Witness |
|---|---|---|---|
| `− n` on each token at spot | DepositOptimizationMath.sol:188, :190 | 2: `A_t − n < R_t` | none |
| `− 1` on the position's tokenIn, `+ 1` on its tokenOut at `E` | DepositOptimizationMath.sol:235 | [maxDeposit.derivation.md](maxDeposit.derivation.md) 3.4: the solve's exact move from the floored start, under 1 from `amountsAt` at `E` | none |
| the limit one unit toward spot | DepositOptimizationMath.sol:208-210 | maxDeposit.derivation.md 3.5: spare when the solve's error is under one unit | none |

## 5. Open

- The second half of 5, and so of 6, rests on [maxDeposit.derivation.md](maxDeposit.derivation.md), whose open part is `getRoot`'s guard band at the step that holds `E`.
- 6 is derived, not built: no test asserts a state with `maxDeposit > 0` and `previewDeposit(maxDeposit) = 0`. The code has no guard on the capped amount's shares.
