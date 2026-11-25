# DepositOptimizationMath.maxDeposit: the deposit of at most the cap ends at or before the walk's limit

Code: `src/vaults/libraries/math/DepositOptimizationMath.sol` `maxDeposit` (:167-237), its limit :205-210 and its cap :229-236, `computeSwap` (:58-125), `getBalanceIn` (:252-259), `getAmountOut` (:272-316), `getQuadraticCoefficients` (:362-406), `getNormalizedParameters` (:423-487), `src/vaults/types/SwapState.sol` `setNextTick` (:100-117), `computeSwapStep` (:126-144), `getStepFees` (:153-166), `crossTick` (:198-234), `src/vaults/libraries/math/EquivalentPositionMath.sol` `getPosition` (:36-99), `amountsAt` (:109-124). Pool behaviour: [PoolAxioms.md](../PoolAxioms.md). Builds on [stepEndRounding.derivation.md](stepEndRounding.derivation.md), [ALMVaultSync/deposit.derivation.md](../ALMVaultSync/deposit.derivation.md) and [QuadraticMath/getRoot.derivation.md](../QuadraticMath/getRoot.derivation.md).

Notation, zero for one written out (prices fall), one for zero mirrors every inequality. `s0` spot, `s_E` the limit after :175-177 and :205-207, `E = min(s_E + 1, s0)` the walk's limit (:208-210). `c = 2n + 4` (:71). The view's walk at its end: `c_v = state.amountIn`, `o_v = state.amountOut`, `D_in^v`, `D_out^v` the amounts of :229-231, and

```
cap = c_v + floor(o_v · max(D_in^v − 1, 0) / (D_out^v + 1))                    (:233-236, :258).
```

The deposit `a <= cap`: `β = a ⊖ (r_in(T) + 3) <= a` its net balance at a step (:84). `j` the step that holds `E`: start `s_j > E`, target `T_j <= E`. At that step `A0`, `O0` the cost and output so far, `pos_j` the walk's position, `W` its liquidity, `b = β − A0`. Along the step, in exact arithmetic as the solve models it: `x*(p)` the cost with its fee, `y*(p)` the output, `Φ(p)` the core's fee share, `D_in^m(p) = amountsAt_in(pos_j, s_j) + W Q (1/p − 1/s_j)`, `D_out^m(p) = amountsAt_out(pos_j, s_j) − W (s_j − p) / Q`. `Ψ(p) = (b − x*(p)) D_out^m(p) − (O0 + y*(p)) (D_in^m(p) + c + Φ(p))`.

## 1. Statement

When the view's walk reaches `E` (:226), for every deposit `a <= cap`:

1. The deposit's walk does not take a step past `E` untested: the step test (:92-105) is true at step `j`, and at the step after it when `T_j = E`.
2. The exact root of that step's equation is at or before `E`: `Ψ(E) <= 0`, or the balance runs out before `E`.
3. So `computeSwap(a)` ends at a price at or before `E`, one unit inside `s_E`, given (a) the solve's price is within one unit of the exact root's on the far side ([stepEndRounding.derivation.md](stepEndRounding.derivation.md) 3.4: within `2^-32` of a unit for prices below `2^160`), and (b) `getRoot` does not return its guard value `2^192` (`QuadraticMath.sol:36`) for that step. With an error of (a) under two units it ends at or before `s_E`.
4. When the core holds no tokenOut at spot and the mint of the supply takes none (:195-197), the deposit swaps nothing.

Open: (b). `getRoot` returns `2^192` on a real root only inside its guard band (getRoot.derivation.md section 1), which here needs `A μ <= B`, with `μ = −(A δ_E^2 − B δ_E + C)` the quadratic's value at the limit's move `δ_E`, in units of `2^-192`. That the cap's slack keeps `A μ > B` is not derived.

## 2. Axioms and bounds used

