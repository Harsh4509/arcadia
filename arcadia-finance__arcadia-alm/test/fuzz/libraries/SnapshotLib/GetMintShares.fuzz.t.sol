/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SnapshotLib_Fuzz_Test } from "./_SnapshotLib.fuzz.t.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getMintShares" of library "SnapshotLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetMintShares_SnapshotLib_Fuzz_Test is SnapshotLib_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getMintShares_NothingToCover(
        uint256 supply,
        uint160 sqrtPriceX96,
        uint256 amount0,
        uint256 amount1,
        bool zeroForOne
    ) public view {
        // Given: No ranges, nothing idle, and a price in the pool's range.
        RangeState[] memory ranges = new RangeState[](0);
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // When: Calculating the shares.
        uint256 shares =
            snapshotLib.getMintShares(pricedOf(ranges), 0, 0, supply, sqrtPriceX96, amount0, amount1, zeroForOne);

        // Then: It covers no shares.
        assertEq(shares, 0);
    }

    function testFuzz_Success_getMintShares_FitsTheTighterLeg(
        uint128 idle0,
        uint128 idle1,
        uint128 supply,
        uint160 sqrtPriceX96,
        uint128 amount0,
        uint128 amount1,
        bool zeroForOne
    ) public view {
        // Given: No ranges, both tokens idle, and a price in the pool's range.
        RangeState[] memory ranges = new RangeState[](0);
        idle0 = uint128(bound(idle0, 1, type(uint128).max));
        idle1 = uint128(bound(idle1, 1, type(uint128).max));
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // When: Calculating the shares of both tokens.
        uint256 shares = snapshotLib.getMintShares(
            pricedOf(ranges), idle0, idle1, supply, sqrtPriceX96, amount0, amount1, zeroForOne
        );

        // Then: It covers what the tighter leg fits, after a wei of headroom on each.
        uint256 fit0 = amount0 > 1 ? uint256(amount0 - 1) * supply / idle0 : 0;
        uint256 fit1 = amount1 > 1 ? uint256(amount1 - 1) * supply / idle1 : 0;
        assertEq(shares, fit0 < fit1 ? fit0 : fit1);
    }

    function testFuzz_Success_getMintShares_NothingPastTheHeadroom(
        uint128 idle0,
        uint128 idle1,
        uint128 supply,
        uint160 sqrtPriceX96,
        uint256 amount0,
        uint256 amount1,
        bool zeroForOne
    ) public view {
        // Given: No ranges, both tokens idle, and a price in the pool's range.
        RangeState[] memory ranges = new RangeState[](0);
        idle0 = uint128(bound(idle0, 1, type(uint128).max));
        idle1 = uint128(bound(idle1, 1, type(uint128).max));
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // And: Balances no larger than the wei of headroom on each leg.
        amount0 = bound(amount0, 0, 1);
        amount1 = bound(amount1, 0, 1);

        // When: Calculating the shares.
        uint256 shares = snapshotLib.getMintShares(
            pricedOf(ranges), idle0, idle1, supply, sqrtPriceX96, amount0, amount1, zeroForOne
        );

        // Then: It covers no shares.
        assertEq(shares, 0);
    }

    function testFuzz_Success_getMintShares_Token0LegOnly(
        uint128 idle0,
        uint128 supply,
        uint160 sqrtPriceX96,
        uint128 amount0,
        uint256 amount1,
        bool zeroForOne
    ) public view {
        // Given: No ranges, only token0 idle, and a price in the pool's range.
        RangeState[] memory ranges = new RangeState[](0);
        idle0 = uint128(bound(idle0, 1, type(uint128).max));
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // When: Calculating the shares of both tokens.
        uint256 shares =
            snapshotLib.getMintShares(pricedOf(ranges), idle0, 0, supply, sqrtPriceX96, amount0, amount1, zeroForOne);

        // Then: Only the token0 leg is fitted.
        assertEq(shares, amount0 > 1 ? uint256(amount0 - 1) * supply / idle0 : 0);
    }

    function testFuzz_Success_getMintShares_Token1LegOnly(
        uint128 idle1,
        uint128 supply,
        uint160 sqrtPriceX96,
        uint256 amount0,
        uint128 amount1,
        bool zeroForOne
    ) public view {
        // Given: No ranges, only token1 idle, and a price in the pool's range.
        RangeState[] memory ranges = new RangeState[](0);
        idle1 = uint128(bound(idle1, 1, type(uint128).max));
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // When: Calculating the shares of both tokens.
        uint256 shares =
            snapshotLib.getMintShares(pricedOf(ranges), 0, idle1, supply, sqrtPriceX96, amount0, amount1, zeroForOne);

        // Then: Only the token1 leg is fitted.
        assertEq(shares, amount1 > 1 ? uint256(amount1 - 1) * supply / idle1 : 0);
    }

    function testFuzz_Success_getMintShares_CostsEveryRange(
        RangeState memory range0,
        RangeState memory range1,
        uint128 idle0,
        uint128 idle1,
        uint128 supply,
        uint160 sqrtPriceX96,
        uint128 amount0,
        uint128 amount1,
        bool zeroForOne
    ) public view {
        // Given: Two ranges, each idle over the 2 wei off its cost, a price in the band.
        givenValidRange(range0);
        givenValidRange(range1);
        RangeState[] memory ranges = new RangeState[](2);
        (ranges[0], ranges[1]) = (range0, range1);
        idle0 = uint128(bound(idle0, 3, type(uint128).max));
        idle1 = uint128(bound(idle1, 3, type(uint128).max));
        sqrtPriceX96 = uint160(
            bound(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );
        supply = uint128(bound(supply, 1, type(uint128).max));

        // And: Balances of both tokens no larger than what is idle.
        amount0 = uint128(bound(amount0, 0, idle0));
        amount1 = uint128(bound(amount1, 0, idle1));

        uint256 cost0;
        uint256 cost1;
        {
            // When: Calculating the shares.
            uint256 shares = snapshotLib.getMintShares(
                pricedOf(ranges), idle0, idle1, supply, sqrtPriceX96, amount0, amount1, zeroForOne
            );

            // Then: A mint of those shares costs no more than the balance on either leg.
            (cost0, cost1) =
                snapshotLib.getMintAmounts(pricedOf(ranges), sqrtPriceX96, idle0, idle1, shares, supply, zeroForOne);
            assertLe(cost0, amount0);
            assertLe(cost1, amount1);

            // And: A mint past them by the headroom costs more than one leg's balance.
            (cost0, cost1) =
                snapshotLib.getMintAmounts(pricedOf(ranges), sqrtPriceX96, idle0, idle1, supply, supply, zeroForOne);
            {
                Snapshot memory snapshot;
                snapshot.ranges = pricedOf(ranges);
                cost0 = shares + 1
                    + (snapshotLib.getRounding(snapshot, sqrtPriceX96, true) + 7).fullMulDivUp(supply, cost0 - 2);
                cost1 = shares + 1
                    + (snapshotLib.getRounding(snapshot, sqrtPriceX96, false) + 7).fullMulDivUp(supply, cost1 - 2);
            }
        }
        assertTrue(
            mintCost(ranges, sqrtPriceX96, idle0, idle1, cost0, supply, zeroForOne, true) > amount0
                || mintCost(ranges, sqrtPriceX96, idle0, idle1, cost1, supply, zeroForOne, false) > amount1
        );
    }

    function testFuzz_Success_getMintShares_TheScarcerLegOverEveryRangesCost(
        RangeState memory range0,
        RangeState memory range1,
        uint64 idle0,
        uint64 idle1,
        uint128 supply,
        uint160 sqrtPriceX96,
        uint128 amount0,
        uint128 amount1,
        bool zeroForOne
    ) public view {
        // Given: A price in the band, two ranges around it, both tokens idle.
        sqrtPriceX96 = uint160(
            bound(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 1),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 1)
            )
        );
        uint256 shares;
        {
            int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
            range0.tickLower = int24(bound(range0.tickLower, -Constants.BOUND_TICK, tick));
            range0.tickUpper = int24(bound(range0.tickUpper, tick + 1, Constants.BOUND_TICK));
            range1.tickLower = int24(bound(range1.tickLower, -Constants.BOUND_TICK, tick));
            range1.tickUpper = int24(bound(range1.tickUpper, tick + 1, Constants.BOUND_TICK));
            range0.liquidity = uint128(bound(range0.liquidity, 1, type(uint64).max));
            range1.liquidity = uint128(bound(range1.liquidity, 1, type(uint64).max));
            (range0.liquidityStaked, range1.liquidityStaked) = (0, 0);
            RangeState[] memory ranges = new RangeState[](2);
            (ranges[0], ranges[1]) = (range0, range1);
            supply = uint128(bound(supply, 1, type(uint128).max));

            // When: Calculating the shares the balances mint.
            shares = snapshotLib.getMintShares(
                pricedOf(ranges), idle0, idle1, supply, sqrtPriceX96, amount0, amount1, zeroForOne
            );
        }

        // Then: The scarcer leg's balance less rounding, over the supply's cost.
        uint256 shares0;
        {
            uint256 upper0 = TickMath.getSqrtPriceAtTick(range0.tickUpper);
            uint256 upper1 = TickMath.getSqrtPriceAtTick(range1.tickUpper);
            uint256 cost0 = uint256(idle0) + (zeroForOne ? 2 : 0)
                + FullMath.mulDivRoundingUp(
                    range0.liquidity, upper0 - sqrtPriceX96, FullMath.mulDiv(sqrtPriceX96, upper0, 1 << 96)
                )
                + FullMath.mulDivRoundingUp(
                    range1.liquidity, upper1 - sqrtPriceX96, FullMath.mulDiv(sqrtPriceX96, upper1, 1 << 96)
                );
            shares0 = FullMath.mulDiv(
                FixedPointMathLib.zeroFloorSub(amount0, 2 * (FixedPointMathLib.divUp(1 << 96, sqrtPriceX96) + 2) + 1),
                supply,
                cost0
            );
        }
        uint256 cost1 = uint256(idle1) + (zeroForOne ? 0 : 2)
            + SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtPriceAtTick(range0.tickLower), sqrtPriceX96, range0.liquidity, true
            )
            + SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtPriceAtTick(range1.tickLower), sqrtPriceX96, range1.liquidity, true
            );
        uint256 shares1 = FullMath.mulDiv(
            FixedPointMathLib.zeroFloorSub(amount1, 2 * (FixedPointMathLib.divUp(sqrtPriceX96, 1 << 96) + 2) + 1),
            supply,
            cost1
        );
        assertEq(shares, FixedPointMathLib.min(shares0, shares1));
    }
}
