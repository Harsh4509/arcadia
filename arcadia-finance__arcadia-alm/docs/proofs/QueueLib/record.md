# QueueLib.record

Code: `src/core/libraries/state/QueueLib.sol` `record` (:408-425).

| Claim | Status | Evidence |
|---|---|---|
| succeeds iff the controller is set, the amount non-zero and the record's, pending shares' and epoch's sums fit, and then adds the request under the pending epoch | open | test/symbolic/libraries/QueueLib.symbolic.t.sol:176 `prove_record_SucceedsIffTheRequestIsValidAndTheSumsFit` |
