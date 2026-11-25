# DepositOptimizationMath.getAmountOut

Code: `src/vaults/libraries/math/DepositOptimizationMath.sol` `getAmountOut` (:272-316). The domain of [getSqrtPrice.md](getSqrtPrice.md), on the calls that return.

| Claim | Status | Evidence |
|---|---|---|
| the price ends between the pool's price and the position's bound, and the output is at most the pool's rounded down output of the move to the bound | open | test/symbolic/libraries/DepositOptimizationMath.symbolic.t.sol:285 `prove_getAmountOut_StaysWithinThePoolsMoveToTheBound` (z3int): timed out at 120 s |
