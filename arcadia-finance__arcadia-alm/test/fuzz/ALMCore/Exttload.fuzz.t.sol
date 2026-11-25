/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { TRANSIENT_SLOT } from "../../../src/core/abstracts/storage/Storage.sol";

/**
 * @notice Fuzz tests for the functions "exttload" of contract "ALMCore".
 */
contract Exttload_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_exttload_LockClearOutsideAPlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range
    ) public {
        // Given: A seeded vault holding a range, and no plan running.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // When: Reading the guard slot.
        // Then: It is clear.
        assertEq(almCore.exttload(Constants.FALLBACK_GUARD_SLOT), bytes32(0));
    }

    function testFuzz_Success_exttload_LockSetDuringAPlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range
    ) public {
        // Given: A seeded vault holding a range.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // When: A router reads the guard slot while a keeper plan hands it control.
        (bool success, bytes memory result) = readDuringPlan(
            address(almCore), abi.encodeWithSignature("exttload(bytes32)", Constants.FALLBACK_GUARD_SLOT)
        );

        // Then: The lock holds the core's own address.
        assertTrue(success);
        assertEq(abi.decode(result, (bytes32)), bytes32(uint256(uint160(address(almCore)))));
    }

    function testFuzz_Success_exttload_NoSlots(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range
    ) public {
        // Given: A seeded vault holding a range.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // When: Reading an empty list of transient slots.
        bytes32[] memory read = almCore.exttload(new bytes32[](0));

        // Then: Nothing comes back.
        assertEq(read.length, 0);
    }

    function testFuzz_Success_exttload_LockClearOutsideAPlanInAList(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range
    ) public {
        // Given: A seeded vault holding a range, and no plan running.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // When: Reading the guard slot in a list.
        bytes32[] memory slots = new bytes32[](1);
        slots[0] = Constants.FALLBACK_GUARD_SLOT;
        bytes32[] memory read = almCore.exttload(slots);

        // Then: It is clear.
        assertEq(read.length, 1);
        assertEq(read[0], bytes32(0));
    }

    function testFuzz_Success_exttload_SlotsInTheOrderAskedDuringAPlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range
    ) public {
        // Given: A seeded vault holding a range.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // When: A router reads the swap flag slot, then the guard slot, during a plan.
        bytes32[] memory slots = new bytes32[](2);
        (slots[0], slots[1]) = (TRANSIENT_SLOT, Constants.FALLBACK_GUARD_SLOT);
        (bool success, bytes memory result) =
            readDuringPlan(address(almCore), abi.encodeWithSignature("exttload(bytes32[])", slots));

        // Then: The swap flag reads clear, then the lock holding the core's address.
        assertTrue(success);
        bytes32[] memory read = abi.decode(result, (bytes32[]));
        assertEq(read.length, 2);
        assertEq(read[0], bytes32(0));
        assertEq(read[1], bytes32(uint256(uint160(address(almCore)))));
    }
}
