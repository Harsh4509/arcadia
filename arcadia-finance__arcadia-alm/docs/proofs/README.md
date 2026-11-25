# Proofs

One file per function or property: `<Contract or library>/<function>.md` for a claim table, `<Contract or library>/<topic>.derivation.md` for a derivation. Each file names the code it covers by file and line range and states each claim with its status and evidence. [PoolAxioms.md](PoolAxioms.md) holds the Metadex pool behaviour the derivations rest on. [INDEX.md](INDEX.md) lists every file with its opening statement.

Status:
- `symbolic`: proven by `forge test --symbolic` (test/symbolic, local only, cvc5 for the math). It holds only on the domain the proof assumes: read its `vm.assume` lines.
- `symbolic (lemmas) + derived`: the derivation's arithmetic steps are proven `symbolic` as lemmas, on their own domain. The derivation composes them.
- `derived`: a written derivation against the code, not machine-checked. The derivation is in the file or next to it.
- `fuzz`: asserted by the cited fuzz test, not a proof.
- `model`: the cited argument, checked against an exact integer model of the code and the pool, not a proof.
- `degenerate`: holds outside a state the file shows cannot occur in normal pools or holdings.
- `open`: claimed or needed, not proven. The evidence column says what is missing.
- `false (derived)`: the claim does not hold. The evidence says what does.

Run the symbolic proofs: `FOUNDRY_TEST=test/symbolic forge test --symbolic --match-path 'test/symbolic/*' --symbolic-timeout 120`.

Proofs whose `forge-config` line is `solver_command = "test/symbolic/tools/z3int.py -in"` (marked z3int) need `z3int`, local only: it translates forge's bit-vector queries exactly to integer arithmetic for z3 and races them against the original query. It needs `python3` (standard library) and `z3` on `PATH`. After changing it, check it against z3:

```sh
python3 -I test/symbolic/tools/z3int_check.py random
Z3INT_LOG=<dir> FOUNDRY_TEST=test/symbolic forge test --symbolic --match-path 'test/symbolic/*' --symbolic-timeout 120
python3 -I test/symbolic/tools/z3int_check.py corpus <dir>
```

## Claim tables

