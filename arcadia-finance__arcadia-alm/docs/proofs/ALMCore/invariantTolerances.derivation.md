# Invariant tolerances: value per share on mint and burn, credited rewards

Test-side derivation. Code: `test/invariant/handlers/ALMCoreHandler.sol:933` `_countPerShareFall`, :940 `_valueAndSupply`,
:986 `creditedAndAccrued`, `test/invariant/handlers/BaseHandler.sol:60` `_holdings`, and
`test/invariant/ALMCore.invariant.t.sol:883` `invariant_stayersValuePerShareNeverFallsOnMintOrWithdraw`,
:923 `invariant_creditedRewardsCoverTheHighWaterLessLossesAndRounding`.

## 1. Value per share on a core mint or burn

Notation: `P` the pool's sqrt price, `p = P^2 / 2^192` the token1 value of one token0, `c = convert(P, true, 1)`,
`R` the number of ranges, `S` the supply before, `S'` after, `I0, I1` the idle tokens (buffer plus net fees). Every
`convert` here takes `roundUp = false`.

Measured value. `_valueAndSupply` (`ALMCoreHandler.sol:940-948`) calls `_holdings`, which starts from the idle tokens
(`BaseHandler.sol:65`) and adds, per range, `LiquidityAmounts.getAmountsForLiquidity(P, ., ., L_r)` (`BaseHandler.sol:67-69`),
then values token0 with `CLMath.convert(P, true, ., false)` (`ALMCoreHandler.sol:946`):

- `getAmount0ForLiquidity` is `mulDiv(L << 96, b - a, b) / a`. Nested floor division by integers is one floor, so
  the range's token0 is `floor(L_r k0_r)` with `k0_r` the exact amount per unit of liquidity. `getAmount1ForLiquidity`
  is one `mulDiv`, `floor(L_r k1_r)`.
- For `P <= 2^128`, `convert(P, true, x, false) = floor(x p)`: below 2^128 one `fullMulDiv(x, P^2, 2^192)`
  ([convert.md](../CLMath/convert.md), `src/shared/libraries/math/CLMath.sol:56-66`), at `P = 2^128` the two-step branch is exact (`floor(P^2 / 2^64) = 2^192`). So
  `c = floor(p) > p - 1`.

Let `U` be the exact value `sum_r L_r (k1_r + p k0_r) + I1 + p I0`. Each range loses less than one unit of each token,
the conversion less than one unit of token1:

```
U - R (1 + p) - 1 < V <= U.                                                   (1)
```

Holdings after the action. Mint (`ALMCore.mint`, `src/core/ALMCore.sol:136`): every range gains liquidity `L' >= ceil(L_r s / S)`
([getMintAmounts.md](../CLMath/getMintAmounts.md), row 1), the buffer gains `ceil(I_i s / S)` of each token (`ALMCore.sol:159-160`), the uncollected fees do not
move (the position manager folds them into `tokensOwed` on the increase, by the same floor). Burn: every range loses
`floor(L_r s / S)` (`src/core/libraries/state/RangesLib.sol:433-437`). The burn collects every unstaked side's fees and books their protocol share floored on the
collected sum, and `floor(x) + floor(y) <= floor(x + y)` keeps the net idle `I_i^c` after the collect at or above
`I_i`. The burner gets `floor(I_i^c s / S)`, so the idle left is at least `I_i^c S' / S >= I_i S' / S`. Either way
every component scales by at least `S' / S` at the unmoved price:

```
U' >= U S' / S.                                                               (2)
```

The check is `floor((V' + t) S / S') >= V` (`ALMCoreHandler.sol:937`). With (1) after the action and (2):

```
(V' + t) S / S' > (U' - R (1 + p) - 1 + t) S / S' >= U + (t - R (1 + p) - 1) S / S'.
```

So `t >= R (1 + p) + 1` gives `(V' + t) S / S' > U >= V`, and `V` is an integer, so the floor holds too. `1 + p < 2 + c`:

```
t = R (2 + c) + 1.
```

The handler uses this `t` (`ALMCoreHandler.sol:936`). `PoolHandler` keeps `P <= 2^128`.

## 2. Credited rewards against the high water

