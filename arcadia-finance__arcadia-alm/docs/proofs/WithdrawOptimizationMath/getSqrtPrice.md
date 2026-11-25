# WithdrawOptimizationMath.getSqrtPrice

Code: `src/vaults/libraries/math/WithdrawOptimizationMath.sol` `getSqrtPrice` (:276-293). One range, prices and target in `[2^64, 2^128)`, pool liquidity below `2^100` holding the position's, fee below one, `uint128` holdings `D = max(B, A)` with `C <= B`, `a <= D` and the position's liquidity below `D * 2^40`.

| Claim | Status | Evidence |
|---|---|---|
| is past the step's start and at most at its target | open | test/symbolic/libraries/WithdrawOptimizationMath.symbolic.t.sol:80 `prove_getSqrtPrice_MovesPastTheStartAndAtMostToTheTarget` (z3int): timed out at 120 s |
