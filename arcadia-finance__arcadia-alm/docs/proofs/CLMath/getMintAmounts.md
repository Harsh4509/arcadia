# CLMath.getMintAmounts

Code: `src/shared/libraries/math/CLMath.sol` `getMintAmounts` (:257-271), `getAmountsForLiquidityRoundingUp` (:136-151), against the position manager's `LiquidityAmounts.getLiquidityForAmounts` (node_modules/metadex-slipstream/contracts/periphery/libraries/LiquidityAmounts.sol) and the pool's `SqrtPriceMath`.

Notation: a < b the bounds of each token's amount: for token0 a = max(lower, spot), b = upper, for token1 a = lower, b = min(spot, upper). ΔL = ⌈L * shares / supply⌉ the owed liquidity, J = ⌊a * b / 2^96⌋ on token0's bounds, d0 = ⌈ΔL (b - a) / J⌉ and d1 = ⌈ΔL (b - a) / 2^96⌉ the core's desired amounts. Rows 4 to 6 take bounds below 2^128 with lower * upper >= 2^96: below it J = 0 on token0's bounds and `getAmount0ForLiquidityRoundingUp` reverts NoLiquidityForToken0 even at no shares.

| Claim | Status | Evidence |
|---|---|---|
| the position manager's liquidity L' is at least ΔL | derived, fuzz | The manager computes L0 = ⌊d0 * J' / (b - a)⌋ with J' = mulDiv(a, b, Q96) = J, the same pair of bounds in every branch (spot and upper inside, lower and upper below), and L1 = ⌊d1 * 2^96 / (b - a)⌋ (lower and spot inside, lower and upper above). d0 ≥ ΔL (b - a) / J gives d0 * J / (b - a) ≥ ΔL, and ΔL is an integer, so L0 ≥ ΔL. The same for L1. L' = min(L0, L1) or the single one, so L' ≥ ΔL. The core takes J from `fullMulDivN(a, b, 96)`, the manager's divisor, which is what makes this hold. The pool's exact a * b / 2^96 would not. `testFuzz_Success_increaseLiquidity_TheCoreAmountsBuyTheOwedLiquidityAndAllTheToken1` (real position manager), `testFuzz_Success_getMintAmounts_RoundsTheLiquidityAndItsAmountsUp` |
| the manager uses all of d1 | derived, fuzz | the pool takes ⌈L' (b - a) / 2^96⌉ token1, at least d1 because L' ≥ ΔL, at most d1 because L' ≤ L1. Same test |
| the manager may use less token0 than d0, by at most ⌈d0 / J⌉ | derived, fuzz | the pool takes ⌈L' 2^96 (b - a) / (a b)⌉ (nested ceilings of `getAmount0Delta`), at least its value at ΔL. d0 - ⌈ΔL 2^96 (b - a) / (a b)⌉ < 1 + x (a b / 2^96 - J) / (J a b / 2^96) < 1 + d0 / J with x = ΔL (b - a), so the shortfall is at most ⌈d0 / J⌉. The core refunds it (ALMCore.mint). Same test |
| of no shares take nothing | open | test/symbolic/libraries/CLMath.symbolic.t.sol:543 `prove_getMintAmounts_OfNoSharesTakeNothing` (z3int) |
| of the whole supply are the range's rounded up amounts | open | test/symbolic/libraries/CLMath.symbolic.t.sol:566 `prove_getMintAmounts_OfTheWholeSupplyAreTheRangesRoundedUpAmounts` (z3int) |
| are monotone in the shares | open | test/symbolic/libraries/CLMath.symbolic.t.sol:592 `prove_getMintAmounts_AreMonotoneInTheShares` (z3int) |
