# Pool axioms

What the ALM assumes about the Metadex CL pool, each statement with the source line it rests on. The pool is `node_modules/metadex-slipstream/contracts/core/` (the package `foundry.toml` remaps as `@metadex-slipstream`, compiled at 0.7.6). `src/shared/libraries/vendored/MetadexSwapMath.sol` and `MetadexTickBitmap.sol` port its `SwapMath.sol` and `TickBitmap.sol`. Paths below are relative to that folder.

Notation: `s` the pool's `sqrtPriceX96`, `Q = 2^96`, `L` the active liquidity, `f = fee / 1e6`, `φ = f / (1 − f)`, `κ = 1 / (1 − f)`. "Exact" amounts are the real numbers `L Q (1/a − 1/b)` of token0 and `L (b − a) / Q` of token1 between prices `a < b`.

Covered: the swap loop, its step math, the tick bitmap, the tick after a swap, the fee split, position amounts, the types and caps of prices, liquidity and fees. Not covered, not read for this file: the oracle (`observations`, `observe`), the gauge and reward paths, flash, the swap hook's fees beyond their cap (`beforeSwap`, `afterSwap`), the router. A derivation that needs them adds them here first.

## 1. Token amounts between two prices

| # | Axiom | Source | Code |
|---|---|---|---|
| A1 | Token1 between two prices is `L (b − a) / Q`, rounded up or down as asked: one rounding, under 1 wei. | `libraries/SqrtPriceMath.sol:173-184` | `FullMath.mulDivRoundingUp(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96)` / `FullMath.mulDiv(...)` |
| A2 | Token0 between two prices is rounded twice in the same direction: `ceil(ceil(N / b) / a)` up, `floor(floor(N / b) / a)` down, `N = L Q (b − a)`. For integers `a, b >= 1` these equal `ceil(N / (a b))` and `floor(N / (a b))` (nested rounding: `ceil(ceil(y) / a) = ceil(y / a)` and `floor(floor(y) / a) = floor(y / a)` for real `y` and integer `a >= 1`, since `y / a` is an integer only if `y` is). So the result is the exact amount rounded once: under 1 wei, as for token1. | `libraries/SqrtPriceMath.sol:148-164` | `UnsafeMath.divRoundingUp(FullMath.mulDivRoundingUp(numerator1, numerator2, sqrtRatioBX96), sqrtRatioAX96)` / `FullMath.mulDiv(numerator1, numerator2, sqrtRatioBX96) / sqrtRatioAX96` |
| A3 | A position's amounts round up when liquidity is added and down when it is removed. | `libraries/SqrtPriceMath.sol:191-214`, called from `libraries/CLPoolNonSwapPath.sol:452-474` | `liquidity < 0 ? -getAmount0Delta(..., false) : getAmount0Delta(..., true)` |

## 2. One swap step

`SwapMath.computeSwapStep(current, target, L, amountRemaining, feePips)`, `libraries/SwapMath.sol:21-85`. The pool calls it with a positive amount for exact input (`CLPool.sol:528` `exactInput = amountSpecified > 0`, `:585`).

