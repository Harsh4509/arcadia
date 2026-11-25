/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { Epoch } from "../../../src/core/types/State.sol";
import { STATE_SLOT } from "../../../src/core/abstracts/storage/Storage.sol";

/**
 * @notice Fuzz tests for the functions "extsload" of contract "ALMCore".
 */
contract Extsload_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_extsload_OneSlot(bytes32 slot, bytes32 value) public {
        // Given: A value stored at a slot of the core.
        vm.store(address(almCore), slot, value);

        // When: Reading that slot.
        // Then: It is the value.
        assertEq(almCore.extsload(slot), value);
    }

    function testFuzz_Success_extsload_ConsecutiveSlotsFromAStart(uint256 start, bytes32[3] memory values) public {
        // Given: Three values stored at three consecutive slots of the core.
        start = bound(start, 0, type(uint256).max - 2);
        for (uint256 i; i < 3; ++i) {
            vm.store(address(almCore), bytes32(start + i), values[i]);
        }

        // When: Reading three slots from the first.
        bytes32[] memory read = almCore.extsload(bytes32(start), 3);

        // Then: Each value comes back at its slot's distance from the first.
        assertEq(read.length, 3);
        for (uint256 i; i < 3; ++i) {
            assertEq(read[i], values[i]);
        }
    }

    function testFuzz_Success_extsload_NoSlotsFromAStart(bytes32 slot, bytes32 value) public {
        // Given: A value stored at a slot of the core.
        vm.store(address(almCore), slot, value);

        // When: Reading zero slots from that slot.
        bytes32[] memory read = almCore.extsload(slot, 0);

        // Then: Nothing comes back.
        assertEq(read.length, 0);
    }

    function testFuzz_Success_extsload_SlotsInTheOrderAsked(bytes32[3] memory slots, bytes32[3] memory values) public {
        // Given: Three values stored at three distinct slots of the core.
        vm.assume(slots[0] != slots[1] && slots[0] != slots[2] && slots[1] != slots[2]);
        bytes32[] memory asked = new bytes32[](3);
        for (uint256 i; i < 3; ++i) {
            vm.store(address(almCore), slots[i], values[i]);
            asked[2 - i] = slots[i];
        }

        // When: Reading the slots in reverse order.
        bytes32[] memory read = almCore.extsload(asked);

        // Then: Each value comes back at the position its slot was asked at.
        assertEq(read.length, 3);
        for (uint256 i; i < 3; ++i) {
            assertEq(read[2 - i], values[i]);
        }
    }

    function testFuzz_Success_extsload_NoSlots(bytes32 slot, bytes32 value) public {
        // Given: A value stored at a slot of the core.
        vm.store(address(almCore), slot, value);

        // When: Reading an empty list of slots.
        bytes32[] memory read = almCore.extsload(new bytes32[](0));

        // Then: Nothing comes back.
        assertEq(read.length, 0);
    }

    function testFuzz_Success_extsload_ReadsTwoEpochs(
        address vault,
        uint32 id,
        Epoch memory deposit,
        Epoch memory redeem
    ) public {
        // Given: A deposit and a redeem epoch written through the accessor.
        almCore.setDepositEpoch(vault, id, deposit);
        almCore.setRedeemEpoch(vault, id, redeem);

        // When: Reading both of their slots in one call.
        bytes32 base = keccak256(abi.encode(vault, bytes32(uint256(STATE_SLOT) + 20)));
        bytes32[] memory slots = new bytes32[](2);
        slots[0] = keccak256(abi.encode(uint256(id), bytes32(uint256(base) + 1)));
        slots[1] = keccak256(abi.encode(uint256(id), bytes32(uint256(base) + 5)));
        bytes32[] memory read = almCore.extsload(slots);

        // Then: Each word packs its epoch's amounts.
        assertEq(read[0], bytes32((uint256(deposit.amountOut) << 128) | deposit.amountIn));
        assertEq(read[1], bytes32((uint256(redeem.amountOut) << 128) | redeem.amountIn));
    }
}
