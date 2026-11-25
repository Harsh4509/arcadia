# DepositOptimizationMath.computeSwap at a step's end: the step test, the run-out price and the solve's price

Code: `src/vaults/libraries/math/DepositOptimizationMath.sol` `computeSwap` (:58-125), `getBalanceIn` (:252-259), `getAmountOut` (:272-316), `getSqrtPrice` (:330-345), `src/vaults/types/SwapState.sol` `computeSwapStep` (:126-144), `getStepFees` (:153-166), `crossTick` (:198-234), `src/shared/libraries/math/CLMath.sol` `getNextSqrtPrice` (:78-99), `src/vaults/libraries/math/QuadraticMath.sol` `getRoot` (:33-51). Pool behaviour: [PoolAxioms.md](../PoolAxioms.md).

Notation. zeroForOne, oneForZero mirrors every inequality with one wei of token0's price move in place of `Q / L`. `s0` the step's start (`state.sqrtPriceX96`), `T` its target (`step.sqrtPriceTargetX96`), `L` the pool liquidity, `Q = 2^96`, `f` the fee in 1e-6, `A0 = state.amountIn`, `O0 = state.amountOut`, `β = balanceNet` (DepositOptimizationMath.sol:84), `c = 2n + 4` the position margin (DepositOptimizationMath.sol:71).

- `in(x) = ceil(L Q (s0 − x) / (s0 x))`, `fee(x) = ceil(in(x) f / (1e6 − f))`, `out(x) = floor(L (s0 − x) / Q)`: the step's amounts to a price `x` (`computeSwapStep` with `roundUp`, SwapState.sol:132-143, A2, A1, B2, B4).
- `cost(x) = A0 + in(x) + fee(x)`.
- `C1 = cost(T) > β`, the first step test (DepositOptimizationMath.sol:92). `C2 = β <= G` with `G = getBalanceIn(cost(T), O0 + out(T), posIn(T), posOut(T)) = cost(T) + floor((O0 + out(T)) posIn(T) / posOut(T))`, `posIn(T) = amountsAt_in(T) + feesIn + c` (DepositOptimizationMath.sol:95-104), or `2^256 − 1` when `posOut(T) = 0` (DepositOptimizationMath.sol:257).
- `P` the price `getSqrtPrice` returns, `K` the run-out price (where `a = floor((β − A0) (1e6 − f) / 1e6)` moves the pool, DepositOptimizationMath.sol:286-297), `x* = max(P, K)`, `y = out(x*)` (DepositOptimizationMath.sol:298), `R` the price `getAmountOut` returns: `R = x*` when `x*` is the position's bound, else `R = s0 − ceil(y Q / L)` (DepositOptimizationMath.sol:312-315, B7).

## 1. Statement

In every step of `computeSwap`:

1. The step is last iff `C2`.
2. Under `not C1`, `K <= T`, so `x* = P` whenever `P >= K`. Under `C1`, `K > T`.
3. For `x*` short of the bound, `x* <= R < x* + Q / L`. With `L >= Q`, `R = x*`.
4. `|G − G*| < 3 + (1 + (O0 + out(T)) / posOut(T)) (1 + posIn(T) / posOut(T))`, `G*` the same deposit in exact arithmetic. The exact root `P*(β)` passes `T` iff `β > G*`, and `|P*(β) − T| <= |β − G*| s0^2 / (L Q)`. Away from the double root, `ceil(P*(β)) <= P <= ceil(P*(β)) + 1`.
5. A step whose solve returns a price at or past `T` is taken in full and the walk moves on, so a root past `T` is priced at the liquidity past `T`. A step whose solve returns a price strictly inside ends the swap there.

## 2. Axioms and bounds used

A1, A2, B2, B4, B6, B7, D2, D3. `getRoot` rounds its root down, its error near the double root reaching `2^98` units of `2^-192`: [QuadraticMath/getRoot.derivation.md](../QuadraticMath/getRoot.derivation.md) sections 3 and 6. `getNextSqrtPrice` floors `s0 δ` (CLMath.sol:90).

## 3. Proof

### 3.1 The second test implies the first

`G >= cost(T)`: `getBalanceIn` is a `saturatingAdd` of a nonnegative term to `cost(T)` (DepositOptimizationMath.sol:258). So `C1` implies `C2`, and `last = C1 or C2 = C2` (DepositOptimizationMath.sol:92-105).

### 3.2 The run-out price

