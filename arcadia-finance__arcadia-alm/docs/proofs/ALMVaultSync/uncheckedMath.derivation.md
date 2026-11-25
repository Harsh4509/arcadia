# Unchecked arithmetic: the bound of each block

Code: every `unchecked` block of `src/`. Pool behaviour is taken from [PoolAxioms.md](../PoolAxioms.md) (A1 to G5 and C1 to C7 refer to it). Pool paths are relative to `node_modules/metadex-slipstream/contracts/core/`.

Notation: `s` the walk's price, `t` a step's target, `Q = 2^96`, `L` the pool's active liquidity, `n` the range count, `f = fee / 1e6`.

Status: `guard`, a check in the code bounds the operation (cited). `derived`, the bound follows from the cited bounds or section. `open`, no derivation here.

## 1. Bounds of the ALM used below

| # | Bound | Source |
|---|---|---|
| H1 | A core holds at most `MAX_RANGE_CAP = 14` ranges: a range is pushed only while its index is below `rangeCap`, and `rangeCap` has one writer, capped at `MAX_RANGE_CAP`. | `ConfigLib.sol:30`, `RangesLib.sol:62`, `:69-70`, `ALMAdminExtension.sol:65`, `:68` |
| H2 | `protocolSwapFeeBps` and `protocolEmissionFeeBps` are at most `MAX_FEE_BPS = 5000`, `maxShortfallBps` and `maxSwapCostBps` at most `BPS_DENOMINATOR = 10_000`. Each has one writer. | `ConfigLib.sol:24`, `:27`, `ALMAdminExtension.sol:165-166`, `:235` |
| H3 | `maxSwapCostBps` is read as a `uint16`. | `ALMCoreViewLogic.sol:170-171` |
| H4 | A range's stored `stakedLiquidity` is at most the liquidity of its staked position: it rises by what the position manager reports as minted or added and falls by what it removes, and a third party can only add to a position. | `RangesLib.sol:164-166`, `:210-212`, `:262` |
| H5 | A range's unstaked position sits in the pool position of the position manager and its staked position in the pool position of the gauge: staking moves an NFT's liquidity from the first to the second. An NFT's liquidity is at most its pool position's `uint128` liquidity (G3), which counts in `liquidityGross` of its ticks whoever adds to it (G4), so each is below `2^122`. With H4, `unstaked + stakedLiquidity < 2^123`. | `libraries/CLPoolNonSwapPath.sol:197-211`, G3, G4, H4 |
| H6 | A `PricedRange` has `sqrtPriceLowerX96 < sqrtPriceUpperX96`: the pool mints only with `tickLower < tickUpper`, and the tick prices are strictly increasing. | `libraries/CLPoolNonSwapPath.sol:311` |

## 2. Every block

### Core

