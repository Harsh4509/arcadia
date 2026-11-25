# Settlement pays no flow more than its pro-rata share

Code: `src/core/types/PlanCache.sol` `getSettlementAmountsOut` (:282-381) and `getLevies` (:396-422), `src/shared/libraries/math/CLMath.sol` `convert` (:39-68).

## Notation

- `p` the trusted sqrt price, `P` its price, `c1(x, up) = convert(p, true, x, up)`, `c0(y) = convert(p, false, y, false)`. Above a sqrt price of 2^128, `convert` multiplies by `P'd = floor(p^2 / 2^64) / 2^128` rounding down and by `P'u = ceil(p^2 / 2^64) / 2^128` rounding up (CLMath.sol:44-53), `P'd <= P <= P'u`, `P'u - P'd <= 2^-128`.
- `S = supplyBefore`, `dv0 = c1(depositAssets0, down)` (:288), `dv1 = depositAssets1` (:368).
- `b = (amount0, amount1) - swapDelta - (depositAssets0, depositAssets1)` (:296-297), the existing aLP's tokens before the swap. Assumption B0: `b0, b1 >= 0` (else `getValue`, :254-261, values the negative side at zero). [ALMKeeperExtension/swapSettlement.derivation.md](../ALMKeeperExtension/swapSettlement.derivation.md) Lemma (E) proves B0 at every settlement under its assumption (T).
- `R = redeemValue = b1 + c1(b0, down)` (:298), `R^u = b1 + c1(b0, up)` (:299).
- `swapped = c1(|swapDelta.amount0|, down)` (:306), `swapped^u = c1(|swapDelta.amount0|, up)` (:307). `gain = swapDelta.amount1 - swapped^u` for a token0 sale (`swapDelta.amount0 < 0`), `swapDelta.amount1 + swapped` otherwise (:310-312).
- `v = value = max(R + gain, 0)` (:315), `Vu = v + (R^u - R) + (swapped^u - swapped)` (:316), both before the levies.
- `cost = R ⊖ v`, the `swapCost` passed to `getLevies` (:344, :354). `cost = R - v` whenever `cost != 0`, and `cost = 0` when the swap gained.
- `dL`, `rL` the levies, `R' = min(R, v + dL + rL)` the redeems' price (:362), `Vu' = Vu + dL + rL` the deposits' divisor (:363).
- `F(x, y, d) = fullMulDiv(x, y, d) = floor(x y / d)` (solady's specification).
- `v*` the real value of the existing aLP after the swap, `P b0 + b1 + swapDelta.amount1 + P swapDelta.amount0` (`P'd` or `P'u` in place of `P` gives the same bounds below).

`Vu >= v*` and `v <= max(v*, 0)` under B0. For a sale of `in`: `v = floor(P b0) + b1 + out - ceil(P in) <= v*` and `Vu = ceil(P b0) + b1 + out - floor(P in) >= v*`. For a purchase of `out0` (or no swap): `v = floor(P b0) + b1 - in + floor(P out0) <= v*` and `Vu = ceil(P b0) + b1 - in + ceil(P out0) >= v*`. In both cases `v* <= R^u + gain + (swapped^u - swapped)`. When `R + gain < 0` the clamp sets `v = 0`, and `Vu = (R^u - R) + (swapped^u - swapped) > (R + gain) + (R^u - R) + (swapped^u - swapped) >= v*`.

## 1. Deposits get at most `F(dv, S, Vu)`, so at most their part of the real value

For the deposit in the swap's input token (`dv0` when `swapDelta.amount0 < 0`, else `dv1`) `shares = F(dv - dL, S, Vu')`, and for the other deposit `shares = F(dv, S, Vu')` (:369-379). `dL <= dv`: `getLevies` caps the deposit levy at `depositIn` (:420), which is that deposit's value. So

```
shares <= F(dv, S, Vu')   Lemma M (monotone in the amount), dv - dL <= dv
       <= F(dv, S, Vu)    Lemma D (never rises with the divisor), Vu <= Vu'
       <= dv * S / v*     Vu >= v* > 0
```

and `F(dv, S, Vu) <= F(dv, S, v)` by Lemma D with `v <= Vu`. A deposit gets at most its value's part of the supply at the real value of the existing aLP after the swap, so the existing holders are not diluted.

The divisor is nonzero: the division runs only for a deposit whose value after the levy is nonzero (:378-379), then `dv0 + dv1 != 0`, the `ZeroValue` check (:320) gives `v != 0`, and `Vu' >= Vu >= v > 0`. A deposit whose value after the levy is 0 skips the division and gets 0.

Lemma M: test/symbolic/libraries/FixedPointMathLib.symbolic.t.sol:21 `prove_fullMulDiv_IsMonotoneInTheAmount`, for `x2 * y < 2^256`.
Lemma D: test/symbolic/libraries/FixedPointMathLib.symbolic.t.sol:47 `prove_fullMulDiv_NeverRisesWithTheDivisor`, for `x * y < 2^256`, any divisors.

Both hold whenever `dv * S < 2^256`, so for every uint128 deposit value and supply.

## 2. Without a swap each flow is its floored pro-rata share at a bound of the value

`swapDelta = 0` gives `swapped = swapped^u = 0`, `gain = 0`, `v = R`, `Vu = R^u` and `cost = 0`, so `getLevies` returns `(0, 0)` (:407), `R' = R` and `Vu' = R^u`. Then

```
assets1 = F(R, redeemShares1, S)
assets0 = c0(F(R, redeemShares0, S))
shares_i = F(dv_i, S, R^u)          for each nonzero deposit, 0 otherwise
```

The redeems get the floor of their part of `R <= v*`, the deposits the floor of their part of the supply at `R^u >= v*`: each flow is rounded against itself. `R^u - R = c1(b0, up) - c1(b0, down)`: in `{0, 1}` up to a sqrt price of 2^128 (0 exactly when `P b0` is an integer), and at most 2 above it for `b0 < 2^128` (`ceil(b0 P'u) - floor(b0 P'd) < b0 2^-128 + 2 < 3`).

## 3. Each redeem gets at most its part of the value before the swap

Lemma R: `F(a + c, s, S) <= F(a, s, S) + c` for integers `a, c >= 0` and `s <= S`. With `x = a s / S` and `y = c s / S <= c`: `floor(x + y) <= floor(x) + ceil(y) <= floor(x) + c`, the first since `floor(x + y)` is an integer below `floor(x) + 1 + ceil(y)`, the second since `c` is an integer at least `y`. It rests on `F` being the exact floor of the 512-bit quotient (node_modules/solady/src/utils/FixedPointMathLib.sol:455-512), not machine-checked.

For a redeem with shares `s <= S` (`assets_i = F(R', s, S)`, :366-367):

- The redeem in the swap's input token, or either redeem without a swap, gets `F(R', s, S) <= F(R, s, S)`, its part of the existing value before the swap, and `<= F(v + dL + rL, s, S)`.
- The redeem in the swap's output token (`assets1` when `swapDelta.amount0 < 0`, else the token0 redeem before `c0`) gets `out = F(R', s, S) - rL` (:371, :374). So `out <= F(R, s, S) - rL <= F(R, s, S)`, and by Lemma R `out <= F(v + dL + rL, s, S) - rL <= F(v + dL, s, S)`. `dL <= depositIn <= dv0 + dv1`, all values in token1, so `out <= F(v + dv0 + dv1, s, S)`.

The subtraction does not underflow: `rL <= redeemOut = F(s, v, S)` (:324-325, :421), and when `cost != 0` the price `R' >= v` (`R = v + cost >= v`), so `F(R', s, S) >= F(v, s, S) >= rL`. When `cost = 0` the levies are 0. Token0 payouts go through `c0` (:380), which is non-decreasing, so every bound in value carries over to the token0 amount.

## 4. Open

A symbolic run on the whole function (eight `fullMulDiv`s and `getLevies`' six on symbolic inputs) does not complete, so sections 1 to 3 compose lemmas and are not checked in one run.