| Unit | Function | Claims |
|---|---|---|
| ALMCore | [invariantTolerances](ALMCore/invariantTolerances.md) | 3 derived, 1 open |
| ALMCoreViewLogic | [decodePauseAndDeviation](ALMCoreViewLogic/decodePauseAndDeviation.md) | 1 open |
| ALMCoreViewLogic | [decodeRange](ALMCoreViewLogic/decodeRange.md) | 1 open |
| ALMCoreViewLogic | [decodeRecord](ALMCoreViewLogic/decodeRecord.md) | 1 symbolic |
| ALMCoreViewLogic | [decodeWord](ALMCoreViewLogic/decodeWord.md) | 1 symbolic |
| ALMCoreViewLogic | [getConfig](ALMCoreViewLogic/getConfig.md) | 1 symbolic |
| ALMCoreViewLogic | [getLastClearedDepositEpoch](ALMCoreViewLogic/getLastClearedDepositEpoch.md) | 1 symbolic |
| ALMCoreViewLogic | [getMaxSwapCostBps](ALMCoreViewLogic/getMaxSwapCostBps.md) | 1 open |
| ALMCoreViewLogic | [getTwapWindow](ALMCoreViewLogic/getTwapWindow.md) | 1 open |
| ALMVaultSync | [previews](ALMVaultSync/previews.md) | 2 derived, 1 derived for `A = 0`, `W = 0`, model inside the binding step otherwise, 1 open |
| CLMath | [convert](CLMath/convert.md) | 3 open, 6 symbolic |
| CLMath | [getAmount0ForLiquidityRoundingUp](CLMath/getAmount0ForLiquidityRoundingUp.md) | 4 open |
| CLMath | [getAmount1ForLiquidityRoundingUp](CLMath/getAmount1ForLiquidityRoundingUp.md) | 1 open, 1 symbolic |
| CLMath | [getAmountsForLiquidity](CLMath/getAmountsForLiquidity.md) | 2 open, 1 symbolic |
| CLMath | [getBand](CLMath/getBand.md) | 1 open, 6 symbolic |
| CLMath | [getMintAmounts](CLMath/getMintAmounts.md) | 3 derived, fuzz, 3 open |
| CLMath | [getNextSqrtPrice](CLMath/getNextSqrtPrice.md) | 4 open |
| CLMath | [getPrincipalAmounts](CLMath/getPrincipalAmounts.md) | 1 open |
| CalldataLogic | [decodeControllers](CalldataLogic/decodeControllers.md) | 1 symbolic |
| CalldataLogic | [decodeCoreImmutables](CalldataLogic/decodeCoreImmutables.md) | 1 symbolic |
| CalldataLogic | [decodeDecrease](CalldataLogic/decodeDecrease.md) | 2 symbolic |
| CalldataLogic | [decodeIncrease](CalldataLogic/decodeIncrease.md) | 2 symbolic |
| CalldataLogic | [decodeOpen](CalldataLogic/decodeOpen.md) | 1 symbolic |
| CalldataLogic | [decodePosition](CalldataLogic/decodePosition.md) | 1 symbolic |
| CalldataLogic | [decodeQueue](CalldataLogic/decodeQueue.md) | 1 symbolic |
| CalldataLogic | [decodeRange](CalldataLogic/decodeRange.md) | 1 symbolic |
| CalldataLogic | [decodeStake](CalldataLogic/decodeStake.md) | 1 symbolic |
| CalldataLogic | [decodeSwapViaPool](CalldataLogic/decodeSwapViaPool.md) | 1 symbolic |
| CalldataLogic | [decodeSwapViaRouter](CalldataLogic/decodeSwapViaRouter.md) | 1 symbolic |
| CalldataLogic | [readController](CalldataLogic/readController.md) | 1 symbolic |
| CommandLogic | [pausable](CommandLogic/pausable.md) | 1 symbolic |
| DepositOptimizationMath | [getAmountOut](DepositOptimizationMath/getAmountOut.md) | 1 open |
| DepositOptimizationMath | [getBalanceIn](DepositOptimizationMath/getBalanceIn.md) | 3 open |
| DepositOptimizationMath | [getNormalizedParameters](DepositOptimizationMath/getNormalizedParameters.md) | 2 open |
| DepositOptimizationMath | [getQuadraticCoefficients](DepositOptimizationMath/getQuadraticCoefficients.md) | 1 derived, 1 derived, symbolic open, 1 open |
| DepositOptimizationMath | [getSqrtPrice](DepositOptimizationMath/getSqrtPrice.md) | 1 open |
| DepositOptimizationMath | [maxDeposit](DepositOptimizationMath/maxDeposit.md) | statements in the file |
| EmissionsLogic | [getHiddenEmissions](EmissionsLogic/getHiddenEmissions.md) | 1 symbolic |
| EmissionsLogic | [isPenaltyWindowOpen](EmissionsLogic/isPenaltyWindowOpen.md) | 3 symbolic |
| EquivalentPositionMath | [amountsAt](EquivalentPositionMath/amountsAt.md) | 4 symbolic |
| EquivalentPositionMath | [getPosition](EquivalentPositionMath/getPosition.md) | 7 open |
| MintOptimizationMath | [getMintAmountOut](MintOptimizationMath/getMintAmountOut.md) | 2 open |
| PlanCache | [getLevies](PlanCache/getLevies.md) | 1 false (derived), 2 open, 1 symbolic, 2 symbolic (lemmas) + derived |
| PlanCacheLib | [applyBufferDelta](PlanCacheLib/applyBufferDelta.md) | 1 symbolic |
| PlanCacheLib | [applyLiquidityDelta](PlanCacheLib/applyLiquidityDelta.md) | 1 open |
| PlanCacheLib | [checkShortfall](PlanCacheLib/checkShortfall.md) | 3 symbolic |
| PlanCacheLib | [closeRange](PlanCacheLib/closeRange.md) | 1 symbolic |
| PlanCacheLib | [getCleared_setCleared](PlanCacheLib/getCleared_setCleared.md) | 2 symbolic |
| PlanCacheLib | [getSettlementAmountsOut](PlanCacheLib/getSettlementAmountsOut.md) | 2 derived, 1 open, 1 symbolic (lemmas) + derived |
| PlanCacheLib | [getValueAfter](PlanCacheLib/getValueAfter.md) | 1 symbolic |
| PlanCacheLib | [hasUnsettledEpochs](PlanCacheLib/hasUnsettledEpochs.md) | 1 symbolic |
| PlanCacheLib | [isOpenedRange](PlanCacheLib/isOpenedRange.md) | 1 symbolic |
| PlanCacheLib | [openRange](PlanCacheLib/openRange.md) | 1 symbolic |
| PoolTokensLib | [creditCollected](PoolTokensLib/creditCollected.md) | 2 open |
| QuadraticMath | [getRoot](QuadraticMath/getRoot.md) | 2 degenerate, 11 derived, 2 derived, symbolic open, 1 model, 4 open, 1 symbolic |
| QueueLib | [cancel](QueueLib/cancel.md) | 1 open |
| QueueLib | [creditSettled](QueueLib/creditSettled.md) | 1 open |
| QueueLib | [isPending_isSettled](QueueLib/isPending_isSettled.md) | 1 symbolic |
| QueueLib | [record](QueueLib/record.md) | 1 open |
| QueueLib | [requestAmountIn](QueueLib/requestAmountIn.md) | 2 symbolic |
| QueueLib | [requestAmountOut](QueueLib/requestAmountOut.md) | 3 symbolic |
| QueueLib | [requirePending](QueueLib/requirePending.md) | 1 symbolic |
| QueueLib | [startClearedEpoch](QueueLib/startClearedEpoch.md) | 1 symbolic |
| QueueLib | [takeClaimable](QueueLib/takeClaimable.md) | 3 open |
| RangesLib | [decodeRanges](RangesLib/decodeRanges.md) | 1 symbolic |
| RangesLib | [unsafeAccess](RangesLib/unsafeAccess.md) | 1 symbolic |
| RewardsLib | [accrueBalanceReward](RewardsLib/accrueBalanceReward.md) | 4 open |
| RewardsLib | [getRewardPerShare](RewardsLib/getRewardPerShare.md) | 1 open |
| ShareLib | [checkPerUserCap](ShareLib/checkPerUserCap.md) | 1 symbolic |
| ShareLib | [getPendingShares](ShareLib/getPendingShares.md) | 1 derived, symbolic open, 1 symbolic |
| ShareLib | [setLastExchangeRate](ShareLib/setLastExchangeRate.md) | 1 symbolic |
| Snapshot | [decodePricedRanges](Snapshot/decodePricedRanges.md) | 1 open |
| Snapshot | [getAmountsAt](Snapshot/getAmountsAt.md) | 2 open, 1 symbolic |
| Snapshot | [getBurnAmounts](Snapshot/getBurnAmounts.md) | 2 open |
| Snapshot | [getMintAmounts](Snapshot/getMintAmounts.md) | 1 false (derived), 4 open |
| Snapshot | [getMintShares](Snapshot/getMintShares.md) | 2 open |
| Snapshot | [getPosition](Snapshot/getPosition.md) | 1 symbolic |
| Snapshot | [getSwapCostLimit](Snapshot/getSwapCostLimit.md) | 3 open |
| Snapshot | [idle](Snapshot/idle.md) | 1 symbolic |
| SwapState | [accrueFees](SwapState/accrueFees.md) | 1 open |
| SwapState | [computeSwapStep](SwapState/computeSwapStep.md) | 1 fuzz, 4 open |
| SwapState | [getStepFees](SwapState/getStepFees.md) | 4 derived, 1 open, 4 symbolic |
| TokenDeltaLib | [add](TokenDeltaLib/add.md) | 1 symbolic |
| TokenDeltaLib | [applyDelta](TokenDeltaLib/applyDelta.md) | 1 symbolic |
| TokenDeltaLib | [fromAmounts](TokenDeltaLib/fromAmounts.md) | 2 symbolic |
| TokenDeltaLib | [neg](TokenDeltaLib/neg.md) | 1 symbolic |
| TokenDeltaLib | [single](TokenDeltaLib/single.md) | 1 symbolic |
| TokenDeltaLib | [toAmounts](TokenDeltaLib/toAmounts.md) | 1 symbolic |
| VaultCalldataLogic | [decodeAssetIsToken0](VaultCalldataLogic/decodeAssetIsToken0.md) | 1 symbolic |
| VaultCalldataLogic | [decodeCore](VaultCalldataLogic/decodeCore.md) | 1 symbolic |
| VaultCalldataLogic | [decodePool](VaultCalldataLogic/decodePool.md) | 1 symbolic |
| WithdrawOptimizationMath | [getNextSqrtPrice](WithdrawOptimizationMath/getNextSqrtPrice.md) | 1 open |
| WithdrawOptimizationMath | [getNormalizedParameters](WithdrawOptimizationMath/getNormalizedParameters.md) | 4 derived, 1 derived, fuzz, 1 symbolic (lemmas) + derived |
| WithdrawOptimizationMath | [getQuadraticCoefficients](WithdrawOptimizationMath/getQuadraticCoefficients.md) | 3 derived, 1 fuzz, 1 open |
| WithdrawOptimizationMath | [getSharesForAmounts](WithdrawOptimizationMath/getSharesForAmounts.md) | 1 open |
| WithdrawOptimizationMath | [getSqrtPrice](WithdrawOptimizationMath/getSqrtPrice.md) | 1 open |