| Block | Operation | Bound | Status |
|---|---|---|---|
| `ALMAdminExtension.sol:337-340` | `rewardOwed + fullMulDiv(balance, rewardPerShare − paid, 1e18)` | The difference is of the `uint128` values `rewardPerShare` and `rewardPerSharePaid` (State.sol:65, :81, read as at RewardsLib.sol:223) and wraps as at `RewardsLib.sol:231-233`, correct while below `2^128` ([RewardsLib/chainStatus.derivation.md](../RewardsLib/chainStatus.derivation.md) section 4). The balance is at most the supply, which `checkTotalCap` keeps at most the `uint128` `totalCap` (State.sol:39, ShareLib.sol:38), so the quotient is below `2^256 / 1e18`. `rewardOwed` is a `uint128` (State.sol:82), so the sum fits. | derived |
| `ALMAdminExtension.sol:394-396`, `:419-421` | `shares − DEAD_SHARES` | `shares <= DEAD_SHARES` reverts (`:391`). | guard |
| `ALMCore.sol:146-148` | `balanceOf(receiver) + shares` | `checkTotalCap(supplyBefore + shares)` passes in checked arithmetic (`:144`), and a balance is at most the supply. | derived |
| `ALMCore.sol:181-185` | `amount0Desired − used0`, `amount0 += used0`, `amount1 += used1` | The refund is guarded in its statement (`:182`). The idle amounts went through `TokenDeltaLib.fromAmounts` and the used amounts come out of a `TokenDelta`: each is at most `2^127`. | derived |
| `ALMCore.sol:314-316` | `fees − floor(fees bps / 10_000)` | H2: `bps <= 5000`, so the floored part is at most `fees`. | derived |
| `ALMCore.sol:325-330` | `buffer + netFees`, `amount += fromBuffer` | The buffer is a `uint128`, the net fees are at most the collected fees, an `int128` magnitude, and the principal is one too. `fromBuffer <= buffer + netFees` as `shares <= supplyBefore`. Every sum is below `2^130`. | derived |
| `ALMCore.sol:524-526` | `balanceOf(receiver) + shares` | Both are parts of the supply, which `checkTotalCap` keeps within a `uint128` (`ShareLib.sol:38`): below `2^129`. | derived |
| `ALMKeeperExtension.sol:83-87` | `lastPlanAt + minPlanInterval` | Two `uint32` widened to `uint256`. | derived |
| `ALMKeeperExtension.sol:247-249` | `ranges.length − 1` | `_rangeAt` reverts unless `index < ranges.length` (`:933`, `:937`). | guard |
| `ALMKeeperExtension.sol:259-261`, `:376-378` | `−int256(uint256(liquidity))` | The liquidity is a `uint128`. | derived |
| `ALMKeeperExtension.sol:410-412` | `ranges.length − 1` | `openRange` pushed a range (`RangesLib.sol:69-70`). | guard |
| `ALMKeeperExtension.sol:524-527` | `−amount0`, `−amount1` | C7: a swap's output is below `2^213`, so the pool's signed amount is above `type(int256).min`. | derived |
| `ALMKeeperExtension.sol:592-600` | `BPS_DENOMINATOR − maxSwapCostBps` | H2 | derived |
| `ALMKeeperExtension.sol:605-607` | `toInt128(balanceIn) − toInt128(amountIn)` | `toInt128` returns values in `[0, 2^127 − 1]`, so the difference is in `(−2^127, 2^127)`. | derived |
| `ALMKeeperExtension.sol:658-660` | `cleared += amountIn` | Section 3.6. | derived |
| `ALMKeeperExtension.sol:852-854` | `open * bps` | `bps <= 10_000` (`:847`), and `open` is a `uint128` buffer amount less a payout (`:850`). | guard |
| `ALMKeeperExtension.sol:903-905` | `open − target0` | `target0 = floor(open * targetRatio / 10_000)` (`:900`) with `targetRatio <= 10_000` (`:890`). | guard |
| `ALMCoreViewLogic.sol:352-354` | `2 * count` | `count` is the core's range count, at most 14 (H1). | derived |
| `ALMCoreViewLogic.sol:401-403` | `2 * index` | Its caller loops `index < words.length / 2` (`Snapshot.sol:128-131`). | guard |
| `ALMCoreViewLogic.sol:774-776` | `STATE_SLOT + offset` | `STATE_SLOT` ends in a zero byte (`Storage.sol:11`) and every member offset is below 256 (`ALMCoreViewLogic.sol:34-80`), so the sum does not carry past the last byte. | derived |
| `CalldataLogic.sol:274-279` | `payload.length − QUEUE_LENGTH` | Guarded in its statement by `payload.length < QUEUE_LENGTH ||` (`:275`). | guard |
| `CalldataLogic.sol:330-336` | `QUEUE_LENGTH + index * CONTROLLER_LENGTH` | Both callers loop `index < count` (`ALMKeeperExtension.sol:642`, `:799`) with `count = (payload.length − QUEUE_LENGTH) / CONTROLLER_LENGTH` (`CalldataLogic.sol:278`), so the offset is below `payload.length`. | derived |
| `EmissionsLogic.sol:123-125` | `rewardGrowthGlobalX128 += (projected − last).fullMulDiv(2^128, stakedLiquidity)` | `projected > last` is checked above it and `fullMulDiv` reverts on a quotient past `2^256`. The sum wraps as the pool's own accumulator does: section 5.1. | derived |
| `EmissionsLogic.sol:146-150` | `getRewardGrowthInside(...) − rewardGrowthInside(tokenId)` | A difference of two readings of a wrapping accumulator: section 5.1. | derived |
| `EmissionsLogic.sol:154-157` | `accrued * penaltyRate`, `accrued * share`, the four subtractions, `hidden +=` | Section 5.2, given `accrued < 2^236`. src bounds `accrued` by `2^256` only: [EmissionsLogic/getHiddenEmissions.derivation.md](../EmissionsLogic/getHiddenEmissions.derivation.md). | derived |
| `PoolTokensLib.sol:54-56` | `fees − floor(fees bps / 10_000)` | H2 | derived |
| `PoolTokensLib.sol:133-139` | `buffer + protocolFees + escrowed` | Three `uint128` widened to `uint256`. | derived |
| `QueueLib.sol:131-134`, `:156-158` | `pendingShares −= record's pending shares` | [QueueLib/queueInvariants.derivation.md](../QueueLib/queueInvariants.derivation.md) I1: a controller's `pendingShares` is the sum over its records, and the subtrahend is one term. | derived |
| `QueueLib.sol:190-193`, `:213-216` | pending epoch `amountIn −= record`, cleared epoch `amountIn += record` | [QueueLib/queueInvariants.derivation.md](../QueueLib/queueInvariants.derivation.md) I2 for the subtraction: an epoch's `amountIn` is the sum of its records' amounts. Its section 3.4 for the sum. | derived |
| `QueueLib.sol:307-310` | `pendingShares −= pendingShares`, `claimableShares += shares` | [QueueLib/queueInvariants.derivation.md](../QueueLib/queueInvariants.derivation.md) I1 for the subtraction. I3 and I4 for the sum: the claimable shares are part of the core's balance, below `2^128`. | derived |
| `QueueLib.sol:327-329` | `pendingShares −= record.amountIn` | [QueueLib/queueInvariants.derivation.md](../QueueLib/queueInvariants.derivation.md) I1. | derived |
| `QueueLib.sol:362-364` | `claimableShares −= shares` | [QueueLib/queueInvariants.derivation.md](../QueueLib/queueInvariants.derivation.md) I3: `claimableShares` is the sum of the controller's deposit piles, and `shares` is at most this vault's pile (`:510-512`). | derived |
| `QueueLib.sol:439-441` | pending epoch `amountIn −= record.amountIn` | [QueueLib/queueInvariants.derivation.md](../QueueLib/queueInvariants.derivation.md) I2, the record pending at every caller (`ALMCore.sol:430`, `:457`, `ALMKeeperExtension.sol:806`). | derived |
| `QueueLib.sol:466-469` | epoch `amountIn −= amountIn`, epoch `amountOut −= amountOut` | [QueueLib/queueInvariants.derivation.md](../QueueLib/queueInvariants.derivation.md) I2 for the record's epoch gives `amountIn <= epoch.amountIn`, which bounds the `amountIn` subtraction and gives `floor(amountIn · epoch.amountOut / epoch.amountIn) <= epoch.amountOut` for the `amountOut` one (its consequences table, rows `QueueLib.sol:467` and `:468`). | derived |
| `QueueLib.sol:516-519` | `claimableIn − amountIn`, `claimableOut − amountOut` | `amountIn > claimableIn` reverts (`:507`), and `amountOut` is at most `requestAmountOut(amountIn, claimableIn, claimableOut) <= claimableOut` or `claimableOut` itself (`:510-512`). | guard |
| `RangesLib.sol:164-166`, `:210-212` | `stakedLiquidity += liquidity` | H5. A range without a staked side holds none: `decreaseStakedLiquidity` clears the token id only when the stored liquidity is zero (`:262-268`). | derived |
| `RangesLib.sol:340-342` | `unstakedLiquidity + stakedLiquidity` in `uint128` | H5 | derived |
| `RangesLib.sol:350-353` | sums of the ranges' amounts | H1, C6: at most 14 terms below `2^192`. | derived |
| `RangesLib.sol:433-437`, `:556-560` | `unstakedLiquidity + stakedLiquidity` in `uint256` | Two `uint128` widened first. | derived |
| `RangesLib.sol:452-454` | `fromUnstaked − unstakedLiquidity` | `fromUnstaked > unstakedLiquidity` (`:450`). | guard |
| `RangesLib.sol:524-527` | `fees − floor(fees bps / 10_000)` | H2 | derived |
| `RangesLib.sol:575-578` | sums of the ranges' amounts | H1, C6: at most 14 terms below `2^193`, the two sides rounded apart. | derived |
| `RangesLib.sol:598-600`, `:641-643` | `++count` | `count <= i < length` in the loop (`:592`, `:626`). | guard |
| `RewardsLib.sol:69-71` | `rewardOwed −= amountReward` | `amountReward = min(rewardOwed, lastRewardBalance)` (`:67`). | guard |
| `RewardsLib.sol:109-111` | `protocolFees −= amountReward` | `amountReward = min(protocolFees, lastRewardBalance)` (`:107`). | guard |
| `RewardsLib.sol:164-168` | `lastRewardBalance += received`, `protocolFees += protocolFee`, `claimedCumulative += received − protocolFee` | `received − protocolFee` is non-negative by H2. [RewardsLib/checkpoint.derivation.md](../RewardsLib/checkpoint.derivation.md): `claimedCumulative` stays at most the high water, stored through `toUint128` (`:185`). `lastRewardBalance` is the core's reward token balance less the reserve and `protocolFees` is at most `2 highWater + preCredited`: both fit given a reward token balance below `2^128` and a lifetime credit below `2^126`, which src does not enforce. | derived |
| `RewardsLib.sol:231-233` | `accumulator − rewardPerSharePaid` | The accumulator wraps and only its difference between two interactions of an account is read: correct while that difference is below `2^128` ([RewardsLib/chainStatus.derivation.md](../RewardsLib/chainStatus.derivation.md)). | derived |
| `RewardsLib.sol:283-285`, `:355-358` | `x − floor(x bps / 10_000)` | H2 | derived |
| `RewardsLib.sol:289-292` | `preCredited − hidden`, `hidden − preCredited`, `highWater +=` | Each subtraction is guarded by the comparison in its statement (`:290`). The operands are `uint256` locals (`:270`, `:278`), with `highWater` and `preCredited` read from `uint128` storage (`:273`, State.sol:66, :71), so `highWater +=` stays below `2^129`. | guard |
| `RewardsLib.sol:299-301` | `credit += total − highWater` | `total > highWater` (`:297`). | guard |
| `RewardsLib.sol:309-311` | `rewardPerShare + toUint128(...)` in `uint128` | The accumulator wraps by design, as `:231-233`. | derived |
| `ShareLib.sol:54-58` | `shares + claimableShares + pendingShares` | `shares` is below `2^129` at every caller: a balance, a balance plus shares within the total cap (`ALMCore.sol:146-148`, `:524-526`), or the seed's shares. The stored terms are `uint128`: below `2^131`. | derived |
| `PlanCache.sol:85-88` | `amount += buffer.amount` | The amounts are the sums of `RangesLib.sol:350-353` plus the collected fees, below `2^197`, and the buffer is a `uint128`. | derived |
| `PlanCache.sol:114-120` | `BPS_DENOMINATOR − maxShortfallBps` | H2 | derived |

