/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { DepositOptimizationMath_Fuzz_Test } from "./_DepositOptimizationMath.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "getSqrtPrice" of library "DepositOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetSqrtPrice_DepositOptimizationMath_Fuzz_Test is DepositOptimizationMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override {
        DepositOptimizationMath_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getSqrtPrice_ZeroForOne_NoToken1(DepositParams memory params) public view {
        // Given: A deposit of token0 and a position on its segment.
        givenValidDepositParams(params, true);

        // And: The position holds no token1, and some token0.
        params.positionAmount1 = 0;
        params.positionAmount0 = bound(params.positionAmount0, 1, type(uint128).max);

        // When: Calling getSqrtPrice().
        uint160 sqrtPriceNew = getSqrtPrice(params);

        // Then: It returns sqrtPriceOld.
        assertEq(sqrtPriceNew, params.sqrtPriceOld);
    }

    function testFuzz_Success_getSqrtPrice_ZeroForOne_LimitAtSpot(DepositParams memory params) public view {
        // Given: A deposit of token0 and a position on its segment.
        givenValidDepositParams(params, true);

        // And: The segment ends at sqrtPriceOld.
        params.sqrtPriceBound = params.sqrtPriceOld;

        // When: Calling getSqrtPrice().
        uint160 sqrtPriceNew = getSqrtPrice(params);

        // Then: It returns sqrtPriceOld.
        assertEq(sqrtPriceNew, params.sqrtPriceOld);
    }

    function testFuzz_Success_getSqrtPrice_ZeroForOne_WithinSegment(DepositParams memory params) public view {
        // Given: A deposit of token0 and a position on its segment.
        givenValidDepositParams(params, true);

        // When: Calling getSqrtPrice().
        uint160 sqrtPriceNew = getSqrtPrice(params);

        // Then: sqrtPriceNew lies between sqrtPriceBound and sqrtPriceOld.
        assertLe(sqrtPriceNew, params.sqrtPriceOld);
        assertGe(sqrtPriceNew, params.sqrtPriceBound);
    }

    function testFuzz_Success_getSqrtPrice_ZeroForOne_CrossingWithinPrecision(DepositParams memory params) public view {
        // Given: A deposit of token0 and a position on its segment.
        givenValidDepositParams(params, true);

        // When: Calling getSqrtPrice().
        uint160 sqrtPriceNew = getSqrtPrice(params);

        // Then: If it buys, token0 is not short a window of Δk + 3 before sqrtPriceNew.
        params = withTheMargin(params);
        uint256 window = getWindow(params, sqrtPriceNew);
        uint160 sqrtPriceBefore =
            params.sqrtPriceOld - sqrtPriceNew > window ? uint160(sqrtPriceNew + window) : params.sqrtPriceOld;
        if (sqrtPriceNew != params.sqrtPriceOld) assertTrue(isNotShort(params, sqrtPriceBefore, true));

        // And: token1 is not short the same window past it, unless beyond the segment.
        if (sqrtPriceNew - params.sqrtPriceBound > window) {
            assertTrue(isNotShort(params, uint160(sqrtPriceNew - window), false));
        }
    }

    function testFuzz_Success_getSqrtPrice_OneForZero_NoToken0(DepositParams memory params) public view {
        // Given: A deposit of token1 and a position on its segment.
        givenValidDepositParams(params, false);

        // And: The position holds no token0, and some token1.
        params.positionAmount0 = 0;
        params.positionAmount1 = bound(params.positionAmount1, 1, type(uint128).max);

        // When: Calling getSqrtPrice().
        uint160 sqrtPriceNew = getSqrtPrice(params);

        // Then: It returns sqrtPriceOld.
        assertEq(sqrtPriceNew, params.sqrtPriceOld);
    }

    function testFuzz_Success_getSqrtPrice_OneForZero_LimitAtSpot(DepositParams memory params) public view {
        // Given: A deposit of token1 and a position on its segment.
        givenValidDepositParams(params, false);

        // And: The segment ends at sqrtPriceOld.
        params.sqrtPriceBound = params.sqrtPriceOld;

        // When: Calling getSqrtPrice().
        uint160 sqrtPriceNew = getSqrtPrice(params);

        // Then: It returns sqrtPriceOld.
        assertEq(sqrtPriceNew, params.sqrtPriceOld);
    }

    function testFuzz_Success_getSqrtPrice_OneForZero_WithinSegment(DepositParams memory params) public view {
        // Given: A deposit of token1 and a position on its segment.
        givenValidDepositParams(params, false);

        // When: Calling getSqrtPrice().
        uint160 sqrtPriceNew = getSqrtPrice(params);

        // Then: sqrtPriceNew lies between sqrtPriceOld and sqrtPriceBound.
        assertGe(sqrtPriceNew, params.sqrtPriceOld);
        assertLe(sqrtPriceNew, params.sqrtPriceBound);
    }

    function testFuzz_Success_getSqrtPrice_OneForZero_CrossingWithinPrecision(DepositParams memory params) public view {
        // Given: A deposit of token1 and a position on its segment.
        givenValidDepositParams(params, false);

        // When: Calling getSqrtPrice().
        uint160 sqrtPriceNew = getSqrtPrice(params);

        // Then: If it buys, token1 is not short a window of Δk + 3 before sqrtPriceNew.
        params = withTheMargin(params);
        uint256 window = getWindow(params, sqrtPriceNew);
        uint160 sqrtPriceBefore =
            sqrtPriceNew - params.sqrtPriceOld > window ? uint160(sqrtPriceNew - window) : params.sqrtPriceOld;
        if (sqrtPriceNew != params.sqrtPriceOld) assertTrue(isNotShort(params, sqrtPriceBefore, true));

        // And: token0 is not short the same window past it, unless beyond the segment.
        if (params.sqrtPriceBound - sqrtPriceNew > window) {
            assertTrue(isNotShort(params, uint160(sqrtPriceNew + window), false));
        }
    }
}
