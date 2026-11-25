# getRoot rounding, and what the callers do with it

Code: `src/vaults/libraries/math/QuadraticMath.sol:33-51` `getRoot(int256 a, int256 b, int256 c)`. Callers: `DepositOptimizationMath.getSqrtPrice` (`DepositOptimizationMath.sol:340`) and `WithdrawOptimizationMath.getSqrtPrice` (`WithdrawOptimizationMath.sol:289`). No other site calls it.

Rounding of the solady 0.1.26 primitives used (`node_modules/solady/src/utils/FixedPointMathLib.sol`): `fullMulDiv` (:455) and `fullMulDivUnchecked` (:517) are `floor(x * y / d)`, `fullMulDivUp` (:548) is the ceiling, `sqrt` (:775) is the floor square root.

## Notation

- `u = 2^-192`, one unit of the 192-binary-precision inputs and output. "Units" below are units of `u`.
- Integers `a`, `b`, `c` as passed. Reals: `R = c / b`, `W = 4ac / b^2`, `q = sqrt(1 - W)`, exact root `X = 2R / (1 + q)`, the smaller root of `a x^2 - b x + c = 0` in the form the code uses, `X = 2c / (b + sqrt(b^2 - 4ac))` (`QuadraticMath.sol:23-30`).
- `ratio`, `D = 4 floor(a ratio / b)`, `S` the discriminant root, `x` the integers the code computes. `r = ratio * u`, `d = D * u`, `s = S / 2^127`, `X_c = x * u`.
- `e1, e2, e4` in `[0, 1)`: the fractional parts lost by the three floors (ratio, discriminant, final division). `eps_s` in `[0, 2^-127)`: the part the ceiling square root adds, at its own precision.

## 1. Guards and the domain of the interior

`QuadraticMath.sol:35-36`:

```solidity
if (c <= 0) return 0;
if (c >= b || uint256(a).fullMulDiv(uint256(c), uint256(b)) >= uint256(b) / 4) return 1 << 192;
```

After the guards: `c >= 1`, `b > c` so `b >= 2`, `a >= 0` (callers, section 5), and `floor(ac / b) < floor(b / 4)`.

- `floor(ac / b) < floor(b / 4)` implies `ac / b < b / 4`, so `4ac < b^2` strictly. The interior has a real root with `q > 0`.
- The converse fails on a band: inputs with `4ac < b^2` but `floor(ac / b) = floor(b / 4)` return `1 << 192`. On the band `ac / b` lies in `[floor(b / 4), b / 4)`, so `W` lies in `(1 - 4 / b, 1)`. For `b` near `2^192` that is `q < 2^-95`. The exact root there is `X = 2R / (1 + q)`, close to `2R`, and the function returns 1.
- `floor(b / 4) >= 1` is needed for any interior point, so `b >= 4` in the interior. For `b` in `{2, 3}` every `c` returns 1 (section 4).
- `uint256(a)` for `a < 0` is `2^256 + a`. Not reachable from the callers (section 5).

## 2. The interior, step by step

`QuadraticMath.sol:39-50`. Three floors and one ceiling. The bound `D <= 2^192 - 4` makes the unchecked subtraction safe and the final product fits the 512-bit path.

### Step 1, `ratio = c.fullMulDivUnchecked(1 << 192, b)` (:41)

`ratio = floor(c * 2^192 / b) = floor(R / u)`, so `r = R - e1 * u`. Loses `e1 < 1` unit, downward.

`ratio = 0` iff `c * 2^192 < b`.

### Step 2, `4 * a.fullMulDivUnchecked(ratio, b)` (:43)

`t = a * ratio / b = (W / 4) / u - (a / b) * e1`, and `floor(t) = t - e2`. So

```
d = D * u = W - eps_d,   eps_d = 4u * ((a / b) * e1 + e2)  in  [0, 4u * (a / b + 1)).
```

With `4ac < b^2`, `a / b < 1 / (4R)`, so `eps_d < u * (1 + 4R) / R`. The discriminant rounds down, so `1 - d` rounds up.

Bound: `t <= ac * 2^192 / b^2 < 2^190` by the guard, so `floor(t) <= 2^190 - 1` and `D <= 2^192 - 4`. The unchecked `(1 << 192) - D` is at least 4.

### Step 3, the ceiling square root (:43-46)