### Shared

| Block | Operation | Bound | Status |
|---|---|---|---|
| `PoolLogic.sol:58-60` | `MIN_SQRT_PRICE + 1`, `MAX_SQRT_PRICE − 1` | G5: both constants lie strictly inside the `uint160` range. | derived |
| `CLMath.sol:56-66` | `sqrtPriceX96 * sqrtPriceX96` | The branch runs only for `sqrtPriceX96 <= 2^128 − 1` (`:44`), so the square is below `2^256`. | guard |
| `CLMath.sol:84-98` | `sqrtPriceOld − sqrtPriceBound`, `sqrtPriceBound − sqrtPriceOld`, `sqrtPriceOld − move`, `2^192 − sqrtPriceDelta` | [CLMath/getNextSqrtPrice.derivation.md](../CLMath/getNextSqrtPrice.derivation.md): the bound is on the swap's side at the one caller, and `sqrtPriceDelta < 2^192` past the early return. Degenerate: a pool at exactly `MIN_SQRT_RATIO`, zero for one, where the first subtraction wraps. | derived |
| `CLMath.sol:115-117` | `1e18 + deviation` | Every caller passes a `uint64` deviation (`ALMCoreViewLogic.sol:758`, `ConfigLib.sol:60-61`, `:79`, `:83`) or one below `2^62` (`Snapshot.sol:112`, H3). | derived |
| `CLMath.sol:173-175`, `:192-194` | `sqrtPriceBX96 − sqrtPriceAX96` | The only caller, `getAmountsForLiquidityRoundingUp`, passes ordered bounds in each branch (`CLMath.sol:143-150`) given a range's ordered bounds (H6). | derived |
| `MetadexOracle.sol:28-36` | `int56` difference, division, remainder, `int24` decrement | Section 3.5. | derived |
| `MetadexPositionValue.sol:37-44` | growth difference, `tokensOwed +` | Equal in every result to upstream `periphery/libraries/PositionValue.sol:119-125`, which has no overflow checks: the growth difference wraps as section 5.1. | derived |
| `MetadexSwapMath.sol:43-94` | the step's arithmetic | Equal in every result to upstream `libraries/SwapMath.sol:21-85`, which has no overflow checks. The pool's behaviour is B1 to B7. | derived |
| `MetadexTickBitmap.sol:33-60` | the compression, masks and the next tick | Equal in every result to upstream `libraries/TickBitmap.sol:44-72`, which has no overflow checks: `type(uint256).max >> (255 − bitPos) = (1 << bitPos) − 1 + (1 << bitPos)`, and `++compressed` then `compressed` is `compressed + 1`. | derived |

