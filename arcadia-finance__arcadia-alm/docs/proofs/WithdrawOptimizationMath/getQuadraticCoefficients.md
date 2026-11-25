# WithdrawOptimizationMath.getQuadraticCoefficients

Code: `src/vaults/libraries/math/WithdrawOptimizationMath.sol:349-373` `getQuadraticCoefficients`. Derivation: [getNormalizedParameters.derivation.md](getNormalizedParameters.derivation.md).

| Claim | Status | Evidence |
|---|---|---|
| `quadraticCoefficient = reserveOutNormalized + liquidityNormalized >= 0` (WithdrawOptimizationMath.sol:369), with no clamp | derived | the reserve term is non-negative ([getNormalizedParameters](getNormalizedParameters.md)) and `liquidityNormalized` is a `uint256`. Derivation statement 1 |
| `quadraticCoefficient = 0` exactly when the reserve term and the liquidity term are both 0, for example `W = 0` and `R B < D`, and the quadratic is then linear | derived | derivation statement 2 |
| Each coefficient is a sum of at most three normalized terms of at most `2^192` each (WithdrawOptimizationMath.sol:369-371), below `2^194` in size, so the unchecked sums are exact | derived | derivation statement 3 |
| The coefficients are the sums of the normalized terms | fuzz | test/fuzz/libraries/WithdrawOptimizationMath/GetQuadraticCoefficients.fuzz.t.sol:26 `testFuzz_Success_getQuadraticCoefficients_FromTheNormalizedTerms` |
| `quadraticCoefficient >= 0` in one run on the function: one range, price in `[2^64, 2^128)`, pool liquidity below `2^100` holding the position's, fee below one, `uint128` holdings `D = max(B, A)` with `C <= B`, `a <= D` and the position's liquidity below `D * 2^40` | open | test/symbolic/libraries/WithdrawOptimizationMath.symbolic.t.sol:53 `prove_getQuadraticCoefficients_TheQuadraticCoefficientIsNonNegative` (z3int): timed out at 120 s |
