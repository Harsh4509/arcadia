/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { CLMath_Fuzz_Test } from "./_CLMath.fuzz.t.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getMintAmounts" of library "CLMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetMintAmounts_CLMath_Fuzz_Test is CLMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getMintAmounts_LiquidityPastUint128(
        RangeState memory range,
        uint256 shares,
        uint128 supply,
        uint160 sqrtPriceX96
    ) public {
        // Given: A range holding liquidity.
        givenValidRange(range);
        range.liquidityStaked =
            uint128(bound(range.liquidityStaked, range.liquidity == 0 ? 1 : 0, type(uint128).max - range.liquidity));
        uint256 total = uint256(range.liquidity) + range.liquidityStaked;

        // And: A supply, and shares claiming more of the range than a uint128 holds.
        supply = uint128(bound(supply, 1, type(uint128).max));
        shares = bound(
            shares, FixedPointMathLib.fullMulDiv(type(uint128).max, supply, total) + 1, type(uint256).max / total
        );

        // When: Taking the range's share.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        clMath.getMintAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(range.tickLower),
            TickMath.getSqrtPriceAtTick(range.tickUpper),
            uint256(range.liquidity) + range.liquidityStaked,
            shares,
            supply
        );
    }

    function testFuzz_Success_getMintAmounts_RoundsTheLiquidityAndItsAmountsUp(
        RangeState memory range,
        uint256 shares,
        uint128 supply,
        uint160 sqrtPriceX96
    ) public view {
        // Given: A range, and a price in the band.
        givenValidRange(range);
        sqrtPriceX96 = uint160(
            bound(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );

        // And: A supply, and shares whose claim on the range fits a uint128.
        supply = uint128(bound(supply, 1, type(uint128).max));
        uint256 total = uint256(range.liquidity) + range.liquidityStaked;
        shares = bound(
            shares, 0, total == 0 ? type(uint256).max : FixedPointMathLib.fullMulDiv(type(uint128).max, supply, total)
        );

        // When: Taking the range's share.
        (uint256 amount0, uint256 amount1) = clMath.getMintAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(range.tickLower),
            TickMath.getSqrtPriceAtTick(range.tickUpper),
            uint256(range.liquidity) + range.liquidityStaked,
            shares,
            supply
        );

        // Then: They are the least the manager mints the shares' part from, rounded up.
        assertLeastAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(range.tickLower),
            TickMath.getSqrtPriceAtTick(range.tickUpper),
            FixedPointMathLib.fullMulDivUp(total, shares, supply),
            amount0,
            amount1
        );
    }
}
