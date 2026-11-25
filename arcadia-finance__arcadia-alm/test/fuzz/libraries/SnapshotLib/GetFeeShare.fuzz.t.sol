/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "../../ALMCore/_ALMCore.fuzz.t.sol";
import { Constants } from "../../../utils/Constants.sol";
import { ICLPool } from "../../../utils/fixtures/metadex/interfaces/ICLPool.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SnapshotLibExtension } from "../../../utils/extensions/SnapshotLibExtension.sol";

/**
 * @notice Fuzz tests for the function "getFeeShare" of library "SnapshotLib".
 */
contract GetFeeShare_SnapshotLib_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    SnapshotLibExtension internal snapshotLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        snapshotLib = new SnapshotLibExtension();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getFeeShare(PoolState memory poolState, uint16 protocolSwapFeeBps, uint24 unstakedFee)
        public
    {
        // Given: A core on a pool with a fuzzed unstaked fee share and protocol swap fee.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        unstakedFee = uint24(bound(unstakedFee, 0, Constants.MAX_UNSTAKED_FEE));
        vm.mockCall(address(pool), abi.encodeCall(ICLPool.unstakedFee, ()), abi.encode(unstakedFee));
        protocolSwapFeeBps = uint16(bound(protocolSwapFeeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(0, protocolSwapFeeBps, users.feeRecipient);
        Snapshot memory snapshot = snapshotLib.getSnapshot(address(almCore), address(pool), address(this));

        // When: Calculating the share of fees the core's unstaked liquidity keeps.
        uint256 feeShare = snapshotLib.getFeeShare(snapshot, address(pool));

        // Then: What the pool's levy and the protocol's share leave, to 10 decimals.
        assertEq(feeShare, (1e6 - uint256(unstakedFee)) * (1e4 - uint256(protocolSwapFeeBps)));
    }
}
