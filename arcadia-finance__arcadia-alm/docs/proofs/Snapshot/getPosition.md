# SnapshotLib.getPosition

Code: `src/vaults/types/Snapshot.sol` `getPosition` (:160-167). With ranges it is `EquivalentPositionMath.getPosition`: [EquivalentPositionMath/getPosition.md](../EquivalentPositionMath/getPosition.md).

| Claim | Status | Evidence |
|---|---|---|
| without ranges holds the buffer plus the uncollected fees, no liquidity, bounded by the pool's extreme price, for a buffer and fees below 2^254 each | symbolic | test/symbolic/libraries/SnapshotLib.symbolic.t.sol:456 `prove_getPosition_WithoutRangesHoldsTheIdleTokens` |
