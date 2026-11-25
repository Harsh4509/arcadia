# EquivalentPositionMath.amountsAt

Code: `src/vaults/libraries/math/EquivalentPositionMath.sol` `amountsAt` (:109-124).

| Claim | Status | Evidence |
|---|---|---|
| floors the negated constants without liquidity | symbolic | test/symbolic/libraries/EquivalentPositionMath.symbolic.t.sol:23 `prove_amountsAt_FloorsTheNegatedConstantsWithoutLiquidity` |
| token0 never rises with the price | symbolic | test/symbolic/libraries/EquivalentPositionMath.symbolic.t.sol:46 `prove_amountsAt_Token0NeverRisesWithThePrice` |
| is the floored value of the position at the price | symbolic | test/symbolic/libraries/EquivalentPositionMath.symbolic.t.sol:69 `prove_amountsAt_FloorsTheOwnAmountsLessTheConstants` (z3int, the real solady 0.1.26, no spec) |
| token1 never falls with the price | symbolic | test/symbolic/libraries/EquivalentPositionMath.symbolic.t.sol:97 `prove_amountsAt_Token1NeverFallsWithThePrice` (z3int, the real solady 0.1.26, no spec) |
