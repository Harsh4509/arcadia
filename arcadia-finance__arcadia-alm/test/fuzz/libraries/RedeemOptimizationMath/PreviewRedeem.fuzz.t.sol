/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { RedeemOptimizationMath_Fuzz_Test } from "./_RedeemOptimizationMath.fuzz.t.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";

/**
 * @notice Fuzz tests for the function "previewRedeem" of library "RedeemOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract PreviewRedeem_RedeemOptimizationMath_Fuzz_Test is RedeemOptimizationMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_previewRedeem_PaysTheBurnAndThePoolsSaleOfItsTokenIn(
        RedeemState memory state,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A range around spot in its pool, and fewer shares than the supply.
        state.supply = uint128(bound(state.supply, 2, type(uint64).max));
        (Snapshot memory snapshot, address pool) = givenValidState(state, range);
        shares = bound(shares, 1, state.supply - 1);

        // When: Previewing the redeem.
        uint256 amountOut = redeemMath.previewRedeem(snapshot, pool, state.zeroForOne, shares, 0);

        // Then: It pays the burn's tokenOut plus the pool's sale of its tokenIn.
        assertEq(amountOut, redeemOf(snapshot, state, 1, shares, 0));
    }
}
