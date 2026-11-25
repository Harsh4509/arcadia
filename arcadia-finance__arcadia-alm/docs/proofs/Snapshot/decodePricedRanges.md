# SnapshotLib.decodePricedRanges

Code: `src/vaults/types/Snapshot.sol` `decodePricedRanges` (:123-141). One range stored by the compiler, valid ticks, unstaked plus staked liquidity within `uint128` (the sum is unchecked, :132-134).

| Claim | Status | Evidence |
|---|---|---|
| holds both sides' liquidity, the unstaked side's, and `TickMath`'s sqrt prices at the stored ticks | open | test/symbolic/libraries/SnapshotLib.symbolic.t.sol:480 `prove_decodePricedRanges_PricesTheStoredRange`: stuck at the solver query limit (10000), from `TickMath` at symbolic ticks |
