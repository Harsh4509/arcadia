# WithdrawOptimizationMath.getNormalizedParameters: the reserve term is never negative, so the quadratic coefficient needs no clamp

Code: `src/vaults/libraries/math/WithdrawOptimizationMath.sol:390-472` `getNormalizedParameters` and `:349-373` `getQuadraticCoefficients`, on their one caller chain `previewWithdraw` (:44-132), `getSqrtPrice` (:276-293), `getQuadraticCoefficients`, `getNormalizedParameters`. Pool behaviour: [PoolAxioms.md](../PoolAxioms.md).

Notation, all amounts in units of `2^-96` wei as `previewWithdraw` scales them:

- `s` the step's start price `state.sqrtPriceX96`, `L = state.liquidity` the pool's active liquidity there, `W = state.position.liquidity` the core's equivalent position's liquidity there, `n = snapshot.ranges.length`, `κ = 1e6 / (1e6 − fee)`.
- `B = holdingsIn`, `A = holdingsOut`, `C = amountIn` (the cost so far, with the rounding), `a = amountOutLeft`, `D = max(B, A)`.
- `R = reserveOut`, `W_out = positionOut`: `L s` and `W s` for zeroForOne, `floor(L 2^192 / s)` and `floor(W 2^192 / s)` otherwise (:420-425).
- `r` the reserve term before normalization: `r = floor(R B / D) − floor(C W_out / D)` (:428-429).
- `F(x, y, d) = fullMulDiv(x, y, d) = floor(x y / d)` (`node_modules/solady/src/utils/FixedPointMathLib.sol:455`, reverts when the quotient does not fit 256 bits or `d = 0`).
- `q(k)` the price of tick `k`, `t = slot0.tick`.

## 1. Statement

At every call from `previewWithdraw` that returns:

1. `r >= 0`. So `uint256(reserveOutNormalized)` in `largest` (:458) and in the normalization (:465) is exact, and `quadraticCoefficient = reserveOutNormalized + liquidityNormalized >= 0` (:369) with no clamp.
2. `quadraticCoefficient = 0` exactly when `r = 0` and `liquidityNormalized = 0`, both being non-negative: for example `W = 0` and `R B < D`. Then the quadratic is linear and `QuadraticMath.getRoot` returns the floored `c / b` ([getRoot.derivation.md](../QuadraticMath/getRoot.derivation.md) section 4).
3. Each returned term is the computed term times `2^192 / largest`, floored in magnitude (:465-471), with `largest >= 1` the largest magnitude among the four terms and 1 (:457-462): each is at most `2^192` in size. The quadratic is homogeneous, so the common factor `(B / D) 2^192 / largest` leaves its root unchanged, and the normalization moves the root only through the floors of section 3.7.

What the normalization's accuracy is measured against: the quadratic in real amounts. With asset token0 and `A = 0`, the walk's output to price `p` is `R − ceil(L 2^192 / p)`, `R = floor(L 2^192 / s)`, `d = L 2^192 mod s`, which pays the amount left `a` iff `p >= x = (s R + d) / (R − a)`. The quadratic crosses at `s R / (R − a)`, `d / (R − a)` price units below `x`. `previewWithdraw` solves for `a + 1` (it passes `amountOut − state.amountOut + 1`, :105), whose crossing `p̂ = s R / (R − a − 1)` is at or above `x`, since `s R − d (R − a − 1) > 0` for `d < s`. So accuracy statements about this file bound the root's distance to the quadratic's crossing, not to the walk's least paying price.

## 2. Axioms and bounds used

