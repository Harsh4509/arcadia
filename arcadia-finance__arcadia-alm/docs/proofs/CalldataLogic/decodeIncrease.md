# CalldataLogic.decodeIncrease

Code: `src/core/libraries/logic/CalldataLogic.sol` `decodeIncrease` (:157-174).

| Claim | Status | Evidence |
|---|---|---|
| unstaked, round trips with any trailing bytes | symbolic | test/symbolic/libraries/CalldataLogic.symbolic.t.sol:174 `prove_decodeIncrease_Unstaked_RoundTripsWithAnyTrailingBytes` |
| staked, round trips with any trailing bytes | symbolic | test/symbolic/libraries/CalldataLogic.symbolic.t.sol:215 `prove_decodeIncrease_Staked_RoundTripsWithAnyTrailingBytes` |
