# PlanCacheLib.hasUnsettledEpochs

Code: `src/core/types/PlanCache.sol` `hasUnsettledEpochs` (:203-205).

| Claim | Status | Evidence |
|---|---|---|
| is true exactly when any queue's cleared amount is nonzero | symbolic | test/symbolic/libraries/PlanCacheLib.symbolic.t.sol:235 `prove_hasUnsettledEpochs_IsWhetherAnyQueueWasCleared` |
