# Donated liquidity: the unstaked side's liquidity is the position's liquidity

The core stores no liquidity for a range's unstaked side (`Range`, `src/core/types/Range.sol:10-17`). Every site that needs it reads `positions(unstakedTokenId).liquidity` from the position manager, L_pm. Liquidity a third party adds to that NFT is the core's liquidity: priced, minted against, burned and collected like the rest, owned by the holders. The staked side keeps `stakedLiquidity`.

Notation: L_pm the unstaked NFT's liquidity, L_s = `range.stakedLiquidity`, G the pool's fee growth inside the range, T_pm the NFT's `tokensOwed`, S the aLP supply, V the booked value, D a third party's addition.

Position manager: `node_modules/metadex-slipstream/contracts/periphery/NonfungiblePositionManager.sol`, cited as PM.

## 1. Facts about the position manager

- `increaseLiquidity` (PM:223-275) has no authorisation except `msg.sender == gauge` when the gauge owns the NFT (PM:236). The core owns its unstaked NFTs (`PositionManagerLogic.mint` mints to `address(this)`, `PositionManagerLogic.sol:37`), so anyone can add liquidity to them. It pokes `tokensOwed` with the old `position.liquidity` (PM:258-266) before `position.liquidity += liquidity` (PM:271). A poke adds at least one unit of liquidity (`core/libraries/CLPoolNonSwapPath.sol:324` `require(input.amount > 0)`).
- The staked NFT is owned by the gauge while staked (`RangesLib.sol:294-295` `approve` then `gauge.deposit`), so `increaseLiquidity` on it needs `msg.sender == gauge`, and the gauge has no such call. Between `unstake` and `stake` inside one plan the core holds it under `nonReentrant`. So only the unstaked side can be added to.
- `decreaseLiquidity` (PM:282-330), `collect` (PM:334-407) and `burn` (PM:411-416) are `isAuthorizedForToken`: core only. `decreaseLiquidity` needs `params.liquidity > 0` (PM:290) and `<= position.liquidity` (PM:294). `burn` needs `liquidity == 0` and both `tokensOwed == 0` (PM:413).
- `positions(tokenId)` (PM:100-137) reverts on `poolId == 0` (PM:120), a burned or never minted id.
- `tokensOwed` on an NFT with `liquidity == 0` is zero whenever the core reads it: every core decrease is followed by a collect of everything owed (`PositionManagerLogic.decreaseLiquidityAndCollect`, `PositionManagerLogic.sol:103-111`, `collect` :86-96 with `amountMax = type(uint128).max` at :90), and a third party cannot decrease. The only other writer of `tokensOwed` is the poke, which multiplies by the liquidity before the change (PM:258-266, :313-322, :366-375), zero on an empty side. The keeper's `_collect` (`ALMKeeperExtension.sol:340-345`) and the plan's `collectFees` collect everything owed as well.

Invariant of the core: every stored range holds a live unstaked NFT the core owns. `openRange` mints it (`RangesLib.sol:66`) and pushes the range with its id (:69-79). `closeRange` burns it (:124) and pops the range (:127-128). The only other `burn` in `RangesLib` is the staked side's (:267). So `positions(range.unstakedTokenId)` never hits the `poolId == 0` revert. `test/invariant/ALMCore.invariant.t.sol:1188` `invariant_rangeLiquidityMatchesItsPositions` checks the ticks, the staked side and the ownership.

## 2. Sites, and which read each one reuses

Every read of the position manager's liquidity, and every use of the unstaked side's liquidity, in src:

| Site | Code | Read reused |
|---|---|---|
| `Range` (`Range.sol:10-17`) | no unstaked liquidity. Word 1 holds `tickLower`, `tickUpper`, `unstakedTokenId` (at 48), `stakedLiquidity` (at 128), word 2 `stakedTokenId`, `stakedBlock` (at 80): `ALMCoreViewLogic.sol:108-114`. `unsafeAccess` (`RangesLib.sol:655-660`, `shl(1, index)` at :658) | |
| `ALMCoreViewLogic.decodeRanges` (:362), `decodeRange` (:394) | shifts of that layout. `decodeRange` returns `(tickLower, tickUpper, stakedLiquidity)` | |
| `openRange` (`RangesLib.sol:56-82`) | stores no liquidity | |
| `closeRange` (`RangesLib.sol:96-129`) | reads L_pm once (:112), decreases it all when positive (:113-117), else collects (:118-121). Returns L_pm as `liquidity` for the plan cache (`ALMKeeperExtension.sol:250-251`, :259-261) | its own read |
| unstaked increases and decreases | the PM call at the caller, no state update: `addLiquidity` (`RangesLib.sol:376-395`), keeper `_increaseLiquidity` (`ALMKeeperExtension.sol:449`), `removeLiquidity` (`RangesLib.sol:408-478`), keeper `_decreaseLiquidity` (`ALMKeeperExtension.sol:301-302`) | |
| `collectFees` (`RangesLib.sol:326-363`) | L_pm (:336-337), `liquidity = L_pm + L_s` (:340-342), the collect skipped on `L_pm == 0` (:357) | the collect that follows |
| `removeLiquidity` (`RangesLib.sol:408-478`) | pro rata on `L_pm + L_s` (:430-437), `fromUnstaked = min(delta, L_pm)` (:449-455), collect on `L_pm > 0` when the burn removes nothing (:440-447) | the decrease or collect that follows |
| `getUnstakedPositions` (`RangesLib.sol:502-528`) | reads `positions()` per range (:511-512), skips on `L_pm == 0` (:513), growth on L_pm (`MetadexPositionValue.fees`, :517), returns `positionLiquidity` (:514) | one read per range: `MetadexPositionValue.fees` takes the position already read |
| `RangesLib.getMintAmounts` (:541-580) | `positionLiquidity[i] + L_s` (:556-560), the array from `getUnstakedPositions`, which `ALMCore.mint` calls first (`ALMCore.sol:158`, :163-164) | the mint's view read |
| keeper `_decreaseLiquidity` sentinel (`ALMKeeperExtension.sol:283-287`) | `positions(range.unstakedTokenId).liquidity`. `range.unstakedTokenId`, not `params.tokenId`: the payload may carry `Sentinels.OPENED` for a range opened in the plan (`_rangeAt`, :925-938) | the decrease that follows |
| `ALMCoreView.getPosition` (`ALMCoreView.sol:450`) | `positionLiquidity[i]` (:491) from the `getUnstakedPositions` call the function makes before the loop (:475) | the view's own read |
| `Snapshot.getSnapshot` (`Snapshot.sol:56-67`), `decodePricedRanges` (:123-141) | `getUnstakedPositions` returns the array (:58), `decodePricedRanges(words, positionLiquidity)` (:60) sets `unstakedLiquidity = positionLiquidity[i]` and `liquidity = positionLiquidity[i] + stakedLiquidity` (:134-137) | the snapshot's own `getUnstakedPositions` call |
| `EquivalentPositionMath.getPosition` (`EquivalentPositionMath.sol:77`), `SwapStateLib.getStepFees` (`SwapState.sol:159-165`), the deposit's fee term (`DepositOptimizationMath.sol:467-475`), `Snapshot.getBurnAmounts` (`Snapshot.sol:365`) | `PricedRange.unstakedLiquidity`, which holds L_pm | |

The `L_pm + L_s` sums (`Snapshot.sol:135`, `RangesLib.sol:341`, :435, :559) fit a uint128: both NFTs sit at the same ticks, the pool keeps `liquidityGross <= maxLiquidityPerTick <= type(uint128).max` per tick (`core/libraries/Tick.sol:171`), and `liquidityGross` at `tickLower` counts both.

No stored flag marks an empty unstaked side: it would be stored state about the unstaked side, and it would be wrong the moment a third party refills the side.

## 3. Proofs and attack analysis

### (a) Inflation

Facts: `ALMCore.mint` is shares-in with ceilings (`ALMCore.sol:159-160` `fullMulDivUp`), so a core minter is never rounded to zero shares. `seed` mints `DEAD_SHARES = 1e6` to `address(1)` (`ALMAdminExtension.sol:36`, :415), so S >= 1e6 forever (burns cannot reach the dead shares). A sync vault depositor gets, over the two pool tokens, the least `floor((balance - getRounding) x S / cost)` shares, `cost` the whole supply's holdings rounded up plus a wei per range on tokenIn (`Snapshot.getMintShares`, `Snapshot.sol:287`). The core takes `getMintAmounts` of those shares, rounded up, the vault refunds the unused asset, and the bought token the mint leaves stays in the vault (`ALMVaultSync.sol:242-250`). A mint of zero shares reverts (`ALMCore.sol:140`, `ZeroShares`).

