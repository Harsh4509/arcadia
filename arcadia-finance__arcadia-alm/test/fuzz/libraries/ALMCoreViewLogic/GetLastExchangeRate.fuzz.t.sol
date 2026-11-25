/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { ExchangeRate } from "../../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getLastExchangeRate" of library "ALMCoreViewLogic".
 */
contract GetLastExchangeRate_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getLastExchangeRate_ReadsBothWords(
        PoolState memory poolState,
        uint256 supplyPerValueX128,
        uint160 sqrtPriceX96
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A stored exchange rate.
        almCore.setLastExchangeRate(supplyPerValueX128, sqrtPriceX96);

        // When: Reading it.
        ExchangeRate memory read = coreViewLogic.getLastExchangeRate(address(almCore));

        // Then: Both fields read back.
        assertEq(read.supplyPerValueX128, supplyPerValueX128);
        assertEq(read.sqrtPriceX96, sqrtPriceX96);
    }
}
