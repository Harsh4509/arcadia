/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import {
    INonfungiblePositionManager
} from "../../../utils/fixtures/metadex/interfaces/INonfungiblePositionManager.sol";
import { PositionManagerLogic_Fuzz_Test } from "./_PositionManagerLogic.fuzz.t.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "collect" of library "PositionManagerLogic".
 */
// forge-lint: disable-next-item(unused-return)
contract Collect_PositionManagerLogic_Fuzz_Test is PositionManagerLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_collect_CollectsEverythingOwed(
        PoolState memory poolState,
        RangeState memory range,
        uint128 liquidity,
        uint256 amountIn
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A caller of the library on the pool's tokens and tick spacing.
        deployPositionManagerLogic();

        // And: A position the caller owns that earned swap fees.
        givenValidRangeState(range, poolState, false);
        (uint256 tokenId,) = mintPositionFor(
            pool,
            users.liquidityProvider,
            address(positionManagerLogic),
            range.tickLower,
            range.tickUpper,
            range.liquidity
        );
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            feeEarningTrade(pool, range.liquidity, amountIn, true)
        );

        // And: Part of its liquidity removed, its principal left owed.
        liquidity = uint128(bound(liquidity, 1, positionLiquidity(tokenId)));
        vm.prank(address(positionManagerLogic));
        POSITION_MANAGER.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId, liquidity: liquidity, amount0Min: 0, amount1Min: 0, deadline: vm.getBlockTimestamp()
            })
        );

        // When: Collecting the position.
        TokenDelta gross = positionManagerLogic.collect(tokenId);

        // Then: The caller received what was collected.
        assertEq(int256(gross.amount0()), int256(token0.balanceOf(address(positionManagerLogic))));
        assertEq(int256(gross.amount1()), int256(token1.balanceOf(address(positionManagerLogic))));

        // And: Nothing is left owed to the token id.
        (uint128 owed0, uint128 owed1) = positionOwed(tokenId);
        assertEq(owed0, 0);
        assertEq(owed1, 0);
    }
}
