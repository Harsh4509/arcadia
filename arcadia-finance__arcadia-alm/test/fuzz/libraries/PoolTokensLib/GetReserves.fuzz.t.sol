/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PoolTokensLib_Fuzz_Test } from "./_PoolTokensLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "getReserves" of library "PoolTokensLib".
 */
contract GetReserves_PoolTokensLib_Fuzz_Test is PoolTokensLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getReserves_SumsTheBufferTheFeesAndTheEscrow(
        uint128 buffer0,
        uint128 buffer1,
        uint128 protocolFees0,
        uint128 protocolFees1,
        uint128 escrowed0,
        uint128 escrowed1
    ) public {
        // Given: Buffers, protocol fees and escrow in both tokens.
        poolTokensLib.setPoolTokens(buffer0, buffer1, protocolFees0, protocolFees1);
        poolTokensLib.setEscrowed(escrowed0, escrowed1);

        // When: Reading the accounted amounts.
        (uint256 reserve0, uint256 reserve1) = poolTokensLib.getReserves();

        // Then: Each is its token's buffer, protocol fee and escrow summed.
        assertEq(reserve0, uint256(buffer0) + protocolFees0 + escrowed0);
        assertEq(reserve1, uint256(buffer1) + protocolFees1 + escrowed1);
    }
}
