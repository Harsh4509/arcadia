# SwapStateLib.accrueFees

Code: `src/vaults/types/SwapState.sol:175-186` `accrueFees`.

| Claim | Status | Evidence |
|---|---|---|
| moves the fee into tokenIn's constant and the snapshot's fees, tokenOut's untouched | open | test/symbolic/libraries/SwapStateLib.symbolic.t.sol:246 `prove_accrueFees_MoveTheFeeIntoThePositionAndTheSnapshot` |