| # | Axiom | Source | Code |
|---|---|---|---|
| B1 | Exact input, the remainder `R` net of fee is `R' = floor(R (1e6 − fee) / 1e6)`. | `SwapMath.sol:32` | `FullMath.mulDiv(uint256(amountRemaining), 1e6 - feePips, 1e6)` |
| B2 | The step reaches its target iff `R'` is at least the input to the target rounded up (A1, A2). Its input is then that rounded-up amount and its fee `ceil(input fee / (1e6 − fee))`. | `SwapMath.sol:33-37`, `:59-61`, `:66-68`, `:83` | `if (amountRemainingLessFee >= amountIn) sqrtRatioNextX96 = sqrtRatioTargetX96`, `feeAmount = FullMath.mulDivRoundingUp(amountIn, feePips, 1e6 - feePips)` |
| B3 | Otherwise the step ends inside, at `getNextSqrtPriceFromInput(R')`, takes the rounded-up input to that price and the whole rest of `R` as fee: it consumes exactly `R`. | `SwapMath.sol:38-41`, `:61`, `:68`, `:79-81` | `feeAmount = uint256(amountRemaining) - amountIn` |
| B4 | The step's output is the amount between its two prices rounded down (A1 for token1, A2 for token0). | `SwapMath.sol:62-64`, `:69-71` | `getAmount1Delta(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, false)` |
| B5 | Exact output: the step reaches its target iff the output left is at least the rounded-down output to the target. Else it ends at `getNextSqrtPriceFromOutput`. The output is capped at the request. Input and fee as B2. | `SwapMath.sol:42-52`, `:75-77`, `:83` | `if (!exactIn && amountOut > uint256(-amountRemaining)) amountOut = uint256(-amountRemaining)` |
| B6 | Every price is an integer `sqrtPriceX96`. From an input of token0 the next price is rounded up (the price falls by at most the exact move). From an input of token1 it is `s + floor(a Q / L)`, rounded down. | `libraries/SqrtPriceMath.sol:28-48` (`add = true`), `:69-83`, `:103-116` | `FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator)`, `uint256(sqrtPX96).add(quotient)` |
| B7 | From an output of token1 the next price is `s − ceil(a Q / L)`. From an output of token0 it is `ceil(L Q s / (L Q − a s))`. Both pass the exact price, so the step pays at least the request before the cap of B5. | `libraries/SqrtPriceMath.sol:84-93`, `:49-56`, `:125-138` | `UnsafeMath.divRoundingUp(amount << FixedPoint96.RESOLUTION, liquidity)`, `FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator)` |

Consequences used by the ALM, each a line of arithmetic on the axioms:

- C1 (from B2, A1, A2). A full step costs at least `κ x` and less than `κ x + 2 + φ`, `x` the exact input, for either token: the input is under 1 over exact and the fee is a ceiling on it.
- C2 (from B4, A1, A2). A step pays at most `y` and more than `y − 1`, `y` the exact output, for either token.
- C3 (from B3). An exact input swap consumes its whole input unless it reaches the price limit (D1) or runs out of liquidity.
- C8 (section 2.1). In B3 the rounded-up input to the inside price is at most `R'`, the inside price lies strictly before the target, and `SwapMath.sol:81` does not wrap.

### 2.1 B3, line by line

Claim: in `computeSwapStep` with `amountRemaining = R >= 0` and `R' < amountIn` at `SwapMath.sol:36`, the step ends strictly before its target, the `amountIn` of `SwapMath.sol:61` or `:68` is at most `R'`, and `feeAmount = R − amountIn` (`SwapMath.sol:81`) is at least `R − R' >= 0`.

Notation: `s` the current price, `t` the target, `L > 0` the liquidity (`SqrtPriceMath.sol:110`), `Q = 2^96`, `p` the price of `SwapMath.sol:39-40`. `FullMath.mulDiv` is the floor and `mulDivRoundingUp` the ceiling of the 512-bit quotient (`libraries/FullMath.sol:14`, :109-113), `UnsafeMath.divRoundingUp` the ceiling (`libraries/UnsafeMath.sol:12-16`).

`R' = floor(R (1e6 − fee) / 1e6) <= R` (`SwapMath.sol:32`, G1).

Token1 in (`s < t`, `SwapMath.sol:28`).

