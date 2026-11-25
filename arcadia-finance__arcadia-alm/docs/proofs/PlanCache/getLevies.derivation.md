# The levies against the swap's cost

Code: `src/core/types/PlanCache.sol` `getLevies` (:396-422), called from `getSettlementAmountsOut` (:338-358).

## Notation

- `swapped` (:306): `convert(trustedSqrtPriceX96, true, |swapDelta.amount0|, false)`, the token0 the swap moved, valued in token1.
- `cost`: the `swapCost` argument, which `getSettlementAmountsOut` passes as `redeemValue ⊖ value` (:344, :354), with `redeemValue` the existing aLP's value before the swap rounded down (:298) and `value = max(redeemValue + gain, 0)` its value after the swap (:315). `gain` is rounded down: `amount1 - convert(p, true, |amount0|, true)` for a token0 sale (:311), `amount1 + swapped` for a token0 purchase (:312). So `cost = min(max(-gain, 0), redeemValue)`: for a sale `ceil(P in) - out`, for a purchase `in - floor(P out)`, floored at 0 and capped at `redeemValue`. Above a sqrt price of 2^128 the ceiling and the floor are taken at the rounded-up and the rounded-down truncated prices of `convert`, which bracket `P`. In both cases `cost` is at least the swap's real cost `P in - out` or `in - P out` whenever it is below the cap. The function returns `(0, 0)` unless `cost != 0`, `swapped != 0` and `heldIn + heldOut != 0` (:407).
- `dS`, `rS`, `offset` (:410-413), `k = dS + rS - offset > 0` past :416.
- `U(x, y, d) = fullMulDivUp(x, y, d)`, `F(x, y, d) = fullMulDiv(x, y, d)`.

## 1. The code is a composition of three rounded-up parts

```solidity
levy = U(cost, min(k, swapped), swapped);                 // :419
depositLevy = min(U(levy, dS, dS + rS), depositIn);       // :420
redeemLevy = min(U(levy, rS, dS + rS), redeemOut);        // :421
```

Lemma A (test/symbolic/libraries/FixedPointMathLib.symbolic.t.sol:63 `prove_fullMulDivUp_APartOfAnAmountIsAtMostTheAmount`): `U(x, y, d) <= x` for `y <= d`, `d != 0`, `x * y < 2^256`.

Lemma B1 (test/symbolic/libraries/FixedPointMathLib.symbolic.t.sol:90 `prove_fullMulDivUp_APartRoundedUpAndTheRestFlooredMakeTheAmount`): `U(x, a, a + b) + F(x, b, a + b) = x` for uint128 `a`, `b`, `a + b != 0`, `x * (a + b) < 2^256`.

Lemma B2 (test/symbolic/libraries/FixedPointMathLib.symbolic.t.sol:77 `prove_fullMulDivUp_ExceedsFullMulDivByAtMostOne`): `U(x, y, d) <= F(x, y, d) + 1` for `x * y < 2^256`, `d != 0`.

Together: `U(x, a, a + b) + U(x, b, a + b) <= U(x, a, a + b) + F(x, b, a + b) + 1 = x + 1` (Lemma B).

## 2. The bounds

- `levy <= cost`: Lemma A with `x = cost`, `y = min(k, swapped) <= swapped = d` (:419).
- `depositLevy <= levy <= cost`: the `min` at :420, then Lemma A with `x = levy`, `y = dS <= dS + rS = d` (`k > 0` gives `dS + rS > 0`). The same for `redeemLevy` at :421.
- `depositLevy + redeemLevy <= U(levy, dS, dS + rS) + U(levy, rS, dS + rS) <= levy + 1 <= cost + 1`: the two `min`s, then Lemma B with `x = levy`, `a = dS`, `b = rS`.

The lemmas' domain holds whenever the flows and holdings are below `2^127` and `cost` below `2^128`: `dS <= depositIn`, `rS <= redeemOut` (each a floored part of a flow, :410-411), so `min(k, swapped) <= dS + rS < 2^128` and both products stay below `2^256`. Past it the steps rest on solady's `fullMulDiv` being the floor of the 512-bit quotient (node_modules/solady/src/utils/FixedPointMathLib.sol:455-512), not machine-checked.

## 3. The bound is tight: the sum can be one wei past the cost

Two ceilings of halves overshoot by one when the levy is odd. At a price of one, a token0 sale of `2h` for `2h - f` token1 at an odd fee `f <= 2h`, an existing value `redeemValue >= f`, and two flows of `2h` over equal holdings: `swapped = 2h`, `cost = 2h - (2h - f) = f`, `dS = rS = F(2h, held, 2 held) = h`, `offset = 0`, `k = 2h`, `levy = U(f, 2h, 2h) = f`, each levy `min(ceil(f / 2), 2h) = (f + 1) / 2`, together `f + 1 = cost + 1`. The smallest member is `h = 1`, `f = 1`: a sale of 2 token0 for 1 token1, cost 1, levies 1 and 1, from the three lines of section 1. The same inputs sit inside the domain of test/fuzz/libraries/PlanCacheLib/GetLevies.fuzz.t.sol:49 `testFuzz_Success_getLevies_EachLevyIsItsShareRoundedUp` (`deposit = redeem = 1`, `sold = 2`, `fee = 1`), which asserts each levy is `ceil(fee * deposit / (deposit + redeem)) = 1`.

So "the levies never exceed the swap's cost" holds per levy and fails for their sum by one wei. The extra wei cannot raise a redeem past its share of the value before the swap: `getSettlementAmountsOut` prices the redeems at `min(redeemValue, value + depositLevy + redeemLevy)` (:362), and `value + cost = redeemValue` whenever `cost != 0`. It stays with the core: it raises the divisor of the deposit shares (:363) and the redeems' price up to that cap.