### Vaults

| Block | Operation | Bound | Status |
|---|---|---|---|
| `ALMVaultSync.sol:221-229` | `−toInt256(max(amountSwapOut, 1))` | `toInt256` returns a value in `[0, 2^255 − 1]`. | derived |
| `ALMVaultSync.sol:247-249` | `balanceIn − assets` | `assets > balanceIn` reverts (`:242`). | guard |
| `DepositOptimizationMath.sol:70-72` | `2 n + 4` | H1 | derived |
| `DepositOptimizationMath.sol:83-85` | `getRounding + 3` | `getRounding` is below `2^69` (`Snapshot.sol:219-222` row). | derived |
| `DepositOptimizationMath.sol:285-287` | `1e6 − fee` | G1 | derived |
| `DepositOptimizationMath.sol:301-307` | `sqrtPriceX96 + floor(balanceInLessFee 2^96 / L)` cast to `uint160` | [DepositOptimizationMath/getQuadraticCoefficients.derivation.md](../DepositOptimizationMath/getQuadraticCoefficients.derivation.md) section 3.4: `getSqrtPrice` returned, so the move is at most `2^60` times the price and the sum is below `2^221`. The cast is of the minimum with a `uint160`. | derived |
| `DepositOptimizationMath.sol:381-405` | the coefficients `C`, `κ`, `A`, `B` and the fee term's adjustment, as `int256` | [DepositOptimizationMath/getQuadraticCoefficients.derivation.md](../DepositOptimizationMath/getQuadraticCoefficients.derivation.md) section 3.2: each normalized balance is at most `MAX_NORMALIZED = 2^252` (`:35`, `:486`), each position term at most `2^192`, every sum below `2^254` in size. | derived |
| `DepositOptimizationMath.sol:469-474` | `unstakedLiquidity * feeShare`, `liquidity * 1e10`, `fee << 192`, `1e6 − fee` | H1, G3: the position's liquidities are sums of at most 14 `uint128`, below `2^132`, and `feeShare <= 1e10` (`Snapshot.sol:79-82` row). G1: `fee <= 100_000 < 2^17`, so `fee << 192 < 2^209`. | derived |
| `EquivalentPositionMath.sol:45-48` | `−toInt256(idle)` | `toInt256` returns a value in `[0, 2^255 − 1]`. | derived |
| `EquivalentPositionMath.sol:75-80` | sums of the in-range branch | H1, C6: liquidity sums below `2^132`. The constants start at or below zero and rise by at most 14 terms below `2^192`. | derived |
| `EquivalentPositionMath.sol:85-87` | `floor(L Q / lower) − floor(L Q / upper)` | H6 | derived |
| `EquivalentPositionMath.sol:93-95` | `upper − lower` | H6 | derived |
| `QuadraticMath.sol:39-50` | the interior's products, the `1 − w` subtraction, the ceiling square root | [QuadraticMath/getRoot.derivation.md](../QuadraticMath/getRoot.derivation.md) section 2: `D <= 2^192 − 4` past the guard (`QuadraticMath.sol:36`), each term at most `2^254`. `a >= 0` comes from the callers: the withdraw's `reserveOutNormalized + liquidityNormalized` ([WithdrawOptimizationMath/getQuadraticCoefficients.md](../WithdrawOptimizationMath/getQuadraticCoefficients.md):7, [getNormalizedParameters.derivation.md](../WithdrawOptimizationMath/getNormalizedParameters.derivation.md):87: the normalized reserve term is non-negative for either sign of `r` and `liquidityNormalized` is a `uint256`), and the deposit's quadratic coefficient, at least the position's normalized tokenIn ([DepositOptimizationMath/getQuadraticCoefficients.derivation.md](../DepositOptimizationMath/getQuadraticCoefficients.derivation.md) section 3.3). | derived |
| `WithdrawOptimizationMath.sol:71-73` | `getRounding * 2^96` | Below `2^165`. | derived |
| `WithdrawOptimizationMath.sol:101-112` | `amountOut − state.amountOut + 1` | Section 3.1. | derived |
| `WithdrawOptimizationMath.sol:118-121` | `target ± 1` | Section 3.2. | derived |
| `WithdrawOptimizationMath.sol:222-224` | `(L + n) * 1e6` | G3, H1 | derived |
| `WithdrawOptimizationMath.sol:233-236` | `target − price` moving up, `1e6 − fee` | Section 3.2, which rests on the pool axioms C4 (`slot0.tick` is `T(spot)` or `T(spot) − 1`, [PoolAxioms.md](../PoolAxioms.md):49) and E3 (the next-tick search moving up returns a tick above, PoolAxioms.md:57, `libraries/TickBitmap.sol:59-72`). G1. | derived |
| `WithdrawOptimizationMath.sol:244-247` | `position.liquidity * 1e6` | H1, G3: below `2^152`. | derived |
| `WithdrawOptimizationMath.sol:318-331` | the two moves, `price ± 1` | Section 3.3. | derived |
| `WithdrawOptimizationMath.sol:368-372` | sums of normalized terms | Section 3.4. | derived |
| `WithdrawOptimizationMath.sol:413-416` | `n * position.liquidity` | H1, G3: below `2^136`. | derived |
| `WithdrawOptimizationMath.sol:427-430`, `:435-438`, `:449-452` | `toInt256(a) − toInt256(b)` | Both operands are in `[0, 2^255 − 1]`, so the difference is in `(−2^255, 2^255)`. | derived |
| `WithdrawOptimizationMath.sol:464-470` | the normalized terms, signed | Section 3.4: each is at most `2^192` in size. | derived |
| `Snapshot.sol:79-82` | `1e6 − unstakedFee`, `1e4 − protocolSwapFeeBps`, their product | G2, H2. The product is at most `1e10`. | derived |
| `Snapshot.sol:110-114` | `maxSwapCostBps * 100`, `* 5e11` | H3: at most `65_535 * 100 * 5e11 < 2^62`. | derived |
| `Snapshot.sol:134-136` | `positionLiquidity + stakedLiquidity` in `uint128` | H5 | derived |
| `Snapshot.sol:193-196` | sums of the ranges' amounts | H1, C6: at most 14 terms below `2^192`. | derived |
| `Snapshot.sol:219-222` | `n * (u + 2) + 1` | H1, G5: `u = ceil(Q / p) <= 2^64` or `ceil(p / Q) <= 2^64`, so the result is below `2^69`. | derived |
| `Snapshot.sol:252-265` | sums of the ranges' amounts and active liquidity | H1, C6: at most 14 amounts below `2^193` and 14 `uint128` liquidities. | derived |
| `Snapshot.sol:354-378` | `liquidityDelta −= fromUnstaked`, sums of the released amounts and active liquidity | `fromUnstaked = min(liquidityDelta, unstakedLiquidity)` (`:365`). H1, C6 for the sums. | guard |
| `SwapState.sol:136-140` | `1e6 − fee` | G1 | derived |
| `SwapState.sol:159-165` | `feeAmount * feeShare`, `1e10 * L` | C6: the fee is below `2^189`. `feeShare <= 1e10` (`Snapshot.sol:79-82` row). `L < 2^128`. Product below `2^223`. Used by the deposit and the mint walk only, whose steps are in native units. | derived |
| `SwapState.sol:216-222` | `int256(L) ± liquidityNet` | G3: `|liquidityNet| <= 2^127`, `L < 2^128`, both widened to `int256`. | derived |
| `SwapState.sol:225-227` | `tickNext − 1` | `tickNext >= MIN_TICK` after the clamp (`:112`), so `tickNext − 1 >= −887_273`, inside `int24`. | guard |