```solidity
uint256 radicand = ((1 << 192) - 4 * uint256(a).fullMulDivUnchecked(ratio, uint256(b))) << 62;
uint256 discriminantRoot = radicand.sqrt(); // 127 binary precision.
if (discriminantRoot * discriminantRoot < radicand) ++discriminantRoot;
```

`S = ceil(sqrt((1 - d) * 2^254)) = ceil(2^127 * q')`, `q' = sqrt(1 - d) = sqrt(q^2 + eps_d) >= q`. So `s = q' + eps_s`, `eps_s` in `[0, 2^-127)`. The radicand is at most `2^254`, so `S <= 2^127` and the denominator `2^127 + S` is at most `2^128`. The radicand is at least `2^64`, so `S >= 2^32`. At `a = 0` the radicand is exactly `2^254`, the floor square root is exact and the ceiling adds nothing.

### Step 4, `x = (2 * ratio).fullMulDivUnchecked(1 << 127, (1 << 127) + discriminantRoot)` (:49)

`x = floor(2 * ratio / (1 + s))`, so `X_c = 2r / (1 + s) - e4 * u`. The product `2 * ratio * 2^127 < 2^320` goes through the 512-bit path. The result is below `2 * ratio < 2^193`. Loses `e4 < 1` unit, downward.

## 3. Error of the interior, `a > 0`

```
X - X_c = 2R * eps_s / ((1 + q)(1 + s))        (A: the ceiling square root in the denominator)
        + 2R * (q' - q) / ((1 + q)(1 + s))     (B: the floored discriminant, through the square root)
        + 2 e1 u / (1 + s)                     (C: the floored ratio)
        + e4 u                                 (D: the final floor)
```

Every term is non-negative, so `X_c <= X` on every interior input: the root rounds down.

### Size

- `A < X * 2^-127 / (1 + s) <= X * 2^-127`, at most `2^66` units for roots near 2.
- `C + D < 2u / (1 + s) + u <= 3u`.
- For B, `q' - q = eps_d / (q + q')` and `R * eps_d = u * (W e1 + 4R e2)`:

```
B  <=  u (W e1 + 4R e2) / (q (1 + q)(1 + s))  <  5u / (q (1 + q)^2)
```

using `q' >= q`, `s >= q`, `W < 1`, `R < 1`.

Two regimes for B:

- Away from the double root (`q >= sqrt(eps_d)`, in practice any `q` above about `2^-95`): the bound above. `q = 1` (`W = 0`): `B < 1.25` units. `q = 1 / 2` (`W = 3 / 4`): `B < 4.45` units. `q = 2^-10`: `B < 5120` units.
- Near the double root (`q < sqrt(eps_d)`): `q' - q <= sqrt(eps_d)`, so `B <= 2R sqrt(eps_d) < 2 sqrt(u R (1 + 4R))`. In units, with `R / u < ratio + 1`: `B < 2 sqrt(5 (ratio + 1))` units, at most `2 sqrt(5) * 2^96`, about `2^98.2` units, or `2^-95` relative to a root near 1. The square root turns a `2^-192` error of the discriminant into a `2^-96` error of its root.

Downward bound, every interior input:

```
X - X_c  <  X * 2^-127 + min(5 / (q (1 + q)^2), 2 sqrt(5 (ratio + 1))) + 3   units.
```

State near the double root: `a = 7073324060253611866407234439993655827128101267085152528705787348803870`, `b = 28290530699856738163588324652525157579828045524446183240606196288311307`, `c = 28287765429018111863871024898243776527305882630557239904728653067436980`, the last interior point before the guard (`q = 1.29e-35`). B's bound there is about `2^98` units.

## 4. The other branches and the edges

- `a = 0`, `b >= 4`: `D = 0`, radicand `2^254`, `S = 2^127` exactly, `x = floor(2 * ratio * 2^127 / 2^128) = ratio = floor(c * 2^192 / b)`. The floored `c / b`, error in `(-1, 0]` units. `test/fuzz/libraries/QuadraticMath/GetRoot.fuzz.t.sol:83` `testFuzz_Success_getRoot_LinearWhenTheQuadraticTermIsZero`.
- `a = 0`, `b` in `{2, 3}`: `floor(b / 4) = 0`, the guard returns 1 for `c = 1` or `2`. Exact roots `1 / 2`, `1 / 3`, `2 / 3`. Degenerate: a linear coefficient of two or three units of `2^-192`.
- `a < 0`: unreachable from src (section 5). `uint256(a) >= 2^255`, and past the guard `4 floor(uint256(a) ratio / b)` can exceed `2^192`, so the unchecked subtraction underflows. The fuzz and symbolic domains exclude it.
- `ratio = 0` (`c * 2^192 < b`): `D = 0`, `S = 2^127`, `x = 0`. Exact root `X < 2R < 2u`: below by less than 2 units.
- The guard band (section 1): returns 1 where the exact root is near `2R`. Its interior neighbours are in the near-double-root regime of section 3, off by up to `2^-95` relative.

