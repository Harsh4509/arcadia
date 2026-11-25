/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreView_Fuzz_Test } from "./_ALMCoreView.fuzz.t.sol";
import { Record } from "../../../src/core/types/State.sol";
import { STATE_SLOT } from "../../../src/core/abstracts/storage/Storage.sol";

/**
 * @notice Fuzz tests for the function "getRedeemRecord" of contract "ALMCoreView".
 */
contract GetRedeemRecord_ALMCoreView_Fuzz_Test is ALMCoreView_Fuzz_Test {
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

    function testFuzz_Revert_getRedeemRecord_CoreNotValid(address notCore, address vault, address controller_) public {
        // Given: An address the factory does not hold as a core.
        vm.assume(notCore != address(almCore));

        // When: Reading it through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getRedeemRecord(notCore, vault, controller_);
    }

    function testFuzz_Success_getRedeemRecord_ReadsTheStoredWord(
        address vault,
        address controller_,
        Record memory record
    ) public {
        // Given: A redeem record, stored in its word.
        bytes32 base = keccak256(abi.encode(vault, bytes32(uint256(STATE_SLOT) + 20)));
        bytes32 slot = keccak256(abi.encode(controller_, bytes32(uint256(base) + 6)));
        vm.store(
            address(almCore),
            slot,
            bytes32((uint256(record.pendingShares) << 160) | (uint256(record.amountIn) << 32) | record.epoch)
        );

        // When: Reading it through the lens.
        Record memory read = coreView.getRedeemRecord(address(almCore), vault, controller_);

        // Then: Every field reads back.
        assertEq(read.epoch, record.epoch);
        assertEq(read.amountIn, record.amountIn);
        assertEq(read.pendingShares, record.pendingShares);
    }
}