## 3. Derivations

### 3.1 The withdraw's amount left

Claim: at `getSqrtPrice`'s call in `WithdrawOptimizationMath.previewWithdraw` (`WithdrawOptimizationMath.sol:101-112`), `amountOut − state.amountOut + 1` neither underflows nor overflows.

`amountOut` is a multiple of `2^96` at most `2^256 − 2^96`: it is scaled by `2^96` (`:74`) and raised by `2^96` per moving step (`:88`), both checked. So the `+ 1` fits once the difference is at most `amountOut`.

`state.amountOut < amountOut` holds at every step. It is `0 < amountOut` at the start. A moving step that does not bind has `amountOutLeft = amountOut ⊖ (state.amountOut + step.amountOut) > 0` (`:252-256`), with `step.amountOut` the value `crossTick` then adds (`SwapState.sol:209`), so `state.amountOut` stays below `amountOut`, which only rises. A step that does not move adds zero (`:83`). A step that binds returns (`:94-125`).

### 3.2 The withdraw's step target against the price

Claim: moving up, `sqrtPriceTarget >= sqrtPrice` at every call of `getSharesForAmounts`. The `± 1` on the root fits `uint160` in both directions.

Moving up, the lookup returns a tick above the walk's tick (E3). At the first step the tick is `T(s)` or `T(s) − 1`, the latter only with `s` exactly the price of `T(s)` (C4), so the next tick's price is at or above `s`. After a crossing the walk's tick is `tickNext` and its price that tick's price (`SwapState.sol:225-227`). The limit `MAX_SQRT_PRICE − 1` is at or above every pool price (G5). So the step's target is at or above `s`, and above it where `getSharesForAmounts` is called, as a step with `t = s` is skipped (`WithdrawOptimizationMath.sol:81-83`).