## 5. Callers

### Reachability of the branches

- `DepositOptimizationMath.getQuadraticCoefficients` (`DepositOptimizationMath.sol:362-406`). `feeFactor = floor(1e6 2^192 / (1e6 - fee)) = 2^192 + floor(fee 2^192 / (1e6 - fee))` (:387), so the first term of `A` is `floor((alpha + floor(fee 2^192 / (1e6 - fee))) omega / 2^192)` (:390-393). The fee term is `floor(floor(fee 2^192 / (1e6 - fee)) * f / 2^192)` with `f = floor(omega * omegaU * feeShare / (liquidity * 1e10)) <= omega`, since `omegaU <= liquidity` and `feeShare <= 1e10` (:470-473). So the fee term is at most the first term, and `A >= positionAmountInNormalized >= 0` after `quadraticCoefficient -= feeTerm` (:403). `a < 0` is unreachable.
- `WithdrawOptimizationMath.getQuadraticCoefficients` (`WithdrawOptimizationMath.sol:369`): `quadraticCoefficient = reserveOutNormalized + liquidityNormalized`, without a clamp. `reserveOutNormalized >= 0` at every call that returns ([getNormalizedParameters.derivation.md](../WithdrawOptimizationMath/getNormalizedParameters.derivation.md)) and `liquidityNormalized` is a `uint256`, so `a < 0` is unreachable. `a = 0` exactly when both terms are zero.
- `b <= 0` or `b <= c` in either caller: the guard returns 1 and the callers move to the bound.
- The near-double-root regime (`q` below about `2^-64`, where the downward error exceeds `2^-126` relative) needs the balance curve tangent to the position's curve. For the deposit with the balance product strictly decreasing and the position product strictly increasing in `delta`, the vertex `B / (2A)` lies at or beyond 1 and the smaller root is a transversal crossing. With a negative constant of the equivalent position the position product is not monotone and tangency is not excluded. Open.

### DepositOptimizationMath.computeSwap

`delta = getRoot(...)` (`DepositOptimizationMath.sol:340`) is the relative move of the square root price of tokenIn. `CLMath.getNextSqrtPrice` (`CLMath.sol:78-99`) returns the bound when `delta` reaches it (:87-89, :93-95), else `s0 - floor(s0 delta)` (zeroForOne, :90) or `floor(s0 / (1 - delta))` (oneForZero, :96). Both floors shorten the move. `getAmountOut` (`DepositOptimizationMath.sol:272-316`) caps the price at what `balanceInLessFee` reaches (:288-309), floors the output to that price (:298, :308), and recomputes the price from the output (:312-315). `computeSwap` (:58-125) keeps that price only within the step (:113-117), else walks on and solves in the next step.

- The root is at most the exact one (section 3). The move is short by at most `(5 / (q (1 + q)^2) + 3) * s0 * 2^-192` units of `sqrtPriceX96` plus `s0 delta 2^-127`, so the floored move is the exact move's floor or one unit less, away from the double root. A short move leaves a tokenIn surplus, which the mint does not take and `_swapAndMint` refunds (`ALMVaultSync.sol:245-250`).
- Beyond the step target: the step walks on and the next step solves again (`DepositOptimizationMath.sol:113`).

The core: `ALMCore.mint` prices the shares at the pool's actual amounts, so the existing holders receive full value whatever price the solve picked. `_swapAndMint` checks the mint against the payment and the swap's output (`ALMVaultSync.sol:242`) and the swap's fill (:230). With `bounded` the band is the swap's price limit (:214-218).

### DepositOptimizationMath.maxDeposit (`DepositOptimizationMath.sol:167-237`)

Does not call `getRoot`. It walks the pool to the price limit and caps the deposit by `getBalanceIn` there. The limit is moved one unit toward spot "for the solve's floors" (:204-210). A root at most the exact one ends `deposit(maxDeposit)`'s solve short of the limit on its own, so the margin carries no term for the root.

