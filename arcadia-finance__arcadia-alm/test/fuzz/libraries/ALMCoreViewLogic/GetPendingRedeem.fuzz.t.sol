/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { Record } from "../../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getPendingRedeem" of library "ALMCoreViewLogic".
 */
contract GetPendingRedeem_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
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

    function testFuzz_Success_getPendingRedeem_PendingAtThePendingRedeemEpoch(
        address vault,
        address controller_,
        Record memory record,
        uint32 otherEpoch
    ) public {
        // Given: A redeem record holding an amount in the pending redeem epoch.
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint128).max));
        almCore.setRedeemRecord(vault, controller_, record);
        almCore.setPendingEpochs(vault, otherEpoch, record.epoch);

        // When: Reading the pending redeem.
        uint256 amount = coreViewLogic.getPendingRedeem(address(almCore), vault, controller_);

        // Then: Its amount is pending.
        assertEq(amount, record.amountIn);
    }

    function testFuzz_Success_getPendingRedeem_IgnoresTheDepositEpoch(
        address vault,
        address controller_,
        Record memory record,
        uint32 otherEpoch
    ) public {
        // Given: A redeem record whose epoch is the pending deposit epoch only.
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint128).max));
        unchecked {
            otherEpoch = record.epoch + uint32(bound(otherEpoch, 1, type(uint32).max));
        }
        almCore.setRedeemRecord(vault, controller_, record);
        almCore.setPendingEpochs(vault, record.epoch, otherEpoch);

        // When: Reading the pending redeem.
        uint256 amount = coreViewLogic.getPendingRedeem(address(almCore), vault, controller_);

        // Then: Nothing is pending.
        assertEq(amount, 0);
    }
}
