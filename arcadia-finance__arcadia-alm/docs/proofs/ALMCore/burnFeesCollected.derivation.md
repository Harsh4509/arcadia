# Fee-earning trades in the fuzz tests: both ranges earn a wei

Test-side derivation: the trade size and the range room that make a fuzzed trade earn each range at least one wei of fees.

Tests: test/fuzz/ALMCore/Burn.fuzz.t.sol:1139 `testFuzz_Success_burn_EmitsFeesCollected` and test/fuzz/libraries/RangesLib/GetUnstakedPositions.fuzz.t.sol:66 `testFuzz_Success_getUnstakedPositions_NetOfTheProtocolShare` (fuzzed direction, a positive fee asserted). Helpers: `givenValidRangeState` (test/fuzz/ALMCore/_ALMCore.fuzz.t.sol:361), `givenRangeRoom` (:386), `liquidityCeiling` (:718), `feeEarningTrade` (test/utils/fixtures/metadex/MetadexCLFixture.f.sol:349). Pool: `node_modules/metadex-slipstream/contracts/core/CLPool.sol`, `core/libraries/SwapMath.sol`.

## Notation

- `s` tick spacing, `c = floor(tick / s)` the spot's compressed tick, so `sqrtP(c s) <= spot < sqrtP((c + 1) s)`.
- `L` pool liquidity at spot, `S` its staked part, `L_r` the unstaked liquidity of a range under test, `L_min` the smaller of the two in the two-range test. `L_r <= L - S` (the unstaked position is in `L` and not in `S`).
- `f = pool.fee()` pips, `uf = pool.unstakedFee()` pips, `uf <= 500_000` (`Constants.MAX_UNSTAKED_FEE`).
- Per step `i` of the swap loop: `a_i` consumed input (`amountIn + feeAmount`), `F_i` the fee, `U_i` what reaches fee growth, `g_i` the growth added.

## 1. Fee per wei of input, per step (SwapMath.sol:32-40, :81-83)

Exact input. Reaching the target: `F_i = ceil(in * f / (1e6 - f))`, so `F_i (1e6 - f) >= in f`, i.e. `F_i * 1e6 >= (in + F_i) f = a_i f`. Not reaching it: `in <= floor(rem (1e6 - f) / 1e6)` (`getNextSqrtPriceFromInput` rounds the price so that the delta rounded up stays within the input), `F_i = rem - in >= rem f / 1e6 = a_i f / 1e6`. Either way

```
F_i >= a_i f / 1e6.                                                      (1)
```

## 2. Growth per step (CLPool.sol:597-603, :822-867)

`S = 0`: `U_i = F_i - ceil(F_i uf / 1e6) >= F_i (1e6 - uf) / 1e6 - 1`, `g_i = floor(U_i 2^128 / L)`.

`0 < S < L`: `U_i = (F_i - ceil(F_i S / L)) - ceil(. uf / 1e6) >= F_i (L - S) (1e6 - uf) / (L 1e6) - 2`, `g_i = floor(U_i 2^128 / (L - S))`.

Both cases, with `L - S >= L_r`:

```
g_i >= F_i (1e6 - uf) 2^128 / (L 1e6) - 2 * 2^128 / L_r - 1.                (2)
```

(`S = 0` is the case `L - S = L`, where the bound is slack by one `2^128 / L_r`.)

## 3. What the range needs

The position's fee is `floor(G L_r / 2^128)` with `G = sum g_i` over the steps the price spent inside the range. It is `>= 1` iff `G >= 2^128 / L_r`. Summing (2) over `n` steps and using (1):

```
sum F_i * (1e6 - uf) / 1e6 >= (1 + 2n) L / L_r + n L / 2^128
```

suffices, and `L < 2^128` makes `(1 + 2n) L / L_r + n` enough. With (1), the input consumed inside the range must satisfy

```
A := sum a_i >= ((1 + 2n) L / L_r + n) * 1e12 / (f (1e6 - uf)).            (3)
```

## 4. Steps inside one spacing

`givenRangeRoom` (`_ALMCore.fuzz.t.sol:386-397`) bounds the edge the trade moves towards to `>= (c + 2) s` (oneForZero) or `<= (c - 1) s` (zeroForOne). The price then has the whole spacing `[(c + 1) s, (c + 2) s)` (or `[(c - 1) s, c s)`) inside the range before reaching the edge, on top of the partial tick it starts in. No tick is initialised strictly inside that stretch: the ranges' near edges are at or beyond its end, their far edges are behind spot, and the depth's ticks are at `+-bandTick`. `nextInitializedTickWithinOneWord` therefore stops only at word ends: at most once before `(c + 2) s` (the step from spot ends at a tick `>= (c + 1) s`, the next at a tick `>= (c + 2) s`, mirrored for zeroForOne). So `n <= 2` for the stretch, and later steps only add non-negative `g_i`. (3) with `n = 2`:

```
A >= (5 L / L_r + 2) * 1e12 / (f (1e6 - uf)).                              (4)
```

`feeEarningTrade` floors the trade at `earning = ceil((5 share + 2) 1e12 / (f (1e6 - uf)))` with `share = floor(L / L_r) + 1 >= L / L_r`, so a trade that ends inside the stretch consumes `A = amountIn >= earning` and (4) holds. A trade that leaves the stretch consumed at least the stretch's own input `A_1 >= L * (sqrtP((c + 2) s) - sqrtP((c + 1) s)) / 2^96` (token1, oneForZero) or `L * 2^96 (1 / sqrtP((c - 1) s) - 1 / sqrtP(c s))` (token0, zeroForOne), and (4) needs `A_1 >= earning`.

