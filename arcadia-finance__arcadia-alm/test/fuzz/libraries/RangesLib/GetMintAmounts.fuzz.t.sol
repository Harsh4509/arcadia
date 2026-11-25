/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Range } from "../../../../src/core/types/Range.sol";
import { RangeAmounts } from "../../../../src/core/types/RangeAmounts.sol";
import { RangesLib_Fuzz_Test } from "./_RangesLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getMintAmounts" of library "RangesLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetMintAmounts_RangesLib_Fuzz_Test is RangesLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getMintAmounts_NoRanges(
        PoolState memory poolState,
        uint160 sqrtPriceX96,
        uint256 shares,
        uint256 supply
    ) public {
        // Given: A pool with depth at a fuzzed price, and no ranges.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // When: Taking every range's share of a mint.
        (uint256 amount0Desired, uint256 amount1Desired, RangeAmounts[] memory mintAmounts) =
            rangesLib.getMintAmounts(liquidities(), sqrtPriceX96, shares, supply);

        // Then: Both amounts desired are zero and there is nothing to fund.
        assertEq(amount0Desired, 0);
        assertEq(amount1Desired, 0);
        assertEq(mintAmounts.length, 0);
    }

    function testFuzz_Success_getMintAmounts_SumsEveryRange(
        PoolState memory poolState,
        RangeState memory first,
        RangeState memory second,
        uint128 shares,
        uint128 supply,
        uint160 sqrtPriceX96
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: Two ranges, each with liquidity on either side.
        givenValidRangeState(first, poolState, false);
        pushRangeOf(first);
        givenValidRangeState(second, poolState, false);
        pushRangeOf(second);

        // And: A price on the curve, and a mint up to the supply, shares fit a uint128.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        supply = uint128(bound(supply, 1, type(uint128).max));
        shares = uint128(bound(shares, 0, supply));

        // When: Taking every range's share of the mint.
        RangeAmounts[] memory mintAmounts;
        {
            uint256 amount0Desired;
            uint256 amount1Desired;
            (amount0Desired, amount1Desired, mintAmounts) =
                rangesLib.getMintAmounts(liquidities(), sqrtPriceX96, shares, supply);

            // Then: The totals are the amounts every range desires.
            assertEq(amount0Desired, mintAmounts[0].amount0 + mintAmounts[1].amount0);
            assertEq(amount1Desired, mintAmounts[0].amount1 + mintAmounts[1].amount1);
        }

        // And: The first range is owed the least amounts minting its share rounded up.
        assertLeastAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(first.tickLower),
            TickMath.getSqrtPriceAtTick(first.tickUpper),
            ((uint256(first.liquidity) + first.liquidityStaked) * shares + supply - 1) / supply,
            mintAmounts[0].amount0,
            mintAmounts[0].amount1
        );

        // And: So is the second.
        assertLeastAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(second.tickLower),
            TickMath.getSqrtPriceAtTick(second.tickUpper),
            ((uint256(second.liquidity) + second.liquidityStaked) * shares + supply - 1) / supply,
            mintAmounts[1].amount0,
            mintAmounts[1].amount1
        );
    }
}
