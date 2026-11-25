# DepositOptimizationMath.getSqrtPrice

Code: `src/vaults/libraries/math/DepositOptimizationMath.sol` `getSqrtPrice` (:330-345). The domain of [getQuadraticCoefficients.md](getQuadraticCoefficients.md) with a `uint128` rounding margin, the position's bound a price below `2^128` on the swap's side, on the calls that return.

| Claim | Status | Evidence |
|---|---|---|
| lies between the pool's price and the position's bound | open | test/symbolic/libraries/DepositOptimizationMath.symbolic.t.sol:245 `prove_getSqrtPrice_StaysBetweenThePriceAndTheBound` (z3int): timed out at 120 s |
