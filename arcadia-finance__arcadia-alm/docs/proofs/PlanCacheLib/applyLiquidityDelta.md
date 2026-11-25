# PlanCacheLib.applyLiquidityDelta

Code: `src/core/types/PlanCache.sol` `applyLiquidityDelta` (:144-153). Held amounts `int128`, valid ordered ticks, any `uint128` liquidity whose principal at the price is below `2^127` (else `fromAmounts` reverts). src casts `abs(liquidityDelta)` to `uint128` unchecked (:149): every caller passes a `uint128` liquidity (`src/core/ALMKeeperExtension.sol:260`, :377, :413, :456, :493).

| Claim | Status | Evidence |
|---|---|---|
| adding a liquidity never lowers either held amount, and removing it again restores both | open | test/symbolic/libraries/PlanCacheLib.symbolic.t.sol:196 `prove_applyLiquidityDelta_RemovingTheAddedLiquidityRestoresTheAmounts` (z3int): stuck at the solver query limit (10000), from `TickMath` at symbolic ticks |