### WithdrawOptimizationMath.previewWithdraw

Notation, amounts in units of `2^-96` wei (`WithdrawOptimizationMath.sol:74`): `s` the step's start price, `L` the pool's liquidity on the step, `a = amountOut − state.amountOut` the tokenOut left to pay at the step's start, `A`, `B` the holdings `holdingsOut`, `holdingsIn` at the step's start, `W` the core's liquidity on the step, `e` the error of the computed price against the quadratic's exact root price, in price units (section 3: below `2^-30` for `s < 2^160` away from the double root).

What is solved. In the step where the cost binds at the step's end, `previewWithdraw` calls `getSqrtPrice` with the target `a + 1` (:102-111). The quadratic (:346-347) is in real amounts, with the token0 reserve floored once (`R = floor(L 2^192 / s)`, :423). Its smaller root is the crossing, for the target `a + 1`, of the shares that fund the sale (`F`, rising with the move) and the shares that pay the amount (`M`, falling with it). `getNextSqrtPrice` rounds the root's price to the nearest integer `r` (:319-321), clamped to `[s ± 1, target]` (:316, :322-330).

What is evaluated. `getSharesForAmounts` prices `r` (:113-116) and one neighbour (:118-125): `r` moved one unit toward less sale when the cost binds at `r`, toward more sale when it does not. Both use the walk's rounded amounts and the amount `a`. A candidate's shares are finite in two cases: the cost binds and is within the holdings' tokenIn (:259), or it does not bind and `0 < amountOutLeft <= holdingsOut` (:260-261). Every other candidate gets `type(uint256).max`. So a finite quote pays the amount.

Claim (a core without tokenOut and without liquidity on the step: `A = 0`, `W = 0`). With `e < 1/2`, the root or its neighbour pays the amount, and the paying candidate is below `p̂ + 1`, `p̂` defined below.

With `holdingsOut = 0`, `costBinds` is `amountOutLeft == 0` (:255-256): a candidate is finite iff the pool's rounded output to it is at least `a`.

Token0 out (the price rises). The walk's output to a price `p` is `out(p) = R − ceil(L 2^192 / p)` (:237-238). Let `d = L 2^192 mod s`, so `s R = L 2^192 − d`, `0 <= d < s`. Then

```
out(p) >= a   <=>   L 2^192 / p <= R − a   <=>   p >= x = (s R + d) / (R − a).
```

The quadratic is `R δ² − (R + a') δ + a' = 0` for a target `a'`, smaller root `δ = a' / R`, price `s / (1 − δ) = s R / (R − a')`. For `a' = a` that price is `x − d / (R − a)`: short of the least paying price by up to `s / (R − a)` price units, unbounded as `L / P` falls (`P = s² / 2^192`). For `a' = a + 1` the price is `p̂ = s R / (R − a − 1)`, and for every `p >= p̂`

```
L 2^192 / p  <=  (s R + d) (R − a − 1) / (s R)  =  (R − a − 1) (1 + d / (s R))  <  R − a,
```

since `d < s` and `R − a − 1 < R`. So `x <= p̂`. The computed `r` is at least `p̂ − 1/2 − e`. If `r` pays, it is a candidate. If not, the cost does not bind at `r`, the neighbour is `r + 1 >= p̂ + 1/2 − e > p̂ >= x`, and it pays. The paying candidate is below `p̂ + 1` in both cases.

Edges. `R − a >= 1` in the binding step, as the step's end pays. With `R − a − 1 = 0` the discriminant is zero, `getRoot` returns one, and `getNextSqrtPrice` returns the step's target, which pays. The clamp at `s + 1` only raises the price and the clamp at the target is a paying price.

Token1 out (the price falls). The output `L (s − p)` is exact (:230), so `out(p) >= a` iff `p <= s − a / L`. The root for `a + 1` is at `p̂ = s − (a + 1) / L`. If `r` does not pay, the neighbour is `r − 1 <= p̂ − 1/2 + e < p̂`, and it pays.

Size. For token0 out

```
p̂ − x  =  s R / ((R − a) (R − a − 1)) − d / (R − a)  <=  s R / ((R − a) (R − a − 1)),
```

about `P_end / L` price units: the move that buys one more unit of `2^-96` wei of token0. For token1 out `x − p̂ = 1 / L`. So the quote funds a sale at most one unit of `2^-96` wei of tokenOut plus one price unit longer than the least paying one. The withdrawer burns the shares of that extra cost and the holders keep it.

