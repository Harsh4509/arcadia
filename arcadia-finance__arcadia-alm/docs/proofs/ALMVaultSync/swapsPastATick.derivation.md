# DepositOptimizationMath.computeSwap: the least deposit whose swap ends past a tick

Code: `src/vaults/libraries/math/DepositOptimizationMath.sol` `computeSwap` (:58-125), `getAmountOut` (:272-316), `getSqrtPrice` (:330-345), `src/shared/libraries/math/CLMath.sol` `getNextSqrtPrice` (:78-99), `src/vaults/types/Snapshot.sol` `getRounding` (:213-222). Pool behaviour: [PoolAxioms.md](../PoolAxioms.md). Tests: test/fuzz/ALMVaultSync/Deposit.fuzz.t.sol:1278 `testFuzz_Success_deposit_SwapsPastATick_LiquidityFalls`, :1389 `testFuzz_Success_deposit_SwapsPastATick_LiquidityRises`.

Notation: zeroForOne (asset token0), one core range (`n = 1`). `s0` spot, `sT` the price of the nearest spaced tick below spot, initialized by a foreign position, `L` the pool's liquidity on `[sT, s0]`, `L'` below `sT`, `T2` the second step's target (the next initialized tick or word end below `sT`), `f = fee / 1e6`, `Q = 2^96`, `B` the deposit. `m = 2n + 4` the walk's position margin (DepositOptimizationMath.sol:71) and `r_in(p) = n (ceil(Q / p) + 2) + 1` its balance margin (`getRounding`, Snapshot.sol:220-221, [roundingMargins.derivation.md](roundingMargins.derivation.md) 4.1 to 4.3). `x(p)`, `y(p)` the pool's cost (fee included) and output from `sT` to `p` at `L'`. `x_T`, `y_T` those from `s0` to `sT` at `L`. `p0(p)`, `p1(p)` the core's token0 and token1 at `p` as the walk reads them.

## 1. Statement

With

```
s1      = sT − ceil(Q / L')                 the first price at which the pool pays a wei past the tick
past    = s1 − 1
sold    = ceil(getAmount0Delta(sT, s0, L, true) / (1 − f)) + ceil(getAmount0Delta(past, sT, L', true) / (1 − f))
bought  = getAmount1Delta(sT, s0, L, false) + getAmount1Delta(past, sT, L', true)
total0  >= p0(past) + (the core's fee share of the swap) ,  taken as  amountsRoundedUp(past) + buffer0 + ceil(sold f) + ceil(Q / past) + 3
total1  <= p1(past) ,  taken as  amountsRoundedDown(past) + buffer1
least*  = ceil(bought (total0 + m) / total1) + sold + r_in(T2) + 3 + 2
```

a deposit `B >= least*` ends its swap strictly below `sT`, provided the computed root lies within one price unit short of the exact one ([QuadraticMath/getRoot.derivation.md](../QuadraticMath/getRoot.derivation.md) section 6).

## 2. Axioms and bounds used

- A1, A2 (amounts), B2, B5, B6, B7 (steps), D2 (targets), C2.
- `computeSwap`: step `k` reads `balanceNet = B − (r_in(target_k) + 3)` (DepositOptimizationMath.sol:84), and the position's tokenIn plus `feesIn + m` in its `last` test (DepositOptimizationMath.sol:97) and its solve (DepositOptimizationMath.sol:445).
- `CLMath.getNextSqrtPrice` floors the move to whole price units on the side that moves less (CLMath.sol:90, :96). `getAmountOut` floors the output to the solved price and returns `getNextSqrtPriceFromOutput` of it (DepositOptimizationMath.sol:298, :312-315).
- The root's accuracy: getRoot.derivation.md section 6.

## 3. Proof

Along a zeroForOne move from `sT` the walk's surplus `g(p) = (B − r_in(T2) − 3 − x_T − x(p)) p1(p) − (y_T + y(p)) (p0(p) + m)` is decreasing: `x`, `y`, `p0` rise and `p1` falls as the price falls. `B >= least*` gives `g(past) >= 0`: `sold` bounds `x_T + x(past)` from above (each step's input rounded up and its fee rounded up, `ceil(a / (1 − f)) = a + ceil(a f / (1 − f))` for integer `a`), `bought` bounds `y_T + y(past)` from above, `total0` and `total1` bound the core's amounts from the safe side (the whole swap fee bounds the core's share `feesIn` of it and the solve's fee term `ρ`, and `ceil(Q / past) + 3` bounds the position's floors), and the `+ 2` covers the floors of the normalized balances `α` and `β` (DepositOptimizationMath.sol:478-483), one ulp each worth at most a wei as `L' <= 2^128 <= sT Q`.

Step 1 (target `sT`) is not the last: its balance `B − r_in(sT) − 3 >= B − r_in(T2) − 3` as `T2 < sT`, and `g(sT) > g(past) >= 0` fails both `last` criteria (DepositOptimizationMath.sol:92, :98-104). The walk crosses to `sT` at `L'`.

Step 2. The exact root `s*` of `g` lies at or below `past`. The computed price lies within one unit short of it (getRoot.derivation.md section 6, the move's floor), so it is at most `past + 1 = s1`, and `getAmountOut`'s output is `floor(L' (sT − s1) / Q) >= floor(L' ceil(Q / L') / Q) >= 1`. The balance cap in `getAmountOut` (DepositOptimizationMath.sol:290-297) does not pull the price back: the balance less `x_T` is at least `sold − x_T`, the rounded-up cost to `past`, whose net part moves the price at least to `past` (B6). The end price `getNextSqrtPriceFromOutput(sT, L', amountOut)` is `sT − ceil(amountOut Q / L') <= sT − 1` (B7), and `T2` lies below `past` (in the tests' domain `L' > Q`, so `past = sT − 2`, against a tick spacing of at least `5e-5 sT` price units). The vault's exact output of `y_T + amountOut` with that limit delivers `y_T` at the tick and `amountOut` past it ([maxViews.derivation.md](maxViews.derivation.md) 3.2), so the pool ends below `sT`.

Both `ceil(Q / L')` and the `+ 1` are needed: the deposit is an exact output, so the end moves past `sT` only once the output past it grows by a wei, `ceil(Q / L')` units, and the solve floors its move, so the exact optimum must lie one unit further.

## 4. Constants

| Constant | Where | Sufficiency | Witness |
|---|---|---|---|
| `ceil(Q / L')` | `s1` | the first unit count past `sT` whose floored output is a wei (A1) | none |
| `+ 1` | `past` | the solve's floor of the move (CLMath.sol:90) | none |
| `+ 2` | `least*` | the floors of `α`, `β` | none |
| `m`, `r_in(T2) + 3` | `least*` | the walk's own margins, which the solve reads | none |

## 5. Open

- The two tests compute `least` as `ceil(bought total0 / total1) + sold + 2` (test/fuzz/ALMVaultSync/Deposit.fuzz.t.sol:1349-1351, :1460-1462), without `m` on `total0` and without `r_in(T2) + 3`. Their bound is not proven sufficient for the walk: it falls short of `least*` by `r_in(T2) + 3 + ceil(bought m / total1)` wei at most, which the two units past `sT` cover only when their cost, about `2 L' Q / sT^2` wei of token0, exceeds it.
- The root's accuracy near the quadratic's double root, as getRoot.derivation.md states it.