1. The target's input is `ceil(L (t − s) / Q)` (`SwapMath.sol:35`, `SqrtPriceMath.sol:182`). `R' < ceil(L (t − s) / Q)` with `R'` an integer gives `R' < L (t − s) / Q`.
2. `p = s + q`, `q = floor(R' Q / L)` (`SqrtPriceMath.sol:78-83`: the shift form for `R' <= 2^160 − 1`, where `R' Q < 2^256`, else `mulDiv`). By 1, `q <= R' Q / L < t − s`, so `p < t`: the checked sum and `toUint160` pass, and `max` (`SwapMath.sol:55`) is false.
3. `amountIn = ceil(L (p − s) / Q) = ceil(L q / Q)` (`SwapMath.sol:68`, `SqrtPriceMath.sol:182`). `L q <= R' Q`, so `L q / Q <= R'` and its ceiling is at most the integer `R'`.

Token0 in (`s >= t`, `SwapMath.sol:28`). With `s = t` the target's input is 0 and `SwapMath.sol:36` holds, so here `s > t`.

1. The target's input is `ceil(ceil(N / s) / t) = ceil(N / (s t))`, `N = L Q (s − t)` (`SwapMath.sol:34`, `SqrtPriceMath.sol:156-162`, the identity of A2). `R' < ceil(N / (s t))` gives `R' < L Q / t − L Q / s`.
2. `R' = 0`: `p = s` (`SqrtPriceMath.sol:35`), `p > t`, and `amountIn = 0` (`SwapMath.sol:61`).
3. `R' > 0`. Let `x = L Q s / (L Q + R' s)`, the exact price with `L Q / x − L Q / s = R'`. By 1, `L Q / x < L Q / t`, so `x > t`. `p` is one of two values (`SqrtPriceMath.sol:38-48`): `ceil(x)` when `R' s` and `L Q + R' s` do not overflow (`SqrtPriceMath.sol:40-44`), else `ceil(L Q / (floor(L Q / s) + R'))` (`SqrtPriceMath.sol:48`, the sum checked by `LowGasSafeMath.add`, `libraries/LowGasSafeMath.sol:11-13`). Both are at least `x`: the second since `floor(L Q / s) + R' <= L Q / s + R' = L Q / x`. Both are at most `s`: `x <= s`, and `floor(L Q / s) + R' > L Q / s` for `R' >= 1`. So `t < x <= p <= s`: `p` fits `uint160`, `p > t`, and `max` is false.
4. `amountIn = ceil(ceil(N' / s) / p) = ceil(L Q / p − L Q / s)`, `N' = L Q (s − p)` (`SwapMath.sol:61`, `SqrtPriceMath.sol:156-162`). `p >= x` gives `L Q / p − L Q / s <= L Q / x − L Q / s = R'`, and the ceiling is at most the integer `R'`.

In both directions `amountIn <= R' <= R`, so `SwapMath.sol:81` does not wrap and the step consumes `amountIn + feeAmount = R`. `src/shared/libraries/vendored/MetadexSwapMath.sol:43-94` ports these lines.

## 3. The swap loop

| # | Axiom | Source | Code |
|---|---|---|---|
| D1 | The swap needs a limit strictly on the swap's side of spot and strictly inside `(MIN_SQRT_RATIO, MAX_SQRT_RATIO)`, else it reverts `SPL`. It loops while an amount remains and the price is not the limit. | `CLPool.sol:509-514`, `:560` | `while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != sqrtPriceLimitX96)` |
| D2 | Each step's target is the next tick of the bitmap lookup (E1), clamped to `[MIN_TICK, MAX_TICK]`, or the limit when the limit is nearer. | `CLPool.sol:565-583` | `(zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : ...) ? sqrtPriceLimitX96 : step.sqrtPriceNextX96` |
| D3 | A step that reaches its tick's price crosses the tick if initialized (liquidity changes by `liquidityNet`, negated moving down) and sets the tick to `tickNext − 1` moving down, `tickNext` moving up. | `CLPool.sol:607-647` | `state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext` |
| D4 | A step that moves and ends short of its tick's price sets the tick to `getTickAtSqrtRatio(price)`, the greatest tick whose price is at most the price. A step that does not move leaves the tick. | `CLPool.sol:648-651`, `libraries/TickMath.sol:56-61` | `state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96)` |
| D5 | The pool is created with `tick = getTickAtSqrtRatio(price)`, and only the swap writes the tick afterwards: `slot0.tick` has two writers in the package, the initializer and the swap's write-back. | `CLPool.sol:167`, `libraries/CLPoolNonSwapPath.sol:134`, `CLPool.sol:682` | `CL.initializeSlot0(slot0, observations, _sqrtPriceX96, TickMath.getTickAtSqrtRatio(_sqrtPriceX96), _tickSpacing)`, `(slot0.sqrtPriceX96, slot0.tick, ...) =` |
| D6 | The swap returns the specified amount consumed and the calculated amount, signed by direction. | `CLPool.sol:589-595`, `:703-705` | `(amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)` |

Consequence C4 (from D3, D4, D5): with `T(x) = getTickAtSqrtRatio(x)`, `slot0.tick` is `T(spot)` or `T(spot) − 1`, and it is `T(spot) − 1` only when spot is exactly a tick's price reached by a step moving down onto that tick (D3).

## 4. The tick bitmap

| # | Axiom | Source | Code |
|---|---|---|---|
| E1 | The lookup compresses the tick by the spacing, rounding to negative infinity, and returns a multiple of the tick spacing in both directions. | `libraries/TickBitmap.sol:44-45`, `:56-58`, `:69-71` | `next = ... * tickSpacing` |
| E2 | Moving down it searches the word of the compressed tick at and below its bit: the result is at most the tick. Without an initialized tick it returns the word's first bit, a multiple of `256 * tickSpacing`. | `libraries/TickBitmap.sol:47-58`, `:14-17` | `(compressed - int24(bitPos)) * tickSpacing` |
| E3 | Moving up it searches the word of `compressed + 1` at and above its bit: the result is above the tick. Without an initialized tick it returns the word's last bit. | `libraries/TickBitmap.sol:59-72` | `(compressed + 1 + int24(type(uint8).max - bitPos)) * tickSpacing` |

Consequence C5 (from D2, E1): every price a swap step ends on is the price of a multiple of the tick spacing, the limit, or an inside price of B3 or B5.

## 5. Fees

| # | Axiom | Source | Code |
|---|---|---|---|
| F1 | The staked side's part of a step's fee is rounded up, the unstaked fee on the rest is rounded up, and the growth per unit of unstaked liquidity is rounded down: every rounding is against the unstaked side. | `CLPool.sol:822-829`, `:836-842`, `:846-867` | `stakedFeeAmount = FullMath.mulDivRoundingUp(feeAmount, _stakedLiquidity, _liquidity)`, `FullMath.mulDivRoundingUp(_unstakedFeeAmount, unstakedFee(), 1_000_000)`, `FullMath.mulDiv(unstakedFeeAmount, FixedPoint128.Q128, _liquidity - _stakedLiquidity)` |
| F2 | A position's owed fees are `floor(growth inside since its last update * liquidity / 2^128)`: one floor over the whole uncounted growth, not one per step. | `libraries/Position.sol:66-70` | `FullMath.mulDiv(feeGrowthInside0X128 - _self.feeGrowthInside0LastX128, _self.liquidity, FixedPoint128.Q128)` |

## 6. Who relies on what

| Proof file | Axioms |
|---|---|
| `ALMVaultSync/deposit.derivation.md` section 2 | A1 to A3, B1, B2, B4, B5, B7, C1, C2, D1 to D3, F1, F2, G1, G3, G5 |
| `ALMVaultSync/maxViews.derivation.md` section 2 | A1, A2, B1 to B7, C4, D1, D2, E1 to E3, G5 |
| `ALMVaultSync/mint.derivation.md` section 2 | A1 to A3, B2, B4, B5, B7, C2, D1, D2, F1, F2 |
| `ALMVaultSync/roundingMargins.derivation.md` section 3 | A1 to A3, B1 to B6, C1 to C5, D2, E1 to E3, F1, F2 |
| `ALMVaultSync/swapsPastATick.derivation.md` section 2 | A1, A2, B2, B5 to B7, C2, D2 |
| `ALMVaultSync/uncheckedMath.derivation.md` | A1, C1, C4, C6, C7, E3, G1 to G5 |
| `DepositOptimizationMath/stepEndRounding.derivation.md` | A1, A2, B2, B4, B6, B7, D2, D3 |
| `SwapState/getStepFees.derivation.md` section 2 | B2, B5, C6, F1, F2, G1, G2, and pool lines of its own |
| `WithdrawOptimizationMath/getNormalizedParameters.derivation.md` section 2 | C4, D3 to D5, E1 to E3, G3 to G5, and pool lines of its own |
| `ALMCore/burnFeesCollected.derivation.md` | pool lines of its own |
| `CLMath/getNextSqrtPrice.derivation.md` | D1, D2, E1 to E3, G5 |
| `DepositOptimizationMath/getQuadraticCoefficients.derivation.md` | G1, G2, G5 |
| `DepositOptimizationMath/maxDeposit.derivation.md` | A1, A2, B2, B4, D2, E1 to E3 |
| `MintOptimizationMath/maxMint.derivation.md` | A2 |
| `EmissionsLogic/getHiddenEmissions.derivation.md` | pool and gauge lines of its own |

## 7. Types and caps

| # | Axiom | Source | Code |
|---|---|---|---|
| G1 | The swap fee is at most 100_000 (of 1e6): the tick-spacing fee is capped where it is set, its only write, and a hook's fee is capped before use. | `CLFactory.sol:280`, `:287`, `libraries/hook/SwapHookLib.sol:25`, `:45-51`, `:222-224` | `require(fee > 0 && fee <= 100_000)`, `if (_fee > 0) return cap(_fee)`, `return ICLFactory(_factory).tickSpacingToFee(_tickSpacing)` |
| G2 | The unstaked fee is at most 1_000_000: a module's fee above it is dropped for the default, which is at most 500_000 and starts at 0. | `CLFactory.sol:258-275`, `:196`, `:76` | `if (fee <= 1_000_000) return fee`, `require(_defaultUnstakedFee <= 500_000)` |
| G3 | The pool's active liquidity and a position's liquidity are `uint128`, a tick's `liquidityNet` is an `int128`. | `CLPool.sol:101`, `libraries/Position.sol:15`, `libraries/Tick.sol:23` | `uint128 public override liquidity` |
| G4 | A tick's `liquidityGross` is at most `maxLiquidityPerTick = type(uint128).max / numTicks`, with `numTicks >= 109` as the tick spacing is below 16_384: below `2^122`. Every position on a tick counts in its `liquidityGross`, and `liquidityNet` is at most `liquidityGross` in size. | `libraries/Tick.sol:56-61`, `:168-171`, `:191-193`, `CLFactory.sol:284` | `require(liquidityGrossAfter <= maxLiquidity, 'LO')` |
| G5 | Every pool price is in `[MIN_SQRT_RATIO, MAX_SQRT_RATIO)`, `MIN_SQRT_RATIO = 4_295_128_739 > 2^32` and `MAX_SQRT_RATIO < 2^160`: the initial price passes `getTickAtSqrtRatio`, and a swap's limit lies strictly inside (D1). Ticks are in `[MIN_TICK, MAX_TICK] = [-887_272, 887_272]`. | `libraries/TickMath.sol:9-16`, `:63`, `CLPool.sol:167`, `:509-514` | `require(sqrtPriceX96 >= MIN_SQRT_RATIO && sqrtPriceX96 < MAX_SQRT_RATIO, 'R')` |

Consequences:

- C6 (from A1, A2, G3, G5). The amount between two pool prices `a < b` is below `2^192` for either token: `L (b − a) / Q < 2^128 * 2^160 / 2^96` and `L Q (1/a − 1/b) < 2^128 * 2^96 / 2^32`. A step's fee is at most its input times `1e5 / 9e5`, rounded up (B2, G1): below `2^189`.
- C7 (from D1 to D3, E2, E3, G1, G5). A swap has fewer than `2^21` steps: a step that reaches its tick's price moves the tick strictly in the swap's direction (down to `tickNext − 1` with the next lookup at or below it, up to `tickNext` with the next lookup above it), a step that ends short of it ends the swap, and there are `1_774_545` ticks. After the loop, `SwapHookLib.afterSwap` adds a fee of at most `100_000 / 1e6` of the calculated side to it (`libraries/hook/SwapHookLib.sol:136-155`), which lowers an exact input's output and raises an exact output's input. With C6 a swap's input with its fees is below `1_774_546 * 1.125 * 1.1 * 2^192 < 2^214` and its output below `2^213`.

