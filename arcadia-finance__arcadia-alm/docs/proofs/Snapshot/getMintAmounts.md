# SnapshotLib.getMintAmounts

Code: `src/vaults/types/Snapshot.sol` `getMintAmounts` (:239-276), against `getBurnAmounts` (:342-387) and `getRounding` (:213-223). One range, bounds below 2^128 with lower * upper >= 2^96 (below it `getAmount0ForLiquidityRoundingUp` reverts NoLiquidityForToken0 whenever the token0 branch runs, at any shares), supply uint128. Row 2 takes prices of at most one and liquidity below 2^63, row 3 a price above the range and token0 as tokenIn.

| Claim | Status | Evidence |
|---|---|---|
| of no shares take nothing, in both tokens and in liquidity | open | test/symbolic/libraries/SnapshotLib.symbolic.t.sol:115 `prove_getMintAmounts_OfNoSharesTakeNothing` (z3int) |
| are at least the burn amounts of the same shares, in both tokens | open | test/symbolic/libraries/SnapshotLib.symbolic.t.sol:142 `prove_getMintAmounts_AreAtLeastTheBurnAmounts` (z3int) |
| above the range with token0 as tokenIn, exceed the burn's token1 by at most getRounding(token1) | open | test/symbolic/libraries/SnapshotLib.symbolic.t.sol:170 `prove_getMintAmounts_AboveTheRange_ExceedTheBurnAmountsByAtMostTheRounding` (z3int) |
| above the range with token1 as tokenIn, exceed the burn's token1 by at most getRounding(token1) | false (derived) | derivation, last point: the excess reaches `getRounding(token1) + 1`. The bound that holds is `getRounding(token1) + ceil(n s / S)` |
| of one share of the supply, token1 in exceeds the position's token1 by at most three | open | test/symbolic/libraries/SnapshotLib.symbolic.t.sol:363 `prove_getMintAmounts_OfTheSupply_Token1InExceedsThePositionByAtMostThree` (z3int) |

## Derivation

Notation: `S` the supply, `s` the shares, `L` the range's liquidity, `u` its unstaked part, `D = floor(L s / S)`, `C = ceil(L s / S) <= D + 1`, `x` an idle token, `w = (upper - lower) / 2^96`.

- No shares: `C = 0`, so the range adds no amounts and no active liquidity, and `ceil((x + R) * 0 / S) = 0` for each idle token, the tokenIn margin included.
- At least the burn: the burn releases `f(min(D, u)) + f(D - min(D, u))` per token, `f` the pool's rounded down amount (one floor of the exact amount: nested floor division by integers), at most the exact amount of `D`. The mint takes the rounded up amount of `C >= D`: token1 `ceil(C w)`, token0 `ceil(C (b - a) / J)` with `J = floor(a b / 2^96) <= a b / 2^96`, so at least the exact amount. Idle: `ceil(x s / S) >= floor(x s / S)`, and the tokenIn margin only adds.
- Above the range, token0 as tokenIn: token1 has no margin. Range: `ceil(C w) <= ceil(D w) + ceil(w) <= floor(D w) + 1 + ceil(w)`, and the burn's `floor(i w) + floor((D - i) w) >= floor(D w) - 1`, so the range adds at most `ceil(w) + 2`. Idle: `ceil(x s / S) - floor(x s / S) <= 1`. `upper <= P` gives `w < P / 2^96`, so the excess is at most `ceil(P / 2^96) + 3 = getRounding(token1)` at one range.

- Above the range, token1 as tokenIn: the bound `getRounding(token1)` does not hold. The idle part carries the margin wei (`Snapshot.sol:269-270`): `ceil((x + n) s / S) - floor(x s / S) <= 1 + ceil(n s / S)`. The range adds at most `ceil(w) + 2` as above, and `ceil(w) <= ceil(P / 2^96)`. So at one range the excess is at most `ceil(P / 2^96) + 3 + ceil(s / S) = getRounding(token1) + ceil(s / S)` (`Snapshot.sol:220-221`), and that is reached. The step `ceil(w) < ceil(P / 2^96)` fails whenever `w` and `P / 2^96` share a ceiling.

State, one range, `zeroForOne = false`: `lower = 2^93`, `upper = 2^97`, price `P = 2^97` (at the upper bound, so the range holds token1 alone, `CLMath.sol:148-150`), liquidity `L = 4` of which `u = 1` unstaked, idle token1 `x = 1`, supply `S = 3`, shares `s = 2`. `w = 15 / 8`, `P / 2^96 = 2`.

| | Range | Idle | Token1 |
|---|---|---|---|
| mint (`Snapshot.sol:255-272`) | `C = ceil(8 / 3) = 3`, `ceil(3 · 15 / 8) = 6` | `ceil((1 + 1) · 2 / 3) = 2` | 8 |
| burn (`Snapshot.sol:357-383`) | `D = floor(8 / 3) = 2`, `floor(15 / 8) + floor(15 / 8) = 2` | `floor(1 · 2 / 3) = 0` | 2 |

The mint exceeds the burn by 6. `getRounding(P, token1) = 1 · (ceil(2^97 / 2^96) + 2) + 1 = 5`.

The mint's cover by the balances does not use this bound: [getMintShares.md](getMintShares.md) and [ALMVaultSync/deposit.derivation.md](../ALMVaultSync/deposit.derivation.md) section 3.3 count the margin wei in the cost (`Snapshot.sol:295-297`), not in the rounding.