`creditedAndAccrued` (`ALMCoreHandler.sol:986-997`) returns `credited = protocolFees + claimedCumulative - lastRewardBalance + sum_h rewardOwed(h)`,
which is the reward paid out plus the reward credited to holders and the protocol, and
`accrued = sum_h floor(b_h (rps - paid_h) / 1e18)` over the actors, the steward, `address(1)` and the core.

High water plus pre-credit (`RewardsLib.getRewardPerShare`, `src/core/libraries/state/RewardsLib.sol:283-311`). A rise of the hidden emissions credits `hidden - pre` and
sets `pre = hidden`. A drop moves `pre - hidden` into the high water with no credit (:290-291). A lifetime reward above the high
water credits the excess and raises the high water to it (:300). So every checkpoint raises `highWater + preCredited` by
exactly its credit `C`, a drop included: it moves `pre − hidden` from the pre-credit to the high water and the
checkpoint's credit is still the rise of the sum. So the credits sum to `highWater + preCredited`, and this
inequality needs no `losses` term: the sum of `ALMCore.invariant.t.sol:925-926` only loosens it. What a drop lowers
is the lifetime reward against the high water, the subject of section 3. The `losses` sum also adds one unit per
`claimEmissions` and per `setProtocolFees` call (`handler.ghostClaims()`, `ALMCoreHandler.sol:369`, :687): section 3
derives what that term must equal.

Rounding per checkpoint with credit `C` at supply `S_k`: `rps += floor(C 1e18 / S_k)` (`RewardsLib.sol:310`), so the supply as a whole earns
`S_k floor(C 1e18 / S_k) / 1e18 > C - S_k / 1e18`. `S_k` is the supply after the previous action, at most
`ghostMaxSupply`, so the loss is below `floor(ghostMaxSupply / 1e18) + 1`.

Rounding per accrual (`accrueBalanceReward`, `RewardsLib.sol:232`): one floor, below 1, for each account whose balance moves or that claims.
One core call accrues at most the actors and the core: a plan's redeem cancels move escrow to at most every actor,
a repeated controller accrues again at an unchanged accumulator and loses nothing, every other call moves one or two
accounts. So below `actors + 1` per call.

At evaluation, `accrued` floors once per holder: below `actors + 3`.

Every checkpoint is one counted call: each call checkpoints once (a plan resets its flag once), and every handler that
makes a core call counts it in `ghostCheckpoints`, including `DonorHandler.donateShares`, whose transfer to the core
checkpoints and accrues the donor and the core. The integer bound, as the invariant sums it (`ALMCore.invariant.t.sol:927-931`):

```
rounding = checkpoints (ghostMaxSupply / 1e18 + actors + 2) + actors + 3.
```

Assumption: the accumulator never wraps past 2^128. `getRewardPerShare` adds modulo 2^128 and reverts a
single step of 2^128 or more (`RewardsLib.sol:310`), while `creditedAndAccrued` subtracts the paid checkpoint from the accumulator in checked
uint256, so after a wrap it reverts.

## 3. The unit term of `losses`: one per drop of the pre-credit

Code: `test/invariant/ALMCore.invariant.t.sol:968` `invariant_rewardDeficitIsBoundedByForfeitsAndGovernanceMoves`, :923
(section 2), `test/invariant/handlers/ALMCoreHandler.sol:369`, :687 `ghostClaims`,
`src/core/libraries/state/RewardsLib.sol` `getRewardTotals` (:324-360), `getRewardPerShare` (:263-313), `checkpoint` (:145-186).

Notation: `r = protocolEmissionFeeBps / 1e4`, `net(x) = x − floor(x r)`. `cc` the stored `claimedCumulative`. At a
checkpoint `k`: `R` the reward token received since the previous one, `E` what the gauge reports earned, `H` the hidden
emissions before the fee, `hw`, `pc` the stored high water and pre-credit. `total = cc + net(R) + net(E)` (:343, :352-359)
and `pc = net(H)` (:284, :293). `D = max(hw − total, 0)`, the deficit the invariant of :968 bounds.

