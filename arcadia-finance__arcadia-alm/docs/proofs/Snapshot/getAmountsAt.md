# SnapshotLib.getAmountsAt

Code: `src/vaults/types/Snapshot.sol` `getAmountsAt` (:176-203), against the pool's `SqrtPriceMath`.

| Claim | Status | Evidence |
|---|---|---|
| without ranges is the buffer plus the uncollected fees, for sums that fit 256 bits | symbolic | test/symbolic/libraries/SnapshotLib.symbolic.t.sol:409 `prove_getAmountsAt_WithoutRangesIsTheIdleTokens` |
| with one range between pool prices is the pool's rounded down amounts of the range at the price plus uint128 idle tokens | open | test/symbolic/libraries/SnapshotLib.symbolic.t.sol:430 `prove_getAmountsAt_OneRange_AddsThePoolsAmountsToTheIdleTokens` (z3int): timed out at 120 s |
| the sum over up to `MAX_RANGE_CAP` ranges | open | no proof: the one-range row is the only one |
