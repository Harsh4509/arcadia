/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { PricedRange } from "../../../../src/vaults/types/PricedRange.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SnapshotLib_Fuzz_Test } from "./_SnapshotLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getRounding" of library "SnapshotLib".
 */
contract GetRounding_SnapshotLib_Fuzz_Test is SnapshotLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getRounding_ABurnReleasesItsPartLessTheRounding(
        SnapshotState memory state,
        RangeState memory range,
        uint256 shares
    ) public view {
        // Given: A range around spot, no fees, and at most the supply in shares.
        (state.fees0, state.fees1) = (0, 0);
        Snapshot memory snapshot = givenValidSnapshot(state, range);
        shares = bound(shares, 1, state.supply);

        // When: Burning the shares and the whole supply.
        (uint256 amount0, uint256 amount1,) = snapshotLib.getBurnAmounts(snapshot, state.sqrtPriceX96, shares, false);
        (uint256 total0, uint256 total1,) =
            snapshotLib.getBurnAmounts(snapshot, state.sqrtPriceX96, state.supply, false);

        // Then: Each release is the shares' part of the supply's, less the rounding.
        assertGe(
            amount0 + snapshotLib.getRounding(snapshot, state.sqrtPriceX96, true),
            FixedPointMathLib.fullMulDiv(total0, shares, state.supply)
        );
        assertGe(
            amount1 + snapshotLib.getRounding(snapshot, state.sqrtPriceX96, false),
            FixedPointMathLib.fullMulDiv(total1, shares, state.supply)
        );
    }

    function testFuzz_Success_getRounding_PerRangeAUnitAndTwoWeiPlusOneForTheIdle(
        uint256 rangeCount,
        uint160 sqrtPriceX96,
        bool isToken0
    ) public view {
        // Given: A snapshot of one to the most ranges, and a price.
        rangeCount = bound(rangeCount, 1, ConfigLib.MAX_RANGE_CAP);
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE));
        Snapshot memory snapshot;
        snapshot.ranges = new PricedRange[](rangeCount);

        // When: Reading the rounding of either token.
        uint256 rounding = snapshotLib.getRounding(snapshot, sqrtPriceX96, isToken0);

        // Then: Per range a unit's amount rounded up and 2 wei, plus 1 wei for idle.
        uint256 unit =
            isToken0 ? FixedPointMathLib.divUp(1 << 96, sqrtPriceX96) : FixedPointMathLib.divUp(sqrtPriceX96, 1 << 96);
        assertEq(rounding, rangeCount * (unit + 2) + 1);
    }
}