`getNextSqrtPrice` returns the target or a price in `[s + 1, t]` moving up (`:322-330`). The neighbour is `root − 1 >= s` when the cost binds and `root + 1 <= MAX_SQRT_PRICE` otherwise. Moving down the root is the target, at least `MIN_SQRT_PRICE + 1` and below `MAX_SQRT_PRICE`, or at least `min(t, s − 1) >= MIN_SQRT_PRICE − 1` and at most `s − 1`, so `root + 1 < 2^160` and `root − 1 > 0`.

Moving down, the mirrored claim `t <= s` needs `s > MIN_SQRT_PRICE` (the limit is `MIN_SQRT_PRICE + 1`). The subtractions that rely on it stay checked: section 4.

### 3.3 The withdraw's move within the step

Claim: in `WithdrawOptimizationMath.getNextSqrtPrice` (`WithdrawOptimizationMath.sol:318-331`), past the early return, the two moves and the `± 1` on the price neither underflow nor overflow. The comparison before it is checked (`:311-316`), so `s >= t` moving down and `t >= s` moving up when it is passed.

Moving down, `δ < floor((s − t) 2^192 / s)`, so `s δ / 2^191 < 2 (s − t)`, `x = floor(s δ / 2^191) <= 2 (s − t) − 1` and `(x + 1) >> 1 <= s − t <= s`. The comparison divides by `s`, so `s >= 1` and `s − 1` fits.

