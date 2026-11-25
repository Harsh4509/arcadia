/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CLMath } from "../../../../src/shared/libraries/math/CLMath.sol";
import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { IALMCore } from "../../../../src/interfaces/IALMCore.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SnapshotLib_Fuzz_Test } from "./_SnapshotLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getSwapCostLimit" of library "SnapshotLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetSwapCostLimit_SnapshotLib_Fuzz_Test is SnapshotLib_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The mock core, holding only a max swap cost.
    address internal constant MOCK_CORE = address(uint160(uint256(keccak256("core"))));

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(SnapshotLib_Fuzz_Test) {
        SnapshotLib_Fuzz_Test.setUp();
        vm.etch(MOCK_CORE, hex"00");
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getSwapCostLimit_SpotWithinTheFee(
        SnapshotState memory state,
        RangeState memory range,
        uint24 fee,
        uint256 maxSwapCostBps,
        bool zeroForOne
    ) public {
        // Given: A core at a spot in the band, a fee, and a max swap cost of at most it.
        Snapshot memory snapshot = givenValidSnapshot(state, range);
        (snapshot.fee, snapshot.core) = (uint24(bound(fee, 0, Constants.MAX_POOL_FEE)), IALMCore(MOCK_CORE));
        maxSwapCostBps = bound(maxSwapCostBps, 0, snapshot.fee / Constants.PIPS_PER_BPS);
        mockMaxSwapCostBps(MOCK_CORE, maxSwapCostBps);

        // When: Calculating the price at which a swap reaches the max swap cost.
        uint160 sqrtPriceLimitX96 = snapshotLib.getSwapCostLimit(snapshot, zeroForOne);

        // Then: It is spot, no swap fitting within the fee.
        assertEq(sqrtPriceLimitX96, snapshot.sqrtPriceX96);
    }

    function testFuzz_Success_getSwapCostLimit_ASwapToItLosesAtMostTheCost(
        SnapshotState memory state,
        RangeState memory range,
        uint24 fee,
        uint256 maxSwapCostBps
    ) public {
        // Given: A core at a spot in the band, a fee, and a max swap cost above it.
        Snapshot memory snapshot = givenValidSnapshot(state, range);
        (snapshot.fee, snapshot.core) = (uint24(bound(fee, 0, Constants.MAX_POOL_FEE)), IALMCore(MOCK_CORE));
        maxSwapCostBps = bound(
            maxSwapCostBps, uint256(snapshot.fee).divUp(Constants.PIPS_PER_BPS) + 1, ConfigLib.BPS_DENOMINATOR - 1
        );
        mockMaxSwapCostBps(MOCK_CORE, maxSwapCostBps);
        uint256 spot = snapshot.sqrtPriceX96;
        uint256 bps = ConfigLib.BPS_DENOMINATOR;

        // When: Calculating where a swap of either token hits the max swap cost.
        uint256 lower = snapshotLib.getSwapCostLimit(snapshot, true);
        uint256 upper = snapshotLib.getSwapCostLimit(snapshot, false);

        // Then: Each lies on its side, (1 - fee) times the price ratio at least 1 - cost.
        assertLe(lower, spot);
        assertGe(upper, spot);
        assertGe(lower.fullMulDivUp(lower, spot) * (1e6 - snapshot.fee) * bps, spot * (bps - maxSwapCostBps) * 1e6);
        assertGe(spot.fullMulDivUp(spot, upper) * (1e6 - snapshot.fee) * bps, upper * (bps - maxSwapCostBps) * 1e6);
    }

    function testFuzz_Success_getSwapCostLimit_TheBandOfHalfTheCostBeyondTheFee(
        SnapshotState memory state,
        RangeState memory range,
        uint24 fee,
        uint256 maxSwapCostBps
    ) public {
        // Given: A core at a spot in the band, a fee, and a max swap cost above it.
        Snapshot memory snapshot = givenValidSnapshot(state, range);
        (snapshot.fee, snapshot.core) = (uint24(bound(fee, 0, Constants.MAX_POOL_FEE)), IALMCore(MOCK_CORE));
        maxSwapCostBps = bound(
            maxSwapCostBps, uint256(snapshot.fee).divUp(Constants.PIPS_PER_BPS) + 1, ConfigLib.BPS_DENOMINATOR - 1
        );
        mockMaxSwapCostBps(MOCK_CORE, maxSwapCostBps);

        // When: Calculating where a swap of either token hits the max swap cost.
        uint256 lower = snapshotLib.getSwapCostLimit(snapshot, true);
        uint256 upper = snapshotLib.getSwapCostLimit(snapshot, false);

        // Then: They bound the price within half the cost past the fee, inward.
        uint256 scale = 1e18 + (maxSwapCostBps * Constants.PIPS_PER_BPS - snapshot.fee) * 5e11;
        assertEq(lower, FullMath.mulDivRoundingUp(snapshot.sqrtPriceX96, 1e18, scale));
        assertEq(upper, FullMath.mulDiv(snapshot.sqrtPriceX96, scale, 1e18));
    }

    function testFuzz_Success_getSwapCostLimit_IsTheBandEdgeInTheSwapsDirection(
        uint256 sqrtPriceX96,
        uint256 fee,
        uint256 maxSwapCostBps,
        bool zeroForOne
    ) public view {
        // Given: A spot price in the band, a fee, and a max swap cost.
        sqrtPriceX96 = bound(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 1),
            TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 1)
        );
        fee = bound(fee, 0, Constants.MAX_POOL_FEE);
        maxSwapCostBps = bound(maxSwapCostBps, 0, ConfigLib.BPS_DENOMINATOR - 1);

        // When: Calculating where a swap from spot reaches the max swap cost.
        uint160 sqrtPriceLimitX96 = snapshotLib.getSwapCostLimit(sqrtPriceX96, fee, maxSwapCostBps, zeroForOne);

        // Then: It is the edge, in the swap's direction, of half the cost beyond the fee.
        (uint256 lower, uint256 upper) =
            CLMath.getBand(sqrtPriceX96, (maxSwapCostBps * Constants.PIPS_PER_BPS).zeroFloorSub(fee) * 5e11);
        assertEq(sqrtPriceLimitX96, zeroForOne ? lower : upper);
    }
}
