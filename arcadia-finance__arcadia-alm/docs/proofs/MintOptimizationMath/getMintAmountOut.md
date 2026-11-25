# MintOptimizationMath.getMintAmountOut

Code: `src/vaults/libraries/math/MintOptimizationMath.sol` `getMintAmountOut` (:217-229). One range, prices between 2^48 and 2^128, supply uint128.

| Claim | Status | Evidence |
|---|---|---|
| is zero iff the mint takes no tokenOut | open | test/symbolic/libraries/MintOptimizationMath.symbolic.t.sol:38 `prove_getMintAmountOut_IsZeroIffTheMintTakesNoTokenOut` (z3int) |
| is at least the mint's tokenOut plus one per range, with the mint's liquidity in range | open | test/symbolic/libraries/MintOptimizationMath.symbolic.t.sol:64 `prove_getMintAmountOut_IsAtLeastTheMintsTokenOutPlusTheRangeCount` (z3int) |