## Derivations

- [ALMCore/burnFeesCollected.derivation.md](ALMCore/burnFeesCollected.derivation.md)
- [ALMCore/invariantTolerances.derivation.md](ALMCore/invariantTolerances.derivation.md)
- [ALMKeeperExtension/swapSettlement.derivation.md](ALMKeeperExtension/swapSettlement.derivation.md)
- [ALMVaultSync/deposit.derivation.md](ALMVaultSync/deposit.derivation.md)
- [ALMVaultSync/maxViews.derivation.md](ALMVaultSync/maxViews.derivation.md)
- [ALMVaultSync/mint.derivation.md](ALMVaultSync/mint.derivation.md)
- [ALMVaultSync/roundingMargins.derivation.md](ALMVaultSync/roundingMargins.derivation.md)
- [ALMVaultSync/swapsPastATick.derivation.md](ALMVaultSync/swapsPastATick.derivation.md)
- [ALMVaultSync/uncheckedMath.derivation.md](ALMVaultSync/uncheckedMath.derivation.md)
- [CLMath/getNextSqrtPrice.derivation.md](CLMath/getNextSqrtPrice.derivation.md)
- [DepositOptimizationMath/getQuadraticCoefficients.derivation.md](DepositOptimizationMath/getQuadraticCoefficients.derivation.md)
- [DepositOptimizationMath/maxDeposit.derivation.md](DepositOptimizationMath/maxDeposit.derivation.md)
- [DepositOptimizationMath/stepEndRounding.derivation.md](DepositOptimizationMath/stepEndRounding.derivation.md)
- [EmissionsLogic/getHiddenEmissions.derivation.md](EmissionsLogic/getHiddenEmissions.derivation.md)
- [MintOptimizationMath/maxMint.derivation.md](MintOptimizationMath/maxMint.derivation.md)
- [PlanCache/getLevies.derivation.md](PlanCache/getLevies.derivation.md)
- [PlanCacheLib/getOwed.derivation.md](PlanCacheLib/getOwed.derivation.md)
- [PlanCacheLib/getSettlementAmountsOut.derivation.md](PlanCacheLib/getSettlementAmountsOut.derivation.md)
- [QuadraticMath/getRoot.derivation.md](QuadraticMath/getRoot.derivation.md)
- [QueueLib/queueInvariants.derivation.md](QueueLib/queueInvariants.derivation.md)
- [RangesLib/donatedLiquidity.derivation.md](RangesLib/donatedLiquidity.derivation.md)
- [RewardsLib/chainStatus.derivation.md](RewardsLib/chainStatus.derivation.md)
- [RewardsLib/checkpoint.derivation.md](RewardsLib/checkpoint.derivation.md)
- [ShareLib/getPendingShares.derivation.md](ShareLib/getPendingShares.derivation.md)
- [SwapState/getStepFees.derivation.md](SwapState/getStepFees.derivation.md)
- [WithdrawOptimizationMath/getNormalizedParameters.derivation.md](WithdrawOptimizationMath/getNormalizedParameters.derivation.md)
