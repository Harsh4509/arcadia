# DepositOptimizationMath.getBalanceIn

Code: `src/vaults/libraries/math/DepositOptimizationMath.sol` `getBalanceIn` (:252-259).

| Claim | Status | Evidence |
|---|---|---|
| is at least the swap's input | open | test/symbolic/libraries/DepositOptimizationMath.symbolic.t.sol:56 `prove_getBalanceIn_IsAtLeastTheSwapsInput` |
| is monotone in the swap's output | open | test/symbolic/libraries/DepositOptimizationMath.symbolic.t.sol:71 `prove_getBalanceIn_IsMonotoneInTheSwapsOutput` (z3int) |
| is unbounded without position tokenOut | open | test/symbolic/libraries/DepositOptimizationMath.symbolic.t.sol:109 `prove_getBalanceIn_IsUnboundedWithoutPositionTokenOut` |