A liquidity donation D raises V with S fixed. To make a victim's deposit of value a round to zero shares the attacker needs V / S > a, so V > a S >= a x 1e6. The donation belongs to all holders pro rata, so at least D x 1e6 / S of it is owned by the dead shares and lost to the attacker outright. A deposit rounded down to fewer shares pays only for the shares it gets: the core gains, beyond their value, the mint's rounding up (each range's liquidity and amounts, the idle part, and the tokenIn margin of a wei per range), shared by all holders. The rest of the victim's loss (the unused bought token, the swap fee) does not reach the core. A deposit rounded to zero shares reverts, and the vault's `minShares` path (`ALMVaultSync.sol:99-109`) lets the victim refuse a smaller count. So the attacker gains at most its pro rata of that rounding per deposit and pays at least D x 1e6 / S per donation, permanently. No profitable inflation: the ERC-4626 dead-shares argument, with the donation as the inflation vector.

### (b) Sandwiching an addition

The addition raises V by the principal of D at once (every site reads L_pm, section 2). A minter who mints s shares just before it and burns just after captures s / (S + s) of D, less the mint ceilings and burn floors and the pro-rata PM calls on every range twice. The rest of D goes to the existing holders. Nobody but the donor funds it: every existing holder's claim is their pro rata of V before the addition and of V + D after. A gift to the unstaked NFT is a gift to whoever holds shares at that block. Bound on the capture: below D x s / (S + s) for a front-runner holding s.

No sandwich on the yield: a third-party poke moves `floor(dG x L_pm / 2^128)` into `tokensOwed` and sets the growth checkpoint (PM:258-269). `MetadexPositionValue.fees` on L_pm computes `tokensOwed + floor((G - G_last) x L_pm / 2^128)` (`MetadexPositionValue.sol:37-44`), the same product with the same floor, so the valuation is unchanged by the poke.

### (c) Keeper griefing: liquidity added between the off-chain plan and its execution

No plan check reads a liquidity the addition lowers:

- `_rangeAt` (`ALMKeeperExtension.sol:925-938`) compares indices and token ids only.
- `decreaseLiquidity` with an explicit amount: the PM needs `params.liquidity <= L_pm` (PM:294), and the addition only raises L_pm. With `RANGE_LIQUIDITY` the keeper reads the live L_pm (`ALMKeeperExtension.sol:283-287`) and needs `L_pm > 0` (PM:290).
- `closeRange` reads the live L_pm (`RangesLib.sol:112`). `burn` sees `liquidity == 0` and `tokensOwed == 0` after the full decrease and collect (PM:413).
- `increaseLiquidity`, `openRange`, `stake`: amounts come from the buffer (`_amount`, `ALMKeeperExtension.sol:840`). The PM's liquidity for given amounts does not depend on the position's existing liquidity.
- `collectFees` and `PlanCacheLib.start` (`PlanCache.sol:71-100`): `valueBefore` is the live principal plus the buffer (:85-89). The plan's own deltas are what its steps release or consume (`applyLiquidityDelta`, :144, on the liquidity each step moved, `applyBufferDelta`, :132, on what the buffer received). D is in `valueBefore` and stays in the ranges or moves into the cache through a step, so the shortfall check (`checkShortfall`, :108-121) sees the same value on both sides.
- Swap steps check `minAmountOut` on the swap's own output (`ALMKeeperExtension.sol:588`). `checkSolvency` (`PoolTokensLib.sol:148-155`) compares balances, which the addition does not lower.
- Exact-amount payloads (an increase or open of exact amounts, a decrease of an exact liquidity at or below the plan-time L_pm, a swap of an exact amount) depend on L_pm only through the inequality above.

So no plan check, exact payload, cache check or swap check reverts on an addition. The poke's side effect (fees moved into `tokensOwed`) is collected by the plan's `collectFees`.

Additions inside a plan. Inside `execute` (`nonReentrant`), a `SWAP_VIA_ROUTER` step hands `router` and `data` from the payload to `IRouterTrampoline.execute` (`ALMKeeperExtension.sol:561-562`), and src holds no allowlist of routers. Any counterparty of the route can call `increaseLiquidity` on the core's unstaked NFT (PM:223-236) during the step. Every site of section 2 reads L_pm at the step that uses it, so a later `RANGE_LIQUIDITY` decrease drains the whole side and a later `closeRange` decreases all of it before `burn` (PM:413). A value of L_pm carried from an earlier step would leave the addition in the position and make `burn` revert 'NC'.

### (d) The deposit quadratic

`DepositOptimizationMath.getQuadraticCoefficients` (`DepositOptimizationMath.sol:362-406`, fee term :467-475): A = (alpha + kappa - 1) omega + epsilon_In - rho, rho = (kappa - 1) phi omega_U, with omega the sum of `range.liquidity` in range and omega_U the sum of `range.unstakedLiquidity` in range (`EquivalentPositionMath.sol:76-77`). Both come from the same snapshot: `range.unstakedLiquidity = positionLiquidity[i]` and `range.liquidity = positionLiquidity[i] + stakedLiquidity` (`Snapshot.sol:134-137`), so omega_U <= omega per range and summed. With phi <= 1 and kappa - 1 > 0, rho <= (kappa - 1) omega <= (alpha + kappa - 1) omega, hence A >= epsilon_In >= 0. The floors keep it: `feeFactor - (1 << 192) = floor(fee 2^192 / (1e6 - fee)) = K` exactly (:387), the code's rho is `floor(K floor(omega omega_U' phi' / (omega_L' 1e10)) / 2^192)` (:470-473) with `omega_U' <= omega_L'` (the position's unstaked and total liquidity) and `phi' = feeShare <= 1e10`, so rho <= `floor(K omega / 2^192)` <= `floor((alpha + K) omega / 2^192)`, the first term of A (:390-393). This is the condition [getRoot.derivation.md](../QuadraticMath/getRoot.derivation.md) section 5 uses (`a < 0` unreachable). No skim on entry and no flag are needed.

