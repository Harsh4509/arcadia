# DepositOptimizationMath.getNormalizedParameters

Code: `src/vaults/libraries/math/DepositOptimizationMath.sol` `getNormalizedParameters` (:423-487).

| Claim | Status | Evidence |
|---|---|---|
| the largest part of the position normalizes to one, or every part is zero for an empty position (prices below 2^128) | open | test/symbolic/libraries/DepositOptimizationMath.symbolic.t.sol:121 `prove_getNormalizedParameters_NormalizeTheLargestPartOfThePositionToOne` (z3int) |
| reverts AmountInTooLarge iff a balance relative to the pool liquidity exceeds MAX_NORMALIZED (token0 swap, prices at most one, balances below 2^64, token1 balance with `x < 2^96 s`) | open | test/symbolic/libraries/DepositOptimizationMath.symbolic.t.sol:212 `prove_getNormalizedParameters_RevertsIffABalanceExceedsTheMaxNormalized` (z3int). The reference is derived below |

## Derivation of the token1 reference

The token1 balance normalizes as `floor(x 2^160 / s)`, `x = floor(balanceOut 2^128 / L)` (DepositOptimizationMath.sol:482), `s` the square root price, and the check is against `MAX_NORMALIZED = 2^252` (DepositOptimizationMath.sol:35, :486).

- `floor(x 2^160 / s) <= 2^252` iff `x 2^160 < (2^252 + 1) s` iff `x <= 2^92 s + (s − 1) / 2^160`. For `s <= 2^96` the last term is below 1, so the check passes iff `x <= 2^92 s`. The proof's reference takes this form (DepositOptimizationMath.symbolic.t.sol:226-227).
- For `x >= 2^96 s` the quotient is `2^256` or more and `fullMulDiv` reverts `FullMulDivFailed` before the check, so the claim's domain takes `x < 2^96 s` (DepositOptimizationMath.symbolic.t.sol:225). This revert path is the `FullMulDivFailed` case of docs/audit-doc.md 6.4, Extreme prices and amounts.
- The token0 reference `balanceIn (s << 96) / L` is exact: `balanceIn (s 2^96)` is below `2^256` for `balanceIn < 2^64` and `s <= 2^96`.
