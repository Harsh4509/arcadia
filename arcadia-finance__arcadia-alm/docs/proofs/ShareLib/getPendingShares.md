# ShareLib.getPendingShares

Code: `src/core/libraries/state/ShareLib.sol` `getPendingShares` (:99-122).

| Claim | Status | Evidence |
|---|---|---|
| token1 at or above the last price is the assets at the rate rounded up | symbolic | test/symbolic/libraries/ShareLib.symbolic.t.sol:81 `prove_getPendingShares_Token1AtOrAboveTheLastPriceIsTheAssetsAtTheRateRoundedUp` |
| token0 below the last price is monotone in the assets | derived, symbolic open | [derivation](getPendingShares.derivation.md): the code is three `fullMulDivUp`s by the constants 2^96, 2^96 and 2^128, so the claim follows from one lemma, immediate when `fullMulDivUp` is the exact ceiling (solady's specification). No symbolic run of the lemma or the function completed |
