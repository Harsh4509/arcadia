/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "../../ALMCore/_ALMCore.fuzz.t.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { RewardsLibExtension } from "../../../utils/extensions/RewardsLibExtension.sol";
import { StakedRange_Fuzz_Test } from "../_StakedRange.fuzz.t.sol";

/**
 * @notice Common logic needed by all "RewardsLib" fuzz tests.
 */
abstract contract RewardsLib_Fuzz_Test is ALMCore_Fuzz_Test, StakedRange_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    RewardsLibExtension internal rewardsLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function deployRewardsLib() internal {
        rewardsLib = new RewardsLibExtension(
            almCore.REWARD_TOKEN_(), address(gauge), address(clGaugeFactory), address(leafVoter)
        );
    }

    function stakeIntoRange(uint128 liquidity) internal returns (uint256 tokenId) {
        tokenId = stakeIntoRange(TICK_LOWER, TICK_UPPER, liquidity);
    }

    function stakeIntoRange(int24 tickLower, int24 tickUpper, uint128 liquidity) internal returns (uint256 tokenId) {
        Range memory range = stakeIntoRange(pool, gauge, address(almCore), tickLower, tickUpper, liquidity);
        almCore.pushRange(range);
        tokenId = range.stakedTokenId;
    }
}
