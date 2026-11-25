# SwapStateLib.getStepFees: the core's share of a step's fee, rounded up, bounds what the pool credits it

Code: `src/vaults/types/SwapState.sol:153-166` `getStepFees` and `:175-186` `accrueFees`, `src/vaults/types/Snapshot.sol:75-83` `getFeeShare`. Callers: `DepositOptimizationMath.computeSwap` (`DepositOptimizationMath.sol:88`, :116), `DepositOptimizationMath.maxDeposit` (:220), `MintOptimizationMath.computeSwap` (`MintOptimizationMath.sol:42`). Pool behaviour: [PoolAxioms.md](../PoolAxioms.md).

Notation, per swap step:

- `F = step.feeAmount`, the step's fee in tokenIn, as the pool computes it for the same step (the equality of the model's step with the pool's is [computeSwapStep](computeSwapStep.md)'s claim).
- `L = state.liquidity` the pool's active liquidity, `S` the pool's `stakedLiquidity`, `Lu = state.position.unstakedLiquidity` the core's unstaked liquidity in range. The core's unstaked NFTs are in `L` and not in `S`, so `Lu <= L − S`.
- `u = pool.unstakedFee()` in pips, `u' = u / 1e6`, `b = protocolSwapFeeBps`, `b' = b / 1e4`.
- `phi = feeShare = (1e6 − u)(1e4 − b)` (`Snapshot.sol:80-81`).
- `Phi = F phi Lu / (1e10 L)`, the real share, and `Psi = F (1 − u') Lu / L = Phi / (1 − b')`, the share before the protocol's cut.
- `y` the growth the core's unstaked liquidity earns from the step before any position floor, `d = Psi − y`.
- `n_u` the number of the core's ranges with unstaked liquidity in range during the swap.
- `earned` the step's (or swap's) increase in the core's net fees as `RangesLib.getUnstakedPositions` (`RangesLib.sol:502-528`) reports them.
- Fresh state: no fee growth inside a core range since its NFT's last update and no prior gross fees.

## 1. Statement

1. `getStepFees(true) = ceil(Phi)` and `getStepFees(false) = floor(Phi)`. They differ by at most 1, are at most `F` while `Lu <= L` and `phi <= 1e10`, are 0 when `Lu = 0`, and are monotone in `F`.
2. Upper bound against the pool, one step. From the fresh state, `earned <= ceil(Phi)` for any `n_u`, `S`, `u`, `b`. In general `earned <= ceil(Phi) + n_u`, `earned <= ceil(Phi) + n_u − 1` with `b = 0`, and with `n_u = 1`: `earned <= ceil(Phi) + [b > 0]`.
3. Lower bound against the pool, one step. In general `earned >= floor(Phi) − n_u − c`, `c = 3` with a staked leg in range and `u > 0`, `c = 2` with one of them, `c = 1` with neither. From the fresh state with `n_u = 1`, the table of section 3.5.
4. Over a swap of `k` steps, from the fresh state, the sum of `getStepFees(true)` over the steps is at least `earned`, and the sum of `getStepFees(false)` exceeds `earned` by less than `Σ d_k + 1`, with `d_k < Lu / 2^128`, `< 2` or `< 3` per step as in section 3.2.
5. Every caller's rounding direction is safe for the core's holders, since the core prices a mint at the pool's actual fees (section 3.7).

## 2. Axioms and bounds used

