# CLMath.convert

Code: `src/shared/libraries/math/CLMath.sol` `convert` (:39-68). Every row takes `roundUp = false`. The rows after the first take `sqrtPriceX96 <= 2^128 - 1`, the branch that divides once (`amount * P^2 / 2^192` or `amount * 2^192 / P^2`, one `fullMulDiv`). Above 2^128 the code divides twice (`floor(amount floor(P^2 / 2^64) / 2^128)`, `floor(floor(amount 2^96 / P) 2^96 / P)`), which no row covers, and no row covers `roundUp = true`.

| Claim | Status | Evidence |
|---|---|---|
| is the identity at price one | symbolic | test/symbolic/libraries/CLMath.symbolic.t.sol:37 `prove_convert_IsTheIdentityAtPriceOne` |
| zero for one, is the floored value | symbolic | test/symbolic/libraries/CLMath.symbolic.t.sol:45 `prove_convert_ZeroForOne_IsTheFlooredValue` |
| one for zero, is the floored value | symbolic | test/symbolic/libraries/CLMath.symbolic.t.sol:56 `prove_convert_OneForZero_IsTheFlooredValue` |
| of nothing is nothing | symbolic | test/symbolic/libraries/CLMath.symbolic.t.sol:68 `prove_convert_OfNothingIsNothing` |
| zero for one, is monotone in the amount | symbolic | test/symbolic/libraries/CLMath.symbolic.t.sol:78 `prove_convert_ZeroForOne_IsMonotoneInTheAmount` |
| one for zero, is monotone in the amount | symbolic | test/symbolic/libraries/CLMath.symbolic.t.sol:94 `prove_convert_OneForZero_IsMonotoneInTheAmount` |
| zero for one, is monotone in the price (prices at most one, amounts below 2^64) | open | test/symbolic/libraries/CLMath.symbolic.t.sol:195 `prove_convert_ZeroForOne_IsMonotoneInThePrice` (z3int) |
| one for zero, is antitone in the price (prices at most one, amounts below 2^64) | open | test/symbolic/libraries/CLMath.symbolic.t.sol:212 `prove_convert_OneForZero_IsAntitoneInThePrice` (z3int) |
| there and back never gains (prices at most one, amounts below 2^64) | open | test/symbolic/libraries/CLMath.symbolic.t.sol:230 `prove_convert_ThereAndBackNeverGains` (z3int) |
