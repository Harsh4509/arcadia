# SnapshotLib.idle

Code: `src/vaults/types/Snapshot.sol` `idle` (:149-151).

| Claim | Status | Evidence |
|---|---|---|
| succeeds exactly when both sums fit 256 bits, and is the buffer plus the uncollected fees | symbolic | test/symbolic/libraries/SnapshotLib.symbolic.t.sol:385 `prove_idle_SucceedsIffBothSumsFit` |
