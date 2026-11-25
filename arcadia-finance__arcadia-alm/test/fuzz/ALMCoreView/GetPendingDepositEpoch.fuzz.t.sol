/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreView_Fuzz_Test } from "./_ALMCoreView.fuzz.t.sol";
import { STATE_SLOT } from "../../../src/core/abstracts/storage/Storage.sol";

/**
 * @notice Fuzz tests for the function "getPendingDepositEpoch" of contract "ALMCoreView".
 */
contract GetPendingDepositEpoch_ALMCoreView_Fuzz_Test is ALMCoreView_Fuzz_Test {
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

    function testFuzz_Revert_getPendingDepositEpoch_CoreNotValid(address notCore, address vault) public {
        // Given: An address the factory does not hold as a core.
        vm.assume(notCore != address(almCore));

        // When: Reading it through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getPendingDepositEpoch(notCore, vault);
    }

    function testFuzz_Success_getPendingDepositEpoch_ReadsTheStoredWord(address vault, uint32 pendingEpoch) public {
        // Given: A vault's pending deposit epoch, in the first word of its deposit queue.
        bytes32 base = keccak256(abi.encode(vault, bytes32(uint256(STATE_SLOT) + 20)));
        vm.store(address(almCore), base, bytes32(uint256(pendingEpoch)));

        // When: Reading it through the lens.
        uint32 read = coreView.getPendingDepositEpoch(address(almCore), vault);

        // Then: It reads back.
        assertEq(read, pendingEpoch);
    }
}
