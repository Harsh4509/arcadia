# EmissionsLogic.isPenaltyWindowOpen

Code: `src/core/libraries/logic/EmissionsLogic.sol` `isPenaltyWindowOpen` (:79-86).

| Claim | Status | Evidence |
|---|---|---|
| closes at the boundary | symbolic | test/symbolic/libraries/EmissionsLogic.symbolic.t.sol:23 `prove_isPenaltyWindowOpen_ClosesAtTheBoundary` |
| never reopens at a later block | symbolic | test/symbolic/libraries/EmissionsLogic.symbolic.t.sol:42 `prove_isPenaltyWindowOpen_NeverReopensAtALaterBlock` |
| never opens without a config | symbolic | test/symbolic/libraries/EmissionsLogic.symbolic.t.sol:59 `prove_isPenaltyWindowOpen_NeverOpensWithoutAConfig` |