The constant `1` in `a + 1` (:105). Sufficiency is the display above. It is the least: amounts are integers in units of `2^-96` wei, and with the target `a` both candidates miss whenever `d / (R − a) > 3/2 + e`. No witness test.

The other states.

- `holdingsOut > 0` at both candidates: a candidate where the cost does not bind has the shares `M`, finite when `amountOutLeft <= holdingsOut`. The target `a + 1` moves the crossing toward more sale by the move that buys one unit of `2^-96` wei, which raises `M` at a fixed price by `N / holdingsOut` shares, under one share while the supply is below the holdings in units of `2^-96` wei.
- The rounded curves against the real ones in a thin pool. `getSharesForAmounts` rounds the core's parts (`step.amountIn − 2` floored, :245-246, `step.amountOut + 2` ceiled, :248) and the pool's token0 output (the `d` term). Model for `A > 0` or `W > 0`, in three steps. (1) Within a step the core's in-range liquidity pays out at most what it holds, `W_out δ <= A_true`, as the step ends at or before the core's edge, an initialized tick (`SwapState.sol:107-116`), and `A` is `A_true` less at most `n` wei (:58-59). (2) With `holdingsOut >= 1` wei at a candidate, the rounded evaluation (:246, :248) moves `amountOutLeft` and `holdingsOut` by at most `2 + 2 W / L + 1` units of `2^-96` wei, so the paying shares move by under `N 2^-94 / holdingsOut`: under one share. (3) With `holdingsOut = 0` and `W > 0` the root sits at `α / (1 − σ W / L)` instead of the least paying `α = a / R`, `σ` the burnt fraction. That state exists only within `n` wei of the core's edge, so the extra sale is at most `n σ L / (L − σ W)` wei of tokenOut, above the margins only when `W^2` is below about `n L` over the range's relative width: a dust core. An exact integer model of the walk and the pool finds no withdraw of at most `maxWithdraw` that fails to pay.
- Degenerate: the double root. At `δ = 1` the quadratic (:346-347) is `f(1) = (κ / B) (n W Q^2 + a W_in − A R_in)`. With `f(1) < 0` one root is below 1 and one above, so the roots are apart unless the root is near 1, which no swap inside a band is. `f(1) >= 0` needs `a W >= A (L + n)` up to the `n` terms, and then the paying curve `N (a − R δ) / (A − W_out δ)` is at least `N L / W >= N` wherever `holdingsOut > 0`, so no candidate there pays. With idle tokenOut (`A > 0`) the two curves touch only as the burnt fraction `σ` reaches 1 with `W = L`, which `DEAD_SHARES` exclude (`σ <= 1 − 1e6 / N`). Without it (`A = 0`, `W > 0`) the double root is at `δ* ≈ sqrt(B / (κ W s))`, within the step's move `ω` (the range's relative width) only when the range holds at most `n` wei of tokenOut: a dust core. A wrong root there costs only the quote's optimality, never payment: every finite candidate is priced by `getSharesForAmounts`. The lower bound on `q` in terms of `1 − σ W / L` is section 7.

Direction. The claim holds for either sign of the error while `e < 1/2`, so this caller needs no rounding direction from `getRoot`.

`maxWithdraw` (`WithdrawOptimizationMath.sol:146-185`) does not call `getRoot`: it is `previewRedeem(maxRedeem, roundingMarginIn)` less `roundingMarginOut` (:183-184). Its margins carry no term for the candidate's distance to the least paying price, so `previewWithdraw(maxWithdraw) <= maxRedeem` needs the slack of [roundingMargins.derivation.md](../ALMVaultSync/roundingMargins.derivation.md) section 5.

### Summary per caller

| Caller | Too-low root | Core absorbs | Revert in a normal state | Max view overstates |
|---|---|---|---|---|
| Deposit `computeSwap` | swap short, tokenIn refunded | yes, mint at actual amounts | no | n.a. |
| Deposit `maxDeposit` | ends short of the limit | n.a. | no | no |
| Withdraw `previewWithdraw` | the candidate pair moves one unit when the error crosses a half-integer. With the target `a + 1` the root or its neighbour still pays while `e < 1/2` (proven for `A = 0`, `W = 0`, model otherwise) | holders gain the difference | excluded for `A = 0`, `W = 0` with `e < 1/2`, model in a thin pool, degenerate near the double root | `previewWithdraw(maxWithdraw) <= shares`: open to the slack of roundingMargins section 5 |