Two facts on `net`: it does not fall in `x`, and `net(x) + net(y) − 1 <= net(x + y) <= net(x) + net(y)`
(`floor(x r) + floor(y r) <= floor((x + y) r) <= floor(x r) + floor(y r) + 1`).

### 3.1 Statement

Over one checkpoint, from the state `(E0, H0, hw0)` the previous one left to `(R, E1, H1)`:

1. Without a drop of the pre-credit (`net(H1) >= pc0`): `D1 <= D0 + net(g)`, `g = max(E0 − R − E1, 0)` the visible
   emissions lost.
2. With a drop (`net(H1) < pc0`, `RewardsLib.sol:290`): `D1 <= D0 + net(f) + 1`,
   `f = max(E0 + H0 − R − E1 − H1, 0)` the emissions lost, visible and hidden.
3. The `+ 1` is reached with nothing lost.

So `highWater − total <= Σ net(lost) + F`, `F` the number of checkpoints at which the pre-credit drops. The unit term
of `losses` must be at least `F` in the invariant of :968. In the invariant of :923 it must be at least 0 (section 2).

`ghostClaims` counts the successful `claimEmissions` and `setProtocolFees` calls. That is not `F`: a claim skips the
sides inside their window (`RangesLib.sol:634-637`) and leaves the pre-credit, and a drop happens at the first
checkpoint after a window closes or a staked side is unstaked, in whichever call makes it. `ghostClaims >= F` is not
derived, and fails for a run with a drop and no claim.

### 3.2 Proof

After a checkpoint the received reward is folded into `cc` at its own floor (`RewardsLib.sol:165-167`), so `total0 = cc0 + net(E0)`,
and the next one has `total1 = cc0 + net(R) + net(E1)`.

1. No drop: the high water becomes `max(hw0, total1)` (:297-303). `hw0 − total1 = (hw0 − total0) + net(E0) − net(R) − net(E1)`,
   and `E0 <= R + E1 + g` gives `net(E0) <= net(R) + net(E1) + net(g)`.
2. Drop: the high water becomes `max(hw0 + net(H0) − net(H1), total1)` (:290, :297-303). So
   `D1 <= D0 + net(E0) + net(H0) − net(H1) − net(R) − net(E1)`, and
   `net(E0) + net(H0) <= net(E0 + H0) + 1 <= net(R + E1 + H1 + f) + 1 <= net(R) + net(E1) + net(H1) + net(f) + 1`.
3. `bps = 5000`, `E0 = 1`, `H0 = 1`, `hw0 = total0 = cc + 1`, `pc0 = net(1) = 1`. The window closes with no emission
   since: `R = 0`, `E1 = 2`, `H1 = 0` (the hidden wei is earned, `EmissionsLogic.sol:155-156` against
   `Gauge.sol:164`). The high water becomes `cc + 2` and `total1 = cc + net(2) = cc + 1`: `D1 = 1`, `f = 0`.

`r` changes only in `setProtocolFees`, after it claimed every emission and checkpointed at the old fee (`src/core/ALMAdminExtension.sol:247-252`): `E = 0` and `H = 0` there, so the change moves neither `total` nor the pre-credit.

Between the call's checkpoint and the invariant's read, a transfer from the gauge moves `x` from `E` to the unfolded
`R`: `net(x) + net(E − x) >= net(E)`, so `total` does not fall.

### 3.3 The handler's count

A run in which the unit is needed and not counted: a side is staked with a penalty window, one checkpoint leaves
`E0`, `H0` with `frac(E0 r) + frac(H0 r) >= 1`, the chain stops accruing (`GaugeHandler.sol:170`), the window passes,
and a call other than `claimEmissions` and `setProtocolFees` makes the next checkpoint, with no claim before it.
Then `highWater − total = 1` and `losses = 0`. Derived, not run. A run with emissions accruing between the two
checkpoints raises `total` by them and hides the unit.

The forfeiting calls count `net` of the whole hidden emissions (`ALMCoreHandler.sol:302-308`, `KeeperHandler.sol:420-422`), not
`net(f) + 1`: they cover statement 2 when the hidden emissions exceed the part lost by a wei of `net`, and not when
all of it is lost. `GaugeHandler.sol:200` adds the unit itself.
