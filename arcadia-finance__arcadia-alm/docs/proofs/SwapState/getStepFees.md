# SwapState.getStepFees

Code: `src/vaults/types/SwapState.sol:153-166` `getStepFees`. Derivation: [getStepFees.derivation.md](getStepFees.derivation.md).

| Claim | Status | Evidence |
|---|---|---|
| Rounded up is `ceil(Phi)`, rounded down `floor(Phi)`, `Phi = F feeShare Lu / (1e10 L)` | symbolic | derivation section 3.1, on `F < 2^64`: test/symbolic/libraries/SwapStateLib.symbolic.t.sol:34 `prove_getStepFees_RoundedUpIsTheCeiledShare`, :55 `prove_getStepFees_RoundedDownIsTheFlooredShare` |
| Rounded up exceeds rounded down by at most one | symbolic | section 3.1, test/symbolic/libraries/SwapStateLib.symbolic.t.sol:76 `prove_getStepFees_RoundedUpExceedsRoundedDownByAtMostOne` |
| At most the step's fee while `Lu <= L` and `feeShare <= 1e10` | symbolic | section 3.1, test/symbolic/libraries/SwapStateLib.symbolic.t.sol:98 `prove_getStepFees_NeverExceedTheStepsFee` |
| Zero without unstaked liquidity, monotone in the step's fee | symbolic | section 3.1, test/symbolic/libraries/SwapStateLib.symbolic.t.sol:117 `prove_getStepFees_AreNothingWithoutUnstakedLiquidity`, :135 `prove_getStepFees_AreMonotoneInTheFee` |
| From the fresh state, rounded up is at or above what the pool credits the core, per step and summed over a swap | derived | sections 3.5, 3.6 |
| In general the credit is at most rounded up plus `n_u`, plus `[b > 0]` with one unstaked range in range, and the `+ 1` is reached | derived | section 3.5 |
| The credit is below the exact share by `d < 3` per step with a staked leg and an unstaked fee, `< 2` with one of them, `< Lu / 2^128` with neither, so rounded down exceeds it by up to `n_u + 3`, `n_u + 2` or `n_u + 1` | derived | sections 3.2, 3.5 |
| Every caller's rounding direction is safe for the core's holders | derived | section 3.7 |
| The fuzz tests' lower tolerances hold under the conditions of the sharper rows of section 3.5 | open | section 5: the tests' domains are not shown to imply them. test/fuzz/libraries/SwapStateLib/GetStepFees.fuzz.t.sol:98, :170, :240 |
