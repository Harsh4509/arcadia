# CLMath.getNextSqrtPrice

Code: `src/shared/libraries/math/CLMath.sol` `getNextSqrtPrice` (:78-99). Every row assumes sqrt prices below 2^64 and a move of at most one. Above, the 512-bit path of `fullMulDivUnchecked` is open.

The unchecked block's subtractions at the one caller: [getNextSqrtPrice.derivation.md](getNextSqrtPrice.derivation.md).

| Claim | Status | Evidence |
|---|---|---|
| stays between the old price and the bound | open | test/symbolic/libraries/CLMath.symbolic.t.sol:244 `prove_getNextSqrtPrice_StaysBetweenTheOldPriceAndTheBound` (z3int) |
| without a move is the old price | open | test/symbolic/libraries/CLMath.symbolic.t.sol:270 `prove_getNextSqrtPrice_WithoutAMoveIsTheOldPrice` (z3int) |
| is monotone in the move | open | test/symbolic/libraries/CLMath.symbolic.t.sol:286 `prove_getNextSqrtPrice_IsMonotoneInTheMove` (z3int) |
| short of the bound, the realized relative move of tokenIn's sqrt price (rounded up) never exceeds the requested one | open | test/symbolic/libraries/CLMath.symbolic.t.sol:309 `prove_getNextSqrtPrice_ShortOfTheBoundNeverMovesPastTheRequestedMove` (z3int) |
