/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { EquivalentPosition } from "../../../../src/vaults/types/EquivalentPosition.sol";
import { IALMCore } from "../../../../src/interfaces/IALMCore.sol";
import { PoolMock } from "../../../utils/mocks/PoolMock.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { Snapshot, SnapshotLib } from "../../../../src/vaults/types/Snapshot.sol";
import { SwapState } from "../../../../src/vaults/types/SwapState.sol";
import { SwapStateLib_Fuzz_Test } from "./_SwapStateLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getSwapState" of library "SwapStateLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetSwapState_SwapStateLib_Fuzz_Test is SwapStateLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getSwapState_StartsAtThePoolsStateAndTheCoresPosition(
        uint160 sqrtPriceX96,
        uint24 fee,
        int24 tickSpacing,
        uint128 liquidity,
        uint64 buffer0,
        uint64 buffer1,
        bool zeroForOne
    ) public {
        // Given: A snapshot with a price, tick, fee and buffers, and a pool.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        Snapshot memory snapshot = Snapshot({
            buffer0: buffer0,
            buffer1: buffer1,
            fees0: 0,
            fees1: 0,
            supply: 1,
            sqrtPriceX96: sqrtPriceX96,
            tick: TickMath.getTickAtSqrtPrice(sqrtPriceX96),
            fee: fee,
            core: IALMCore(address(0)),
            ranges: new PricedRange[](0)
        });
        address pool = address(new PoolMock(tickSpacing, liquidity));

        // When: Calling getSwapState().
        SwapState memory state = swapStateLib.getSwapState(snapshot, pool, zeroForOne);

        // Then: Price, tick and fee are the snapshot's, liquidity and spacing the pool's.
        assertEq(state.sqrtPriceX96, sqrtPriceX96);
        assertEq(state.tick, snapshot.tick);
        assertEq(state.fee, fee);
        assertEq(state.liquidity, liquidity);
        assertEq(state.tickSpacing, tickSpacing);

        // And: Nothing is taken or paid yet.
        assertEq(state.amountIn, 0);
        assertEq(state.amountOut, 0);

        // And: The core's position is its equivalent position at spot.
        EquivalentPosition memory position = SnapshotLib.getPosition(snapshot, sqrtPriceX96, zeroForOne);
        assertEq(abi.encode(state.position), abi.encode(position));
    }
}
