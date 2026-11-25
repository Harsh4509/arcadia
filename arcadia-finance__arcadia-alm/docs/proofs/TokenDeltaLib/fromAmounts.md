# TokenDeltaLib.fromAmounts

Code: `src/core/types/TokenDelta.sol` `fromAmounts` (:85-90).

| Claim | Status | Evidence |
|---|---|---|
| succeeds iff both amounts are below 2^127 | symbolic | test/symbolic/libraries/TokenDeltaLib.symbolic.t.sol:79 `prove_fromAmounts_SucceedsIffBothAmountsAreBelow2To127` |
| round trips through to amounts | symbolic | test/symbolic/libraries/TokenDeltaLib.symbolic.t.sol:92 `prove_fromAmounts_RoundTripsThroughToAmounts` |
