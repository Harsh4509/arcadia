/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { EmissionsLogicExtension } from "../../../utils/extensions/EmissionsLogicExtension.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { ICLGauge } from "../../../utils/fixtures/metadex/interfaces/ICLGauge.sol";
import { ICLPool } from "../../../utils/fixtures/metadex/interfaces/ICLPool.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { StakedRange_Fuzz_Test } from "../_StakedRange.fuzz.t.sol";

/**
 * @notice Common logic needed by all "EmissionsLogic" fuzz tests.
 */
abstract contract EmissionsLogic_Fuzz_Test is Fuzz_Test, StakedRange_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    EmissionsLogicExtension internal emissionsLogic;
    ICLPool internal pool;
    ICLGauge internal gauge;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();
        emissionsLogic = new EmissionsLogicExtension();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function deployStakedPool() internal {
        deployMetadex(false);
        deployMetadexCL();
        pool = createPool(address(token0), address(token1), TICK_SPACING, 1 << 96, 10);
        gauge = createGauge(pool, true);
    }

    function stakeIntoRange(int24 tickLower, int24 tickUpper, uint128 liquidity) internal returns (uint256 tokenId) {
        Range memory range = stakeIntoRange(pool, gauge, users.liquidityProvider, tickLower, tickUpper, liquidity);
        emissionsLogic.pushRange(range);
        tokenId = range.stakedTokenId;
    }
}
