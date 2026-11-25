# QueueLib.requestAmountIn

Code: `src/core/libraries/state/QueueLib.sol` `requestAmountIn` (:597-603).

| Claim | Status | Evidence |
|---|---|---|
| is the ceiled pro rata input | symbolic | test/symbolic/libraries/QueueLib.symbolic.t.sol:139 `prove_requestAmountIn_IsTheCeiledProRataInput` |
| of the output never exceeds the request, for `amountIn <= batchAmountIn`, which src does not check: a record within its epoch by [queueInvariants.derivation.md](queueInvariants.derivation.md) I2 | symbolic | test/symbolic/libraries/QueueLib.symbolic.t.sol:159 `prove_requestAmountIn_OfTheOutputNeverExceedsTheRequest` |
