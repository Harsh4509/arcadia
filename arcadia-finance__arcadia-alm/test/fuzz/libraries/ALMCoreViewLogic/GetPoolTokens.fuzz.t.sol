/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { PoolTokens } from "../../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getPoolTokens" of library "ALMCoreViewLogic".
 */
contract GetPoolTokens_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
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

    function testFuzz_Success_getPoolTokens_ReadsEveryFieldFreeOfItsNeighbours(
        uint128 buffer0,
        uint128 buffer1,
        uint128 protocolFees0,
        uint128 protocolFees1,
        uint128 escrowed0,
        uint128 escrowed1
    ) public {
        // Given: The buffer, the protocol fees and the escrow, written through accessors.
        almCore.setBuffers(buffer0, buffer1);
        almCore.setFeesOwed(protocolFees0, protocolFees1, 0);
        almCore.setEscrowed(escrowed0, escrowed1);

        // When: Reading the pool tokens.
        PoolTokens memory poolTokens = coreViewLogic.getPoolTokens(address(almCore));

        // Then: Every field reads back.
        assertEq(poolTokens.buffer.amount0, buffer0);
        assertEq(poolTokens.buffer.amount1, buffer1);
        assertEq(poolTokens.protocolFees.amount0, protocolFees0);
        assertEq(poolTokens.protocolFees.amount1, protocolFees1);
        assertEq(poolTokens.escrowed.amount0, escrowed0);
        assertEq(poolTokens.escrowed.amount1, escrowed1);
    }
}
