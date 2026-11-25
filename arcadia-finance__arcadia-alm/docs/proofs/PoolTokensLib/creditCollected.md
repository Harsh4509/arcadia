# PoolTokensLib.creditCollected

Code: `src/core/libraries/state/PoolTokensLib.sol` `creditCollected` (:42-64). Protocol share at most 5000 bps.

| Claim | Status | Evidence |
|---|---|---|
| the protocol gets floor(fees bps / 1e4) of each token, the buffer the principal and the rest, and the returned delta is the buffer's | open | test/symbolic/libraries/PoolTokensLib.symbolic.t.sol:71 `prove_creditCollected_SplitsTheFeesBetweenTheProtocolAndTheBuffer` (z3int) |
| the protocol share is at most half of the fees and the split is exact | open | test/symbolic/libraries/PoolTokensLib.symbolic.t.sol:107 `prove_creditCollected_TheProtocolShareIsAtMostHalfOfTheFees` (z3int) |
