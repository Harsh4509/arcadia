/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { RangesLibExtension } from "../../../utils/extensions/RangesLibExtension.sol";
import { SnapshotLib_Fuzz_Test } from "./_SnapshotLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getMintAmounts" of library "SnapshotLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetMintAmounts_SnapshotLib_Fuzz_Test is SnapshotLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getMintAmounts_IdleOnly(
        uint160 sqrtPriceX96,
        uint128 idle0,
        uint128 idle1,
        uint128 shares,
        uint128 supply,
        bool zeroForOne
    ) public view {
        // Given: No ranges, and tokens idle beside them.
        RangeState[] memory ranges = new RangeState[](0);

        // And: A supply and a mint of any size against it.
        supply = uint128(bound(supply, 1, type(uint128).max));

        // When: Costing the mint for a buy in either direction.
        (uint256 cost0, uint256 cost1) =
            snapshotLib.getMintAmounts(pricedOf(ranges), sqrtPriceX96, idle0, idle1, shares, supply, zeroForOne);

        // Then: It costs the shares' part of what is idle, rounded up.
        assertEq(cost0, (uint256(idle0) * shares + supply - 1) / supply);
        assertEq(cost1, (uint256(idle1) * shares + supply - 1) / supply);
    }

    function testFuzz_Success_getMintAmounts_RangesAndIdle(
        RangeState memory range,
        uint160 sqrtPriceX96,
        uint128 idle0,
        uint128 idle1,
        uint128 shares,
        uint128 supply,
        bool zeroForOne
    ) public view {
        // Given: A range, and a price in the band.
        givenValidRange(range);
        RangeState[] memory ranges = new RangeState[](1);
        ranges[0] = range;
        sqrtPriceX96 = uint160(
            bound(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );

        // And: A mint no larger than the supply, so the range's share fits a uint128.
        supply = uint128(bound(supply, 1, type(uint128).max));
        shares = uint128(bound(shares, 0, supply));

        // When: Costing the mint for a buy in either direction.
        (uint256 cost0, uint256 cost1) =
            snapshotLib.getMintAmounts(pricedOf(ranges), sqrtPriceX96, idle0, idle1, shares, supply, zeroForOne);

        // Then: The range's share, the idle's part, and a wei per range on tokenIn.
        cost0 -= ((uint256(idle0) + (zeroForOne ? 1 : 0)) * shares + supply - 1) / supply;
        cost1 -= ((uint256(idle1) + (zeroForOne ? 0 : 1)) * shares + supply - 1) / supply;
        uint256 liquidity = ((uint256(range.liquidity) + range.liquidityStaked) * shares + supply - 1) / supply;
        assertLeastAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(range.tickLower),
            TickMath.getSqrtPriceAtTick(range.tickUpper),
            liquidity,
            cost0,
            cost1
        );
    }

    function testFuzz_Success_getMintAmounts_IsTheCorePullAndAWeiPerRangeOnTokenIn(
        RangeState[3] memory fuzzed,
        uint160 sqrtPriceX96,
        uint128 shares,
        uint128 supply,
        bool zeroForOne
    ) public {
        // Given: Three ranges, stored as the core stores them, and a price in the band.
        RangesLibExtension coreRanges = new RangesLibExtension(
            address(1), address(0), address(0), address(0), address(token0), address(token1), 1
        );
        RangeState[] memory ranges = new RangeState[](3);
        uint128[] memory positionLiquidity = new uint128[](3);
        for (uint256 i; i < 3; ++i) {
            givenValidRange(fuzzed[i]);
            ranges[i] = fuzzed[i];
            positionLiquidity[i] = fuzzed[i].liquidity;
            coreRanges.pushRange(
                Range({
                    stakedLiquidity: fuzzed[i].liquidityStaked,
                    tickLower: fuzzed[i].tickLower,
                    tickUpper: fuzzed[i].tickUpper,
                    unstakedTokenId: 0,
                    stakedTokenId: 0,
                    stakedBlock: 0
                })
            );
        }
        sqrtPriceX96 = uint160(
            bound(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );

        // And: A mint no larger than the supply.
        supply = uint128(bound(supply, 1, type(uint128).max));
        shares = uint128(bound(shares, 0, supply));

        // When: Costing the mint for a buy in either direction, nothing idle.
        (uint256 cost0, uint256 cost1) =
            snapshotLib.getMintAmounts(pricedOf(ranges), sqrtPriceX96, 0, 0, shares, supply, zeroForOne);

        // Then: The core's pro-rata amounts, plus a wei per range pro rata on tokenIn.
        (uint256 pull0, uint256 pull1,) = coreRanges.getMintAmounts(positionLiquidity, sqrtPriceX96, shares, supply);
        uint256 margin = (3 * uint256(shares) + supply - 1) / supply;
        assertEq(cost0, zeroForOne ? pull0 + margin : pull0);
        assertEq(cost1, zeroForOne ? pull1 : pull1 + margin);
    }

    function testFuzz_Success_getMintAmounts_AddsLiquidityAlongTheBuysFirstStep(
        RangeState memory range,
        uint128 shares,
        uint128 supply,
        bool zeroForOne,
        bool onLowerEdge
    ) public view {
        // Given: A range, and a price on one of its edges.
        givenValidRange(range);
        RangeState[] memory ranges = new RangeState[](1);
        ranges[0] = range;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(onLowerEdge ? range.tickLower : range.tickUpper);

        // And: A supply and a mint of at most it.
        supply = uint128(bound(supply, 1, type(uint128).max));
        shares = uint128(bound(shares, 0, supply));

        // When: Costing the mint for a buy in either direction.
        uint256 activeLiquidityDelta =
            snapshotLib.getMintLiquidityDelta(pricedOf(ranges), sqrtPriceX96, shares, supply, zeroForOne);

        // Then: The minted liquidity, rounded up, only if the buy moves into it.
        uint256 rangeLiquidity = uint256(range.liquidity) + range.liquidityStaked;
        uint256 minted = (rangeLiquidity * shares + supply - 1) / supply;
        assertEq(activeLiquidityDelta, zeroForOne == onLowerEdge ? 0 : minted);
    }

    function testFuzz_Success_getMintAmounts_AddsTheLiquidityOfTheRangesAroundThePrice(
        RangeState[4] memory fuzzed,
        uint160 sqrtPriceX96,
        uint128 shares,
        uint128 supply,
        bool zeroForOne
    ) public view {
        // Given: A price in the band, a tick clear of its ends.
        sqrtPriceX96 = uint160(
            bound(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 2),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 2)
            )
        );
        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        // And: Two ranges around the price, one wholly above and one wholly below it.
        RangeState[] memory ranges = new RangeState[](4);
        for (uint256 i; i < 4; ++i) {
            ranges[i] = fuzzed[i];
            ranges[i].liquidity = uint128(bound(ranges[i].liquidity, 1, type(uint64).max));
            ranges[i].liquidityStaked = uint128(bound(ranges[i].liquidityStaked, 0, type(uint64).max));
            if (i < 2) {
                ranges[i].tickLower = int24(bound(ranges[i].tickLower, -Constants.BOUND_TICK, tick - 1));
                ranges[i].tickUpper = int24(bound(ranges[i].tickUpper, tick + 1, Constants.BOUND_TICK));
            }
        }
        ranges[2].tickLower = int24(bound(ranges[2].tickLower, tick + 1, Constants.BOUND_TICK - 1));
        ranges[2].tickUpper = int24(bound(ranges[2].tickUpper, ranges[2].tickLower + 1, Constants.BOUND_TICK));
        ranges[3].tickUpper = int24(bound(ranges[3].tickUpper, -Constants.BOUND_TICK + 1, tick - 1));
        ranges[3].tickLower = int24(bound(ranges[3].tickLower, -Constants.BOUND_TICK, ranges[3].tickUpper - 1));

        // And: A supply and at most it in shares.
        supply = uint128(bound(supply, 1, type(uint128).max));
        shares = uint128(bound(shares, 0, supply));

        // When: Costing the mint for a buy in either direction.
        uint256 activeLiquidityDelta =
            snapshotLib.getMintLiquidityDelta(pricedOf(ranges), sqrtPriceX96, shares, supply, zeroForOne);

        // Then: It adds the minted liquidity, rounded up, of the ranges around it only.
        uint256 liquidity0 = uint256(ranges[0].liquidity) + ranges[0].liquidityStaked;
        uint256 liquidity1 = uint256(ranges[1].liquidity) + ranges[1].liquidityStaked;
        assertEq(
            activeLiquidityDelta,
            FullMath.mulDivRoundingUp(liquidity0, shares, supply)
                + FullMath.mulDivRoundingUp(liquidity1, shares, supply)
        );
    }
}
