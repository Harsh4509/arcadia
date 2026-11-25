/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreView_Fuzz_Test } from "./_ALMCoreView.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { ExchangeRate } from "../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getLastExchangeRate" of contract "ALMCoreView".
 */
contract GetLastExchangeRate_ALMCoreView_Fuzz_Test is ALMCoreView_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreView_Fuzz_Test) {
        ALMCoreView_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getLastExchangeRate_CoreNotValid(PoolState memory poolState, address notCore) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: An address the factory does not hold as a core.
        vm.assume(notCore != address(almCore));

        // When: Reading it through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getLastExchangeRate(notCore);
    }

    function testFuzz_Revert_getLastExchangeRate_CoreNotValid_HalfCreated(PoolState memory poolState) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A pool whose creation stopped with its four vaults deployed and no core.
        address core = BaseVault(halfCreatedVaults()[0]).share();

        // When: Reading its core address through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getLastExchangeRate(core);
    }

    function testFuzz_Success_getLastExchangeRate_IsTheStoredRate(
        PoolState memory poolState,
        uint256 supplyPerValueX128,
        uint160 sqrtPriceX96
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A stored exchange rate, written through the accessor.
        almCore.setLastExchangeRate(supplyPerValueX128, sqrtPriceX96);

        // When: Reading it through the lens.
        ExchangeRate memory read = coreView.getLastExchangeRate(address(almCore));

        // Then: Both fields read back.
        assertEq(read.supplyPerValueX128, supplyPerValueX128);
        assertEq(read.sqrtPriceX96, sqrtPriceX96);
    }
}
