/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { EmissionsLogic_Fuzz_Test } from "./_EmissionsLogic.fuzz.t.sol";
import { IArbSys } from "../../../../src/interfaces/IArbSys.sol";

/**
 * @notice Fuzz tests for the function "getBlockNumber" of library "EmissionsLogic".
 */
contract GetBlockNumber_EmissionsLogic_Fuzz_Test is EmissionsLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getBlockNumber_BlockNumber(uint32 blocks) public {
        // Given: A chain whose gauges count blocks with vm.getBlockNumber().
        vm.roll(vm.getBlockNumber() + blocks);

        // When: Getting the block number.
        // Then: It is vm.getBlockNumber().
        assertEq(emissionsLogic.getBlockNumber(false), vm.getBlockNumber());
    }

    function testFuzz_Success_getBlockNumber_ArbBlockNumber(uint256 arbBlockNumber) public {
        // Given: A chain whose gauges count blocks with ArbSys.arbBlockNumber.
        vm.etch(address(0x64), hex"00");
        vm.mockCall(address(0x64), abi.encodeCall(IArbSys.arbBlockNumber, ()), abi.encode(arbBlockNumber));

        // When: Getting the block number.
        // Then: It is ArbSys.arbBlockNumber.
        assertEq(emissionsLogic.getBlockNumber(true), arbBlockNumber);
    }
}
