/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PositionManagerLogic_Fuzz_Test } from "./_PositionManagerLogic.fuzz.t.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "mint" of library "PositionManagerLogic".
 */
contract Mint_PositionManagerLogic_Fuzz_Test is PositionManagerLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_mint_MintsAFreshTokenIdToItself(PoolState memory poolState, RangeState memory range)
        public
    {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A caller of the library on the pool's tokens and tick spacing.
        deployPositionManagerLogic();

        // And: The amounts a range's liquidity takes, held by the caller.
        givenValidRangeState(range, poolState, false);
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        token0.mint(address(positionManagerLogic), amount0);
        token1.mint(address(positionManagerLogic), amount1);

        // When: Minting a position with those amounts.
        (uint256 tokenId, uint128 liquidity, TokenDelta delta) =
            positionManagerLogic.mint(range.tickLower, range.tickUpper, amount0, amount1, 0, 0);

        // Then: The caller owns a fresh token id at the range's ticks with its liquidity.
        assertEq(POSITION_MANAGER.ownerOf(tokenId), address(positionManagerLogic));
        (int24 tickLower, int24 tickUpper) = positionTicks(tokenId);
        assertEq(tickLower, range.tickLower);
        assertEq(tickUpper, range.tickUpper);
        assertEq(positionLiquidity(tokenId), liquidity);
        assertEq(liquidity, liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, amount0, amount1));

        // And: The delta takes exactly what the mint consumed.
        assertEq(-int256(delta.amount0()), int256(amount0 - token0.balanceOf(address(positionManagerLogic))));
        assertEq(-int256(delta.amount1()), int256(amount1 - token1.balanceOf(address(positionManagerLogic))));
    }
}
