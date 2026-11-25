# DepositOptimizationMath.getQuadraticCoefficients: the coefficients fit `int256`, `A >= 0`, and the run-out cap fits

Code: `src/vaults/libraries/math/DepositOptimizationMath.sol` `getQuadraticCoefficients` (:362-406), its unchecked block :381-405, `getNormalizedParameters` (:423-487), `getAmountOut` (:272-316), its unchecked block :301-307, `MAX_NORMALIZED` (:35). Pool behaviour: [PoolAxioms.md](../PoolAxioms.md). `H1` to `H6`: [ALMVaultSync/uncheckedMath.derivation.md](../ALMVaultSync/uncheckedMath.derivation.md) section 1.

Notation: `u = 2^192`. The outputs of `getNormalizedParameters`: `α = balanceInNormalized`, `β = balanceOutNormalized`, `ω = positionLiquidityNormalized`, `εIn`, `εOut` the position's normalized amounts, `ρ = feeTerm`. `fee = state.fee`, `Φ = floor(fee · u / (1e6 − fee))`, `κ' = feeFactor = floor(1e6 · u / (1e6 − fee))` (:387). `W = state.position.liquidity`, `U = state.position.unstakedLiquidity`, `L = state.liquidity`, `s = state.sqrtPriceX96`. `F(x, y, d) = floor(x y / d)`, the value of `fullMulDiv`, and of `fullMulDivN(x, y, 192)` at `d = u`.

## 1. Statement

At every call that returns:

1. Bounds of the inputs: `α, β <= 2^252`, `ω, εIn, εOut <= u`, `ρ <= Φ < u / 9`, `κ' = u + Φ < 10 u / 9`.
2. No operation of :381-405 wraps and every `int256` cast is exact: `|C| <= 2^252`, `0 <= A < 2^252 + 2^193`, `−2^252 <= B < 2^254`.
3. `A >= εIn >= 0`: `getRoot`'s `a >= 0` from the deposit. `A = 0` needs `εIn = 0`.
4. One for zero, `s + F(balanceInLessFee, 2^96, L) <= s (1 + 2^60) < 2^221`: the sum of :304 does not wrap, and the cast of :302 is of a value at most `sqrtPriceNew < 2^160`.

## 2. Bounds used

- G1: `fee <= 100_000`, so `1e6 − fee >= 900_000` (:387, :473).
- `U <= W`. `getPosition` adds `range.liquidity` to `W` and `range.unstakedLiquidity` to `U` for the same ranges (`EquivalentPositionMath.sol:76-77`), and `range.liquidity = positionLiquidity + stakedLiquidity >= positionLiquidity = range.unstakedLiquidity` (`Snapshot.sol:135`, :137, the sum exact by H5).
- `feeShare <= 1e10`: `(1e6 − unstakedFee)(1e4 − protocolSwapFeeBps)` with G2 and H2 (`Snapshot.sol:79-82`).
- `MAX_NORMALIZED = 2^252`, checked at :486 on both balances.

## 3. Proof

### 3.1 The inputs

`α, β <= 2^252`: `getNormalizedParameters` reverts `AmountInTooLarge` otherwise (:486).

`ω, εIn, εOut <= u`: each is `F(x, u, largest)` with `largest` the maximum of the three values `x` and 1 (:457-463), so `x <= largest`.

`κ' = u + Φ`: `1e6 · u = (1e6 − fee) u + fee · u`, and the floor of a sum with an integer term splits. `Φ <= fee · u / (1e6 − fee) <= u / 9` (G1), and `u / 9` is not an integer, so `Φ < u / 9`.

`ρ <= Φ`: for `U > 0`, `g = F(ω, U · feeShare, W · 1e10)` (:470-472) and `ρ = F(Φ, g, u)` (:473). `U · feeShare <= W · 1e10` (section 2), so `g <= ω <= u` and `ρ <= Φ`. For `U = 0`, `ρ = 0` (:467). `U > 0` implies `W > 0`, so the divisor is not zero.

### 3.2 The block

