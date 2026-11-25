/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { DepositOptimizationMathExtension } from "../../../utils/extensions/DepositOptimizationMathExtension.sol";
import { FixedPoint96 } from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { MetadexTickBitmap } from "../../../../src/shared/libraries/vendored/MetadexTickBitmap.sol";
import { OptimizationMath_Fuzz_Test } from "../_OptimizationMath.fuzz.t.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { SwapState } from "../../../../src/vaults/types/SwapState.sol";
import { SwapMath } from "@uniswap/v4-core/src/libraries/SwapMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Common logic needed by all "DepositOptimizationMath" fuzz tests.
 */
// forge-lint: disable-next-item(unsafe-typecast)
abstract contract DepositOptimizationMath_Fuzz_Test is OptimizationMath_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    struct DepositParams {
        bool zeroForOne;
        uint24 fee;
        uint128 liquidity;
        uint160 sqrtPriceOld;
        uint160 sqrtPriceBound;
        uint256 positionLiquidity;
        uint256 positionUnstakedLiquidity;
        uint256 positionAmount0;
        uint256 positionAmount1;
        uint256 balanceIn;
        uint256 balanceOut;
        uint256 roundingMargin;
    }

    struct AmountOutParams {
        bool zeroForOne;
        uint24 fee;
        uint128 poolLiquidity;
        uint160 sqrtPrice;
        uint160 sqrtPriceLower;
        uint160 sqrtPriceUpper;
        uint128 liquidity;
        uint256 idle0;
        uint256 idle1;
        uint256 balanceIn;
        uint256 balanceOut;
        uint256 supply;
    }

    struct MarginState {
        uint24 fee;
        uint24 unstakedFee;
        uint128 poolLiquidity;
        uint160 sqrtPrice;
        uint256 idle0;
        uint256 idle1;
        uint256 supply;
        uint256 assets;
    }

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    // The mock pool's tick spacing, a bitmap word spanning each side of tick zero.
    int24 internal constant MOCK_TICK_SPACING = 4096;
    // The tick spacing of the margin tests' pools, a standard Metadex spacing.
    int24 internal constant MARGIN_TICK_SPACING = 100;

    DepositOptimizationMathExtension internal optimizationMath;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(OptimizationMath_Fuzz_Test) {
        OptimizationMath_Fuzz_Test.setUp();
        optimizationMath = new DepositOptimizationMathExtension();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function givenValidDepositParams(DepositParams memory params, bool zeroForOne) internal pure {
        params.zeroForOne = zeroForOne;
        params.positionUnstakedLiquidity = 0;
        params.fee = uint24(bound(params.fee, 0, Constants.MAX_POOL_FEE));
        params.sqrtPriceOld =
            uint160(bound(params.sqrtPriceOld, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE - 2));

        // And: A liquidity at which the solve takes at least 1 of tokenIn.
        params.liquidity = uint128(
            bound(
                params.liquidity,
                zeroForOne
                    ? FixedPointMathLib.divUp(params.sqrtPriceOld, 1 << 156)
                    : FixedPointMathLib.divUp(1 << 36, params.sqrtPriceOld),
                type(uint128).max
            )
        );

        params.positionLiquidity = bound(params.positionLiquidity, 0, params.liquidity);
        params.positionAmount0 = bound(params.positionAmount0, zeroForOne ? 0 : 1, type(uint128).max);
        params.positionAmount1 = bound(params.positionAmount1, zeroForOne ? 1 : 0, type(uint128).max);

        (uint256 minBalanceIn, uint256 maxBalanceIn) = getBalanceInBounds(params);
        params.balanceIn = bound(params.balanceIn, minBalanceIn, maxBalanceIn);
        params.balanceOut = bound(
            params.balanceOut,
            0,
            FixedPointMathLib.min(
                zeroForOne
                    ? FullMath.mulDiv(params.liquidity, params.sqrtPriceOld, 1 << 36)
                    : FullMath.mulDiv(params.liquidity, 1 << 156, params.sqrtPriceOld),
                type(uint128).max
            )
        );

        params.sqrtPriceBound = zeroForOne
            ? uint160(bound(params.sqrtPriceBound, getSegmentEnd(params), params.sqrtPriceOld))
            : uint160(bound(params.sqrtPriceBound, params.sqrtPriceOld, getSegmentEnd(params)));

        // And: A rounding margin up to computeSwap's at the most ranges.
        params.roundingMargin = bound(params.roundingMargin, 0, 2 * ConfigLib.MAX_RANGE_CAP + 4);
    }

    function givenValidAmountOutParams(AmountOutParams memory params, bool zeroForOne) internal pure {
        params.zeroForOne = zeroForOne;
        params.fee = uint24(bound(params.fee, 0, Constants.MAX_POOL_FEE));
        params.sqrtPrice =
            uint160(bound(params.sqrtPrice, 2 * Constants.MIN_RANGE_SQRT_PRICE, Constants.MAX_RANGE_SQRT_PRICE / 2));

        params.liquidity = uint128(bound(params.liquidity, 0, Constants.MAX_RANGE_LIQUIDITY));

        // And: Other liquidity: none, or enough to solve past any range edge in band.
        uint256 liquidityOther =
            bound(params.poolLiquidity, params.liquidity == 0 ? 1 : 0, type(uint128).max - params.liquidity);
        if (liquidityOther > 0) {
            liquidityOther = bound(
                liquidityOther,
                zeroForOne
                    ? FixedPointMathLib.divUp(params.sqrtPrice, Constants.MIN_RANGE_SQRT_PRICE)
                        .fullMulDivUp(params.sqrtPrice, 1 << 156)
                    : FixedPointMathLib.divUp(Constants.MAX_RANGE_SQRT_PRICE, params.sqrtPrice)
                        .fullMulDivUp(1 << 36, params.sqrtPrice),
                type(uint128).max - params.liquidity
            );
        }
        params.poolLiquidity = uint128(params.liquidity + liquidityOther);
        params.idle0 = bound(params.idle0, 0, type(uint128).max / 2);
        params.idle1 = bound(params.idle1, 0, type(uint128).max / 2);

        // And: A deposit that stays in the band at the other liquidity.
        (uint256 minBalanceIn, uint256 maxBalanceIn) = getBalanceInBounds(depositOf(params));
        if (liquidityOther > 0) {
            maxBalanceIn = FixedPointMathLib.min(
                maxBalanceIn,
                FixedPointMathLib.min(
                    zeroForOne
                        ? liquidityOther.fullMulDiv(1 << 156, params.sqrtPrice)
                            .fullMulDiv(Constants.MIN_RANGE_SQRT_PRICE, params.sqrtPrice)
                        : liquidityOther.fullMulDiv(params.sqrtPrice, 1 << 36)
                            .fullMulDiv(params.sqrtPrice, Constants.MAX_RANGE_SQRT_PRICE),
                    (zeroForOne
                            ? SqrtPriceMath.getAmount0Delta(
                                Constants.MIN_RANGE_SQRT_PRICE, params.sqrtPrice, uint128(liquidityOther), false
                            )
                            : SqrtPriceMath.getAmount1Delta(
                                params.sqrtPrice, Constants.MAX_RANGE_SQRT_PRICE, uint128(liquidityOther), false
                            ))
                    .fullMulDiv(1e6, 1e6 - params.fee)
                )
            );
        }
        params.balanceIn = bound(params.balanceIn, minBalanceIn, maxBalanceIn);
        params.balanceOut = 0;
        params.supply = bound(params.supply, 1, type(uint128).max);
    }

    function givenValidRangeAroundSpot(AmountOutParams memory params) internal pure {
        // And: A range around spot, on ticks.
        params.sqrtPriceLower =
            onTickBelow(bound(params.sqrtPriceLower, Constants.MIN_RANGE_SQRT_PRICE, params.sqrtPrice - 1));
        params.sqrtPriceUpper =
            onTickAbove(bound(params.sqrtPriceUpper, params.sqrtPrice + 1, Constants.MAX_RANGE_SQRT_PRICE));
    }

    function givenValidRangeBehindSpot(AmountOutParams memory params) internal pure {
        // And: A range on the side of spot the swap moves away from, on ticks.
        if (params.zeroForOne) {
            params.sqrtPriceLower =
                onTickAbove(bound(params.sqrtPriceLower, params.sqrtPrice, Constants.MAX_RANGE_SQRT_PRICE / 2));
            params.sqrtPriceUpper =
                onTickAbove(bound(params.sqrtPriceUpper, params.sqrtPriceLower + 1, Constants.MAX_RANGE_SQRT_PRICE));
        } else {
            params.sqrtPriceUpper =
                onTickBelow(bound(params.sqrtPriceUpper, 2 * Constants.MIN_RANGE_SQRT_PRICE, params.sqrtPrice));
            params.sqrtPriceLower =
                onTickBelow(bound(params.sqrtPriceLower, Constants.MIN_RANGE_SQRT_PRICE, params.sqrtPriceUpper - 1));
        }
    }

    function givenValidIdleTokenOut(AmountOutParams memory params) internal pure {
        // And: Idle tokens holding some tokenOut.
        if (params.zeroForOne) params.idle1 = bound(params.idle1, 1, type(uint128).max / 2);
        else params.idle0 = bound(params.idle0, 1, type(uint128).max / 2);
    }

    function givenValidCrossing(AmountOutParams memory params) internal pure {
        // And: Spot within 2^60 of ranges, a range within a quarter band, no word end
        params.sqrtPrice = uint160(
            bound(params.sqrtPrice, Constants.MIN_RANGE_SQRT_PRICE << 4, Constants.MAX_RANGE_SQRT_PRICE >> 4)
        );
        params.liquidity = uint128(bound(params.liquidity, 1, Constants.MAX_RANGE_LIQUIDITY));
        uint160 edge;
        {
            int24 tick = TickMath.getTickAtSqrtPrice(params.sqrtPrice);
            edge = params.zeroForOne
                ? TickMath.getSqrtPriceAtTick(
                    int24(
                        bound(
                            int256(uint256(params.sqrtPriceUpper)),
                            spacedTickBelow(TickMath.getTickAtSqrtPrice(4 * Constants.MIN_RANGE_SQRT_PRICE))
                                / MOCK_TICK_SPACING + 1,
                            FixedPointMathLib.min(
                                spacedTickBelow(TickMath.getSqrtPriceAtTick(tick) == params.sqrtPrice ? tick - 1 : tick)
                                / MOCK_TICK_SPACING,
                                0
                            )
                        )
                    ) * MOCK_TICK_SPACING
                )
                : TickMath.getSqrtPriceAtTick(
                    int24(
                        bound(
                            int256(uint256(params.sqrtPriceLower)),
                            FixedPointMathLib.max(spacedTickBelow(tick) / MOCK_TICK_SPACING + 1, 0),
                            spacedTickBelow(TickMath.getTickAtSqrtPrice(Constants.MAX_RANGE_SQRT_PRICE / 4))
                                / MOCK_TICK_SPACING
                        )
                    ) * MOCK_TICK_SPACING
                );
        }

        // And: A pool liquidity where twice the move to the edge fits the idle cap.
        uint256 rate = params.zeroForOne
            ? uint256(params.sqrtPrice).fullMulDivUp(params.sqrtPrice, 1 << 192)
            : (uint256(1) << 192).divUp(uint256(params.sqrtPrice) * params.sqrtPrice);
        uint256 cap = params.fee > 0
            ? FixedPointMathLib.min(type(uint128).max, (type(uint128).max / 2 / rate - 3).fullMulDiv(1e6, params.fee))
            : type(uint128).max;
        {
            uint256 liquidityFit = ((cap / 2 - 1).fullMulDiv(1e6 - params.fee, 1e6) - 1)
            .fullMulDiv(
                params.zeroForOne ? uint256(params.sqrtPrice).fullMulDiv(edge, 1 << 96) : 1 << 96,
                params.zeroForOne ? params.sqrtPrice - edge : edge - params.sqrtPrice
            );
            params.poolLiquidity = uint128(
                bound(
                    params.poolLiquidity, 1, FixedPointMathLib.min(type(uint128).max - params.liquidity, liquidityFit)
                )
            );
        }

        // And: A deposit of 2x+ the move to the edge and u + 6, the far edge unreached.
        {
            (uint256 minBalanceIn, uint256 maxBalanceIn) = getBalanceInBounds(depositOf(params));
            maxBalanceIn = FixedPointMathLib.min(
                FixedPointMathLib.min(maxBalanceIn, cap),
                (params.zeroForOne
                        ? SqrtPriceMath.getAmount0Delta(
                            Constants.MIN_RANGE_SQRT_PRICE, params.sqrtPrice, params.poolLiquidity, true
                        )
                        : SqrtPriceMath.getAmount1Delta(
                            params.sqrtPrice, Constants.MAX_RANGE_SQRT_PRICE, params.poolLiquidity, true
                        ))
                .fullMulDivUp(1e6, 1e6 - params.fee)
            );
            minBalanceIn = FixedPointMathLib.max(
                minBalanceIn,
                2
                    * (params.zeroForOne
                            ? SqrtPriceMath.getAmount0Delta(edge, params.sqrtPrice, params.poolLiquidity, true)
                            : SqrtPriceMath.getAmount1Delta(params.sqrtPrice, edge, params.poolLiquidity, true))
                    .fullMulDivUp(1e6, 1e6 - params.fee)
            );
            minBalanceIn += (params.zeroForOne ? uint256(1 << 96).divUp(edge) : uint256(edge).divUp(1 << 96)) + 6;
            params.balanceIn = bound(params.balanceIn, minBalanceIn, maxBalanceIn);
        }
        uint160 sqrtPriceReach = reach(params, params.balanceIn);
        if (params.zeroForOne) {
            params.sqrtPriceUpper = edge;
            int24 tickFar = spacedTickBelow(TickMath.getTickAtSqrtPrice(sqrtPriceReach));
            int24 tickEdge = TickMath.getTickAtSqrtPrice(edge);
            params.sqrtPriceLower = TickMath.getSqrtPriceAtTick(
                int24(
                    bound(
                        int256(uint256(params.sqrtPriceLower)),
                        spacedTickBelow(TickMath.getTickAtSqrtPrice(Constants.MIN_RANGE_SQRT_PRICE))
                            / MOCK_TICK_SPACING,
                        (tickFar < tickEdge ? tickFar : tickEdge - MOCK_TICK_SPACING) / MOCK_TICK_SPACING
                    )
                ) * MOCK_TICK_SPACING
            );
        } else {
            params.sqrtPriceLower = edge;
            params.sqrtPriceUpper = onTickAbove(FixedPointMathLib.max(sqrtPriceReach, uint256(edge) + 1));
        }

        // And: Idle tokenOut only, worth over φ, two wei and the margin 2n + 4 = 6.
        uint256 feeBound = FixedPointMathLib.fullMulDivUp(params.balanceIn, params.fee, 1e6) + 8;
        if (params.zeroForOne) {
            (params.idle0, params.idle1) = (0, bound(params.idle1, feeBound * rate + 1, type(uint128).max / 2));
        } else {
            (params.idle0, params.idle1) = (bound(params.idle0, feeBound * rate + 1, type(uint128).max / 2), 0);
        }
    }

    function givenValidSpotOnATick(AmountOutParams memory params, bool zeroForOne) internal pure {
        // And: Spot on a spaced tick in the band, no bitmap word end in swap direction.
        params.sqrtPrice = TickMath.getSqrtPriceAtTick(
            int24(
                bound(
                    int256(uint256(params.sqrtPrice)),
                    zeroForOne
                        ? spacedTickBelow(TickMath.getTickAtSqrtPrice(2 * Constants.MIN_RANGE_SQRT_PRICE))
                            / MOCK_TICK_SPACING + 1
                        : int256(0),
                    zeroForOne
                        ? int256(0)
                        : spacedTickBelow(TickMath.getTickAtSqrtPrice(Constants.MAX_RANGE_SQRT_PRICE / 2))
                        / MOCK_TICK_SPACING
                )
            ) * MOCK_TICK_SPACING
        );
    }

    function givenValidDepositShortOfTheEdge(AmountOutParams memory params) internal pure {
        // And: A deposit inside the band, the range's edge in its direction out of reach.
        (uint256 minBalanceIn, uint256 maxBalanceIn) = getBalanceInBounds(depositOf(params));
        if (params.zeroForOne) {
            maxBalanceIn = FixedPointMathLib.min(
                maxBalanceIn,
                SqrtPriceMath.getAmount0Delta(
                        Constants.MIN_RANGE_SQRT_PRICE + 1, params.sqrtPrice, params.poolLiquidity, false
                    )
                    .fullMulDiv(1e6, 1e6 - params.fee)
            );
            params.balanceIn = bound(params.balanceIn, minBalanceIn, maxBalanceIn);
            params.sqrtPriceLower = onTickBelow(
                bound(params.sqrtPriceLower, Constants.MIN_RANGE_SQRT_PRICE, reach(params, params.balanceIn) - 1)
            );
        } else {
            maxBalanceIn = FixedPointMathLib.min(
                maxBalanceIn,
                SqrtPriceMath.getAmount1Delta(
                        params.sqrtPrice, Constants.MAX_RANGE_SQRT_PRICE - 1, params.poolLiquidity, false
                    )
                    .fullMulDiv(1e6, 1e6 - params.fee)
            );
            params.balanceIn = bound(params.balanceIn, minBalanceIn, maxBalanceIn);
            params.sqrtPriceUpper = onTickAbove(
                bound(params.sqrtPriceUpper, reach(params, params.balanceIn) + 1, Constants.MAX_RANGE_SQRT_PRICE)
            );
        }
    }

    function depositOf(AmountOutParams memory params) internal pure returns (DepositParams memory deposit) {
        (deposit.zeroForOne, deposit.fee, deposit.liquidity, deposit.sqrtPriceOld) =
        (params.zeroForOne, params.fee, params.poolLiquidity, params.sqrtPrice);
    }

    function reach(AmountOutParams memory params, uint256 amountIn) internal pure returns (uint160 sqrtPriceNew) {
        sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromInput(
            params.sqrtPrice, params.poolLiquidity, amountIn.fullMulDiv(1e6 - params.fee, 1e6), params.zeroForOne
        );
    }

    function getBalanceInBounds(DepositParams memory params)
        internal
        pure
        returns (uint256 minBalanceIn, uint256 maxBalanceIn)
    {
        if (params.zeroForOne) {
            minBalanceIn = FixedPointMathLib.divUp(params.liquidity, uint256(params.sqrtPriceOld) << 84);
            maxBalanceIn = FullMath.mulDiv(params.liquidity, 1 << 156, params.sqrtPriceOld);
        } else {
            minBalanceIn = FixedPointMathLib.divUp(
                FullMath.mulDivRoundingUp(params.liquidity, params.sqrtPriceOld, 1 << 255), 1 << 21
            );
            maxBalanceIn = FullMath.mulDiv(params.liquidity, params.sqrtPriceOld, 1 << 36);
        }
        minBalanceIn = FixedPointMathLib.max(minBalanceIn, 1);
        maxBalanceIn = FixedPointMathLib.min(maxBalanceIn, type(uint128).max);
    }

    function getSegmentEnd(DepositParams memory params) internal pure returns (uint160 sqrtPriceEnd) {
        uint256 liquidity = params.positionLiquidity;
        if (params.zeroForOne) {
            uint256 drop =
                liquidity == 0 ? type(uint256).max : FullMath.mulDiv(params.positionAmount1, 1 << 96, liquidity);
            sqrtPriceEnd = params.sqrtPriceOld - TickMath.MIN_SQRT_PRICE > drop
                ? uint160(params.sqrtPriceOld - drop)
                : TickMath.MIN_SQRT_PRICE;
        } else {
            uint256 numerator = liquidity << 96;
            sqrtPriceEnd = TickMath.MAX_SQRT_PRICE - 1;
            if (params.positionAmount0 < numerator / params.sqrtPriceOld) {
                uint256 end = FullMath.mulDiv(
                    numerator, params.sqrtPriceOld, numerator - params.positionAmount0 * params.sqrtPriceOld
                );
                if (end < sqrtPriceEnd) sqrtPriceEnd = uint160(end);
            }
        }
    }

    function givenValidLimit(MintState memory state, uint256 sqrtPriceLimitX96) internal pure returns (uint256) {
        // And: A limit in the buy's direction, in the band, its root within 2^32 of spot.
        return state.zeroForOne
            ? bound(
                sqrtPriceLimitX96,
                FixedPointMathLib.max(TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK), state.sqrtPriceX96 >> 32),
                state.sqrtPriceX96
            )
            : bound(
                sqrtPriceLimitX96,
                state.sqrtPriceX96,
                FixedPointMathLib.min(
                    TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK), uint256(state.sqrtPriceX96) << 32
                )
            );
    }

    function givenValidWordStartBelowSpot(MintState memory state, RangeState memory range)
        internal
        pure
        returns (int24 tickWord)
    {
        // And: A word start at sqrt prices 2^92 to 2^94, a fee, and tokenOut idle only.
        tickWord =
            (int24(
                        bound(
                            int256(uint256(state.sqrtPriceX96)),
                            TickMath.getTickAtSqrtPrice(uint160(FixedPoint96.Q96 >> 4)) + Constants.BITMAP_WORD_TICKS,
                            TickMath.getTickAtSqrtPrice(uint160(FixedPoint96.Q96 >> 2))
                        )
                    )
                    >> 8) << 8;
        state.fee = uint24(bound(state.fee, 1, Constants.MAX_POOL_FEE));
        state.supply = uint128(bound(state.supply, 1, type(uint64).max));
        (state.idle0, state.idle1) = (0, uint64(bound(state.idle1, type(uint48).max, type(uint64).max)));

        // And: An unstaked range around the word start, its lower edge two words under.
        range.tickLower = int24(
            bound(
                range.tickLower,
                tickWord - 2 * Constants.BITMAP_WORD_TICKS,
                tickWord - Constants.BITMAP_WORD_TICKS - Constants.BITMAP_WORD_TICKS / 4
            )
        );
        range.tickUpper = int24(
            bound(range.tickUpper, tickWord + Constants.BITMAP_WORD_TICKS, tickWord + 4 * Constants.BITMAP_WORD_TICKS)
        );
        range.liquidityStaked = 0;
    }

    function givenValidHalfTokenStepToTheWordStart(MintState memory state, RangeState memory range, int24 tickWord)
        internal
        pure
    {
        // And: A liquidity so small the step to the word start takes under 2^11 tokenIn.
        uint160 wordStart = TickMath.getSqrtPriceAtTick(tickWord);
        range.liquidity = uint128(
            bound(
                range.liquidity, (uint256(1) << 105) / wordStart, (uint256(wordStart) << 17) >> FixedPoint96.RESOLUTION
            )
        );

        // And: Spot in the word's upper half, the step's tokenOut half a token over.
        uint256 liquidity = range.liquidity;
        uint256 steps = bound(
            state.sqrtPriceX96,
            FixedPointMathLib.divUp(
                (TickMath.getSqrtPriceAtTick(tickWord + Constants.BITMAP_WORD_TICKS / 2) - wordStart) * liquidity,
                FixedPoint96.Q96
            ),
            (TickMath.getSqrtPriceAtTick(tickWord + Constants.BITMAP_WORD_TICKS - 1) - wordStart) * liquidity
                / FixedPoint96.Q96 - 1
        );
        state.sqrtPriceX96 =
            wordStart + uint160(FixedPointMathLib.fullMulDiv(2 * steps + 1, FixedPoint96.Q96, 2 * liquidity));
    }

    function givenValidForeignTickAhead(
        MintState memory state,
        RangeState memory range,
        int24 tickForeign,
        bool zeroForOne
    ) internal pure returns (int24) {
        // And: Spot in the band, in the half word the swap leaves.
        int24 half = Constants.BITMAP_WORD_TICKS / 2;
        int24 tickWord =
            (int24(
                        bound(
                            int256(uint256(state.sqrtPriceX96)),
                            TickMath.getTickAtSqrtPrice(Constants.MIN_RANGE_SQRT_PRICE) + Constants.BITMAP_WORD_TICKS,
                            TickMath.getTickAtSqrtPrice(Constants.MAX_RANGE_SQRT_PRICE) - Constants.BITMAP_WORD_TICKS
                        )
                    )
                    >> 8) << 8;
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(zeroForOne ? tickWord + half : tickWord),
                TickMath.getSqrtPriceAtTick(tickWord + (zeroForOne ? 2 * half : half) - 1)
            )
        );
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));
        state.supply = uint128(bound(state.supply, 1, type(uint64).max));

        // And: An unstaked range around spot, its edges outside the word.
        range.tickLower = int24(bound(range.tickLower, tickWord - 4 * Constants.BITMAP_WORD_TICKS, tickWord - 1));
        range.tickUpper = int24(
            bound(range.tickUpper, tickWord + Constants.BITMAP_WORD_TICKS, tickWord + 4 * Constants.BITMAP_WORD_TICKS)
        );
        range.liquidity =
            uint128(bound(range.liquidity, Constants.MIN_DEPOSIT_RANGE_LIQUIDITY, Constants.MAX_RANGE_LIQUIDITY));
        range.liquidityStaked = 0;

        // And: A foreign tick in the word, in the swap's direction.
        return zeroForOne
            ? int24(bound(tickForeign, tickWord, tickWord + half - 1))
            : int24(bound(tickForeign, tickWord + half, tickWord + 2 * half - 1));
    }

    function depositPassingAt(
        MintState memory state,
        RangeState memory range,
        uint160 sqrtPriceEnd,
        uint128 poolLiquidity,
        bool zeroForOne
    ) internal pure returns (uint256 balanceIn) {
        // The deposit whose swap to the price, fee share accrued, ends at the ratio.
        uint256 stepIn = zeroForOne
            ? SqrtPriceMath.getAmount0Delta(sqrtPriceEnd, state.sqrtPriceX96, poolLiquidity, true)
            : SqrtPriceMath.getAmount1Delta(state.sqrtPriceX96, sqrtPriceEnd, poolLiquidity, true);
        uint256 feeAmount = stepIn.fullMulDivUp(state.fee, 1e6 - state.fee);
        uint256 stepOut = zeroForOne
            ? SqrtPriceMath.getAmount1Delta(sqrtPriceEnd, state.sqrtPriceX96, poolLiquidity, false)
            : SqrtPriceMath.getAmount0Delta(state.sqrtPriceX96, sqrtPriceEnd, poolLiquidity, false);
        uint256 feesIn = (feeAmount * 1e10).fullMulDivUp(range.liquidity, 1e10 * uint256(poolLiquidity));
        uint256 amount0 = uint256(state.idle0) + FixedPointMathLib.fullMulDiv(range.liquidity, 1 << 96, sqrtPriceEnd)
            - FixedPointMathLib.fullMulDiv(range.liquidity, 1 << 96, TickMath.getSqrtPriceAtTick(range.tickUpper));
        uint256 amount1 = uint256(state.idle1) + FixedPointMathLib.fullMulDiv(range.liquidity, sqrtPriceEnd, 1 << 96)
            - FixedPointMathLib.fullMulDiv(range.liquidity, TickMath.getSqrtPriceAtTick(range.tickLower), 1 << 96);
        (uint256 positionIn, uint256 positionOut) = zeroForOne ? (amount0, amount1) : (amount1, amount0);

        // The position with its margin 2n + 4 = 6, and the balance margin u + 6.
        balanceIn = stepIn + feeAmount + stepOut.fullMulDiv(positionIn + feesIn + 6, positionOut)
            + (zeroForOne ? uint256(1 << 96).divUp(sqrtPriceEnd) : uint256(sqrtPriceEnd).divUp(1 << 96)) + 6;
    }

    function netOf(AmountOutParams memory params, address pool, uint256 amountOut, bool past)
        internal
        view
        returns (uint256 balanceNet)
    {
        // The end of the step the buy ends in, or the next when it ends on a step's end.
        uint160 sqrtPriceEnd = SqrtPriceMath.getNextSqrtPriceFromOutput(
            params.sqrtPrice, params.poolLiquidity, amountOut, params.zeroForOne
        );
        int24 tick = TickMath.getTickAtSqrtPrice(past == params.zeroForOne ? sqrtPriceEnd - 1 : sqrtPriceEnd);
        (tick,) = MetadexTickBitmap.nextInitializedTickWithinOneWord(pool, tick, MOCK_TICK_SPACING, params.zeroForOne);
        if (tick < TickMath.MIN_TICK) tick = TickMath.MIN_TICK;
        else if (tick > TickMath.MAX_TICK) tick = TickMath.MAX_TICK;
        sqrtPriceEnd = TickMath.getSqrtPriceAtTick(tick);
        if (sqrtPriceEnd == TickMath.MIN_SQRT_PRICE) ++sqrtPriceEnd;
        else if (sqrtPriceEnd == TickMath.MAX_SQRT_PRICE) --sqrtPriceEnd;

        // The balance less the balance margin there, r_in + 3.
        balanceNet = params.balanceIn
            .zeroFloorSub(snapshotLib.getRounding(snapshotOf(params), sqrtPriceEnd, params.zeroForOne) + 3);
    }

    function snapshotOf(MintState memory state, RangeState memory range) internal pure returns (Snapshot memory) {
        RangeState[] memory ranges = new RangeState[](1);
        ranges[0] = range;
        return snapshotOf(pricedOf(ranges), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee);
    }

    function snapshotOf(AmountOutParams memory params) internal pure returns (Snapshot memory snapshot) {
        PricedRange[] memory ranges = new PricedRange[](1);
        ranges[0] = PricedRange({
            liquidity: params.liquidity,
            unstakedLiquidity: params.liquidity,
            sqrtPriceLowerX96: params.sqrtPriceLower,
            sqrtPriceUpperX96: params.sqrtPriceUpper
        });
        snapshot = snapshotOf(ranges, params.idle0, params.idle1, params.supply, params.sqrtPrice, params.fee);
        if (params.zeroForOne && TickMath.getSqrtPriceAtTick(snapshot.tick) == params.sqrtPrice) --snapshot.tick;
    }

    function poolOf(AmountOutParams memory params) internal returns (address pool) {
        pool = poolOf(MOCK_TICK_SPACING, params.poolLiquidity, snapshotOf(params).ranges);
    }

    function onTickBelow(uint256 sqrtPriceX96) internal pure returns (uint160 sqrtPriceTickX96) {
        sqrtPriceTickX96 =
            TickMath.getSqrtPriceAtTick(spacedTickBelow(TickMath.getTickAtSqrtPrice(uint160(sqrtPriceX96))));
    }

    function onTickAbove(uint256 sqrtPriceX96) internal pure returns (uint160 sqrtPriceTickX96) {
        int24 tick = spacedTickBelow(TickMath.getTickAtSqrtPrice(uint160(sqrtPriceX96)));
        sqrtPriceTickX96 = TickMath.getSqrtPriceAtTick(tick);
        if (sqrtPriceTickX96 < sqrtPriceX96) sqrtPriceTickX96 = TickMath.getSqrtPriceAtTick(tick + MOCK_TICK_SPACING);
    }

    function spacedTickBelow(int24 tick) internal pure returns (int24 spacedTick) {
        spacedTick = spacedTickBelow(tick, MOCK_TICK_SPACING);
    }

    function spacedTickBelow(int24 tick, int24 tickSpacing) internal pure returns (int24 spacedTick) {
        spacedTick = tick / tickSpacing * tickSpacing;
        if (spacedTick > tick) spacedTick -= tickSpacing;
    }

    function swapStateOf(DepositParams memory params) internal pure returns (SwapState memory state) {
        // The pool at spot, and the position holding its amounts there.
        (state.sqrtPriceX96, state.fee, state.liquidity) = (params.sqrtPriceOld, params.fee, params.liquidity);
        (state.position.liquidity, state.position.unstakedLiquidity, state.position.sqrtPriceBound) =
        (params.positionLiquidity, params.positionUnstakedLiquidity, params.sqrtPriceBound);
        state.position.constant0 = int256(
            FullMath.mulDiv(params.positionLiquidity, FixedPoint96.Q96, params.sqrtPriceOld)
        ) - int256(params.positionAmount0);
        state.position.constant1 = int256(
            FullMath.mulDiv(params.positionLiquidity, params.sqrtPriceOld, FixedPoint96.Q96)
        ) - int256(params.positionAmount1);
    }

    function withTheMargin(DepositParams memory params) internal pure returns (DepositParams memory) {
        // The position the solve sees: the rounding margin more tokenIn.
        if (params.zeroForOne) params.positionAmount0 += params.roundingMargin;
        else params.positionAmount1 += params.roundingMargin;
        params.roundingMargin = 0;
        return params;
    }

    function getAmountOut(DepositParams memory params) internal view returns (uint256 amountOut) {
        (, amountOut) = optimizationMath.getAmountOut(
            params.zeroForOne, swapStateOf(params), params.balanceIn, params.balanceOut, params.roundingMargin
        );
    }

    function getSqrtPrice(DepositParams memory params) internal view returns (uint160 sqrtPriceNew) {
        sqrtPriceNew = optimizationMath.getSqrtPrice(
            params.zeroForOne, swapStateOf(params), params.balanceIn, params.balanceOut, params.roundingMargin
        );
    }

    function getNormalizedParameters(DepositParams memory params)
        internal
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256)
    {
        SwapState memory state = swapStateOf(params);
        return optimizationMath.getNormalizedParameters(
            params.zeroForOne, state, params.balanceIn, params.balanceOut, state.position, params.roundingMargin
        );
    }

    function positionOf(AmountOutParams memory params, bool movesInto, bool favorTokenIn)
        internal
        pure
        returns (DepositParams memory position)
    {
        position.zeroForOne = params.zeroForOne;
        position.fee = params.fee;
        position.liquidity = params.poolLiquidity;
        position.sqrtPriceOld = params.sqrtPrice;
        position.sqrtPriceBound = params.zeroForOne
            ? (movesInto ? params.sqrtPriceLower : TickMath.MIN_SQRT_PRICE + 1)
            : (movesInto ? params.sqrtPriceUpper : TickMath.MAX_SQRT_PRICE - 1);
        position.positionLiquidity = movesInto ? params.liquidity : 0;
        position.positionUnstakedLiquidity = position.positionLiquidity;
        position.positionAmount0 = params.idle0;
        position.positionAmount1 = params.idle1;

        // The position with the position margin 2n + 4 = 6 of tokenIn.
        if (params.zeroForOne) position.positionAmount0 += 6;
        else position.positionAmount1 += 6;
        position.balanceIn = params.balanceIn;
        position.balanceOut = params.balanceOut;

        // Round tokenOut up and tokenIn down to check tokenIn, the reverse for tokenOut.
        if (params.sqrtPrice == params.sqrtPriceLower) {
            position.positionAmount0 += SqrtPriceMath.getAmount0Delta(
                params.sqrtPriceLower, params.sqrtPriceUpper, params.liquidity, movesInto == favorTokenIn
            );
        } else {
            position.positionAmount1 += SqrtPriceMath.getAmount1Delta(
                params.sqrtPriceLower, params.sqrtPriceUpper, params.liquidity, movesInto == favorTokenIn
            );
        }
    }

    function buy(DepositParams memory params, uint256 amountOut)
        internal
        pure
        returns (uint160 sqrtPriceNew, uint256 amountIn)
    {
        sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            params.sqrtPriceOld, params.liquidity, amountOut, params.zeroForOne
        );
        uint256 feeAmount;
        (, amountIn,, feeAmount) = SwapMath.computeSwapStep(
            params.sqrtPriceOld, sqrtPriceNew, params.liquidity, int256(amountOut), params.fee
        );
        amountIn += feeAmount;
    }

    function crossThePosition(AmountOutParams memory params, address pool, bool movesInto, uint256 amountOut)
        internal
        view
        returns (uint256 amountIn, bool withinBound, bool notShortIn, bool notShortOut)
    {
        // The tokenIn side on the balance net of the margin of the step the buy ends in.
        uint256 balanceIn = params.balanceIn;
        params.balanceIn = netOf(params, pool, amountOut, false);
        (amountIn, withinBound, notShortIn,) = crossThePosition(params, movesInto, amountOut);

        // The tokenOut side net of the next step's margin, for a wei more.
        params.balanceIn = balanceIn;
        params.balanceIn = netOf(params, pool, amountOut, true);
        (,,, notShortOut) = crossThePosition(params, movesInto, amountOut);
        params.balanceIn = balanceIn;
    }

    function crossThePosition(AmountOutParams memory params, bool movesInto, uint256 amountOut)
        internal
        pure
        returns (uint256 amountIn, bool withinBound, bool notShortIn, bool notShortOut)
    {
        DepositParams memory position = positionOf(params, movesInto, true);
        uint160 sqrtPriceOut;
        (sqrtPriceOut, amountIn) = buy(position, amountOut);
        withinBound =
            params.zeroForOne ? sqrtPriceOut >= position.sqrtPriceBound : sqrtPriceOut <= position.sqrtPriceBound;

        uint160 sqrtPriceNext = position.sqrtPriceBound;
        uint256 amountInNext = type(uint256).max;
        if (
            amountOut
                < (params.zeroForOne
                        ? SqrtPriceMath.getAmount1Delta(
                            position.sqrtPriceBound, params.sqrtPrice, params.poolLiquidity, false
                        )
                        : SqrtPriceMath.getAmount0Delta(
                            params.sqrtPrice, position.sqrtPriceBound, params.poolLiquidity, false
                        ))
        ) {
            (sqrtPriceNext, amountInNext) = buy(position, amountOut + 1);
        }
        uint256 window = getWindow(position, sqrtPriceNext);

        if (params.zeroForOne) {
            notShortIn = isNotShort(
                position,
                params.sqrtPrice - sqrtPriceOut > window ? uint160(sqrtPriceOut + window) : params.sqrtPrice,
                true
            );
            position = positionOf(params, movesInto, false);
            notShortOut = sqrtPriceNext - position.sqrtPriceBound <= window || amountInNext > params.balanceIn
                || isNotShort(position, uint160(sqrtPriceNext - window), false);
        } else {
            notShortIn = isNotShort(
                position,
                sqrtPriceOut - params.sqrtPrice > window ? uint160(sqrtPriceOut - window) : params.sqrtPrice,
                true
            );
            position = positionOf(params, movesInto, false);
            notShortOut = position.sqrtPriceBound - sqrtPriceNext <= window || amountInNext > params.balanceIn
                || isNotShort(position, uint160(sqrtPriceNext + window), false);
        }
    }

    function getWindow(DepositParams memory params, uint160 sqrtPriceNew) internal pure returns (uint256 window) {
        uint256 balanceInNormalized = params.zeroForOne
            ? FullMath.mulDiv(params.balanceIn, uint256(params.sqrtPriceOld) << 96, params.liquidity)
            : FullMath.mulDiv(
                FullMath.mulDiv(params.balanceIn, 1 << 128, params.liquidity), 1 << 160, params.sqrtPriceOld
            );
        uint256 relative;
        uint256 scale;
        if (params.zeroForOne) {
            relative = (params.sqrtPriceOld - sqrtPriceNew) >> 96;
            scale = params.sqrtPriceOld;
        } else {
            scale = mulDivRoundingUpSaturating(sqrtPriceNew, sqrtPriceNew, params.sqrtPriceOld);
            relative =
                mulDivRoundingUpSaturating(sqrtPriceNew - params.sqrtPriceOld, sqrtPriceNew, params.sqrtPriceOld) >> 96;
        }
        uint256 absolute;
        if (balanceInNormalized * 5 >= 8 << 192) absolute = scale >> 157;
        else if (balanceInNormalized >= 1 << 192) absolute = scale >> 186;
        else absolute = mulDivRoundingUpSaturating(scale, 64, balanceInNormalized);

        window = absolute > type(uint256).max - relative - 3 ? type(uint256).max : relative + absolute + 3;
    }

    function isNotShort(DepositParams memory params, uint160 sqrtPrice, bool tokenIn)
        internal
        pure
        returns (bool notShort)
    {
        uint256 demandIn;
        uint256 demandOut;
        {
            uint256 slack0;
            uint256 slack1;
            {
                uint256 largest = FixedPointMathLib.max(
                    params.positionLiquidity << 64,
                    FixedPointMathLib.max(
                        FullMath.mulDiv(params.positionAmount0, params.sqrtPriceOld, 1 << 32),
                        FullMath.mulDiv(params.positionAmount1, 1 << 160, params.sqrtPriceOld)
                    )
                );
                slack0 = FixedPointMathLib.divUp(FixedPointMathLib.divUp(largest, 1 << 160), params.sqrtPriceOld) + 1;
                slack1 = FixedPointMathLib.divUp(
                    FixedPointMathLib.divUp(largest, 1 << 192) * params.sqrtPriceOld, 1 << 160
                ) + 1;
            }
            uint256 rise;
            uint256 fall;
            {
                uint128 liquidity = uint128(
                    tokenIn ? FixedPointMathLib.zeroFloorSub(params.positionLiquidity, 1) : params.positionLiquidity
                );
                if (params.zeroForOne) {
                    rise = SqrtPriceMath.getAmount0Delta(sqrtPrice, params.sqrtPriceOld, liquidity, !tokenIn);
                    fall = SqrtPriceMath.getAmount1Delta(sqrtPrice, params.sqrtPriceOld, liquidity, !tokenIn);
                } else {
                    rise = SqrtPriceMath.getAmount1Delta(params.sqrtPriceOld, sqrtPrice, liquidity, !tokenIn);
                    fall = SqrtPriceMath.getAmount0Delta(params.sqrtPriceOld, sqrtPrice, liquidity, !tokenIn);
                }
            }

            // The unstaked liquidity earns its share of f / (1 - f) of rise.
            if (params.positionUnstakedLiquidity > 0) {
                rise += tokenIn
                    ? FullMath.mulDiv(
                        rise * params.fee,
                        params.positionUnstakedLiquidity,
                        (1e6 - params.fee) * params.positionLiquidity
                    )
                    : FullMath.mulDivRoundingUp(
                        rise * params.fee,
                        params.positionUnstakedLiquidity,
                        (1e6 - params.fee) * params.positionLiquidity
                    );
            }

            if (params.zeroForOne) {
                demandIn = tokenIn
                    ? FixedPointMathLib.zeroFloorSub(params.positionAmount0, slack0) + rise
                    : params.positionAmount0 + rise;
                demandOut = tokenIn
                    ? FixedPointMathLib.zeroFloorSub(params.positionAmount1, fall)
                    : FixedPointMathLib.zeroFloorSub(params.positionAmount1, fall + slack1);
            } else {
                demandIn = tokenIn
                    ? FixedPointMathLib.zeroFloorSub(params.positionAmount1, slack1) + rise
                    : params.positionAmount1 + rise;
                demandOut = tokenIn
                    ? FixedPointMathLib.zeroFloorSub(params.positionAmount0, fall)
                    : FixedPointMathLib.zeroFloorSub(params.positionAmount0, fall + slack0);
            }
        }

        uint256 balanceIn;
        uint256 balanceOut;
        {
            uint256 amountInLessFee;
            if (params.zeroForOne) {
                amountInLessFee =
                    SqrtPriceMath.getAmount0Delta(sqrtPrice, params.sqrtPriceOld, params.liquidity, !tokenIn);
                balanceOut = SqrtPriceMath.getAmount1Delta(sqrtPrice, params.sqrtPriceOld, params.liquidity, !tokenIn);
            } else {
                amountInLessFee =
                    SqrtPriceMath.getAmount1Delta(params.sqrtPriceOld, sqrtPrice, params.liquidity, !tokenIn);
                balanceOut = SqrtPriceMath.getAmount0Delta(params.sqrtPriceOld, sqrtPrice, params.liquidity, !tokenIn);
            }
            balanceIn = FixedPointMathLib.zeroFloorSub(
                tokenIn ? params.balanceIn : FixedPointMathLib.zeroFloorSub(params.balanceIn, 2),
                tokenIn
                    ? FullMath.mulDiv(amountInLessFee, 1e6, 1e6 - params.fee)
                    : FullMath.mulDivRoundingUp(amountInLessFee, 1e6, 1e6 - params.fee)
            );
            balanceOut += params.balanceOut;
        }

        (uint256 highIn, uint256 lowIn) = mul512(balanceIn, demandOut);
        (uint256 highOut, uint256 lowOut) = mul512(balanceOut, demandIn);
        notShort = tokenIn
            ? highIn > highOut || (highIn == highOut && lowIn >= lowOut)
            : highOut > highIn || (highOut == highIn && lowOut >= lowIn);
    }

    function givenValidPositionMarginState(
        MarginState memory state,
        RangeState memory range,
        RangeState memory below,
        bool twoRanges
    ) internal view returns (PricedRange[] memory ranges) {
        // And: A spot in the band, a fee, an unstaked fee, a supply and idle token0 only.
        state.sqrtPrice = uint160(
            bound(
                state.sqrtPrice,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 3 * MARGIN_TICK_SPACING),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 2 * MARGIN_TICK_SPACING)
            )
        );
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));
        state.unstakedFee = uint24(bound(state.unstakedFee, 0, Constants.MAX_UNSTAKED_FEE));
        state.supply = bound(state.supply, 1, type(uint128).max);
        (state.idle0, state.idle1) = (bound(state.idle0, 0, type(uint64).max), 0);

        // And: An unstaked range around spot on spaced ticks, the pool's only liquidity.
        int24 spaced = spacedTickBelow(TickMath.getTickAtSqrtPrice(state.sqrtPrice), MARGIN_TICK_SPACING);
        range.tickLower = int24(
            bound(range.tickLower, -Constants.BOUND_TICK + 2 * MARGIN_TICK_SPACING, spaced) / MARGIN_TICK_SPACING
        ) * MARGIN_TICK_SPACING;
        if (TickMath.getSqrtPriceAtTick(range.tickLower) == state.sqrtPrice) range.tickLower -= MARGIN_TICK_SPACING;
        range.tickUpper = int24(bound(range.tickUpper, spaced + MARGIN_TICK_SPACING, Constants.BOUND_TICK))
            / MARGIN_TICK_SPACING * MARGIN_TICK_SPACING;
        (range.liquidity, range.liquidityStaked) = (uint128(bound(range.liquidity, 1, type(uint64).max)), 0);
        state.poolLiquidity = range.liquidity;

        // And: With two ranges, an unstaked one below the first holding token1 alone.
        RangeState[] memory staged = new RangeState[](twoRanges ? 2 : 1);
        staged[0] = range;
        if (twoRanges) {
            below.tickUpper = int24(
                bound(below.tickUpper, -Constants.BOUND_TICK + MARGIN_TICK_SPACING, range.tickLower)
                    / MARGIN_TICK_SPACING
            ) * MARGIN_TICK_SPACING;
            below.tickLower = int24(
                bound(below.tickLower, -Constants.BOUND_TICK, below.tickUpper - MARGIN_TICK_SPACING)
                    / MARGIN_TICK_SPACING
            ) * MARGIN_TICK_SPACING;
            (below.liquidity, below.liquidityStaked) = (uint128(bound(below.liquidity, 1, type(uint64).max)), 0);
            staged[1] = below;
        }
        ranges = pricedOf(staged);
        givenValidMarginDeposit(state, ranges);
    }

    function givenValidMarginDeposit(MarginState memory state, PricedRange[] memory ranges) internal view {
        // And: A token1 deposit past its margin r_in + 3 at spot, the solve normalized.
        DepositParams memory deposit;
        (deposit.liquidity, deposit.sqrtPriceOld) = (state.poolLiquidity, state.sqrtPrice);
        (, uint256 maxBalanceIn) = getBalanceInBounds(deposit);
        state.assets = bound(
            state.assets,
            snapshotLib.getRounding(snapshotOf(ranges, 0, 0, 1, state.sqrtPrice, 0), state.sqrtPrice, false) + 3,
            FixedPointMathLib.min(maxBalanceIn, type(uint64).max)
        );
    }

    function measure(MarginState memory state, PricedRange[] memory ranges)
        internal
        returns (uint256 legIn, uint256 legOut, uint256 stranded, uint256 tolerance)
    {
        Snapshot memory snapshot =
            snapshotOf(ranges, state.idle0, state.idle1, state.supply, state.sqrtPrice, state.fee);

        // The token1 deposit: its shares, its swap's input and output, the core's fees.
        uint160 sqrtPriceNew;
        uint256 shares;
        {
            address pool = poolOf(MARGIN_TICK_SPACING, state.poolLiquidity, ranges);
            vm.mockCall(pool, abi.encodeWithSignature("unstakedFee()"), abi.encode(state.unstakedFee));
            shares = optimizationMath.previewDeposit_(snapshot, pool, false, state.assets);
            (sqrtPriceNew, legIn, legOut,, stranded) = optimizationMath.computeSwap(snapshot, pool, false, state.assets);
        }
        uint256 amountOut = legOut;
        snapshot.buffer1 += stranded;

        // The token1 kept net of rounding, against the cost ratio per token0 bought.
        legIn = state.assets - legIn - snapshotLib.getRounding(snapshot, sqrtPriceNew, false);
        (uint256 cost0, uint256 cost1) =
            snapshotLib.getMintAmounts(snapshot.ranges, sqrtPriceNew, snapshot.buffer0, snapshot.buffer1, 1, 1, false);
        legIn *= cost0 + ranges.length;
        legOut = amountOut * cost1;

        // The token0 the mint of the shares leaves, against the deposit's bound on it.
        (uint256 mint0,) = snapshotLib.getMintAmounts(
            snapshot.ranges, sqrtPriceNew, snapshot.buffer0, snapshot.buffer1, shares, snapshot.supply, false
        );
        stranded = amountOut - mint0;
        tolerance = 2 * snapshotLib.getRounding(snapshot, sqrtPriceNew, true) + cost0.divUp(snapshot.supply)
            + snapshot.ranges.length * (shares.divUp(snapshot.supply) + 1)
            + amountOut.divUp(
                uint256(snapshot.ranges[0].sqrtPriceLowerX96).fullMulDiv(snapshot.ranges[0].sqrtPriceUpperX96, 1 << 96)
            );
    }

    function mul512(uint256 x, uint256 y) internal pure returns (uint256 high, uint256 low) {
        assembly ("memory-safe") {
            let mm := mulmod(x, y, not(0))
            low := mul(x, y)
            high := sub(sub(mm, low), lt(mm, low))
        }
    }

    function mulDivRoundingUpSaturating(uint256 x, uint256 y, uint256 denominator)
        internal
        pure
        returns (uint256 result)
    {
        (uint256 high,) = mul512(x, y);
        if (high >= denominator) return type(uint256).max;
        result = FullMath.mulDiv(x, y, denominator);
        if (result < type(uint256).max && mulmod(x, y, denominator) > 0) result++;
    }
}
