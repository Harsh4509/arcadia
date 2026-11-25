/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { LiquidityAmounts } from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import { PositionManagerLogic_Fuzz_Test } from "./_PositionManagerLogic.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "decreaseLiquidity" of library "PositionManagerLogic".
 */
// forge-lint: disable-next-item(unused-return)
contract DecreaseLiquidity_PositionManagerLogic_Fuzz_Test is PositionManagerLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_decreaseLiquidity_LeavesThePrincipalOwed(
        PoolState memory poolState,
        RangeState memory range,
        uint128 liquidity
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A caller of the library on the pool's tokens and tick spacing.
        deployPositionManagerLogic();

        // And: A position the caller owns, and a part of its liquidity.
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
        liquidity = uint128(bound(liquidity, 1, liquidityBefore));

        // When: Removing that liquidity.
        TokenDelta principal = positionManagerLogic.decreaseLiquidity(tokenId, liquidity, 0, 0);

        // Then: The position shrank by it.
        assertEq(positionLiquidity(tokenId), liquidityBefore - liquidity);

        // And: The principal is that liquidity at the current price, rounded down.
        (uint256 expected0, uint256 expected1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96(pool),
            TickMath.getSqrtPriceAtTick(range.tickLower),
            TickMath.getSqrtPriceAtTick(range.tickUpper),
            liquidity
        );
        assertEq(int256(principal.amount0()), int256(expected0));
        assertEq(int256(principal.amount1()), int256(expected1));

        // And: It is left owed to the token id rather than paid out.
        (uint128 owed0, uint128 owed1) = positionOwed(tokenId);
        assertEq(owed0, expected0);
        assertEq(owed1, expected1);
        assertEq(token0.balanceOf(address(positionManagerLogic)), 0);
        assertEq(token1.balanceOf(address(positionManagerLogic)), 0);
    }
}
