# QuadraticMath.getRoot

Code: `src/vaults/libraries/math/QuadraticMath.sol:33-51` `getRoot`. Derivation: [getRoot.derivation.md](getRoot.derivation.md).

| Claim | Status | Evidence |
|---|---|---|
| returns the edges outside the interior | symbolic | test/symbolic/libraries/QuadraticMath.symbolic.t.sol:19 `prove_getRoot_ReturnsTheEdgesOutsideTheInterior` |
| interior roots round down, at most the exact root | derived | derivation section 3: the ceiling square root (QuadraticMath.sol:45-46) in the denominator joins the three floors. test/fuzz/libraries/QuadraticMath/GetRoot.fuzz.t.sol:164 `testFuzz_Success_getRoot_TheDiscriminantRootRoundedUpAtAHalfDiscriminant` asserts the ceiling |
| interior root below the exact root by less than `X 2^-127 + min(5 / (q (1 + q)^2), 2 sqrt(5 (ratio + 1))) + 3` units of `2^-192`, `q = sqrt(1 - 4ac / b^2)` | derived | derivation section 3 |
| the near-double-root error reaches about `2^98` units of `2^-192` (`2^-95` relative) | derived | derivation section 3: bound of term B at the last interior point before the guard |
| callers need a root that rounds down: the deposit's swap must land short, the withdraw's candidates are direction-free | derived | derivation section 6 |
| a = 0 returns the floored c / b, for b >= 4 | derived | derivation section 4. test/fuzz/libraries/QuadraticMath/GetRoot.fuzz.t.sol:83 `testFuzz_Success_getRoot_LinearWhenTheQuadraticTermIsZero` |
| a = 0 returns the floored c / b, for b >= 4 (c below 2^64) | open | test/symbolic/libraries/QuadraticMath.symbolic.t.sol:31 `prove_getRoot_WithoutAQuadraticTermIsTheFlooredRatio` (z3int) |
| for a = 0 and b in {2, 3} the root is one (degenerate: a linear coefficient of 2 or 3 units of `2^-192`) | derived, symbolic open | derivation section 4. test/symbolic/libraries/QuadraticMath.symbolic.t.sol:40 `prove_getRoot_WithoutAQuadraticTermAndALinearCoefficientBelowFourIsOne` |
| the guard returns one on interior inputs with 4ac / b^2 in (1 - 4 / b, 1) | derived | derivation sections 1 and 4 |
| ratio = 0 (c 2^192 < b) returns zero on the interior | derived, symbolic open | derivation section 4. test/symbolic/libraries/QuadraticMath.symbolic.t.sol:50 `prove_getRoot_IsZeroWhenTheRatioFloorsToZero` (z3int) |
| interior root at most twice the floored ratio | open | test/symbolic/libraries/QuadraticMath.symbolic.t.sol:61 `prove_getRoot_IsAtMostTwiceTheRatio`. test/fuzz/libraries/QuadraticMath/GetRoot.fuzz.t.sol:95 `testFuzz_Success_getRoot_BetweenTheLinearRootAndTwiceIt` |
| interior root at least the floored ratio | open | test/symbolic/libraries/QuadraticMath.symbolic.t.sol:72 `prove_getRoot_IsAtLeastTheRatio` (z3int) |
| a < 0 is unreachable from src | derived | derivation section 5: Deposit's A is at least its position term after the fee term. Withdraw's coefficient is non-negative without a clamp ([getQuadraticCoefficients](../WithdrawOptimizationMath/getQuadraticCoefficients.md)) |
| Deposit computeSwap: holders unaffected, no revert, a short move refunds tokenIn | derived | derivation section 5 |
| Deposit maxDeposit: a root at most the exact one ends short of the limit, the one-unit limit margin carries no term for the root | derived | derivation section 5 |
| Withdraw previewWithdraw: with the target `a + 1` the root or its neighbour pays while the price error is under half a unit, for a core without tokenOut and liquidity on the step | derived | derivation section 5 |
| Withdraw previewWithdraw: the same in a thin pool with `A > 0` or `W > 0` | model | derivation section 5: the core pays out at most what it holds in a step, the rounded evaluation moves the paying shares by under one share, and the `holdingsOut = 0`, `W > 0` state exceeds the margins only for a dust core |
| Withdraw previewWithdraw near the quadratic's double root | degenerate | derivation section 5: with idle tokenOut it needs the burnt fraction to reach 1, which `DEAD_SHARES` exclude, without it a core holding at most `n` wei of tokenOut over its whole range. Only the quote's optimality is affected. The lower bound on `q` is derivation section 7 |
| previewWithdraw(maxWithdraw) is at most the shares | open | `maxWithdraw`'s margins (WithdrawOptimizationMath.sol:154-180) carry no term for the candidate's distance to the least paying price |
| the near-double-root regime (q below about 2^-64) is reachable from the withdraw's callers only in degenerate states | degenerate | derivation section 5 (the double root's condition) and section 7: it needs the burn and the sale to take all but `2^-63` of the step's tokenOut reserve |
| withdraw quadratic in real amounts: `q = (c − a X^2) / (c + a X^2)`, `q >= (θ − X) / (θ + X)` with `θ = (R − σ W_out) / (R' + ν)`, and `q >= (1 − X) / (1 + X)` when the model's tokenOut left at the root covers the `n` term | derived | derivation section 7. The floors of the computed coefficients are not carried into the bound |
