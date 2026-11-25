/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { ALMCoreViewLogicExtension } from "../../../utils/extensions/ALMCoreViewLogicExtension.sol";

/**
 * @notice Fuzz tests for the function "isLocked" of library "ALMCoreViewLogic".
 */
contract IsLocked_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_isLocked_FalseOutsideAPlan(
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

        // When: Reading the lock.
        // Then: It is clear.
        assertFalse(coreViewLogic.isLocked(address(almCore)));
    }

    function testFuzz_Success_isLocked_TrueDuringAPlan(
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

        // When: A router reads the lock while a keeper plan hands it control.
        (bool success, bytes memory result) = readDuringPlan(
            address(coreViewLogic), abi.encodeCall(ALMCoreViewLogicExtension.isLocked, (address(almCore)))
        );

        // Then: It is set.
        assertTrue(success);
        assertTrue(abi.decode(result, (bool)));
    }
}
