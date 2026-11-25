# PlanCache.getLevies

Code: `src/core/types/PlanCache.sol` `getLevies` (:396-422). [Derivation](getLevies.derivation.md).

| Claim | Status | Evidence |
|---|---|---|
| each levy is at most the swap's cost | symbolic (lemmas) + derived | [derivation](getLevies.derivation.md) section 2 from test/symbolic/libraries/FixedPointMathLib.symbolic.t.sol:63 `prove_fullMulDivUp_APartOfAnAmountIsAtMostTheAmount`. Lemma domain: products below 2^256, which holds for flows and holdings below 2^127 and a cost below 2^128 |
| both levies together are at most the swap's cost plus 1 wei | symbolic (lemmas) + derived | section 2, with test/symbolic/libraries/FixedPointMathLib.symbolic.t.sol:90 `prove_fullMulDivUp_APartRoundedUpAndTheRestFlooredMakeTheAmount` (z3int) and :77 `prove_fullMulDivUp_ExceedsFullMulDivByAtMostOne` |
| the levies together never exceed the swap's cost | false (derived) | section 3: two ceilings of halves of an odd levy. At a price of one, a sale of 2 token0 for 1 token1 (cost 1) and two flows of 2 over equal holdings of 1 levy 1 and 1. The inputs lie inside the domain of test/fuzz/libraries/PlanCacheLib/GetLevies.fuzz.t.sol:49 `testFuzz_Success_getLevies_EachLevyIsItsShareRoundedUp`, which asserts each levy is 1 there |
| is `(0, 0)` without a cost, without a swapped value or without holdings, for holdings whose sum fits 256 bits | symbolic | test/symbolic/libraries/PlanCacheLib.symbolic.t.sol:299 `prove_getLevies_AreNothingWithoutACostOrHoldings` |
| each levy is at most its flow and the swap's cost, in one run on the function (flows and holdings below 2^127, cost and swapped value below 2^128) | open | test/symbolic/libraries/PlanCacheLib.symbolic.t.sol:323 `prove_getLevies_EachLevyIsAtMostItsFlowAndTheSwapsCost`: the solver returned unknown within the 120 s timeout |
| both levies together are at most the swap's cost plus 1 wei, in one run on the function (same domain) | open | test/symbolic/libraries/PlanCacheLib.symbolic.t.sol:349 `prove_getLevies_TogetherAreAtMostTheSwapsCostPlusOne` (z3int): timed out at 120 s |
