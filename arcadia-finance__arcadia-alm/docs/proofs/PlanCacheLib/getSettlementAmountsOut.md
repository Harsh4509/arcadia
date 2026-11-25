# PlanCacheLib.getSettlementAmountsOut

Code: `src/core/types/PlanCache.sol` `getSettlementAmountsOut` (:282-381). [Derivation](getSettlementAmountsOut.derivation.md).

| Claim | Status | Evidence |
|---|---|---|
| each deposit gets at most `floor(depositValue * supplyBefore / valueUp)` shares, `valueUp` the existing aLP's value after the swap rounded up, before the levies, so at most its part of the supply at the real value | symbolic (lemmas) + derived | [derivation](getSettlementAmountsOut.derivation.md) section 1: test/symbolic/libraries/FixedPointMathLib.symbolic.t.sol:21 `prove_fullMulDiv_IsMonotoneInTheAmount` and test/symbolic/libraries/FixedPointMathLib.symbolic.t.sol:47 `prove_fullMulDiv_NeverRisesWithTheDivisor`. Lemma domain: `depositValue * supplyBefore < 2^256`, every uint128 value and supply |
| without a swap the redeems get their floored share of the existing value rounded down and the deposits their floored share of the supply at that value rounded up (the two values 1 wei apart at most, 2 above a sqrt price of 2^128) | derived | section 2: `getLevies` returns `(0, 0)` |
| each redeem gets at most its shares' part of the existing value before the swap, and the levied one at most its part of the value after the swap plus the deposit levy, for redeem shares within the supply | derived | section 3, its lemma `F(a + r, s, S) <= F(a, s, S) + r` derived on solady's floor specification, not machine-checked |
| the claims above in one symbolic run on the function | open | section 4: no completed symbolic run of the whole function |