- The deposit's steps are the pool's, and so the view's: `setNextTick` reads the walk's tick and the bitmap (D2, E1 to E3, `SwapState.sol:107-116`), and the limit only clips the last target.
- A1, A2, B2, B4 for the step amounts: `in↑`, `fee↑` rounded up, `in↓`, `fee↓`, `out↓` rounded down (`SwapState.sol:132-143`).
- The view rounds the step that ends on `E` down and every other step up (:218-220). The deposit rounds every step up (:80).
- `getRoot` rounds down and `getNextSqrtPrice` floors the move (getRoot.derivation.md section 3, `CLMath.sol:90`): the computed price is at or on the near side of the root of the computed quadratic.
- `amountsAt` of one position is monotone in the price: `floor(W Q / p)` rises and `floor(W p / Q)` falls as `p` falls (`EquivalentPositionMath.sol:115-116`).

## 3. Proof

### 3.1 The same state up to step `j`

A deposit's step before `j` either ends the walk inside it, before `E`, or is taken in full (stepEndRounding.derivation.md statement 5). A full step adds the same rounded-up cost, fee and fee share as the view's step, and `crossTick` is the same code (`SwapState.sol:207-232`). So at step `j` the deposit's state is the view's at the start of its last step.

### 3.2 The position at `E` is the walk's

Let `p_r` be the price `pos_j` was computed at (spot or the last core edge the walk landed on) and `bound` its `sqrtPriceBound`, the nearest core edge strictly below `p_r` (`EquivalentPositionMath.sol:62-64`). For every `p` in `(bound, p_r]` the ranges with `lower < p <= upper` (:71-73) are the same set: no core edge lies strictly between. So `getPosition` at such a `p` returns `pos_j`'s liquidity and constants, given the same idle tokens. The view's snapshot at its end holds the fee shares of its steps (`SwapState.sol:180-181`), which are those of `pos_j` plus the last step's floored share `φ_v`. Hence for `E > bound`:

```
D_out^v = amountsAt_out(pos_j, E),      D_in^v <= amountsAt_in(pos_j, E) + φ_v.
```

For `E = bound` (then `T_j = E`) the same holds with the position `crossTick` renews at `E` in place of `pos_j` (`SwapState.sol:230-232`).

### 3.3 The step test at step `j`, `T_j < E`

The deposit's test compares `β` with

```
G_j = getBalanceIn(A0 + in↑(T_j) + fee↑(T_j),  O0 + out↓(T_j),  amountsAt_in(pos_j, T_j) + feesIn + c,  amountsAt_out(pos_j, T_j))      (:95-104).
```

Against the cap's four arguments: `A0 + in↑(T_j) + fee↑(T_j) >= c_v` and `O0 + out↓(T_j) >= o_v` (a farther target, rounded up against down). `amountsAt_in(pos_j, T_j) + feesIn + c >= amountsAt_in(pos_j, E) + φ_v + c >= D_in^v − 1` (monotone, and the rounded-up share to a farther target is at least `φ_v`). `amountsAt_out(pos_j, T_j) <= amountsAt_out(pos_j, E) = D_out^v <= D_out^v + 1`. `getBalanceIn` does not fall in its first three arguments and does not rise in the fourth, and is `2^256 − 1` when the fourth is 0 (:257-258). So `G_j >= cap >= a >= β`: the test is true and the solve runs.

### 3.4 The exact root at step `j`, `T_j < E`

The quadratic of :357-358 is `Ψ` times `(1 − δ)` and the positive normalization: `α (1 − δ) − κ δ` is `(b − x*) (1 − δ)` over the pool's liquidity, `εOut − ω δ` is `D_out^m`, `β + δ` is `O0 + y*`, and `εIn + (ω + ρ − εIn) δ` is `(D_in^m + c + Φ)(1 − δ)`, `c` inside `εIn` (:445).

The model against the cap, at `E`:

- `D_in^m(E) > amountsAt_in(pos_j, E) − 1`: the two differ by `frac(W Q / s_j) − frac(W Q / E)`. With `Φ(E) >= φ_v` (a floor of a floored fee on a floored input) and `c >= 1`: `D_in^m(E) + c + Φ(E) > max(D_in^v − 1, 0)`.
- `D_out^m(E) < amountsAt_out(pos_j, E) + 1 = D_out^v + 1`: they differ by `frac(W E / Q) − frac(W s_j / Q)`.
- `c_v <= A0 + x*(E)` and `o_v <= O0 + y*(E)`: the view rounds the step to `E` down.

