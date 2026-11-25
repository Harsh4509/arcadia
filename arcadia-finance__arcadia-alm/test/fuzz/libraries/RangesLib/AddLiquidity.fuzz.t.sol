/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { RangeAmounts } from "../../../../src/core/types/RangeAmounts.sol";
import { RangesLib } from "../../../../src/core/libraries/state/RangesLib.sol";
import { RangesLib_Fuzz_Test } from "./_RangesLib.fuzz.t.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "addLiquidity" of library "RangesLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract AddLiquidity_RangesLib_Fuzz_Test is RangesLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_addLiquidity_SkipsAFundingOfNoAmounts(PoolState memory poolState, RangeState memory held)
        public
    {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core with a range, and a funding of no amounts.
        deployRangesLib();
        givenValidRangeState(held, poolState, false);
        pushRangeOf(held);
        RangeAmounts[] memory mintAmounts = new RangeAmounts[](1);

        // When: Funding the range.
        TokenDelta delta = rangesLib.addLiquidity(mintAmounts);

        // Then: Nothing is used and the range is untouched.
        assertEq(-int256(delta.amount0()), 0);
        assertEq(-int256(delta.amount1()), 0);
        assertEq(positionLiquidity(rangesLib.getRange(0).unstakedTokenId), held.liquidity);
    }

    function testFuzz_Success_addLiquidity_AddsTheFundingToTheRange(
        PoolState memory poolState,
        RangeState memory range,
        uint128 liquidity
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core with a range.
        deployRangesLib();
        givenValidRangeState(range, poolState, false);
        pushRangeOf(range);

        // And: A funding of a liquidity, the amounts the pool takes desired, in the core.
        liquidity = uint128(bound(liquidity, Constants.MIN_FUZZED_LIQUIDITY, range.liquidity));
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);
        token0.mint(address(rangesLib), amount0);
        token1.mint(address(rangesLib), amount1);
        RangeAmounts[] memory mintAmounts = new RangeAmounts[](1);
        mintAmounts[0] = RangeAmounts({ amount0: amount0, amount1: amount1 });

        // When: Funding the range.
        TokenDelta delta = rangesLib.addLiquidity(mintAmounts);

        // Then: The range's unstaked side grew by the liquidity the amounts buy.
        Range memory funded = rangesLib.getRange(0);
        assertEq(
            positionLiquidity(funded.unstakedTokenId) - range.liquidity,
            liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1)
        );
        assertEq(positionLiquidity(range.unstakedTokenId), positionLiquidity(funded.unstakedTokenId));

        // And: What was used is what the position manager consumed.
        assertEq(-int256(delta.amount0()), int256(amount0 - token0.balanceOf(address(rangesLib))));
        assertEq(-int256(delta.amount1()), int256(amount1 - token1.balanceOf(address(rangesLib))));
    }

    function testFuzz_Success_addLiquidity_AddsAFundingOfEqualAmounts(
        PoolState memory poolState,
        RangeState memory range,
        uint256 amount
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core with a range wholly below the price.
        deployRangesLib();
        {
            int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
            int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
            range.tickLower = int24(bound(range.tickLower, -band + 1, compressed - 2)) * poolState.tickSpacing;
            range.tickUpper = int24(bound(range.tickUpper, range.tickLower / poolState.tickSpacing + 1, compressed - 1))
                * poolState.tickSpacing;
        }
        givenValidRangeState(range, poolState, false);
        pushRangeOf(range);

        // And: Equal amounts of both tokens, its token1 buying the fuzzed liquidity.
        {
            (, uint256 least1) =
                amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
            (, uint256 most1) = amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
            amount = bound(amount, least1, most1);
        }
        token0.mint(address(rangesLib), amount);
        token1.mint(address(rangesLib), amount);
        RangeAmounts[] memory mintAmounts = new RangeAmounts[](1);
        mintAmounts[0] = RangeAmounts({ amount0: amount, amount1: amount });

        // When: Funding the range.
        rangesLib.addLiquidity(mintAmounts);

        // Then: The range's unstaked side grew by the liquidity the amounts buy.
        Range memory funded = rangesLib.getRange(0);
        assertEq(
            positionLiquidity(funded.unstakedTokenId) - range.liquidity,
            liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount, amount)
        );
        assertGt(positionLiquidity(funded.unstakedTokenId), range.liquidity);
    }

    function testFuzz_Success_addLiquidity_AddsEveryFunding(
        PoolState memory poolState,
        RangeState memory first,
        RangeState memory second,
        uint128 liquidity0,
        uint128 liquidity1
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core with two ranges.
        deployRangesLib();
        givenValidRangeState(first, poolState, false);
        pushRangeOf(first);
        givenValidRangeState(second, poolState, false);
        second.index = 1;
        rangesLib.pushRange(stageRange(address(rangesLib), second));

        // And: A funding for each, the amounts the pool takes for its liquidity desired.
        RangeAmounts[] memory mintAmounts = new RangeAmounts[](2);
        liquidity0 = uint128(bound(liquidity0, Constants.MIN_FUZZED_LIQUIDITY, first.liquidity));
        liquidity1 = uint128(bound(liquidity1, Constants.MIN_FUZZED_LIQUIDITY, second.liquidity));
        (mintAmounts[0].amount0, mintAmounts[0].amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), first.tickLower, first.tickUpper, liquidity0);
        (mintAmounts[1].amount0, mintAmounts[1].amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), second.tickLower, second.tickUpper, liquidity1);
        token0.mint(address(rangesLib), mintAmounts[0].amount0 + mintAmounts[1].amount0);
        token1.mint(address(rangesLib), mintAmounts[0].amount1 + mintAmounts[1].amount1);

        // When: Funding both ranges.
        TokenDelta delta = rangesLib.addLiquidity(mintAmounts);

        // Then: Each range's unstaked side grew by the liquidity its amounts buy.
        assertEq(
            positionLiquidity(rangesLib.getRange(0).unstakedTokenId) - first.liquidity,
            liquidityForAmounts(
                sqrtPriceX96(pool), first.tickLower, first.tickUpper, mintAmounts[0].amount0, mintAmounts[0].amount1
            )
        );
        assertEq(
            positionLiquidity(rangesLib.getRange(1).unstakedTokenId) - second.liquidity,
            liquidityForAmounts(
                sqrtPriceX96(pool), second.tickLower, second.tickUpper, mintAmounts[1].amount0, mintAmounts[1].amount1
            )
        );

        // And: What was used is what the position manager consumed over both.
        assertEq(
            -int256(delta.amount0()),
            int256(mintAmounts[0].amount0 + mintAmounts[1].amount0 - token0.balanceOf(address(rangesLib)))
        );
        assertEq(
            -int256(delta.amount1()),
            int256(mintAmounts[0].amount1 + mintAmounts[1].amount1 - token1.balanceOf(address(rangesLib)))
        );
    }
}
