# CLMath.getAmount0ForLiquidityRoundingUp

Code: `src/shared/libraries/math/CLMath.sol` `getAmount0ForLiquidityRoundingUp` (:160-176). Rows assume ordered bounds below 2^128. Above, the 512-bit path of `fullMulDivN` is open.

| Claim | Status | Evidence |
|---|---|---|
| is the liquidity times the width over the manager's floored divisor J = floor(a b / 2^96), rounded up | open | test/symbolic/libraries/CLMath.symbolic.t.sol:368 `prove_getAmount0ForLiquidityRoundingUp_IsTheCeiledAmountOverTheManagersDivisor` (z3int) |
| reverts NoLiquidityForToken0 iff the bounds' product is below 2^96 | open | test/symbolic/libraries/CLMath.symbolic.t.sol:385 `prove_getAmount0ForLiquidityRoundingUp_RevertsIffTheBoundsProductIsBelowQ96` (z3int) |
| is at least the pool's rounded down token0 delta floor(L 2^96 (b - a) / (a b)), for liquidity times width below 2^160 | open | test/symbolic/libraries/CLMath.symbolic.t.sol:408 `prove_getAmount0ForLiquidityRoundingUp_IsAtLeastThePoolsRoundedDownDelta` (z3int) |
| is monotone in the liquidity | open | test/symbolic/libraries/CLMath.symbolic.t.sol:426 `prove_getAmount0ForLiquidityRoundingUp_IsMonotoneInTheLiquidity` (z3int) |
