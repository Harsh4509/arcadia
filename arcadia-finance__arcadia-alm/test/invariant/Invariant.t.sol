/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "../fuzz/ALMCore/_ALMCore.fuzz.t.sol";
import { CLMath } from "../../src/shared/libraries/math/CLMath.sol";
import { Constants } from "../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { SnapshotLib } from "../../src/vaults/types/Snapshot.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";

/**
 * @notice Common logic needed by all invariant tests.
 */
// forge-lint: disable-next-item(uninitialized-local)
abstract contract Invariant_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The aLP the seed mints, above DEAD_SHARES so the first mint has a denominator.
    uint256 internal constant INITIAL_SUPPLY = 1e21;

    // The denominator of a pool fee, in pips.
    uint256 internal constant FEE_DENOMINATOR = 1e6;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function swapBounds(bool zeroForOne, uint256 buffer) internal view returns (uint256 floor, uint256 ceiling) {
        uint160 spot = sqrtPriceX96(pool);
        uint128 liquidity = pool.liquidity();
        uint256 maxSwapCostBps = almCore.maxSwapCostBps_();
        uint256 margin = FixedPointMathLib.zeroFloorSub(maxSwapCostBps * 100, pool.fee());
        // The output of one sqrt-price unit at the pool's liquidity, plus a wei of rounding, within the cost margin.
        uint256 unit = FixedPointMathLib.fullMulDivUp(liquidity, 1, 1 << 96) + 1;
        floor = FixedPointMathLib.fullMulDivUp(
            zeroForOne ? CLMath.convert(spot, false, unit, true) : unit,
            FEE_DENOMINATOR,
            FixedPointMathLib.max(margin, 1)
        );
        uint160 limit = SnapshotLib.getSwapCostLimit(spot, pool.fee(), maxSwapCostBps, zeroForOne);
        ceiling = zeroForOne
            ? SqrtPriceMath.getAmount0Delta(limit, spot, liquidity, false)
            : SqrtPriceMath.getAmount1Delta(spot, limit, liquidity, false);
        ceiling = FixedPointMathLib.min(ceiling, buffer);
        floor = FixedPointMathLib.min(floor, ceiling);
    }

    function setInvariantState() internal {
        PoolState memory poolState;
        CoreState memory coreState;
        RangeState memory range;
        poolState.sqrtPrice = SQRT_PRICE_ONE_X96;
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        (range.tickLower, range.tickUpper) = (-poolState.tickSpacing, poolState.tickSpacing);
        range.liquidity =
            liquidityForAmounts(sqrtPriceX96(pool), range.tickLower, range.tickUpper, INITIAL_SUPPLY, INITIAL_SUPPLY);
        range.liquidityStaked = range.liquidity;
        (uint256 amount0, uint256 amount1) = amountsRoundedUp(
            sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        (coreState.supply, coreState.buffer0, coreState.buffer1) =
        (INITIAL_SUPPLY, amount0 + Constants.SEED_AMOUNT, amount1 + Constants.SEED_AMOUNT);
        setCoreState(coreState);
        setRangeState(range);
    }
}
