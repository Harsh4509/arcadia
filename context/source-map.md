# Source map

Document locations and statement identifiers. Read the complete records in [statements.json](statements.json); document metadata is in [entries.json](entries.json). Query examples are in the [context map](README.md).

The engagement document and repository audit document have different wording in the scope introduction, deployment environment, production parameters, and disclosures. Their locations are listed separately below. The [selected guidelines, §2](judging-guidelines.md#2-order-of-authority) state how statements and context apply.

## Engagement document

The [protocol document](Arcadia-Context-Doc-Final.md) is the supplied attachment declared written for this engagement.

| Topic | Location | Statement IDs |
| --- | --- | --- |
| [Scope introduction](Arcadia-Context-Doc-Final.md) | lines 3–5 | S1 |
| [Protocol overview](Arcadia-Context-Doc-Final.md#1-protocol-overview) | lines 7–45 | S2–S9 |
| [Components and invariants](Arcadia-Context-Doc-Final.md#2-detailed-breakdown-by-component) | lines 46–203 | S10–S19 |
| [Deployment environment](Arcadia-Context-Doc-Final.md#3-deployment-environment) | lines 204–239 | S20–S27 |
| [Roles, parameters, and operations](Arcadia-Context-Doc-Final.md#4-roles-permissions--trust-model) | lines 240–281 | S28–S38 |
| [Previous audits](Arcadia-Context-Doc-Final.md#5-previous-audits) | lines 282–288 | S39 |
| [Disclosure introduction and transaction ordering](Arcadia-Context-Doc-Final.md#6-known-issues-accepted-risks--design-decisions) | lines 289–301 | S40–S44 |
| [Core disclosures](Arcadia-Context-Doc-Final.md#61-core-mint-burn-share-token-caps) | lines 302–318 | S45–S58 |
| [Keeper plans and async settlement disclosures](Arcadia-Context-Doc-Final.md#62-keeper-plans-and-async-settlement) | lines 319–334 | S59–S71 |
| [Emissions disclosures](Arcadia-Context-Doc-Final.md#63-emissions) | lines 335–345 | S72–S79 |
| [Sync vault disclosures](Arcadia-Context-Doc-Final.md#64-sync-vault) | lines 346–358 | S80–S89 |
| [Factory and governance disclosures](Arcadia-Context-Doc-Final.md#65-factory-and-governance) | lines 359–364 | S90–S92 |
| [Standards](Arcadia-Context-Doc-Final.md#66-standards) | lines 365–368 | S93 |
| [Build, tests, and PoC setup](Arcadia-Context-Doc-Final.md#7-build-test--poc-setup) | lines 369–416 | — |

## Repository documentation

| Source | Statement IDs |
| --- | --- |
| [audit-doc.md](../arcadia-finance__arcadia-alm/docs/audit-doc.md) | S148–S235 |
| [proofs/ALMCore/invariantTolerances.md](../arcadia-finance__arcadia-alm/docs/proofs/ALMCore/invariantTolerances.md) | S236 |
| [proofs/ALMKeeperExtension/swapSettlement.derivation.md](../arcadia-finance__arcadia-alm/docs/proofs/ALMKeeperExtension/swapSettlement.derivation.md) | S237–S238 |
| [proofs/ALMVaultSync/deposit.derivation.md](../arcadia-finance__arcadia-alm/docs/proofs/ALMVaultSync/deposit.derivation.md) | S239–S242 |
| [proofs/ALMVaultSync/previews.md](../arcadia-finance__arcadia-alm/docs/proofs/ALMVaultSync/previews.md) | S243 |
| [proofs/ALMVaultSync/roundingMargins.derivation.md](../arcadia-finance__arcadia-alm/docs/proofs/ALMVaultSync/roundingMargins.derivation.md) | S244–S249 |
| [proofs/ALMVaultSync/uncheckedMath.derivation.md](../arcadia-finance__arcadia-alm/docs/proofs/ALMVaultSync/uncheckedMath.derivation.md) | S250–S266 |
| [proofs/CLMath/getAmount0ForLiquidityRoundingUp.md](../arcadia-finance__arcadia-alm/docs/proofs/CLMath/getAmount0ForLiquidityRoundingUp.md) | S267 |
| [proofs/CLMath/getAmountsForLiquidity.md](../arcadia-finance__arcadia-alm/docs/proofs/CLMath/getAmountsForLiquidity.md) | S268 |
| [proofs/CLMath/getBand.md](../arcadia-finance__arcadia-alm/docs/proofs/CLMath/getBand.md) | S269 |
| [proofs/CLMath/getNextSqrtPrice.derivation.md](../arcadia-finance__arcadia-alm/docs/proofs/CLMath/getNextSqrtPrice.derivation.md) | S270 |
| [proofs/CommandLogic/pausable.md](../arcadia-finance__arcadia-alm/docs/proofs/CommandLogic/pausable.md) | S271 |
| [proofs/DepositOptimizationMath/getBalanceIn.md](../arcadia-finance__arcadia-alm/docs/proofs/DepositOptimizationMath/getBalanceIn.md) | S272 |
| [proofs/DepositOptimizationMath/getQuadraticCoefficients.md](../arcadia-finance__arcadia-alm/docs/proofs/DepositOptimizationMath/getQuadraticCoefficients.md) | S273 |
| [proofs/DepositOptimizationMath/maxDeposit.md](../arcadia-finance__arcadia-alm/docs/proofs/DepositOptimizationMath/maxDeposit.md) | S274 |
| [proofs/EmissionsLogic/isPenaltyWindowOpen.md](../arcadia-finance__arcadia-alm/docs/proofs/EmissionsLogic/isPenaltyWindowOpen.md) | S275–S276 |
| [proofs/INDEX.md](../arcadia-finance__arcadia-alm/docs/proofs/INDEX.md) | S277 |
| [proofs/PlanCache/getLevies.derivation.md](../arcadia-finance__arcadia-alm/docs/proofs/PlanCache/getLevies.derivation.md) | S278 |
| [proofs/PlanCacheLib/applyLiquidityDelta.md](../arcadia-finance__arcadia-alm/docs/proofs/PlanCacheLib/applyLiquidityDelta.md) | S279 |
| [proofs/PlanCacheLib/getOwed.derivation.md](../arcadia-finance__arcadia-alm/docs/proofs/PlanCacheLib/getOwed.derivation.md) | S280 |
| [proofs/PlanCacheLib/getSettlementAmountsOut.derivation.md](../arcadia-finance__arcadia-alm/docs/proofs/PlanCacheLib/getSettlementAmountsOut.derivation.md) | S281 |
| [proofs/PlanCacheLib/getSettlementAmountsOut.md](../arcadia-finance__arcadia-alm/docs/proofs/PlanCacheLib/getSettlementAmountsOut.md) | S282–S283 |
| [proofs/PoolAxioms.md](../arcadia-finance__arcadia-alm/docs/proofs/PoolAxioms.md) | S284 |
| [proofs/QuadraticMath/getRoot.derivation.md](../arcadia-finance__arcadia-alm/docs/proofs/QuadraticMath/getRoot.derivation.md) | S285–S289 |
| [proofs/QuadraticMath/getRoot.md](../arcadia-finance__arcadia-alm/docs/proofs/QuadraticMath/getRoot.md) | S290 |
| [proofs/README.md](../arcadia-finance__arcadia-alm/docs/proofs/README.md) | S291–S320 |
| [proofs/RangesLib/donatedLiquidity.derivation.md](../arcadia-finance__arcadia-alm/docs/proofs/RangesLib/donatedLiquidity.derivation.md) | S321–S322 |
| [proofs/RewardsLib/chainStatus.derivation.md](../arcadia-finance__arcadia-alm/docs/proofs/RewardsLib/chainStatus.derivation.md) | S323–S326 |
| [proofs/RewardsLib/getRewardPerShare.md](../arcadia-finance__arcadia-alm/docs/proofs/RewardsLib/getRewardPerShare.md) | S327 |
| [proofs/ShareLib/getPendingShares.derivation.md](../arcadia-finance__arcadia-alm/docs/proofs/ShareLib/getPendingShares.derivation.md) | S328 |
| [proofs/Snapshot/getAmountsAt.md](../arcadia-finance__arcadia-alm/docs/proofs/Snapshot/getAmountsAt.md) | S329 |
| [proofs/Snapshot/getBurnAmounts.md](../arcadia-finance__arcadia-alm/docs/proofs/Snapshot/getBurnAmounts.md) | S330 |
| [proofs/Snapshot/getMintShares.md](../arcadia-finance__arcadia-alm/docs/proofs/Snapshot/getMintShares.md) | S331 |
| [proofs/SwapState/getStepFees.md](../arcadia-finance__arcadia-alm/docs/proofs/SwapState/getStepFees.md) | S332–S333 |

## Repository source comments

| Source | Statement IDs |
| --- | --- |
| [core/ALMAdminExtension.sol](../arcadia-finance__arcadia-alm/src/core/ALMAdminExtension.sol) | S94–S95 |
| [core/ALMCore.sol](../arcadia-finance__arcadia-alm/src/core/ALMCore.sol) | S96–S102 |
| [core/abstracts/mixins/AsyncVaultGuard.sol](../arcadia-finance__arcadia-alm/src/core/abstracts/mixins/AsyncVaultGuard.sol) | S103 |
| [core/abstracts/tokens/ERC20Share.sol](../arcadia-finance__arcadia-alm/src/core/abstracts/tokens/ERC20Share.sol) | S104 |
| [core/libraries/logic/CalldataLogic.sol](../arcadia-finance__arcadia-alm/src/core/libraries/logic/CalldataLogic.sol) | S105 |
| [core/libraries/logic/EmissionsLogic.sol](../arcadia-finance__arcadia-alm/src/core/libraries/logic/EmissionsLogic.sol) | S106–S107 |
| [core/libraries/logic/PositionManagerLogic.sol](../arcadia-finance__arcadia-alm/src/core/libraries/logic/PositionManagerLogic.sol) | S108 |
| [core/libraries/state/PoolTokensLib.sol](../arcadia-finance__arcadia-alm/src/core/libraries/state/PoolTokensLib.sol) | S109 |
| [core/libraries/state/QueueLib.sol](../arcadia-finance__arcadia-alm/src/core/libraries/state/QueueLib.sol) | S110 |
| [core/libraries/state/RangesLib.sol](../arcadia-finance__arcadia-alm/src/core/libraries/state/RangesLib.sol) | S111–S112 |
| [core/libraries/state/RewardsLib.sol](../arcadia-finance__arcadia-alm/src/core/libraries/state/RewardsLib.sol) | S113–S118 |
| [core/libraries/state/ShareLib.sol](../arcadia-finance__arcadia-alm/src/core/libraries/state/ShareLib.sol) | S119 |
| [core/types/PlanCache.sol](../arcadia-finance__arcadia-alm/src/core/types/PlanCache.sol) | S120–S121 |
| [factory/ALMFactory.sol](../arcadia-finance__arcadia-alm/src/factory/ALMFactory.sol) | S122 |
| [factory/abstracts/base/BaseFactory.sol](../arcadia-finance__arcadia-alm/src/factory/abstracts/base/BaseFactory.sol) | S123 |
| [registry/ALMRegistry.sol](../arcadia-finance__arcadia-alm/src/registry/ALMRegistry.sol) | S124 |
| [shared/libraries/math/CLMath.sol](../arcadia-finance__arcadia-alm/src/shared/libraries/math/CLMath.sol) | S125–S127 |
| [shared/libraries/vendored/MetadexOracle.sol](../arcadia-finance__arcadia-alm/src/shared/libraries/vendored/MetadexOracle.sol) | S128–S129 |
| [shared/libraries/vendored/MetadexPositionValue.sol](../arcadia-finance__arcadia-alm/src/shared/libraries/vendored/MetadexPositionValue.sol) | S130–S131 |
| [shared/libraries/vendored/MetadexSwapMath.sol](../arcadia-finance__arcadia-alm/src/shared/libraries/vendored/MetadexSwapMath.sol) | S132 |
| [shared/libraries/vendored/MetadexTickBitmap.sol](../arcadia-finance__arcadia-alm/src/shared/libraries/vendored/MetadexTickBitmap.sol) | S133 |
| [vaults/ALMSyncExtension.sol](../arcadia-finance__arcadia-alm/src/vaults/ALMSyncExtension.sol) | S134 |
| [vaults/ALMVaultAsync.sol](../arcadia-finance__arcadia-alm/src/vaults/ALMVaultAsync.sol) | S135 |
| [vaults/ALMVaultSync.sol](../arcadia-finance__arcadia-alm/src/vaults/ALMVaultSync.sol) | S136–S137 |
| [vaults/abstracts/base/BaseVault.sol](../arcadia-finance__arcadia-alm/src/vaults/abstracts/base/BaseVault.sol) | S138 |
| [vaults/abstracts/tokens/ERC7540Deposit.sol](../arcadia-finance__arcadia-alm/src/vaults/abstracts/tokens/ERC7540Deposit.sol) | S139 |
| [vaults/libraries/math/DepositOptimizationMath.sol](../arcadia-finance__arcadia-alm/src/vaults/libraries/math/DepositOptimizationMath.sol) | S140 |
| [vaults/libraries/math/EquivalentPositionMath.sol](../arcadia-finance__arcadia-alm/src/vaults/libraries/math/EquivalentPositionMath.sol) | S141 |
| [vaults/libraries/math/MintOptimizationMath.sol](../arcadia-finance__arcadia-alm/src/vaults/libraries/math/MintOptimizationMath.sol) | S142 |
| [vaults/libraries/math/QuadraticMath.sol](../arcadia-finance__arcadia-alm/src/vaults/libraries/math/QuadraticMath.sol) | S143 |
| [vaults/libraries/math/RedeemOptimizationMath.sol](../arcadia-finance__arcadia-alm/src/vaults/libraries/math/RedeemOptimizationMath.sol) | S144–S145 |
| [vaults/types/Snapshot.sol](../arcadia-finance__arcadia-alm/src/vaults/types/Snapshot.sol) | S146–S147 |

Other repository proof documents remain available through the [proofs guide](../arcadia-finance__arcadia-alm/docs/proofs/README.md) and [proofs index](../arcadia-finance__arcadia-alm/docs/proofs/INDEX.md).
