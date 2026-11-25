/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "getBuffer" of library "ALMCoreViewLogic".
 */
contract GetBuffer_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
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

    function testFuzz_Success_getBuffer_ReadsTheBufferFreeOfTheOtherPoolTokens(
        uint128 buffer0,
        uint128 buffer1,
        uint128 fees0,
        uint128 fees1,
        uint128 escrowed0,
        uint128 escrowed1
    ) public {
        // Given: A buffer, beside protocol fees and an escrow.
        almCore.setBuffers(buffer0, buffer1);
        almCore.setFeesOwed(fees0, fees1, 0);
        almCore.setEscrowed(escrowed0, escrowed1);

        // When: Reading the buffer.
        (uint128 amount0, uint128 amount1) = coreViewLogic.getBuffer(address(almCore));

        // Then: Both halves read back.
        assertEq(amount0, buffer0);
        assertEq(amount1, buffer1);
    }
}
