# PlanCacheLib.checkShortfall

Code: `src/core/types/PlanCache.sol` `checkShortfall` (:108-121).

| Claim | Status | Evidence |
|---|---|---|
| reverts below the floor | symbolic | test/symbolic/libraries/PlanCacheLib.symbolic.t.sol:90 `prove_checkShortfall_RevertsBelowTheFloor` |
| succeeds at or above the floor | symbolic | test/symbolic/libraries/PlanCacheLib.symbolic.t.sol:116 `prove_checkShortfall_SucceedsAtOrAboveTheFloor` |
| never reverts without a loss | symbolic | test/symbolic/libraries/PlanCacheLib.symbolic.t.sol:144 `prove_checkShortfall_NeverRevertsWithoutALoss` |
