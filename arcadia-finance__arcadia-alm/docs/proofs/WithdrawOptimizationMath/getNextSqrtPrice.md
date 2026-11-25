# WithdrawOptimizationMath.getNextSqrtPrice

Code: `src/vaults/libraries/math/WithdrawOptimizationMath.sol` `getNextSqrtPrice` (:303-332). Pool prices, the target distinct from the price in the swap's direction, any move.

| Claim | Status | Evidence |
|---|---|---|
| is past the step's start and at most at its target | open | test/symbolic/libraries/WithdrawOptimizationMath.symbolic.t.sol:24 `prove_getNextSqrtPrice_MovesPastTheStartAndAtMostToTheTarget` (z3int): timed out at 120 s |