## 6. Rounding direction the callers need

### Principle

A view may misstate a user-facing amount only toward the side on which execution cannot revert and existing holders cannot lose: `previewDeposit` at or below the shares the core mints, `maxDeposit` at or below what executes within the limit, `previewWithdraw` at or above the shares burned, `maxWithdraw` at or below what the withdraw pays. The core prices every mint and burn at the pool's actual amounts, so the views' rounding decides only what the depositor or withdrawer is promised.

### Deposit: `DepositOptimizationMath.getSqrtPrice` (`DepositOptimizationMath.sol:330-345`)

- The root is the relative move at which the swapped balances hold tokenIn and tokenOut in the position's ratio: the end price of the deposit's own swap.
- Chain to the user-facing amount: `delta` to the price (`CLMath.sol:90`, :96, both floors shorten the move), the price capped at the full sale of the net balance (`DepositOptimizationMath.sol:288-309`), the output to that price rounded down (:298, :308), then `getMintShares` (`Snapshot.sol:287`) on the balances left, which takes the smaller of the two tokens' share counts. The asset's surplus is refunded (`ALMVaultSync.sol:245-250`), the other token's surplus stays in the vault.
- A smaller `delta` is a shorter swap: less tokenOut bought, more tokenIn kept, the mint binds on tokenOut and the tokenIn surplus is refunded. A larger `delta` buys tokenOut the position's ratio does not need, the mint binds on tokenIn and the tokenOut surplus stays in the vault at the depositor's cost. So the root must round down. Every other rounding on the chain points that way: the normalized balances (`DepositOptimizationMath.sol:478-483`, floors), `ratio` (`QuadraticMath.sol:41`, floor), the price, the output.
- Magnitude: the move lands short of the exact one by under one unit of `sqrtPriceX96` plus `e * s1^2 / (s0 * 2^192)` units from the floored `ratio` (`e` in `[0, 1)`), so by at most one unit unless the swap multiplies the square root price by about `2^40` or more.

### Withdraw: `WithdrawOptimizationMath.getSqrtPrice` (`WithdrawOptimizationMath.sol:276-293`)

- The root selects candidate prices only. The shares at each candidate come from `getSharesForAmounts` with the pool's rounding (cost up, output down) and the amount `a`. `previewWithdraw` returns the minimum over the step ends, the root price and its neighbour (:93, :116, :125).
- The claim of section 5 holds for a root error of either sign under half a price unit, so no direction is unsafe. The paying candidate is under one price unit past the crossing for `a + 1`.

### Conclusion

Both callers accept a root that rounds down, and the deposit requires it. `getRoot` rounds down on every interior input (section 3) and is exact at `a = 0` (section 4). No caller needs a root that rounds up.

## 7. The withdraw quadratic: `q` against the liquidity the burn leaves

Code: `src/vaults/libraries/math/WithdrawOptimizationMath.sol` `getQuadraticCoefficients` (:349-373), `getNormalizedParameters` (:390-472), `getSharesForAmounts` (:207-262). Notation of the withdraw paragraphs of section 5 and of [WithdrawOptimizationMath/getNormalizedParameters.derivation.md](../WithdrawOptimizationMath/getNormalizedParameters.derivation.md): `B`, `A` the holdings, `C` the cost so far, `a` the solve's target, `R`, `W_out` the pool's and the position's tokenOut reserve, `R_in`, `W_in` their tokenIn reserve, `R_in` at the liquidity `L + n`, `κ = 1 / (1 − f)`. The quadratic is taken in real amounts, the exact terms of that file's section 3.7, divided by `B`:

```
a_q = R' + ν,   b_q = R' + a' + h,   c_q = a',
R' = R − C W_out / B,   a' = a − C A / B,   h = κ (A R_in − a W_in) / B,   ν = κ n W 2^192 / B      (:346-347, :414-454).
```

`X` is its exact smaller root, `q = sqrt(1 − 4 a_q c_q / b_q^2)`.

### 7.1 Statement

For `c_q > 0`, `a_q > 0` and `X < 1`:

