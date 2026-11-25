# RewardsLib.getRewardPerShare

Code: `src/core/libraries/state/RewardsLib.sol` `getRewardPerShare` (:263-313). Without an open window (windowEnd = 0), lifetime reward uint128.

| Claim | Status | Evidence |
|---|---|---|
| rises by floor((total - highWater) 1e18 / supply) modulo 2^128 when the total exceeds the high water and the supply is non-empty, else stays. On a rise below 2^128 only: the proof assumes it. A rise of 2^128 or more reverts in `SafeCastLib.toUint128` (:310), which no proof covers. The high water becomes max(highWater, total), and the pre-credit and window end stay | open | test/symbolic/libraries/RewardsLib.symbolic.t.sol:132 `prove_getRewardPerShare_WithoutAWindowSpreadsTheExcessOverTheSupply` (z3int) |
