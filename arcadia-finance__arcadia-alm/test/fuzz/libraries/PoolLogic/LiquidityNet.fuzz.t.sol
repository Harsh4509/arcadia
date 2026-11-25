/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PoolLogic_Fuzz_Test } from "./_PoolLogic.fuzz.t.sol";
import { PoolMock } from "../../../utils/mocks/PoolMock.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "liquidityNet" of library "PoolLogic".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract LiquidityNet_PoolLogic_Fuzz_Test is PoolLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_liquidityNet_ReadsTheTicksNetLiquidity(
        int24 tick,
        int128 liquidityNet,
        int128 stakedLiquidityNet
    ) public {
        // Given: A pool with a net and a staked net liquidity change at a tick.
        tick = int24(bound(tick, TickMath.MIN_TICK, TickMath.MAX_TICK));
        PoolMock mock = new PoolMock(1, 1);
        mock.addLiquidityNet(tick, liquidityNet);
        mock.addStakedLiquidityNet(tick, stakedLiquidityNet);

        // When: Reading the tick's net liquidity.
        int128 read = poolLogic.liquidityNet(address(mock), tick);

        // Then: It is the change crossing the tick adds.
        assertEq(read, liquidityNet);
    }
}