- Pool: B2 (exact input fee `ceil(input fee / (1e6 − fee))`), B5 (exact output, the same fee), F1 (the staked share, the levy and the growth each round against the unstaked side), F2 (one floor per position update), C6 (a step's fee is below `2^189`), G1, G2 (`u <= 1e6`).
- Pool, not in PoolAxioms.md, checked against the files under `node_modules/metadex-slipstream/contracts/`:
  - `core/CLPool.sol:597-603`: each step's growth is added to the global growth with no further rounding, and only while `liquidity > 0`.
  - `core/CLPool.sol:846-867`: `calculateFees` gives the whole fee to the gauge and zero growth when `liquidity == stakedLiquidity`, and with `stakedLiquidity == 0` skips the staked split.
  - `core/CLPool.sol:638-644`: a crossing changes `stakedLiquidity` by `stakedLiquidityNet` with the sign of `liquidityNet`.
  - `core/libraries/Tick.sol:72-107`: the growth inside a range is a difference of growth accumulators, with no rounding.
  - `core/libraries/hook/SwapHookLib.sol:126-168`: `afterSwap` changes `amountCalculated` and `gaugeFees` only, not the fee growth.
  - `periphery/NonfungiblePositionManager.sol:258-267`, `:313-322`, `:366-375`: an NFT's `tokensOwed` rises by one floor of its uncounted growth times its liquidity per update.
- ALM: `MetadexPositionValue.fees` (`MetadexPositionValue.sol:37-44`) is an NFT's `tokensOwed` plus one floor of its uncounted growth times its liquidity. `RangesLib.getUnstakedPositions` sums them over the ranges (`RangesLib.sol:517-519`) and subtracts `floor(gross b')` once on each total (:524-527). `b <= MAX_FEE_BPS = 5000` (`ConfigLib.sol:27`, `ALMAdminExtension.sol:235`).

## 3. Proof

### 3.1 What getStepFees computes

`F phi < 2^189 * 1e10 < 2^223` (C6, `phi <= 1e10`), so the unchecked product (`SwapState.sol:161`, :163) is exact, and `1e10 L < 2^162`. `fullMulDivUp` and `fullMulDiv` are the ceiling and the floor of the 512-bit quotient. So the two results are `ceil(Phi)` and `floor(Phi)`. The other properties of statement 1 follow: `ceil − floor <= 1`, `Phi <= F` when `phi Lu <= 1e10 L`, `Phi = 0` when `Lu = 0`, and `Phi` rises with `F`. Symbolic on `F < 2^64`, `L != 0`, `phi <= 1e10`: test/symbolic/libraries/SwapStateLib.symbolic.t.sol:34 `prove_getStepFees_RoundedUpIsTheCeiledShare`, :55 `prove_getStepFees_RoundedDownIsTheFlooredShare`, :76 `prove_getStepFees_RoundedUpExceedsRoundedDownByAtMostOne`, :98 `prove_getStepFees_NeverExceedTheStepsFee` (with `Lu <= L`), :117 `prove_getStepFees_AreNothingWithoutUnstakedLiquidity`, :135 `prove_getStepFees_AreMonotoneInTheFee`.

### 3.2 The pool's growth for one step

By the branch of `calculateFees`:

- `L = S`: zero growth. Then `Lu <= L − S = 0`, `Phi = 0`, exact.
- `S = 0`: `U = F − ceil(F u')`, `g = floor(U 2^128 / L)`. With roundings `e2, e3` in `[0, 1)`: `y = g Lu / 2^128 = Psi − e2 Lu / L − e3 Lu / 2^128`, so `d` is in `[0, Lu / L + Lu / 2^128)`, within `[0, 2)`, and within `[0, Lu / 2^128)` when `u = 0`.
- `0 < S < L`: `s = ceil(F S / L)`, `U1 = F − s`, `U = U1 − ceil(U1 u')`, `g = floor(U 2^128 / (L − S))`. With `e1, e2, e3` in `[0, 1)`: `y = Psi − (e1 (1 − u') + e2) Lu / (L − S) − e3 Lu / 2^128`, so `d` is in `[0, (2 − u') Lu / (L − S) + Lu / 2^128)`, within `[0, 3)`, and within `[0, 2)` when `u = 0`.

`d >= 0` always (F1): `Phi = Psi (1 − b') >= y (1 − b')`.

### 3.3 The position floor

The growth accumulates without rounding (CLPool.sol:597-603, Tick.sol:72-107), and each NFT floors its uncounted growth once when read (`MetadexPositionValue.fees`) or updated (the position manager). With `f_i` in `[0, 1)` the fractional part of range `i`'s uncounted fees before the swap and `y_i` its share of the swap's growth, the increment the core reads is `counted_i = floor(f_i + y_i)`: `counted_i > y_i − 1` and `counted_i <= ceil(y_i)`, and `counted_i = floor(y_i)` from the fresh state. Summed, `Δ = Σ counted_i` with `y − n_u < Δ <= Σ ceil(y_i) < y + n_u`.

### 3.4 The protocol floor

With prior gross `P`, `earned = Δ − D`, `D = floor((P + Δ) b') − floor(P b')`, which is `floor(Δ b')` or `floor(Δ b') + 1`. So `Δ (1 − b') − 1 <= earned <= Δ − floor(Δ b') < Δ (1 − b') + 1`, and from the fresh state `D = floor(Δ b')`, `earned >= Δ (1 − b')`.

### 3.5 One step

Upper, general: `earned < Δ (1 − b') + 1 < (y + n_u)(1 − b') + 1 <= Phi + n_u + 1`, so `earned <= ceil(Phi) + n_u`. With `b = 0`, `earned = Δ <= Σ ceil(Psi_i) <= ceil(Phi) + n_u − 1`. With `n_u = 1`, `earned <= Δ − floor(Δ b') = ceil(Δ (1 − b'))` and `Δ <= ceil(Psi)`, so `earned <= ceil(ceil(Psi)(1 − b')) <= ceil(Phi) + [b > 0]`. The `+ 1` with `b > 0` is reached: `Psi = 2.1`, `b' = 0.3`, a carry giving `Δ = 3`, prior gross `P = 10`: `D = floor(3.9) − 3 = 0`, `earned = 3 > ceil(1.47) = 2`.

Upper, fresh: `Δ <= y`, so `earned < y (1 − b') + 1 <= Phi + 1`, and `earned <= ceil(Phi)`.

Lower, general: `earned >= Δ (1 − b') − 1 > (y − n_u)(1 − b') − 1 >= Phi − d − n_u − 1`, with `d` as in 3.2: statement 3.

Lower, fresh, `n_u = 1`: `Δ = floor(y)`, `earned >= Δ (1 − b') > Phi − (d + 1)(1 − b')`.

| Regime | `earned >=` | Sharper, under |
|---|---|---|
| `S = 0`, `u = 0` | `floor(Phi) − 1` | `floor(Phi)` when `frac(Psi) >= d`, in particular when `frac(Psi) >= Lu / 2^128` |
| `S = 0`, `u > 0` | `floor(Phi) − 2` | `floor(Phi) − 1` when `Lu (L + 2^128) <= L 2^128` |
| `0 < S < L`, `u = 0` | `floor(Phi) − 2` | `floor(Phi) − 1` when `Lu / (L − S) + Lu / 2^128 <= 1` |
| `0 < S < L`, `u > 0` | `floor(Phi) − 3` | `floor(Phi) − 2` when `(2 P + u' Lu) 2^128 >= Lu (L − S)`, `P = L − S − Lu` the other unstaked liquidity in range |

Each sharper row is `d <= 1` (or `d <= 2`) under its condition, from the bounds on `d` in 3.2. The first: with `d <= frac(Psi)`, `Δ = floor(Psi)` and `ceil(floor(Psi)(1 − b')) > Phi − 1`.

After a prior uncounted step (`n_u = 1`), the general bounds apply: `earned <= ceil(Phi) + [b > 0]` and `earned > Phi − (d + 1)(1 − b') − 1`, so `earned >= floor(Phi) − 3` under the condition of the last row.

### 3.6 Over a swap

The growth of the `k` steps adds up without rounding, and the position and protocol floors apply once. From the fresh state `earned <= ceil(Phi_total) <= Σ ceil(Phi_k)`, and `earned > Phi_total − Σ d_k − 1 >= Σ floor(Phi_k) − Σ d_k − 1`: the floor model exceeds `earned` by less than `Σ d_k + 1`. Statement 4.

### 3.7 The callers

`accrueFees` adds the share to `snapshot.fees` on the tokenIn side and subtracts it from the position's tokenIn constant (`SwapState.sol:179-185`), so it moves the position's tokenIn at later prices and every later `idle()`.

`ALMCore.mint` prices the idle part at the pool's actual net fees, `ceil((buffer + fees) shares / supply)` (`ALMCore.sol:157-160`), and pulls that from the vault. So the model never sets what holders receive, and a model error `e = earned − accrued` changes only the vault's request:

- `DepositOptimizationMath.computeSwap`, rounded up. The accrued fees enter the step test and, through `snapshot.fees`, `getMintShares` at the end. With `e <= 0` (the fresh state, statement 2 and 4) the deposit asks for at most the shares its balances buy, and the unused tokenOut stays in the vault. With `e > 0` (carries, up to `n_u` per swap) the core's pull can exceed the asked amount and `ALMVaultSync._swapAndMint` reverts `ExcessiveInput` (`ALMVaultSync.sol:242`), or the transfer does. No holder loses either way.
- `DepositOptimizationMath.maxDeposit`, rounded up on every step except the one ending at the limit, rounded down there. The solve of `computeSwap` prices the in-step fee with its real fee term, and the floor is at most it, so the cap's position at the limit holds at most what the solve's does: the cap is at most the solve's threshold.
- `MintOptimizationMath.computeSwap`, rounded up, the last step's fee from `MetadexSwapMath.computeSwapStep` (`MetadexSwapMath.sol:35-95`) with an exact output (B5). With `e <= 0` the vault pulls up to `|e| shares / supply` more than the core takes and refunds it. With `e > 0` the pull is short and the mint reverts.
- `WithdrawOptimizationMath` and `RedeemOptimizationMath` accrue no step fees. The fees the pool pays the core on the sale stay with the remaining holders.

## 4. Constants

| Constant | Where | Sufficiency | Witness |
|---|---|---|---|
| `1e10` | `SwapState.sol:162`, :164 | The scale of `feeShare`, `1e6` for the unstaked fee times `1e4` for the protocol's bps: `Phi` is exact with it. A scale, not a margin. | no witness |

The tolerances of the fuzz tests are consequences of statements 2 and 3:

- test/fuzz/libraries/SwapStateLib/GetStepFees.fuzz.t.sol:98 `testFuzz_Success_getStepFees_BoundsTheCoresNetFees` (fresh, no staked leg): `earned <= getStepFees(true) + [b > 0]` (:167) holds with one wei of slack when `b > 0`. `getStepFees(false) <= earned + [u > 0]` (:166) holds under the first two sharper rows of 3.5.
- :170 `testFuzz_Success_getStepFees_BoundsTheCoresNetFeesWithAStakedLeg` (fresh, staked leg, `u > 0`): `earned <= getStepFees(true)` (:237) holds. `getStepFees(false) <= earned + 2` (:234) holds under the last row's condition.
- :240 `testFuzz_Success_getStepFees_BoundsTheCoresNetFeesAfterAPriorStep` (one prior uncounted step, staked leg, `u > 0`): `earned <= getStepFees(true) + [b > 0]` (:325) holds. `getStepFees(false) <= earned + 3` (:322) holds under the last row's condition.

## 5. Open

The lower tolerances of the three tests hold under the conditions of the sharper rows of section 3.5 (`frac(Psi) >= d`, `Lu (L + 2^128) <= L 2^128`, `(2 P + u' Lu) 2^128 >= Lu (L − S)`). Whether the tests' domains imply them is not derived. Outside them the bounds of the left column apply, one wei lower.
