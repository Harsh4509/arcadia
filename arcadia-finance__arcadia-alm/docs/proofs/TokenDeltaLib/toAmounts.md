# TokenDeltaLib.toAmounts

Code: `src/core/types/TokenDelta.sol` `toAmounts` (:98-103), against Uniswap's `toBalanceDelta` packing.

| Claim | Status | Evidence |
|---|---|---|
| reads each component sign-extended to 256 bits, so a non-negative component is its magnitude | symbolic | test/symbolic/libraries/TokenDeltaLib.symbolic.t.sol:108 `prove_toAmounts_ReadsBothComponentsSignExtended` |
