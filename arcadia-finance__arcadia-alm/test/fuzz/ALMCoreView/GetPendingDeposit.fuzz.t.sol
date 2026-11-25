/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreView_Fuzz_Test } from "./_ALMCoreView.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { Record } from "../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getPendingDeposit" of contract "ALMCoreView".
 */
contract GetPendingDeposit_ALMCoreView_Fuzz_Test is ALMCoreView_Fuzz_Test {
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

    function testFuzz_Revert_getPendingDeposit_CoreNotValid(address notCore, address vault, address controller_)
        public
    {
        // Given: An address the factory does not hold as a core.
        vm.assume(notCore != address(almCore));

        // When: Reading it through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getPendingDeposit(notCore, vault, controller_);
    }

    function testFuzz_Revert_getPendingDeposit_CoreNotValid_HalfCreated(address vault, address controller_) public {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        address core = BaseVault(halfCreatedVaults()[0]).share();

        // When: Reading its core address through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getPendingDeposit(core, vault, controller_);
    }

    function testFuzz_Success_getPendingDeposit_IsThePendingEpochsAmount(
        address vault,
        address controller_,
        Record memory record
    ) public {
        // Given: A deposit record holding an amount in the pending epoch.
        uint32 pendingEpoch = record.epoch;
        almCore.setPendingEpochs(vault, pendingEpoch, 0);
        almCore.setDepositRecord(vault, controller_, record);

        // When: Reading it through the lens.
        uint256 read = coreView.getPendingDeposit(address(almCore), vault, controller_);

        // Then: The record's amount is pending.
        assertEq(read, record.amountIn);
    }
}