Moving up, `δ < floor((t − s) 2^192 / t) <= 2^192`, so `2^192 − δ > 2^192 s / t > 0` and `floor(s 2^193 / (2^192 − δ)) < 2 t < 2^161`. The early return was not taken with `δ >= 0`, so `t > s` and `s + 1 <= t` fits `uint160`.

### 3.4 The withdraw's coefficients

Claim: in `WithdrawOptimizationMath.getQuadraticCoefficients` (`WithdrawOptimizationMath.sol:368-372`), each sum of normalized terms is below `2^194` in size.

`getNormalizedParameters` returns each term as `x.fullMulDiv(2^192, largest)` with `x <= largest` (`:464-470`): `largest` is the maximum over `uint256(reserveOutNormalized)`, the two absolute values, `liquidityNormalized` and 1. Each term is at most `2^192` in size, for either sign of the reserve term.

### 3.5 The oracle's mean tick

Claim: `MetadexOracle.consult` (`MetadexOracle.sol:28-36`) is equal in every result to upstream `OracleLibrary.consult` (`periphery/libraries/OracleLibrary.sol:29-35`), which runs unchecked. It omits upstream's `require(secondsAgo != 0, 'BP')` (`OracleLibrary.sol:20`), so a zero window reverts with a division panic at `MetadexOracle.sol:31` instead. `setDeviation` rejects a zero window (`ALMAdminExtension.sol:211`).

The pool's tick cumulative is an `int56` that sums `tick * seconds`. The difference of two observations at most `2^32 − 1` seconds apart is at most `887_272 * 2^32 < 2^52` in size, so the difference modulo `2^56` is the true one. The divisor is `secondsAgo` as a non-negative `int56`: the signed division cannot overflow, and a zero divisor still reverts. The quotient is a mean of ticks, at least `MIN_TICK`, so the decrement stays above `type(int24).min`.

### 3.6 The keeper's cleared sum

Claim: in `ALMKeeperExtension._clearRequests`, `cleared += amountIn` (`ALMKeeperExtension.sol:658-660`) does not overflow.