Under `not C1`, `β − A0 >= in(T) + fee(T)`. Then `a >= in(T)`: `(in(T) + fee(T)) (1e6 − f) >= in(T) (1e6 − f) + in(T) f = in(T) 1e6`, since `fee(T) >= in(T) f / (1e6 − f)`, and `in(T)` is an integer. `getNextSqrtPriceFromAmount0RoundingUp(s0, L, a, true) = ceil(L Q s0 / (L Q + a s0))` is at most `T` once `a` is at least the exact input to `T`, which `in(T)` is. So `K <= T`.

Under `C1`, `β − A0 <= in(T) + fee(T) − 1`, and `fee(T) (1e6 − f) < in(T) f + (1e6 − f)` (a ceiling adds less than one), so `(β − A0) (1e6 − f) < in(T) 1e6`, `a <= in(T) − 1`, which is below the exact input to `T`: the price it reaches is above `T`.

### 3.3 The recomputed price

`y = floor(L (s0 − x*) / Q)` gives `ceil(y Q / L) <= s0 − x*`, an integer bound, so `R >= x*`. From `y > L (s0 − x*) / Q − 1`, `ceil(y Q / L) > s0 − x* − Q / L`, so `R < x* + Q / L`. With `L >= Q` the interval holds one integer.

For `x* = T`, `R > T` iff `ceil(out(T) Q / L) < s0 − T` iff `frac(L (s0 − T) / Q) >= L / Q`: a root exactly at the step's end ends the swap inside the step when `L < Q` and the step's tokenOut loses at least one price unit's worth to its floor.

### 3.4 The root against the step's end

`G` rounds `in`, `fee` and `feesIn` up, `out` and the position's amounts down (`amountsAt`, whose constants are floored in `getPosition`), and floors the quotient. The up roundings add less than `2 + (O0 + out(T)) / posOut(T)` wei plus the `posOut` floor's share `(O0 + out(T)) posIn(T) / posOut(T)^2`. The down roundings take less than `1 + posIn(T) / posOut(T)`. That is the bound on `|G − G*|`.

The exact root `P*(β)` falls as `β` grows, and `P*(G*) = T`. At the root, `(β − cost*(s)) D_out(s) = out*(s) D_in(s)`. A wei of `β` moves `s` by at most `1 / cost*'(s) = s^2 / (L Q)` units, the other terms of the derivative having the same sign. That gives the slope bound.

The computed root: `getRoot` rounds down, `getNextSqrtPrice` floors `s0 δ`, and the coefficients' floors are each under `2^-32` of a unit for `s0 < 2^160`, so `P >= P*(β) − 2^-32` and `P < P*(β) + 1 + 2^-32`. Near the double root the downward error of `getRoot` is up to `2^98 s0 / 2^192` units of price: under one unit for `s0 < 2^94`, at most `2^34` units at the largest prices.

### 3.5 What the end-of-step comparison does

Under `not C1`, `x* >= P` (3.2), so `R >= P >= ceil(P*(β))`.

- `C2` with `R` past `T`: needs `β > G*` up to the roundings of 3.4. `computeSwap` keeps `T` as the step's end (`sqrtPriceNew > T` is false, DepositOptimizationMath.sol:113), `crossTick` crosses `T` and the next step is solved at the liquidity past `T`. Ending the step at `R` with the current liquidity would misprice `T` to `R` whenever `T` is an initialized tick.
- `C2` with `R` strictly inside: the step ends at `R`, recomputed by `computeSwapStep` (DepositOptimizationMath.sol:114-116). `crossTick` returns false (SwapState.sol:212) and the walk ends.
- `not C2`: no solve runs, the walk takes the step and solves afresh in a later step. A solve there could return `R > T` (3.3, when `L < Q`), which would end the swap inside a step the balance passes.

A pool whose steps' tokenOut all floor to 0 (`L` of a few hundred, or spot under a wei of output from a range's edge) can quote `x > 0` for `Y = 0` with `S` moved off spot. `_swapAndMint` swaps whenever the quote's end price differs from spot (ALMVaultSync.sol:212), asking the pool for `max(Y, 1)` with `S` as the limit (ALMVaultSync.sol:223-228). With `Y = 0` every walk step's floored output is 0 (B4), so with 1 wei left each pool step reaches its target (B5) and the pool loops until the price is `S` (D1): it ends on `S`, takes the walk's input and fee per step (B2), `x` in total, and pays 0. The core mints at `S`, and the unused asset is refunded (ALMVaultSync.sol:247-250).

## 4. Constants

None of its own. The margins `r_in(T) + 3` and `2n + 4` that enter `β` and `posIn` are in [ALMVaultSync/deposit.derivation.md](../ALMVaultSync/deposit.derivation.md) section 4.

## 5. Open

- 3.4 near the double root rests on [getRoot.derivation.md](../QuadraticMath/getRoot.derivation.md) section 3, not re-derived here.
