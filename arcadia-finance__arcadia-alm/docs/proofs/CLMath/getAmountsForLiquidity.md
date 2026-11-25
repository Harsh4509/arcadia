# CLMath.getAmountsForLiquidity

Code: `src/shared/libraries/math/CLMath.sol` `getAmountsForLiquidity` (:206-221), `getAmountsForLiquidityRoundingUp` (:136-151). Rows assume prices of at most one (sqrt prices at most 2^96) and liquidity below 2^63, so the pool's `getAmount0Delta` product fits 256 bits. The full range is open.

| Claim | Status | Evidence |
|---|---|---|
| of no liquidity are nothing | symbolic | test/symbolic/libraries/CLMath.symbolic.t.sol:468 `prove_getAmountsForLiquidity_OfNoLiquidityAreNothing` |
| are monotone in the liquidity | open | test/symbolic/libraries/CLMath.symbolic.t.sol:487 `prove_getAmountsForLiquidity_AreMonotoneInTheLiquidity` (z3int) |
| the rounded up amounts dominate the rounded down ones in both tokens, for every placement of the price | open | test/symbolic/libraries/CLMath.symbolic.t.sol:445 `prove_getAmountsForLiquidityRoundingUp_DominateTheRoundedDownAmounts` (z3int) |
