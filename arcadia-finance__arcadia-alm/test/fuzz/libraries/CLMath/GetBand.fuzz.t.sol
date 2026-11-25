/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CLMath_Fuzz_Test } from "./_CLMath.fuzz.t.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";

/**
 * @notice Fuzz tests for the function "getBand" of library "CLMath".
 */
contract GetBand_CLMath_Fuzz_Test is CLMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getBand_InsideExactlyWhenTheRatioIsWithinTheDeviation(
        uint160 otherSqrtPriceX96,
        uint160 sqrtPriceX96,
        uint64 deviation
    ) public view {
        // Given: A price, a band as wide as storage holds, and any other price.
        // When: Computing the band.
        (uint256 sqrtPriceLowerX96, uint256 sqrtPriceUpperX96) = clMath.getBand(sqrtPriceX96, deviation);

        // Then: In band exactly when neither price tops the other by more than the ratio.
        assertEq(
            otherSqrtPriceX96 >= sqrtPriceLowerX96 && otherSqrtPriceX96 <= sqrtPriceUpperX96,
            uint256(otherSqrtPriceX96) * (1e18 + uint256(deviation)) >= uint256(sqrtPriceX96) * 1e18
                && uint256(otherSqrtPriceX96) * 1e18 <= uint256(sqrtPriceX96) * (1e18 + uint256(deviation))
        );
    }

    function testFuzz_Success_getBand_SymmetricInRatio(
        uint160 otherSqrtPriceX96,
        uint160 sqrtPriceX96,
        uint64 deviation
    ) public view {
        // Given: Two prices and a band as wide as storage holds.
        // When: Computing the band around each.
        (uint256 sqrtPriceLowerX96, uint256 sqrtPriceUpperX96) = clMath.getBand(sqrtPriceX96, deviation);
        (uint256 otherLowerX96, uint256 otherUpperX96) = clMath.getBand(otherSqrtPriceX96, deviation);

        // Then: Each price is in the band around the other iff the reverse holds.
        assertEq(
            otherSqrtPriceX96 >= sqrtPriceLowerX96 && otherSqrtPriceX96 <= sqrtPriceUpperX96,
            sqrtPriceX96 >= otherLowerX96 && sqrtPriceX96 <= otherUpperX96
        );
    }

    function testFuzz_Success_getBand_LowerRoundsUp(uint160 sqrtPriceX96, uint64 deviation) public view {
        // Given: A price above zero, and a band as wide as storage holds.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, 1, type(uint160).max));

        // When: Computing the band.
        (uint256 sqrtPriceLowerX96,) = clMath.getBand(sqrtPriceX96, deviation);

        // Then: The lower price is the price over the ratio, rounded up.
        assertEq(sqrtPriceLowerX96, FullMath.mulDivRoundingUp(sqrtPriceX96, 1e18, 1e18 + uint256(deviation)));
    }

    function testFuzz_Success_getBand_UpperRoundsDown(uint160 sqrtPriceX96, uint64 deviation) public view {
        // Given: A price, and a band as wide as storage holds.
        // When: Computing the band.
        (, uint256 sqrtPriceUpperX96) = clMath.getBand(sqrtPriceX96, deviation);

        // Then: The upper price is the price times the ratio, rounded down.
        assertEq(sqrtPriceUpperX96, FullMath.mulDiv(sqrtPriceX96, 1e18 + uint256(deviation), 1e18));
    }

    function testFuzz_Success_getBand_ZeroDeviationIsThePrice(uint160 sqrtPriceX96) public view {
        // Given: A price, and a band of zero.
        // When: Computing the band.
        (uint256 sqrtPriceLowerX96, uint256 sqrtPriceUpperX96) = clMath.getBand(sqrtPriceX96, 0);

        // Then: Both ends are the price.
        assertEq(sqrtPriceLowerX96, sqrtPriceX96);
        assertEq(sqrtPriceUpperX96, sqrtPriceX96);
    }
}
