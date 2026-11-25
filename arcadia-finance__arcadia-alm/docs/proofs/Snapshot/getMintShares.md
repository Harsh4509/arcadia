# SnapshotLib.getMintShares

Code: `src/vaults/types/Snapshot.sol` `getMintShares` (:287-326), against `getMintAmounts` (:239-276). One range, bounds below 2^128, supply uint128, balances below 2^127.

| Claim | Status | Evidence |
|---|---|---|
| above the range with no idle token0 and no token0 balance, the mint of its shares takes no token0 and at most the token1 balance, in both directions | open | test/symbolic/libraries/SnapshotLib.symbolic.t.sol:250 `prove_getMintShares_AboveTheRange_TheMintOfItsSharesIsCoveredByTheBalances` (z3int) |
| below the range with a lower bound of at least 2^48, no idle token1 and no token1 balance, the mint of its shares takes at most the token0 balance and no token1, in both directions | open | test/symbolic/libraries/SnapshotLib.symbolic.t.sol:275 `prove_getMintShares_BelowTheRange_TheMintOfItsSharesIsCoveredByTheBalances` (z3int). Below 2^48 the manager's divisor J is small and the token0 ceiling over J can exceed getRounding(token0): (u - l) / J against ceil(2^96 / s), not covered by the proof |

## Derivation

Notation: `S` the supply, `s` the shares, `L` the range's liquidity, `C = ceil(L s / S) < L s / S + 1`, `x0, x1` the idle tokens, `n0, n1` the balances, `g0, g1` getRounding at one range (`ceil(2^96 / P) + 3`, `ceil(P / 2^96) + 3`), `a = lower`, `b = upper`.

- Above the range. With token0 as tokenIn, `cost0 = x0 + 1 = 1` and `n0 = 0`, so `s = 0` and the mint takes nothing. With token1 as tokenIn, `cost0 = 0` skips the token0 leg, and the mint takes token0 `ceil(0 * s / S) = 0`. Its token1 is `ceil(C w) + ceil((x1 + 1) s / S) < (s / S)(L w + x1 + 1) + w + 2`, `w = (b - a) / 2^96`. `cost1 >= x1 + 1 + L w` and `s cost1 / S <= n1 - g1` give less than `n1 - g1 + w + 2`, and `w < P / 2^96` gives `w + 2 < g1`, so the mint takes less than `n1`.
- Below the range. With token1 as tokenIn, `cost1 = x1 + 1 = 1` and `n1 = 0`, so `s = 0`. With token0 as tokenIn, `cost1 = 0` skips the token1 leg, and the mint takes token1 `ceil(0 * s / S) = 0`. Its token0 is `ceil(C (b - a) / J) + ceil((x0 + 1) s / S) < (s / S) cost0 + (b - a) / J + 2 <= n0 - g0 + (b - a) / J + 2`, `J = floor(a b / 2^96)`, `cost0 >= x0 + 1 + L (b - a) / J`. So the mint takes less than `n0` when `(b - a) / J <= ceil(2^96 / P) + 1`, and `P <= a` makes `(b - a) / J <= 2^96 / a + 1` enough. With `J >= (a b - 2^96 + 1) / 2^96` that is implied by `2^96 - 1 + a - a / 2^96 <= a^2 + a^2 b / 2^96`, which holds when `a^2 >= 2^96` (then `a^2 b / 2^96 >= a`). So `a >= 2^48` suffices.

Both rows need `C` within uint128 (`SafeCastLib.toUint128` in `getMintAmounts`), which the below-the-range proof assumes.
