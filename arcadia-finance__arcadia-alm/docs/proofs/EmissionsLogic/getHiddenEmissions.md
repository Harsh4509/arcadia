# EmissionsLogic.getHiddenEmissions

Code: `src/core/libraries/logic/EmissionsLogic.sol` `getHiddenEmissions` (:102-159). One staked side inside its window, gauge and pool mocked, no staked pool liquidity (no projection), growth delta below 2^128, penalty rate and referral share at most MAX_PIPS (the gauge factory's `setPenaltyConfig` 'MR' and `maxShareCap <= MAX_PIPS`), `stakedBlock + minStakeBlocks < 2^48`.

| Claim | Status | Evidence |
|---|---|---|
| hides at most the penalty's cut of the side's accrued emissions, never underflows, and ends the window with the side's | symbolic | test/symbolic/libraries/EmissionsLogic.symbolic.t.sol:108 `prove_getHiddenEmissions_OneStakedSide_HidesAtMostThePenaltysCut` (z3int) |

The bound on the accrued emissions that src enforces: [getHiddenEmissions.derivation.md](getHiddenEmissions.derivation.md).

## Derivation

With `a` the side's accrued emissions (below 2^128: growth delta and `stakedLiquidity` below 2^128), `r` the penalty rate, `h` the referral share, `M = MAX_PIPS`, the code computes `v = a - floor(a r / M)` and adds `(a - floor(a h / M)) - (v - floor(v h / M)) = floor(a r / M) - (floor(a h / M) - floor(v h / M))`.

- At most the penalty's cut: `v <= a` gives `floor(v h / M) <= floor(a h / M)`, so the term is at most `floor(a r / M)`, the gauge's `_applyPenalty` amount (`Gauge.sol` `_reward * _config.penaltyRate / MAX_PIPS`).
- No underflow: `r <= M` gives `v >= 0`, `h <= M` gives `floor(a h / M) <= a`, and `floor(a h / M) - floor(v h / M) <= ceil((a - v) h / M) <= a - v` (`a - v` is an integer and `h <= M`), so the term is non-negative. `a r` and `a h` stay below 2^148.
- Window end: `windowEnd = uint48(max(windowEnd, stakedBlock + minStakeBlocks))` (`EmissionsLogic.sol:140`) equals `stakedBlock + minStakeBlocks` for one side when that sum is below 2^48. Above it the cast keeps the low 48 bits.

Open: Metadex bounds `minStakeBlocks` only by the factory immutable `maxMinStakeBlocks` (`CLGaugeFactory.sol:330`, :339), whose constructor requires only `>= DEFAULT_MIN_STAKE_BLOCKS` (:136). The missing step is a bound `stakedBlock + minStakeBlocks < 2^48` from the deployed factory's `maxMinStakeBlocks` and the chain's block number.
