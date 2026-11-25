# QueueLib.requestAmountOut

Code: `src/core/libraries/state/QueueLib.sol` `requestAmountOut` (:582-588). src does not check `amountIn <= batchAmountIn`: the rows that assume it hold for the callers' requests, a record within its epoch by [queueInvariants.derivation.md](queueInvariants.derivation.md) I2 (`creditSettled`, :462, and `src/core/libraries/logic/ALMCoreViewLogic.sol:689`), and an input within the claimable pile by the check at :507 (`takeClaimable`, :511).

| Claim | Status | Evidence |
|---|---|---|
| is the floored pro rata share | symbolic | test/symbolic/libraries/QueueLib.symbolic.t.sol:87 `prove_requestAmountOut_IsTheFlooredProRataShare` |
| never exceeds the batch, for `amountIn <= batchAmountIn` (a caller invariant, see above) | symbolic | test/symbolic/libraries/QueueLib.symbolic.t.sol:105 `prove_requestAmountOut_NeverExceedsTheBatch` |
| is monotone in the request | symbolic | test/symbolic/libraries/QueueLib.symbolic.t.sol:120 `prove_requestAmountOut_IsMonotoneInTheRequest` |
