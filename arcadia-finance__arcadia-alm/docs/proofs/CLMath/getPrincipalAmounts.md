# CLMath.getPrincipalAmounts

Code: `src/shared/libraries/math/CLMath.sol` `getPrincipalAmounts` (:232-240), against the pool's `SqrtPriceMath` at `TickMath`'s tick prices.

| Claim | Status | Evidence |
|---|---|---|
| is the pool's rounded down amounts from the price clamped to the range to its far edges, for valid ordered ticks, any price and liquidity | open | test/symbolic/libraries/CLMath.symbolic.t.sol:511 `prove_getPrincipalAmounts_AreThePoolsRoundedDownAmountsAtTheTickPrices` (z3int): stuck at the solver query limit (10000), from `TickMath` at symbolic ticks |
