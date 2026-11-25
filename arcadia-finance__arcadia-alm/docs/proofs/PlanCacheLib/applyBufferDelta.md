# PlanCacheLib.applyBufferDelta

Code: `src/core/types/PlanCache.sol` `applyBufferDelta` (:132-135).

| Claim | Status | Evidence |
|---|---|---|
| succeeds exactly when both held amounts plus the delta fit `int256`, and holds the sums | symbolic | test/symbolic/libraries/PlanCacheLib.symbolic.t.sol:168 `prove_applyBufferDelta_SucceedsIffBothSumsFitInt256` |