## 5. `A_1 >= earning` over the fuzz domain

Fixture bounds (`givenValidPoolState`, `liquidityCeiling`, `Constants`), with `m(s) = tickSpacingToMaxLiquidityPerTick(s)` (`2^114.88`, `2^113.88`, `2^112.88`, `2^107.24` at `s = 200, 100, 50, 1`) and `x = sqrtP / 2^96`:

- `s` in `{200, 100, 50, 1}`, `x` in `[5.96e-5, 16777]` (band `type(uint120).max`, `1e3` clear of both ends), so `max(x, 1 / x) <= 2^14.03`.
- Depth: `d = m(s) / 10`, scaled down until its band-wide amounts (at most `d max(x, 1 / x)`) stay under `2^127 / 8`, so `min(m(s) / 10, 2^124 / 2^14.03) <= d <= m(s) / 10`, and the pool's depth is in `[d / 100, d]`.
- Ranges (`Burn.fuzz.t.sol:1157`, :1169, `RangesLib/GetUnstakedPositions.fuzz.t.sol:88`): `L_r` in `[free / 8, free / 4]`, `free = max(F / 2, MIN_FUZZED_LIQUIDITY)` (`liquidityCeiling`, `_ALMCore.fuzz.t.sol:718-727`) with `F` the tick room `m(s) - gross` scaled down until the range-wide amounts (at most `F max(x, 1 / x)`) stay under `2^127`. The first range's gross is at most `m(s) / 8`, so `F >= min(7 m(s) / 8, 2^127 / 2^14.03)`, and every range holds at most `m(s) / 8`.

Worst case for `earning`: `f = 1`, `uf = 500_000`, `L <= m(s) / 10 + 2 m(s) / 8 = 0.35 m(s)`, `L_min >= F / 16`. Worst case for `A_1`: `L >= d / 100` at the smallest `d`, one tick of room (a spacing is `s` ticks, `s >= 1`), `x` at the end of the band that minimises the input token's amount: `A_1 >= L x (1.0001^(1/2) - 1) >= L 2^-28.32` (token1) and `A_1 >= L (1.0001^(1/2) - 1) / x >= L 2^-28.32` (token0).

| `s`  | `L / L_min <=` | `earning <=`      | `A_1 >=`            | margin   |
|------|----------------|-------------------|---------------------|----------|
| 200  | `2^4.5`        | `2^27.8`          | `2^74.9`            | `2^47.1` |
| 100  | `2^3.5`        | `2^26.9`          | `2^74.9`            | `2^48.0` |
| 50   | `2^2.7`        | `2^26.3`          | `2^74.5`            | `2^48.2` |
| 1    | `2^2.7`        | `2^26.3`          | `2^68.9`            | `2^42.6` |

`A_1` is computed for a single tick, so the table also covers the zeroForOne callers that only have `aroundSpot`'s room: there the lower edge is `<= trunc((tick - s) / s) * s <= tick - 1`, a full tick below spot, and the same `n <= 2` argument applies to `[c s - 1 tick, spot]`. For oneForZero the `aroundSpot` room is `sqrtP(trunc((tick + s) / s) s) - spot`, which can be one unit, hence `givenRangeRoom`.

`earning <= 2^27.8 < 2^127 - 1 = MAX_FUZZED_AMOUNT`, so the floor never collapses the trade's domain. `most` (ten spacings) exceeds it by the same table.

## 6. The test-side bounds

| Constant | Where | Sufficiency | Witness |
|---|---|---|---|
| room of two spacing boundaries from spot ahead of the trade | `givenRangeRoom`, `_ALMCore.fuzz.t.sol:394-396` | section 4: the whole spacing ahead lies in the range, `n <= 2` | spot `sqrtP = 2^96 - 1` (tick -1), tick spacing 100, pool fee 1 pip, both ranges `[.., 0)`, trade oneForZero: `givenValidRangeState(.., aroundSpot = true)` alone puts the upper edge at `0`, one sqrtP unit above spot, and the trade leaves both ranges after about 43k wei of input whose fee grows neither range a wei, so `testFuzz_Success_burn_EmitsFeesCollected` fails without the room bound |
| `earning = ceil((5 share + 2) 1e12 / (f (1e6 - uf)))` | `feeEarningTrade`, `MetadexCLFixture.f.sol:375-377` | (4) with `n = 2` and `share >= L / L_r` | the same state: `feeEarningTrade`'s other floor, `share * amount(spot -> tick ± s)`, is a few wei for `s = 1` |

The floor `least = min(max(least, earning), MAX_FUZZED_AMOUNT)` (`MetadexCLFixture.f.sol:377`) only raises a caller's floor to the input that (4) proves necessary under `n <= 2`, by at most `2^27.8` wei. The tests that assert a positive fee call `givenRangeRoom` on each fee-earning range in the fuzzed direction: `Burn.fuzz.t.sol:1155`, :1167, `RangesLib/GetUnstakedPositions.fuzz.t.sol:86`, and `CloseRange.fuzz.t.sol:560` (zeroForOne).