1. `q = (c_q − a_q X^2) / (c_q + a_q X^2)`.
2. With `y = c_q − a_q X`: `q = (y + a_q X (1 − X)) / (y + a_q X (1 + X))`, and `y = (σ − C / B)(A − W_out X) − ν X`, where `σ = (C + K) / (B + G)` is the burnt fraction that funds the sale to the root, `K = κ R_in X / (1 − X)` the sale's cost and `G = κ W_in X / (1 − X)` the core's part of it. `0 <= σ − C / B <= σ`.
3. With `θ = (R − σ W_out) / (R' + ν)`, for `A >= 0` and `σ W_out <= R`:

   ```
   q  >=  (θ − X) / (θ + X),      θ  >=  (1 − σ W_out / R) / (1 + ν / R).
   ```

   Zero for one `W_out / R = W / L`, one for zero it is `W / L` up to the floors of :423-424. Equality holds at `A = 0`.
4. If the model's tokenOut left at the root covers the `n` term, `(σ − C / B)(A − W_out X) >= ν X`, then `q >= (1 − X) / (1 + X)`.
5. No bound holds uniformly in the state: at `A = 0`, `q = 0` exactly when `X = θ`.

So a root inside a step of relative move `δ_T` has `q >= (θ − δ_T) / (θ + δ_T)` when `θ > δ_T`, and the near-double-root regime of section 3 (`q` below about `2^-64`) needs `X > θ (1 − 2^-63)`: the burn and the sale together take all but `2^-63` of the tokenOut reserve `R` on the step. `σ <= 1 − 1e6 / N` (`DEAD_SHARES`, `ALMAdminExtension.sol:415`) and `W <= L` (getNormalizedParameters.derivation.md statement (II)) give `1 − σ W / L >= 1e6 / N`.

### 7.2 Proof

1. `a_q X^2 − b_q X + c_q = 0` gives `b_q = a_q X + c_q / X`, so `b_q^2 − 4 a_q c_q = (c_q / X − a_q X)^2`. `X` is the smaller root, `a_q X <= b_q / 2`, so `c_q / X >= a_q X` and `q = (c_q / X − a_q X) / (c_q / X + a_q X)`.

2. Substitute `c_q = y + a_q X`. For `y`: the quadratic times `B / (1 − X)` is the crossing of the funding and the paying shares,

   ```
   (C + K)(A − W_out X) = (a − R X)(B + G),
   ```

   since `R_in W_out − R W_in = n W 2^192` cancels the `κ` terms of `X^2` down to `ν B` (`R_in` is at `L + n`, :443-444). So `a − R X = σ (A − W_out X)`, and `a' − R' X = (a − R X) − (C / B)(A − W_out X) = (σ − C / B)(A − W_out X)`. `σ − C / B = (B K − C G) / (B (B + G))`, and `B K − C G = κ X (B R_in − C W_in) / (1 − X) >= 0` by `C <= B` and `W <= L` (getNormalizedParameters.derivation.md statements (I) and (II)).

3. `g(y) = (y + p) / (y + r)` with `0 <= p <= r` rises in `y` on `y > −r`. `A >= 0` gives `y >= −Λ X`, `Λ = (σ − C / B) W_out + ν`, and `Λ X < r = a_q X (1 + X)` as `a_q − Λ = R − σ W_out >= 0`. So `q >= g(−Λ X) = (a_q (1 − X) − Λ) / (a_q (1 + X) − Λ) = (θ − X) / (θ + X)` with `θ = (a_q − Λ) / a_q`. `R' <= R` gives the second bound. At `A = 0`, `y = −Λ X` exactly.

4. `y >= 0` and `g(y) >= g(0)`.

5. From 3 at `A = 0`.

### 7.3 Against the claims of section 5

- The `f(1)` argument: `f(1) = a_q − b_q + c_q = ν − h`, and `b_q^2 − 4 a_q c_q = (b_q − 2 c_q)^2 − 4 c_q f(1)`. Statement 4 covers `f(1) <= 0` and more: it needs only `y >= 0`.
- With idle tokenOut and the core's tokenOut not exhausted at the root, statement 4 gives `q >= (1 − X) / (1 + X)`: at least `1/3` for a root within half the price (`X <= 1/2`).
- The dust state of section 5 (`A = 0`, `W > 0`) is statement 5: `X = θ` is `σ W_out + (R' + ν) X = R`, the burn and the sale emptying the reserve.

The computed coefficients differ from these by the floors of getNormalizedParameters.derivation.md section 3.7. Their effect on `q` is not bounded here.
