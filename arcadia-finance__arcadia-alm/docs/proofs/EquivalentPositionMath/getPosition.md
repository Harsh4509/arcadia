# EquivalentPositionMath.getPosition

Code: `src/vaults/libraries/math/EquivalentPositionMath.sol` `getPosition` (:36-99), with `amountsAt` (:109-124). One range, bounds below 2^128, and for the token0 rows below 2^96 with liquidity below 2^63 so the pool's `getAmount0Delta` product fits 256 bits.

| Claim | Status | Evidence |
|---|---|---|
| without ranges holds the idle tokens, with no liquidity and the pool's extreme price as bound | open | test/symbolic/libraries/EquivalentPositionMath.symbolic.t.sol:142 `prove_getPosition_WithoutRangesHoldsTheIdleTokens` |
| one range in range: the position has its liquidity, its amounts at the far edge as constants, and its near edge as bound | open | test/symbolic/libraries/EquivalentPositionMath.symbolic.t.sol:164 `prove_getPosition_OneRangeInRange_FoldsItsLiquidityAndEdges` (z3int) |
| one range above the price: no liquidity, the range's token0 as a constant, its lower edge as the upward bound | open | test/symbolic/libraries/EquivalentPositionMath.symbolic.t.sol:193 `prove_getPosition_OneRangeAboveThePrice_HoldsItsToken0` (z3int) |
| one range below the price: no liquidity, the range's token1 as a constant, its upper edge as the downward bound | open | test/symbolic/libraries/EquivalentPositionMath.symbolic.t.sol:219 `prove_getPosition_OneRangeBelowThePrice_HoldsItsToken1` (z3int) |
| one range in range: amountsAt holds the range's rounded down amounts plus the idle, or one more, in each token | open | test/symbolic/libraries/EquivalentPositionMath.symbolic.t.sol:245 `prove_getPosition_OneRangeInRange_HoldsTheRangesAmountsOrOneMore` (z3int) |
| one range above the price: amountsAt holds the range's token0 plus the idle, or one more, and exactly the idle token1 | open | test/symbolic/libraries/EquivalentPositionMath.symbolic.t.sol:274 `prove_getPosition_OneRangeAboveThePrice_HoldsTheRangesToken0OrOneMore` (z3int) |
| one range below the price: amountsAt holds exactly the range's token1 plus the idle, and the idle token0 | open | test/symbolic/libraries/EquivalentPositionMath.symbolic.t.sol:302 `prove_getPosition_OneRangeBelowThePrice_HoldsTheRangesToken1` (z3int) |
