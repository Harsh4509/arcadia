# CLMath.getAmount1ForLiquidityRoundingUp

Code: `src/shared/libraries/math/CLMath.sol` `getAmount1ForLiquidityRoundingUp` (:185-195). Rows assume ordered bounds less than 2^128 apart.

| Claim | Status | Evidence |
|---|---|---|
| is the liquidity times the width, rounded up | symbolic | test/symbolic/libraries/CLMath.symbolic.t.sol:335 `prove_getAmount1ForLiquidityRoundingUp_IsTheCeiledAmount` (z3int) |
| exceeds the floored amount (the pool's rounded down delta) by at most one | open | test/symbolic/libraries/CLMath.symbolic.t.sol:350 `prove_getAmount1ForLiquidityRoundingUp_ExceedsTheFlooredAmountByAtMostOne` (z3int) |
