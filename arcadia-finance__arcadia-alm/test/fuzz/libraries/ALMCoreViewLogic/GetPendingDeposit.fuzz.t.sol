/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { Record } from "../../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getPendingDeposit" of library "ALMCoreViewLogic".
 */
contract GetPendingDeposit_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
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

    function testFuzz_Success_getPendingDeposit_PendingAtThePendingDepositEpoch(
        address vault,
        address controller_,
        Record memory record,
        uint32 otherEpoch
    ) public {
        // Given: A deposit record holding an amount in the pending deposit epoch.
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint128).max));
        almCore.setDepositRecord(vault, controller_, record);
        almCore.setPendingEpochs(vault, record.epoch, otherEpoch);

        // When: Reading the pending deposit.
        uint256 amount = coreViewLogic.getPendingDeposit(address(almCore), vault, controller_);

        // Then: Its amount is pending.
        assertEq(amount, record.amountIn);
    }

    function testFuzz_Success_getPendingDeposit_IgnoresTheRedeemEpoch(
        address vault,
        address controller_,
        Record memory record,
        uint32 otherEpoch
    ) public {
        // Given: A deposit record whose epoch is the pending redeem epoch only.
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint128).max));
        unchecked {
            otherEpoch = record.epoch + uint32(bound(otherEpoch, 1, type(uint32).max));
        }
        almCore.setDepositRecord(vault, controller_, record);
        almCore.setPendingEpochs(vault, otherEpoch, record.epoch);

        // When: Reading the pending deposit.
        uint256 amount = coreViewLogic.getPendingDeposit(address(almCore), vault, controller_);

        // Then: Nothing is pending.
        assertEq(amount, 0);
    }
}
