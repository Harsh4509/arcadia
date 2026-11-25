/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { MintOptimizationMath_Fuzz_Test } from "./_MintOptimizationMath.fuzz.t.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "previewMint" of library "MintOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract PreviewMint_MintOptimizationMath_Fuzz_Test is MintOptimizationMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_previewMint_CostsTheBuyAndThePullAtItsEnd(
        MintState memory state,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A range around spot, a mint of the supply at most, a pool selling it.
        Snapshot memory snapshot = snapshotOf(
            givenValidRange(state, range), state.idle0, state.idle1, state.supply, state.sqrtPriceX96, state.fee
        );
        shares = bound(shares, 1, state.supply);
        givenValidBuy(
            state, snapshot.ranges, shares, state.zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        );

        // When: Previewing the mint.
        uint256 assets;
        uint160 sqrtPriceNew;
        {
            address pool = poolOf(1, state.liquidity, snapshot.ranges);
            assets = optimizationMath.previewMint(snapshot, pool, state.zeroForOne, shares);

            // Then: It costs the pool's swap and the pull at its end with core fees.
            uint256 amountOut;
            uint256 fees0;
            uint256 fees1;
            (sqrtPriceNew,, amountOut, fees0, fees1) =
                optimizationMath.computeSwap(snapshot, pool, state.zeroForOne, shares);
            (, uint256 swapIn,) = swap(snapshot, pool, state.zeroForOne, int256(amountOut), sqrtPriceNew);
            assets -= swapIn;
            (snapshot.buffer0, snapshot.buffer1) = (state.idle0 + fees0, state.idle1 + fees1);
        }
        (uint256 pull0, uint256 pull1) = snapshotLib.getMintAmounts(
            snapshot.ranges, sqrtPriceNew, snapshot.buffer0, snapshot.buffer1, shares, state.supply, state.zeroForOne
        );
        assertEq(assets, state.zeroForOne ? pull0 : pull1);
    }
}
