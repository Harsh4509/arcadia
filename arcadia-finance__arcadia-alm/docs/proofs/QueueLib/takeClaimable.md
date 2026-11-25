# QueueLib.takeClaimable

Code: `src/core/libraries/state/QueueLib.sol` `takeClaimable` (:499-520).

| Claim | Status | Evidence |
|---|---|---|
| succeeds iff the pile covers the input and is not empty | open | test/symbolic/libraries/QueueLib.symbolic.t.sol:264 `prove_takeClaimable_SucceedsIffTheInputIsCoveredAndThePileIsNotEmpty` |
| takes the floored pro rata output capped at the max, both leaving the pile | open | test/symbolic/libraries/QueueLib.symbolic.t.sol:282 `prove_takeClaimable_TakesTheFlooredProRataOutputCappedAtTheMax` (z3int) |
| without input hands out the output up to the max | open | test/symbolic/libraries/QueueLib.symbolic.t.sol:302 `prove_takeClaimable_WithoutInputHandsOutTheOutputUpToTheMax` |
