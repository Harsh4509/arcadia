# WithdrawOptimizationMath.getNormalizedParameters

Code: `src/vaults/libraries/math/WithdrawOptimizationMath.sol:390-472` `getNormalizedParameters`. Derivation: [getNormalizedParameters.derivation.md](getNormalizedParameters.derivation.md).

| Claim | Status | Evidence |
|---|---|---|
| The reserve term `r = floor(R B / D) − floor(C W_out / D)` is non-negative at every call from `previewWithdraw` that returns, so its `uint256` casts are exact | derived | derivation sections 3.1 to 3.6: `C <= B` by the guard before the solve (WithdrawOptimizationMath.sol:96-98), `W <= L` at every solve |
| `W > L` holds at the snapshot with spot exactly on a core range's edge tick and the pool's tick past it, and the walk's first step is then a zero step whose cross restores `W <= L` before any solve | derived | derivation sections 3.4, 3.5 |
| For `R >= 2^255` the call reverts (checked product, `fullMulDiv` or `toInt256`) instead of returning | derived | derivation section 3.1 |
| The chain `F(C, W_out, D) <= F(B, W_out, D) = F(W_out, B, D) <= F(R, B, D)` holds by the lemmas M and S where `R B < 2^256` (and `L < 2^64` one for zero) | symbolic (lemmas) + derived | derivation section 3.9: test/symbolic/libraries/FixedPointMathLib.symbolic.t.sol:21 `prove_fullMulDiv_IsMonotoneInTheAmount`, :37 `prove_fullMulDiv_IsSymmetricInBothFactors` |
| The function's output is non-negative for either sign of `r`, so the sign is checked on `r` itself | derived, fuzz | derivation section 3.8: test/fuzz/libraries/WithdrawOptimizationMath/GetNormalizedParameters.fuzz.t.sol:106 `testFuzz_Success_getNormalizedParameters_TheReserveTermIsNotNegative` rebuilds `r` |
| Each returned term is at most `2^192` in size, and the normalization changes the quadratic's root only through one floor per term | derived | derivation section 3.7, statement 3 |
