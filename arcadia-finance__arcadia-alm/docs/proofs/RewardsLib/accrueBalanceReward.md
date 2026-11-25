# RewardsLib.accrueBalanceReward

Code: `src/core/libraries/state/RewardsLib.sol` `accrueBalanceReward` (:217-244). Balances uint128.

| Claim | Status | Evidence |
|---|---|---|
| credits floor(shares ((accumulator - paid) mod 2^128) / 1e18) to the holder's owed reward and marks it paid at the accumulator | open | test/symbolic/libraries/RewardsLib.symbolic.t.sol:36 `prove_accrueBalanceReward_CreditsTheFlooredRewardSinceTheLastCredit` (z3int) |
| succeeds iff the owed reward stays in uint128 | open | test/symbolic/libraries/RewardsLib.symbolic.t.sol:60 `prove_accrueBalanceReward_SucceedsIffTheCreditFitsUint128` (z3int) |
| at the same accumulator changes nothing | open | test/symbolic/libraries/RewardsLib.symbolic.t.sol:89 `prove_accrueBalanceReward_AtTheSameAccumulatorChangesNothing` |
| for the core credits the protocol fees and marks the protocol paid | open | test/symbolic/libraries/RewardsLib.symbolic.t.sol:110 `prove_accrueBalanceReward_ForTheCoreCreditsTheProtocolFees` (z3int) |
