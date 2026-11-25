/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "../../ALMCore/_ALMCore.fuzz.t.sol";
import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { RangesLib } from "../../../../src/core/libraries/state/RangesLib.sol";
import { RangesLibExtension } from "../../../utils/extensions/RangesLibExtension.sol";

/**
 * @notice Common logic needed by all "RangesLib" fuzz tests.
 */
// forge-lint: disable-next-item(unsafe-typecast)
abstract contract RangesLib_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    RangesLibExtension internal rangesLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function deployRangesLib() internal {
        rangesLib = new RangesLibExtension(
            address(POSITION_MANAGER),
            address(pool),
            address(gauge),
            address(clGaugeFactory),
            address(token0),
            address(token1),
            pool.tickSpacing()
        );
        rangesLib.setRangeCap(ConfigLib.MAX_RANGE_CAP);
    }

    function setEmergencyWithdrawEnabled(bool enabled) internal {
        clGaugeFactory.setEmergencyWithdrawEnabled(enabled);
    }

    function liquidities() internal view returns (uint128[] memory positionLiquidity) {
        (,, positionLiquidity) = rangesLib.getUnstakedPositions(0);
    }

    function pushRangeOf(RangeState memory range) internal {
        range.index = rangesLib.getRangesLength();
        rangesLib.pushRange(stageRange(address(rangesLib), range));
    }

    function pushRange(int24 tickLower, int24 tickUpper, uint128 unstaked, uint128 staked) internal {
        rangesLib.pushRange(
            Range({
                stakedLiquidity: staked,
                tickLower: tickLower,
                tickUpper: tickUpper,
                unstakedTokenId: 1,
                stakedTokenId: staked == 0 ? 0 : 2,
                stakedBlock: 0
            })
        );
    }

    function pushStaked(uint80 stakedTokenId, uint48 stakedBlock) internal {
        rangesLib.pushRange(
            Range({
                stakedLiquidity: 0,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                unstakedTokenId: 1,
                stakedTokenId: stakedTokenId,
                stakedBlock: stakedBlock
            })
        );
    }
}