Each `amountIn` added is the amount of a record that is pending, which `clearDeposit` or `clearRedeem` then takes out of the pending epoch's `uint128` amount. A controller named twice is pending only once. The pending epoch gains no request during a plan, as the entry points that record one are non-reentrant. So the requests cleared by name over a plan sum to at most `2^128`, and `cleared` starts at what an earlier command of the plan cleared of the same queue (`:639`), at most the epoch's `uint128` amount. The same count bounds the cleared epoch's `amountIn` sum in `QueueLib.clearDeposit` and `clearRedeem` (`QueueLib.sol:190-193`, `:213-216`), with the epoch-sum invariant I2 of [QueueLib/queueInvariants.derivation.md](../QueueLib/queueInvariants.derivation.md).

## 4. What stays checked

| Site | Operation | Why |
|---|---|---|
| `SwapState.sol:208-209` | `state.amountIn +=`, `state.amountOut +=` | The withdraw walk feeds amounts with 96 binary digits, bounded only by `2^256`. |
| `SwapState.sol:180`, `:183`, `Snapshot.sol:149`, `:287`, `EquivalentPositionMath.sol:88`, `:96`, `:109` | sums with the idle tokens, `constant −=` | A position's uncollected fees are a `uint256` with no bound in the code. |
| `WithdrawOptimizationMath.sol:228-230` | moving down: the difference of the two costs, `sqrtPrice − sqrtPriceTarget` | `t <= s` fails for a pool at exactly `MIN_SQRT_PRICE` with liquidity, where the limit `MIN_SQRT_PRICE + 1` is above spot. |
| `ALMVaultSync.sol:126`, `DepositOptimizationMath.sol:147` | `assets − amountSwapIn`, `balanceIn − amountSwapIn` | The walk's cost stays within the balance only while each step's target is on the swap's side of the price, which fails in the same state. |
| `WithdrawOptimizationMath.sol:311-316` | the two differences of the comparison | Moving down, as the row above. They also carry the order that section 3.3 uses. |
| `WithdrawOptimizationMath.sol:228-230`, `:390-472` | `L * price` products, `(...) * 1e6` in `int256` | A `uint128` times a `uint160`, and a reserve term up to `2^256`. |
| `WithdrawOptimizationMath.sol:86`, `:96`, `:128` | `amountIn +=`, `amountOut − state.amountOut > holdingsOut + step.amountOut` | Sums of amounts with 96 binary digits. |
| `RangesLib.sol:262` | `stakedLiquidity − params.liquidity` | The keeper names the liquidity, and the position may hold more than the stored amount (H4), so the position manager's own check does not bound it. |
| `PlanCache.sol:133-134` | `int256 += int128` | Bounded by the number of commands only. |

## 5. The emissions and reward accumulators

### 5.1 The reward growth's wrap

Claim: `accrued` (`EmissionsLogic.sol:146-150`) is the staked side's true emissions since its snapshot, floored, while the true growth inside since the snapshot is below `2^256`.

The pool's `rewardGrowthGlobalX128` is a `uint256` that the pool advances in 0.7.6 arithmetic, which wraps, and its growth inside a range is a difference of such values (`libraries/Tick.sol`, pure subtractions). The gauge's snapshot `rewardGrowthInside(tokenId)` is a reading of the same quantity. A difference of two readings modulo `2^256` is the true growth between them when that growth is below `2^256`. Advancing the global value by the projected emissions before the reading (`EmissionsLogic.sol:123-125`) adds to it modulo `2^256` and keeps that property.

### 5.2 The hidden part

Claim: with `accrued < 2^236` and the rates `penaltyRate`, `share` at most `MAX_PIPS = 1e6`, no operation of `EmissionsLogic.sol:154-157` wraps.

`accrued * rate <= accrued * 1e6 < 2^256`. `floor(accrued rate / 1e6) <= accrued`, so `visible <= accrued` and both inner subtractions are non-negative. `g(x) = x − floor(x share / 1e6)` does not fall in `x`: raising `x` by one raises the floor by at most one as `share <= 1e6`. So `g(accrued) − g(visible) >= 0`, and it is at most `accrued`. `hidden` sums at most 14 such terms (H1): below `2^240`.

The rates' cap is the gauge factory's (`'MR'` and `maxShareCap`), not the ALM's. `accrued < 2^236` is not enforced by any line: it holds for a reward token whose emissions to one gauge total below `2^236` wei, as `accrued` is at most the emissions the staked liquidity earned. The bound src does give and values past it: [EmissionsLogic/getHiddenEmissions.derivation.md](../EmissionsLogic/getHiddenEmissions.derivation.md).
