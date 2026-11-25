# SnapshotLib.getSwapCostLimit

Code: `src/vaults/types/Snapshot.sol` `getSwapCostLimit(uint256, uint256, uint256, bool)` (:104-115). Max swap cost at most 10000 bps (ALMAdminExtension caps it), pool fee below one.

| Claim | Status | Evidence |
|---|---|---|
| zero for one, is at most the price | open | test/symbolic/libraries/SnapshotLib.symbolic.t.sol:68 `prove_getSwapCostLimit_ZeroForOne_IsAtMostThePrice` (z3int) |
| one for zero, is at least the price when the band fits uint160 | open | test/symbolic/libraries/SnapshotLib.symbolic.t.sol:83 `prove_getSwapCostLimit_OneForZero_IsAtLeastThePriceWhenTheBandFitsUint160` (z3int). The uint160 cast truncates when sqrtPrice (1e18 + deviation) / 1e18 exceeds 2^160 - 1, i.e. sqrt prices above about 2^160 / 1.5 (ticks above about 879000) with the maximal cost, not reachable from a pool below that tick |
| without a cost above the fee it is the price, in both directions | open | test/symbolic/libraries/SnapshotLib.symbolic.t.sol:99 `prove_getSwapCostLimit_WithoutACostAboveTheFeeIsThePrice` (z3int) |

## Derivation

The code takes `deviation = max(maxSwapCostBps * 100 - fee, 0) * 5e11` and `getBand(P, deviation)`: `lower = ceil(P 1e18 / (1e18 + deviation))`, `upper = floor(P (1e18 + deviation) / 1e18)`, each cast to uint160. The symbolic rows take `maxSwapCostBps < 10_000`. The math below covers every uint16 `maxSwapCostBps`, so `ALMAdminExtension.setPlanLimits`' cap of `10_000` is inside it (`deviation <= 65535 * 100 * 5e11 < 2^62`, `1e18 + deviation` does not overflow).

- Zero for one: `1e18 + deviation >= 1e18`, so `P 1e18 / (1e18 + deviation) <= P`, and `P` is an integer, so `lower <= P`. `lower <= P < 2^160` makes the cast exact.
- One for zero: `upper >= floor(P 1e18 / 1e18) = P`, and the cast is exact when `upper <= 2^160 - 1`. At `maxSwapCostBps = 10_000` and `fee = 0`, `deviation = 5e17` and that needs `P <= (2^160 - 1) / 1.5`.
- Without a cost above the fee (`maxSwapCostBps * 100 <= fee`): `deviation = 0`, so `lower = ceil(P) = P` and `upper = P`.
