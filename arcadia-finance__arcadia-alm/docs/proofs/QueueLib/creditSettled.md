# QueueLib.creditSettled

Code: `src/core/libraries/state/QueueLib.sol` `creditSettled` (:453-473).

| Claim | Status | Evidence |
|---|---|---|
| moves the record's floored pro rata output and its input from the epoch into the claimable pile, and empties the record | open | test/symbolic/libraries/QueueLib.symbolic.t.sol:234 `prove_creditSettled_MovesTheRecordsProRataOutputIntoTheClaimablePile` (z3int) |