- `C` (:383-384). `F(α, εOut, u) <= α <= 2^252` and `F(β, εIn, u) <= β <= 2^252`. Both casts are exact and the difference is in `[−2^252, 2^252]`.
- `κ'` (:387). `1e6 << 192 < 2^212`.
- `A` (:390-393). `α + κ' − u = α + Φ <= 2^252 + u / 9`, no wrap in either order. `F(α + Φ, ω, u) <= α + Φ`. With `εIn <= u` the sum is below `2^252 + 2^193 < 2^255`: the cast is exact.
- `B` (:396-400). `α + β <= 2^253`, `F(α + β, ω, u) <= 2^253`, `F(κ', εOut, u) <= κ' < 2^193`, `εIn <= u`. The sum is below `2^253 + 2^194 < 2^255`: the cast is exact. With `C` the total is below `2^252 + 2^253 + 2^194`.
- The fee term (:403-404). `ρ < 2^189`, so `A − ρ > −2^189`. `F(β, ρ, u) <= β ρ / u < 2^249`. `B < 2^252 + 2^253 + 2^194 + 2^249 < 2^254`, and `B >= C >= −2^252`.

### 3.3 `A >= 0`

`A = F(α + Φ, ω, u) + εIn − ρ` (:390-393, :403, with `κ' − u = Φ`). `F` is monotone in each factor, so

```
F(α + Φ, ω, u)  >=  F(Φ, ω, u)  >=  F(Φ, g, u)  =  ρ,
```

the second step by `g <= ω` (3.1). Hence `A >= εIn >= 0`.

This is the argument of [QuadraticMath/getRoot.derivation.md](../QuadraticMath/getRoot.derivation.md) section 5, first bullet, with its two premises derived in section 2 above. It needs no bound on the balances beyond 3.2, and no assumption on the sign of the position's constants.

### 3.4 The run-out cap

One for zero, `getAmountOut` calls `getSqrtPrice` first (:280), which reaches `getNormalizedParameters` with the same `balanceIn` and `state`. It returns only if

```
F(x, 2^160, s) <= 2^252,   x = F(balanceIn, 2^128, L)                          (:480, :486).
```

`F(x, 2^160, s) <= 2^252` gives `x 2^160 < (2^252 + 1) s`, so `x < 2^92 s + s / 2^160 < 2^92 s + 1` (G5: `s < 2^160`), and `x <= 2^92 s`. Then `balanceIn · 2^128 / L < x + 1`, so `balanceIn · 2^96 / L < 2^60 s + 2^-32`. `balanceInLessFee <= balanceIn` (:286), so

```
F(balanceInLessFee, 2^96, L)  <=  2^60 s.
```

The sum `s + F(...)` is at most `s (1 + 2^60) < 2^221` and does not wrap. `fullMulDiv` does not revert (the quotient fits, `L > 0` on the walk, :77). The cast `uint160(min(sqrtPriceNew, sum))` (:302-306) is of a value at most `sqrtPriceNew`, a `uint160`.

Zero for one the cap is `getNextSqrtPriceFromAmount0RoundingUp`, checked (:293-295).

## 4. Constants

| Constant | Where | Sufficiency | Witness |
|---|---|---|---|
| `MAX_NORMALIZED = 2^252` | `DepositOptimizationMath.sol:35`, :486 | 3.2: every sum of the block is below `2^254`. 3.4: the run-out move is at most `2^60 s` | none. Not the least: the block's casts stay exact up to a cap of `2^253` (`α + β <= 2^254`, `B < 2^255`), and the sum of 3.4 wraps only past `2^256 − 2^160` |
| `2^60` in the comment of :300 | `2^252 / 2^192` | 3.4 | none, a consequence of the cap |

## 5. Symbolic support

`test/symbolic/libraries/DepositOptimizationMath.symbolic.t.sol:149` `prove_getQuadraticCoefficients_TheQuadraticCoefficientIsNonNegative` (z3int) asserts statement 3 on its domain (prices and balances below `2^128`, `U <= W`, fee share at most one). It does not finish. Statement 3 is derived here on every input.
