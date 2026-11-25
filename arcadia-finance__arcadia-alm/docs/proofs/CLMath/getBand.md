# CLMath.getBand

Code: `src/shared/libraries/math/CLMath.sol` `getBand` (:108-121). Rows with a deviation take it at most `2^64 - 1`, which src does not check: `1e18 + deviation` is unchecked (:115-117), and every caller passes a `uint64` (`ConfigLib.sol:60-61`, :79, :83 the `uint64` config fields, `ALMCoreViewLogic.sol:758` a `uint64` cast, `Snapshot.sol:112` at most `65_535 * 100 * 5e11 < 2^64`).

| Claim | Status | Evidence |
|---|---|---|
| lower is the price over the scale rounded up | symbolic | test/symbolic/libraries/CLMath.symbolic.t.sol:111 `prove_getBand_LowerIsThePriceOverTheScaleRoundedUp` |
| upper is the price times the scale rounded down | symbolic | test/symbolic/libraries/CLMath.symbolic.t.sol:128 `prove_getBand_UpperIsThePriceTimesTheScaleRoundedDown` |
| lower is at most the price | symbolic | test/symbolic/libraries/CLMath.symbolic.t.sol:145 `prove_getBand_LowerIsAtMostThePrice` (z3int) |
| upper is at least the price | symbolic | test/symbolic/libraries/CLMath.symbolic.t.sol:158 `prove_getBand_UpperIsAtLeastThePrice` |
| at zero deviation the lower bound is the price, for pool prices | symbolic | test/symbolic/libraries/CLMath.symbolic.t.sol:171 `prove_getBand_LowerIsThePriceWithoutADeviation` (z3int, the real solady 0.1.26, no spec) |
| at zero deviation the upper bound is the price, for pool prices | symbolic | test/symbolic/libraries/CLMath.symbolic.t.sol:183 `prove_getBand_UpperIsThePriceWithoutADeviation` (z3int, the real solady 0.1.26, no spec) |
| at zero deviation both bounds are the price, for any uint256 price | open | above 2^196 the product takes `fullMulDivUp`'s 512-bit path, which no proof covers |
