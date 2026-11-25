# Token0 pending shares are monotone in the assets

Code: `src/core/libraries/state/ShareLib.sol` `getPendingShares` (:99-122).

## 1. The code is a composition of three rounded-up parts

For `isToken0`, with `u = max(sqrtPriceX96, lastSqrtPriceX96)` (:112, `u = lastSqrtPriceX96` below the last price), `r = supplyPerValueX128` and `U(x, y, d) = fullMulDivUp(x, y, d)`:

```solidity
shares = U(U(U(assets, u, 2^96), u, 2^96), r, 2^128);   // :113 and :121
```

`u`, `r` and the divisors do not depend on `assets`, and the divisors are constant powers of two.

## 2. The argument

One lemma closes it: `U(x1, y, 2^k) <= U(x2, y, 2^k)` for `x1 <= x2`, `k` in `{96, 128}`. Applied once per stage, with `x1`, `x2` that stage's inputs for the smaller and the larger deposit, it gives `shares(assetsLow) <= shares(assetsHigh)`.

On solady's specification, `fullMulDivUp(x, y, d) = ceil(x y / d)` whenever the result fits 256 bits and reverts otherwise (node_modules/solady/src/utils/FixedPointMathLib.sol:548-560), the lemma is immediate: `x1 <= x2` gives `x1 y <= x2 y`, the ceiling of a quotient by a fixed positive divisor is non-decreasing, and the composition of three non-decreasing stages is non-decreasing. The larger call not reverting keeps every stage of the smaller call below 2^256, since each of its stage outputs is at most the larger call's. So the claim is derived on that specification.

The stages' inputs exceed 2^128 for most prices (the first stage's product is up to `2^128 * 2^160`), so a lemma on uint128 inputs or on products below 2^256 covers the first stage of small deposits only. A lemma for the whole domain has to run solady's 512-bit path (FixedPointMathLib.sol:468-507). With a constant power-of-two divisor its modular inverse is a constant.

## 3. Open

The machine check that solady's 512-bit path equals the ceiling for products of 2^256 or more. No symbolic run of the lemma or of the function (two token0 calls, the larger one not reverting) completes. The token1 claim, the same exactness with divisor 2^128 on uint128 inputs, is proven by test/symbolic/libraries/ShareLib.symbolic.t.sol:81 `prove_getPendingShares_Token1AtOrAboveTheLastPriceIsTheAssetsAtTheRateRoundedUp`.