If `b < x*(E)` the balance runs out before `E`: the run-out price `K` (stepEndRounding.derivation.md 3.2) is above `E`, and the step ends at `max(P, K) > E`. Else, if `D_out^m(E) <= 0`, `Ψ(E) <= 0` term by term. Else

```
β  <=  cap  <=  A0 + x*(E) + (O0 + y*(E)) (D_in^m(E) + c + Φ(E)) / D_out^m(E),
```

which is `Ψ(E) <= 0`. With `Ψ(s_j) = C <= 0` the root is 0 and the price `s_j` (`QuadraticMath.sol:35`). With `C > 0` the quadratic is positive at 0 and not positive at `δ_E`, so its smaller root is at most `δ_E`: the exact root's price is at or above `E`.

### 3.5 The end of the walk

`T_j < E`. With (a) and (b) of the statement the solve's price `P` is above `E − 1`, so `P >= E`. `getAmountOut` returns `R >= max(P, K) >= E > T_j` (stepEndRounding.derivation.md statement 3), the step ends inside at `R` and the walk ends (`SwapState.sol:212`).

`T_j = E`. If the deposit's solve returns a price above `E`, the walk ends there. Else it takes the step to `E` and stops there when the pool's liquidity past `E` is zero or `E` is the pool's limit (:77, `SwapState.sol:212`). Else step `j + 1` starts at `E` with the position of 3.2, cost `A0' >= c_v` and output `O0' = o_v` (the same floor). Its test is true by 3.3 with `E` as the start. Its solve reads `amountsAt` at `E` itself (:443-444), with no drift, and

```
(β − A0') · D_out^v  <=  floor(o_v · max(D_in^v − 1, 0) / (D_out^v + 1)) · D_out^v  <=  o_v · (D_in^v + c):
```

the exact constant term is at most 0, the exact root is 0 and the price `E`. With (a) the computed price is `E`, the output 0, `R = E`, and the walk ends at `E` (:113-117, `SwapState.sol:212`).

### 3.6 No tokenOut at spot

:195-197 returns the value bound only when `amountsAt_out(s0) = 0` and the mint of the supply takes no tokenOut. Then every range's rounded-up tokenOut is 0 (`Snapshot.sol:255-260`), so each range has no liquidity or holds tokenIn alone, and the idle tokenOut is 0. Ranges holding tokenIn alone keep doing so as the price moves in the swap's direction (`EquivalentPositionMath.sol:81-88`), so the position's tokenOut is 0 at every price of the walk. At the first step `posOut = 0` makes the test true (:257), the solve has `εOut = 0` and `balanceOut = 0`, so `C = 0`, the root is 0 (`QuadraticMath.sol:35`), the output 0, and the walk ends at spot. With no pool liquidity the walk takes no step (:77).

## 4. Constants

| Constant | Where | Sufficiency | Witness |
|---|---|---|---|
| `+ 1` on the position's tokenOut | :235 | 3.4: the solve moves the tokenOut exactly from its floor at the step's start, under 1 above `amountsAt` at `E` | none. 1 is the least integer over a difference in `[0, 1)` |
| `− 1` on the position's tokenIn | :235 | 3.4: the same drift, under 1 below. Covered a second time by `c >= 4` in the deposit's read | none: `c` wei to spare |
| the limit one unit toward spot | :208-210 | 3.5: with the solve's error (a) under one unit the deposit ends at or before `E`, so the unit is spare. It makes an error under two units sufficient for `s_E` | none |
| the step to the limit rounded down | :218-220 | 3.4: `c_v <= A0 + x*(E)`, `o_v <= O0 + y*(E)`, `φ_v <= Φ(E)` | none |

## 5. Open

- (b) of statement 3: the guard band of `getRoot` at the step that holds `E`.
- (a) is taken from stepEndRounding.derivation.md 3.4, which states the coefficient floors' effect without a derivation per floor.
- No test asserts a state where the cap at `+ 0` or the limit at `s_E` fails.
