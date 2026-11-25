# ALMVaultSync previews: each preview bounds its execution in the same transaction

Code: `src/vaults/ALMSyncExtension.sol` `previewDeposit` (:73-78), `previewMint` (:85-89), `previewRedeem` (:96-101), `src/vaults/ALMVaultSync.sol` `previewWithdraw` (:466-471), and the optimisation libraries they call. Pool behaviour: [PoolAxioms.md](../PoolAxioms.md).

| Claim | Status | Evidence |
|---|---|---|
| `previewDeposit(x)` is at most the shares `deposit(x)` mints, `previewMint(m)` at least the assets `mint(m)` takes, `previewRedeem(m)` at most the assets `redeem(m)` pays, and `previewWithdraw(a)` at least the shares `withdraw(a)` burns, each in the same transaction with the swap filling | open | no symbolic harness: one step would need the walk's pool reads (`setNextTick`, `crossTick`: the tick bitmap and `liquidityNet`) replaced, and `getNormalizedParameters` (seven `fullMulDiv`s on symbolic divisors) and `QuadraticMath.getRoot` carried through |
| the mint's and the deposit's tokenIn pull against the fee carry | derived | [mint.derivation.md](mint.derivation.md) 3.1 to 3.3 |
| `previewRedeem` equals the redeem's payout when the sale fills | derived | [maxViews.derivation.md](maxViews.derivation.md) 3.6 |
| `previewWithdraw`'s margins | derived for `A = 0`, `W = 0`, model inside the binding step otherwise | [roundingMargins.derivation.md](roundingMargins.derivation.md) 4.4, section 5 |
