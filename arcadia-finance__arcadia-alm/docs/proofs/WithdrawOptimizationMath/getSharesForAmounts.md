# WithdrawOptimizationMath.getSharesForAmounts

Code: `src/vaults/libraries/math/WithdrawOptimizationMath.sol` `getSharesForAmounts` (:207-262). One range, price and target in `[2^64, 2^128)` in the swap's direction, nonzero pool liquidity below `2^100` holding the position's, fee below one, `uint128` amounts and supply, nonzero tokenIn holdings.

| Claim | Status | Evidence |
|---|---|---|
| the shares are at most the supply, or `type(uint256).max` when none pay | open | test/symbolic/libraries/WithdrawOptimizationMath.symbolic.t.sol:118 `prove_getSharesForAmounts_AreAtMostTheSupplyOrNone` (z3int): timed out at 120 s |
