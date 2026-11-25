/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "getRewards" of library "ALMCoreViewLogic".
 */
contract GetRewards_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getRewards_ReadsEveryFieldFreeOfItsNeighbours(
        uint128 rewardPerShare,
        uint128 highWater,
        uint128 claimedCumulative,
        uint128 lastRewardBalance,
        uint128 protocolFees,
        uint128 protocolRewardPerSharePaid,
        uint128 preCredited
    ) public {
        // Given: Every field of the emissions accumulator, written through it.
        almCore.setRewardAccounting(rewardPerShare, highWater, claimedCumulative, lastRewardBalance);
        almCore.setFeesOwed(0, 0, protocolFees);
        almCore.setProtocolRewardSnapshot(protocolRewardPerSharePaid);
        almCore.setPreCredited(preCredited);

        // When: Reading the accumulator.
        (uint128 read0, uint128 read1, uint128 read2, uint128 read3, uint128 read4, uint128 read5, uint128 read6) =
            coreViewLogic.getRewards(address(almCore));

        // Then: Every field reads back.
        assertEq(read0, rewardPerShare);
        assertEq(read1, highWater);
        assertEq(read2, claimedCumulative);
        assertEq(read3, lastRewardBalance);
        assertEq(read4, protocolFees);
        assertEq(read5, protocolRewardPerSharePaid);
        assertEq(read6, preCredited);
    }
}