- Pool: C4 (the pool's tick against its price), D3, D4, D5 (who writes the tick), E1, E2, E3 (the bitmap lookup), G3, G4 (liquidity types and `liquidityGross`), G5 (price range).
- Pool, not in PoolAxioms.md: a position counts in the pool's `liquidity` iff `tickLower <= tick < tickUpper` (`node_modules/metadex-slipstream/contracts/core/libraries/CLPoolNonSwapPath.sol:451-472` at mint and burn, `core/CLPool.sol:638-644` at a crossing, which adds `liquidityNet`, negated moving down).
- ALM, H4: the stored `stakedLiquidity` is at most the staked position's liquidity. It rises by what the position manager reports as minted or added (`RangesLib.sol:164-166`, :210-212) and falls by what is removed (`RangesLib.decreaseStakedLiquidity`, :233), and a third party can only add to a position.
- ALM, H5: the unstaked side sits in the position manager's pool position, the staked side in the gauge's: staking moves an NFT's liquidity from the first to the second.
- ALM: `Snapshot.decodePricedRanges` sets `range.liquidity = positionLiquidity[i] + stakedLiquidity` (`Snapshot.sol:134-136`), with `positionLiquidity[i]` the position manager's live liquidity of the unstaked NFT (`RangesLib.sol:511-514`).
- ALM: `EquivalentPositionMath.getPosition` counts a range with `liquidity > 0` when `lower < p <= upper` (zeroForOne) or `lower <= p < upper` (oneForZero) (`EquivalentPositionMath.sol:71-73`), and sets `sqrtPriceBound` to the nearest such range's edge strictly past `p` in the swap's direction (:61-68).
- ALM: `SwapStateLib.crossTick` renews the position exactly when the new price equals `position.sqrtPriceBound` (`SwapState.sol:230-232`).

## 3. Proof

### 3.1 From (I) and (II) to `r >= 0`

`r >= 0` follows from (I) `C <= B` and (II) `W <= L` at the call. Zero for one: `R B = L s B >= W s C = W_out C`. One for zero: `W <= L` gives `floor(W 2^192 / s) <= floor(L 2^192 / s)`, so `W_out <= R`, and again `R B >= W_out C`. The floor is monotone, so `floor(R B / D) >= floor(C W_out / D)`.

The casts (:428-429). `floor(R B / D) <= R` as `B <= D`, and `floor(C W_out / D) <= W_out <= R` as `C <= B <= D`. So for `R < 2^255` both `SafeCastLib.toInt256` calls are exact and the unchecked subtraction is exact in `int256`. For `R >= 2^255` the call does not return: the checked product `L s`, `F(L, 2^192, s)` or `toInt256` reverts. `D >= B >= 1` (section 3.2), so the divisions are defined.

### 3.2 (I): the cost is at most the tokenIn holdings at the call

`getSqrtPrice` is called once, in `previewWithdraw` inside `if (costBinds)` (:94), after `if (amountIn > holdingsIn || ...) return shares` (:96-98). So `amountIn <= holdingsIn` there (:102-111), and `getSqrtPrice` passes both unchanged to `getQuadraticCoefficients` and on to `getNormalizedParameters`: `C <= B`. `B >= 2^96`: `previewWithdraw` returns when `holdingsIn == 0` (:66), then scales it by `2^96` (:74), and only adds to it (:127).

### 3.3 (II) part 1: the core's ranges are pool liquidity

`range.liquidity = positionLiquidity[i] + stakedLiquidity`. `positionLiquidity[i]` is the unstaked NFT's liquidity, a part of the position manager's pool position at `(tickLower, tickUpper)` (H5). `stakedLiquidity` is at most the staked NFT's liquidity (H4), a part of the gauge's pool position at the same ticks (H5). Distinct NFTs hold disjoint parts of their pool positions. So the core's ranges counted at a price sum to at most the liquidity of pool positions at their ticks, and each range with `liquidity > 0` has both ticks initialized (G4: every position counts in its ticks' `liquidityGross`, and a tick is initialized iff that is non-zero).

### 3.4 (II) part 2: where the two counting rules differ

By C4, `(s, t)` at the snapshot has one of three shapes: `q(t) < s < q(t + 1)`, `s = q(t)`, `s = q(t + 1)`, the last only after a step that moved down onto `t + 1` (D3).

| Shape | zeroForOne: position counts | pool counts | ranges counted only by the position |
|---|---|---|---|
| `q(t) < s < q(t + 1)` | `tickLower <= t`, `tickUpper >= t + 1` | same | none |
| `s = q(t + 1)` | `tickLower <= t`, `tickUpper >= t + 1` | same | none |
| `s = q(t)` | `tickLower <= t − 1`, `tickUpper >= t` | `tickLower <= t`, `tickUpper >= t + 1` | `tickUpper = t` |

| Shape | oneForZero: position counts | pool counts | ranges counted only by the position |
|---|---|---|---|
| `q(t) < s < q(t + 1)` | `tickLower <= t`, `tickUpper >= t + 1` | same | none |
| `s = q(t)` | `tickLower <= t`, `tickUpper >= t + 1` | same | none |
| `s = q(t + 1)` | `tickLower <= t + 1`, `tickUpper >= t + 2` | `tickLower <= t`, `tickUpper >= t + 1` | `tickLower = t + 1` |

So `W > L` at the snapshot needs zero for one with spot exactly on a core range's upper tick and `t` that tick (the pool was initialized there, D5, or arrived from below), or one for zero with spot exactly on a core range's lower tick and `t` one below it (the pool arrived from above). A swap whose limit is that tick's price lands there, so the state is reachable. Witness state: core range `[−10, 0)` of liquidity `2^64`, pool initialized at `q(0)` so `t = 0`, another range `[−100, 100)` of liquidity 1: the core's range is not in `L = 1`, while zero for one counts it, `W = 2^64`.

### 3.5 (II) part 3: the first step re-syncs `L` before any solve

In both mismatch shapes the tick at spot (`t` zero for one, `t + 1` one for zero) is a core range's edge with liquidity, so it is initialized (3.3) and a multiple of the spacing. `SwapStateLib.setNextTick` (`SwapState.sol:100-117`) returns exactly it: moving down the lookup includes the compressed tick's own bit (E2), moving up it starts at `compressed + 1 = compress(t + 1)` (E3). The step's target is that tick's price `= s`, which is not the walk's limit (`MIN_SQRT_PRICE + 1` and `MAX_SQRT_PRICE − 1` are no tick's price). `previewWithdraw` sees `step.sqrtPriceTargetX96 == state.sqrtPriceX96` and takes the zero branch (`WithdrawOptimizationMath.sol:81-83`): no `getSharesForAmounts`, no solve. `crossTick` then crosses the initialized tick (`SwapState.sol:213-227`):

