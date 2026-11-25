/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../utils/Constants.sol";
import { Fuzz_Test } from "../Fuzz.t.sol";

/**
 * @notice Common logic needed by the library fuzz tests that draw a range without a pool.
 */
// forge-lint: disable-next-item(unsafe-typecast)
abstract contract Range_Fuzz_Test is Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function givenValidRange(RangeState memory range) internal pure {
        // And: A range inside the band, its two sides together within a uint128.
        range.tickLower = int24(bound(range.tickLower, -Constants.BOUND_TICK, Constants.BOUND_TICK - 1));
        range.tickUpper = int24(bound(range.tickUpper, range.tickLower + 1, Constants.BOUND_TICK));
        range.liquidityStaked = uint128(bound(range.liquidityStaked, 0, type(uint128).max - range.liquidity));
    }
}
