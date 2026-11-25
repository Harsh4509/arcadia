# PlanCacheLib.getCleared_setCleared

Code: `src/core/types/PlanCache.sol` `getCleared` (:214-217), `setCleared` (:226-235).

| Claim | Status | Evidence |
|---|---|---|
| `getCleared` reads the named queue's field | symbolic | test/symbolic/libraries/PlanCacheLib.symbolic.t.sol:254 `prove_getCleared_ReadsTheNamedQueue` |
| `setCleared` writes the named queue's field and keeps the other three | symbolic | test/symbolic/libraries/PlanCacheLib.symbolic.t.sol:275 `prove_setCleared_WritesOnlyTheNamedQueue` |