The model and the core agree on the fee share: the pool credits the NFT `feeAmount (1 - u) L_pm / L_pool` per step, the model credits `feeShare x L_pm / L_pool` (`SwapState.sol:159-165` on `position.unstakedLiquidity` = L_pm), the core values it on L_pm at the next read. [getStepFees.derivation.md](../SwapState/getStepFees.derivation.md) is written in the position's liquidity as the pool sees it, which is L_pm. So `assets <= balanceIn` and `amountMintOut <= amountSwapOut` (`ALMVaultSync.sol:242`) hold with a donation exactly as without: there is no second liquidity for the model to diverge on.

### (e) Async exchange rate

`execute` collects every unstaked side on L_pm (the PM pokes with `position.liquidity`, PM:366-375) and prices `valueBefore` on the live principal (section (c)). Settlements price pending deposits and redeems at `valueAfter` (`PlanCacheLib.getSettlementAmountsOut`, `PlanCache.sol:282`). A donation before the plan is in both: pending depositors pay for their pro rata of D and own it, pending redeemers are paid their pro rata of D. `setLastExchangeRate` (`ShareLib.sol:82`) is the estimate for later requests and lags by one plan as it does for any value change. No step beyond the addition itself, which (b) bounds.

### (f) Per-tick liquidity limits

A third party can fill `maxLiquidityPerTick` at the range's ticks through the core's NFT, after which the core's own increases at those ticks revert 'LO' (`core/libraries/Tick.sol:171`). Any LP can do the same with their own NFT at the same ticks. The core's decreases, burns and `closeRange` are unaffected, and the keeper opens elsewhere. Not donation specific, and it needs liquidity of order `type(uint128).max / tickCount`. The sum `L_pm + L_s` stays within a uint128 (section 2).

### (g) Accounting on the position manager's liquidity

- `PlanCacheLib.start` principal and `collectFees`: on L_pm (section 2), so `cache.amount0/1` is what the ranges hold.
- `checkSolvency` (`PoolTokensLib.sol:148-155`): balances against `buffer + protocolFees + escrowed`. Donated principal reaches the balance only through a collect that books it into the buffer at the same time.
- `ALMCore.mint` price and `addLiquidity`: both on L_pm, so the minter pays for D pro rata and the adds mint against L_pm + L_s.
- Vault model and core: every model read of the unstaked liquidity is L_pm (section 2), identical to the core's reads in the same transaction (the core's `nonReentrant` and the vault's, no callback inside an entry or exit other than the pool's to the vault).
- `test/invariant/handlers/DonorHandler.sol:42` `ghostDonatedLiquidity` counts the additions, asserted positive once (`ALMCore.invariant.t.sol:635`).

### What a donation costs the donor, and what it buys anyone

D goes to the holders at once (section 2). A donor as holder with fraction f recovers f D of it, and every other holder gains. There is no state in which a donation harms a holder, a minter or a depositor, and no state in which anyone but a holder gains from it. The front-run of (b) moves part of D from the existing holders to a one-block minter and is the only residual: a redistribution of a gift.
