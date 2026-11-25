# CalldataLogic.decodeDecrease

Code: `src/core/libraries/logic/CalldataLogic.sol` `decodeDecrease` (:109-125).

| Claim | Status | Evidence |
|---|---|---|
| unstaked, round trips with any trailing bytes | symbolic | test/symbolic/libraries/CalldataLogic.symbolic.t.sol:74 `prove_decodeDecrease_Unstaked_RoundTripsWithAnyTrailingBytes` |
| staked, round trips with any trailing bytes | symbolic | test/symbolic/libraries/CalldataLogic.symbolic.t.sol:104 `prove_decodeDecrease_Staked_RoundTripsWithAnyTrailingBytes` |
