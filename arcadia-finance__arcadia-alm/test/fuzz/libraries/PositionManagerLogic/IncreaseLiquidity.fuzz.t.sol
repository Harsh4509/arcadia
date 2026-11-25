/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CLMath } from "../../../../src/shared/libraries/math/CLMath.sol";
import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { PositionManagerLogic_Fuzz_Test } from "./_PositionManagerLogic.fuzz.t.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "increaseLiquidity" of library "PositionManagerLogic".
 */
contract IncreaseLiquidity_PositionManagerLogic_Fuzz_Test is PositionManagerLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_increaseLiquidity_AddsToTheTokenId(
        PoolState memory poolState,
        RangeState memory range,
        uint128 extra
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A caller of the library on the pool's tokens and tick spacing.
        deployPositionManagerLogic();

        // And: A position the caller owns.
        givenValidRangeState(range, poolState, false);
        (uint256 tokenId,) = mintPositionFor(
            pool,
            users.liquidityProvider,
            address(positionManagerLogic),
            range.tickLower,
            range.tickUpper,
            range.liquidity
        );
        uint128 liquidityBefore = positionLiquidity(tokenId);

        // And: The amounts of up to the position's liquidity again, at the caller.
        extra = uint128(bound(extra, Constants.MIN_FUZZED_LIQUIDITY, range.liquidity));
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, extra);
        token0.mint(address(positionManagerLogic), amount0);
        token1.mint(address(positionManagerLogic), amount1);

        // When: Adding those amounts to the position.
        (uint128 liquidity, TokenDelta delta) = positionManagerLogic.increaseLiquidity(tokenId, amount0, amount1, 0, 0);

        // Then: The position grew by the liquidity the amounts buy.
        assertEq(positionLiquidity(tokenId), liquidityBefore + liquidity);
        assertEq(liquidity, liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1));

        // And: The delta takes exactly what the add consumed.
        assertEq(-int256(delta.amount0()), int256(amount0 - token0.balanceOf(address(positionManagerLogic))));
        assertEq(-int256(delta.amount1()), int256(amount1 - token1.balanceOf(address(positionManagerLogic))));
    }

    function testFuzz_Success_increaseLiquidity_TheCoreAmountsBuyTheOwedLiquidityAndAllTheToken1(
        PoolState memory poolState,
        RangeState memory range,
        uint128 owed
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A caller of the library on the pool's tokens and tick spacing.
        deployPositionManagerLogic();

        // And: A position the caller owns.
        givenValidRangeState(range, poolState, false);
        (uint256 tokenId,) = mintPositionFor(
            pool,
            users.liquidityProvider,
            address(positionManagerLogic),
            range.tickLower,
            range.tickUpper,
            range.liquidity
        );

        // And: The core's rounded-up amounts for an owed liquidity, at the caller.
        owed = uint128(bound(owed, 1, range.liquidity));
        uint160 sqrtPriceLower = TickMath.getSqrtPriceAtTick(range.tickLower);
        uint160 sqrtPriceUpper = TickMath.getSqrtPriceAtTick(range.tickUpper);
        (uint256 amount0, uint256 amount1) =
            CLMath.getAmountsForLiquidityRoundingUp(sqrtPriceX96(pool), sqrtPriceLower, sqrtPriceUpper, owed);
        token0.mint(address(positionManagerLogic), amount0);
        token1.mint(address(positionManagerLogic), amount1);

        // When: Adding those amounts to the position.
        (uint128 liquidity,) = positionManagerLogic.increaseLiquidity(tokenId, amount0, amount1, 0, 0);

        // Then: It adds at least the owed liquidity, and takes all the token1.
        assertGe(liquidity, owed);
        assertEq(token1.balanceOf(address(positionManagerLogic)), 0);

        // And: Its token0 covers the liquidity, at most ceil(amount0 / J) under the ask.
        uint160 spot = sqrtPriceX96(pool) < sqrtPriceLower ? sqrtPriceLower : sqrtPriceX96(pool);
        if (spot < sqrtPriceUpper) {
            uint256 used0 = amount0 - token0.balanceOf(address(positionManagerLogic));
            assertGe(used0, SqrtPriceMath.getAmount0Delta(spot, sqrtPriceUpper, owed, true));
            assertLe(amount0 - used0, FixedPointMathLib.divUp(amount0, FullMath.mulDiv(spot, sqrtPriceUpper, 1 << 96)));
        }
    }
}
