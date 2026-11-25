# QueueLib.cancel

Code: `src/core/libraries/state/QueueLib.sol` `cancel` (:433-443).

| Claim | Status | Evidence |
|---|---|---|
| releases the record's pending shares, takes its amount out of the epoch and empties it | open | test/symbolic/libraries/QueueLib.symbolic.t.sol:212 `prove_cancel_TakesTheRecordOutOfTheEpochAndEmptiesIt` |
