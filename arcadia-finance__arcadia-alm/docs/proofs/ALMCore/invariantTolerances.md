# ALMCore invariant tolerances

Code: `test/invariant/handlers/ALMCoreHandler.sol:933` `_countPerShareFall`, :986 `creditedAndAccrued`, `test/invariant/ALMCore.invariant.t.sol:923` `invariant_creditedRewardsCoverTheHighWaterLessLossesAndRounding`. Derivation: [invariantTolerances.derivation.md](invariantTolerances.derivation.md).

| Claim | Status | Evidence |
|---|---|---|
| a core mint or burn lowers the measured value per share by at most `R (2 + convert(P, true, 1, false)) + 1` over the supply | derived | derivation section 1. test/invariant/ALMCore.invariant.t.sol:883 `invariant_stayersValuePerShareNeverFallsOnMintOrWithdraw` |
| credited plus accrued reward covers high water plus pre-credit less losses and `checkpoints (maxSupply / 1e18 + actors + 2) + actors + 3` | derived | derivation section 2, assumes the accumulator never wraps past 2^128. test/invariant/ALMCore.invariant.t.sol:923 `invariant_creditedRewardsCoverTheHighWaterLessLossesAndRounding` |
| the unit term of `losses` must be the number of checkpoints at which the pre-credit drops, in `invariant_rewardDeficitIsBoundedByForfeitsAndGovernanceMoves`, and is not needed in `invariant_creditedRewardsCoverTheHighWaterLessLossesAndRounding` | derived | derivation section 3 |
| `handler.ghostClaims()`, one unit per claim and per protocol fee change, is at least that number | open | derivation section 3.3: a drop can fall in a call that is neither, with no claim before it. Derived, not run |
