# DepositOptimizationMath.getQuadraticCoefficients

Code: `src/vaults/libraries/math/DepositOptimizationMath.sol` `getQuadraticCoefficients` (:362-406). Prices below 2^128, balances below 2^128, unstaked liquidity within the position's, fee share at most one.

| Claim | Status | Evidence |
|---|---|---|
| the quadratic coefficient A is non-negative (getRoot's a >= 0 from the deposit), on every input that returns | derived, symbolic open | [getQuadraticCoefficients.derivation.md](getQuadraticCoefficients.derivation.md) section 3.3: `A >= positionAmountInNormalized`. test/symbolic/libraries/DepositOptimizationMath.symbolic.t.sol:150 `prove_getQuadraticCoefficients_TheQuadraticCoefficientIsNonNegative` (z3int) |
| no operation of the unchecked block wraps and every `int256` cast is exact | derived | [getQuadraticCoefficients.derivation.md](getQuadraticCoefficients.derivation.md) section 3.2 |
| the linear coefficient B is at least the constant coefficient C | open | test/symbolic/libraries/DepositOptimizationMath.symbolic.t.sol:181 `prove_getQuadraticCoefficients_TheLinearCoefficientIsAtLeastTheConstantCoefficient` (z3int) |
