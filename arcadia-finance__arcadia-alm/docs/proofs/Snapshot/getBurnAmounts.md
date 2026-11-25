# SnapshotLib.getBurnAmounts

Code: `src/vaults/types/Snapshot.sol` `getBurnAmounts` (:342-387), against `getAmountsAt` (:176-203). One range of at most one with liquidity below 2^63, supply uint128.

| Claim | Status | Evidence |
|---|---|---|
| of no shares release nothing | open | test/symbolic/libraries/SnapshotLib.symbolic.t.sol:195 `prove_getBurnAmounts_OfNoSharesReleaseNothing` (z3int) |
| never exceed the core's amounts at the price, in both tokens | open | test/symbolic/libraries/SnapshotLib.symbolic.t.sol:223 `prove_getBurnAmounts_NeverExceedTheCoresAmounts` (z3int) |
