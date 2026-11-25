# QueueLib.requirePending

Code: `src/core/libraries/state/QueueLib.sol` `requirePending` (:562-564).

| Claim | Status | Evidence |
|---|---|---|
| reverts with `RequestNotPending` exactly when the record holds no amount or sits outside the pending epoch | symbolic | test/symbolic/libraries/QueueLib.symbolic.t.sol:71 `prove_requirePending_RevertsIffTheRecordIsNotAnAmountInThePendingEpoch` |