- zero for one: `L' = L − liquidityNet(t)`, `tick' = t − 1`. `L'` counts `tickLower <= t − 1 < tickUpper`, and `s = q(tick' + 1)`: the second row of the first table.
- one for zero: `L' = L + liquidityNet(t + 1)`, `tick' = t + 1`, `s = q(tick')`: the second row of the second table.

The position is not renewed at this cross (`sqrtPriceBound` lies strictly past `s`) and needs no renewal: after the cross the two rules agree. The pool-only ranges of the third rows (`tickLower = t`, `tickUpper = t + 1`) make `L > W`, the safe direction, and the same cross removes them. If the tick at spot is initialized by other positions only, the zero step still runs and `L'` still contains every core range the position counts. If it is not initialized, no position has an edge there and the rules agree.

### 3.6 (II) part 4: later steps keep `W <= L`

After a cross to `T = q(tickNext)`, the walk's liquidity counts `tickLower <= tick' < tickUpper` with `tick' = tickNext − 1` (zero for one) or `tickNext` (one for zero), which is the position's rule at `T`. Every core edge with liquidity is initialized and the lookup stops at every initialized tick (E1 to E3), so the walk lands on each core edge, and there `crossTick` renews the position at `T` (`T == sqrtPriceBound`). Between renewals no core edge lies between `s` and `T`, so the set of ranges the position counts does not change. So at every step start `W` is the core's part of the walk's liquidity, and with 3.3 `W <= L`. The solve runs at a step start, after the zero step of 3.5 when there is one.

### 3.7 The floors of the normalization

The exact terms are `(R B − C W_out) / D`, `(a B − C A) / D`, `κ (R_in A − a W_in) / D` and `κ n W 2^192 / D` (the quadratic of `WithdrawOptimizationMath.sol:346-347` times `B / D`, computed at :413-454). The computed terms differ from them by the floors: the reserve and amount terms by less than 1 (a difference of two floors), the holdings term by less than `κ + 1` (a difference of two floors times `κ`, truncated toward zero by the signed division), the liquidity term by less than `κ + 1` (two floors). The normalization adds one floor in magnitude per term, below `2^-192 largest` in the terms' units.

### 3.8 The function's output does not show the sign of `r`

With `r < 0`, `uint256(r) >= 2^255` enters `largest`, and the normalization returns `F(uint256(r), 2^192, largest) <= 2^192`, cast to a non-negative `int256`. So `reserveOutNormalized >= 0` at the output for either sign of `r`, and a negative `r` would show only as the other terms normalized to about 0. A check of statement 1 must test `r` itself: test/fuzz/libraries/WithdrawOptimizationMath/GetNormalizedParameters.fuzz.t.sol:106 `testFuzz_Success_getNormalizedParameters_TheReserveTermIsNotNegative` rebuilds `r` with `FullMath.mulDiv` on its domain (`W <= L < 2^64`, `C <= B`, `B, A` in `[2^96, 2^160]`) and asserts `r >= 0`.

### 3.9 Symbolic support

Two lemmas, symbolic, in `test/symbolic/libraries/FixedPointMathLib.symbolic.t.sol`:

- M, :21 `prove_fullMulDiv_IsMonotoneInTheAmount`: `F(x1, y, d) <= F(x2, y, d)` for `x1 <= x2`, `x2 y < 2^256`, `d != 0`.
- S, :37 `prove_fullMulDiv_IsSymmetricInBothFactors`: `F(x, y, d) = F(y, x, d)` for `x y < 2^256`, `d != 0`.

With (I) and (II), `r = F(R, B, D) − F(C, W_out, D)` and the chain `F(C, W_out, D) <= F(B, W_out, D) = F(W_out, B, D) <= F(R, B, D)` is M, S, M, with `W_out <= R` by a checked product (zero for one) or M with `y = 2^192` (one for zero). The lemmas cover the chain where `R B < 2^256` (and `L < 2^64` one for zero). Past that the chain rests on `F` being the floor of the 512-bit quotient, as section 3.1 does.

## 4. Constants

| Constant | Where | Sufficiency | Witness |
|---|---|---|---|
| `1` in `largest = max(..., 1)` | `WithdrawOptimizationMath.sol:460` | Keeps the divisor of the normalization at least 1 when all four terms are 0. | no witness |
| `2^192` | `WithdrawOptimizationMath.sol:465-471` | Scale of the normalized terms: each is at most `2^192`, so the coefficient sums (:369-371) stay below `2^194`. A scale, not a margin. | no witness |
| `+ n` in `R_in` at `L + n` | `WithdrawOptimizationMath.sol:443-444` | The cost at the pool's liquidity plus the `n` the burn's floors leave, as `getSharesForAmounts` prices it (:223). Its sufficiency is the margin argument of [roundingMargins.derivation.md](../ALMVaultSync/roundingMargins.derivation.md). | no witness |

Statement 1 has no constant: it needs no clamp and no `−1` arm.
