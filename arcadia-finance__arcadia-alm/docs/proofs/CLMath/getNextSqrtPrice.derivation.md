# CLMath.getNextSqrtPrice: the unchecked subtractions

Code: `src/shared/libraries/math/CLMath.sol` `getNextSqrtPrice` (:78-99), its unchecked block :84-98. Its one caller: `DepositOptimizationMath.getSqrtPrice` (`src/vaults/libraries/math/DepositOptimizationMath.sol:343-344`), reached from `computeSwap` (:108-110) through `getAmountOut` (:280). Pool behaviour: [PoolAxioms.md](../PoolAxioms.md).

Notation: `s = sqrtPriceOld = state.sqrtPriceX96`, `B = sqrtPriceBound = state.position.sqrtPriceBound`, `δ = sqrtPriceDelta`, the root `QuadraticMath.getRoot` returns, `u = 2^192`, `F(x, y, d) = floor(x y / d)` (`fullMulDivUnchecked`, no revert on overflow, `fullMulDivN(x, y, 192) = F(x, y, u)`).

## 1. Statement

At the call, for a pool price above `MIN_SQRT_RATIO`:

1. Zero for one, `1 <= B <= s`. One for zero, `s <= B < 2^160` and `s >= 1`. So `s − B` (:87) and `B − s` (:93) do not underflow and neither division is by zero.
2. Past the early return `δ < u` in both directions. So `s − F(s, δ, u)` (:90) is in `[B, s]`, `u − δ` (:96) is positive, and `F(s, u, u − δ)` is below `B`: both casts to `uint160` are exact.
3. A pool at exactly `MIN_SQRT_RATIO` with liquidity breaks 1 for zero for one: `B = s + 1` and `s − B` wraps to `2^256 − 1`. No swap ends there (D1), so the pool was created at that price and never traded. Degenerate, the state the block's comment excepts (:83).

`δ` itself can exceed `u`: `getRoot` returns up to `2 · ratio < 2^193` on its interior ([QuadraticMath/getRoot.derivation.md](../QuadraticMath/getRoot.derivation.md) section 2, step 4), for example `a = 10 u`, `b = 31 u`, `c = 22 u`, whose roots are `1.1` and `2`.

## 2. Proof

### 2.1 The bound is on the swap's side

`getPosition` starts the bound at `PoolLogic.sqrtPriceLimit`, `MIN_SQRT_PRICE + 1` or `MAX_SQRT_PRICE − 1` (`EquivalentPositionMath.sol:51`, `PoolLogic.sol:56-61`), and moves it only to a range edge strictly past the price it is called at, in the swap's direction (`EquivalentPositionMath.sol:62-68`). So at the price `p` of the call, `B < p` or `B = MIN_SQRT_PRICE + 1` (zero for one), `B > p` or `B = MAX_SQRT_PRICE − 1` (one for zero).

The walk's position is computed at spot (`SwapState.sol:89`) and renewed whenever the walk's price lands on the bound (`SwapState.sol:230-232`). Between renewals the walk's price stays on the start's side of the bound: the bound is the edge of a range with liquidity (`EquivalentPositionMath.sol:56`), so its tick is initialized ([WithdrawOptimizationMath/getNormalizedParameters.derivation.md](../WithdrawOptimizationMath/getNormalizedParameters.derivation.md) section 3.3), every step's target is the next initialized tick, a word end or the limit (D2, E1 to E3, `SwapState.sol:107-116`), and a step never passes its target. So the walk lands on the bound before it can pass it, and the solve runs at a step's start (`DepositOptimizationMath.sol:108-110`).

Zero for one: `B <= s` unless `B = MIN_SQRT_PRICE + 1 > s`, which is `s = MIN_SQRT_RATIO` (G5: every pool price is at least it). One for zero: `B >= s` always, as `s <= MAX_SQRT_RATIO − 1` (G5). `B >= MIN_SQRT_PRICE + 1 > 0` and `s >= MIN_SQRT_RATIO > 0`.

### 2.2 Past the early return

Zero for one. The return is taken when `δ >= F(s − B, u, s)` (:87). `(s − B) u / s < u` as `B >= 1`, so `F(s − B, u, s) <= u − 1`, the quotient fits and every `δ >= u` returns. Past it `δ < (s − B) u / s`, so `s δ / u < s − B` and `F(s, δ, u) <= s − B`: the difference at :90 is at least `B`.

One for zero. The return is taken when `δ >= F(B − s, u, B)` (:93), and `(B − s) u / B < u` as `s >= 1`. Past it `δ < (B − s) u / B`, so `u − δ > u s / B > 0` and `s u / (u − δ) < B`. The quotient at :96 is below `B < 2^160`.

### 2.3 The pool at `MIN_SQRT_RATIO`

`slot0.sqrtPriceX96 = MIN_SQRT_RATIO = 4_295_128_739`, zero for one, no core edge below spot: `B = 4_295_128_740`, `s − B = 2^256 − 1`, and :87 compares `δ` with the low 256 bits of `floor((2^256 − 1) u / s)`. Either branch returns a price at or below `B`, not one derived from the root. The same state leaves the step's target above the price, where the checked subtractions of `DepositOptimizationMath.sol:147` and `ALMVaultSync.sol:126` can revert ([ALMVaultSync/uncheckedMath.derivation.md](../ALMVaultSync/uncheckedMath.derivation.md) section 4).

## 3. Constants

None.
