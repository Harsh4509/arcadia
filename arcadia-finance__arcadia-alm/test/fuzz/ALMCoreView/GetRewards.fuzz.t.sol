/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreView_Fuzz_Test } from "./_ALMCoreView.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";

/**
 * @notice Fuzz tests for the function "getRewards" of contract "ALMCoreView".
 */
contract GetRewards_ALMCoreView_Fuzz_Test is ALMCoreView_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreView_Fuzz_Test) {
        ALMCoreView_Fuzz_Test.setUp();
        setSpotPoolState();
        deployCoreView();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getRewards_CoreNotValid(address notCore) public {
        // Given: An address the factory does not hold as a core.
        vm.assume(notCore != address(almCore));

        // When: Reading it through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getRewards(notCore);
    }

    function testFuzz_Revert_getRewards_CoreNotValid_HalfCreated(uint256 pick) public {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        address[4] memory vaults_ = halfCreatedVaults();
        address core = BaseVault(vaults_[bound(pick, 0, vaults_.length - 1)]).share();

        // When: Reading its core address through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getRewards(core);
    }

    function testFuzz_Success_getRewards_IsTheAccumulator(
        uint128 rewardPerShare,
        uint128 highWater,
        uint128 claimedCumulative,
        uint128 lastRewardBalance,
        uint128 protocolFees,
        uint128 protocolRewardPerSharePaid,
        uint128 preCredited
    ) public {
        // Given: Every field of the emissions accumulator, written through the accessors.
        almCore.setRewardAccounting(rewardPerShare, highWater, claimedCumulative, lastRewardBalance);
        almCore.setFeesOwed(0, 0, protocolFees);
        almCore.setProtocolRewardSnapshot(protocolRewardPerSharePaid);
        almCore.setPreCredited(preCredited);

        // When: Reading it through the lens.
        (uint128 read0, uint128 read1, uint128 read2, uint128 read3, uint128 read4, uint128 read5, uint128 read6) =
            coreView.getRewards(address(almCore));

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
