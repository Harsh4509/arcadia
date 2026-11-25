# SwapStateLib.computeSwapStep

Code: `src/vaults/types/SwapState.sol:126-144` `computeSwapStep`. Rows take the oneForZero direction, prices of at most one and pool liquidity below 2^63, so the pool's `getAmount0Delta` product fits 256 bits.

| Claim | Status | Evidence |
|---|---|---|
| the fee is the pool's fee on the input, rounded up: ceil(amountIn fee / (1e6 - fee)) | open | test/symbolic/libraries/SwapStateLib.symbolic.t.sol:159 `prove_computeSwapStep_OneForZero_TheFeeIsThePoolsFeeOnTheInput` (z3int) |
| the gross input net of the pool's fee covers the input: floor((amountIn + fee)(1e6 - fee) / 1e6) >= amountIn | open | test/symbolic/libraries/SwapStateLib.symbolic.t.sol:181 `prove_computeSwapStep_OneForZero_TheGrossInputNetOfTheFeeCoversTheInput` (z3int) |
| rounded up takes at least rounded down's input and fee and pays the same output | open | test/symbolic/libraries/SwapStateLib.symbolic.t.sol:204 `prove_computeSwapStep_OneForZero_RoundedUpDominatesRoundedDown` (z3int) |
| the fee rounded up on one more wei of input exceeds the fee rounded down by at most two (fee at most 100_000) | open | test/symbolic/libraries/SwapStateLib.symbolic.t.sol:230 `prove_computeSwapStep_TheFeeOnAWeiMoreInputRoundedUpExceedsRoundedDownByAtMostTwo` (z3int) |
| equals the pool's step to its target | fuzz | test/fuzz/libraries/SwapStateLib/ComputeSwapStep.fuzz.t.sol:24 `testFuzz_Success_computeSwapStep_AsThePoolsStepToItsTarget` |
