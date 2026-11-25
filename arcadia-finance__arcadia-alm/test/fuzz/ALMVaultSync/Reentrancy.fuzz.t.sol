/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";
import { ALMVaultSyncExtension } from "../../utils/extensions/ALMVaultSyncExtension.sol";
import { ReentrancyGuardTransient } from "@solady/utils/ReentrancyGuardTransient.sol";

/**
 * @notice Fuzz tests for the reentrancy guard of contract "ALMVaultSync".
 */
// forge-lint: disable-next-item(unused-return)
contract Reentrancy_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultSync_Fuzz_Test) {
        ALMVaultSync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_Reentrancy_EntriesAndExits(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 seed
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded core, and a synchronous vault over token0 whose lock is held.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultSyncExtension vault = vaultExtension(true);
        vault.lock_();

        // And: One of its entries or exits.
        bytes[] memory callDatas = new bytes[](9);
        callDatas[0] = abi.encodeWithSignature("deposit(uint256,address)", 1, users.steward);
        callDatas[1] = abi.encodeWithSignature("deposit(uint256,address,uint256)", 1, users.steward, 0);
        callDatas[2] = abi.encodeWithSignature("mint(uint256,address)", 1, users.steward);
        callDatas[3] = abi.encodeWithSignature("mint(uint256,address,uint256)", 1, users.steward, 1);
        callDatas[4] = abi.encodeWithSignature("redeem(uint256,address,address)", 1, users.steward, users.steward);
        callDatas[5] =
            abi.encodeWithSignature("redeem(uint256,address,address,uint256)", 1, users.steward, users.steward, 0);
        callDatas[6] = abi.encodeWithSignature("withdraw(uint256,address,address)", 1, users.steward, users.steward);
        callDatas[7] =
            abi.encodeWithSignature("withdraw(uint256,address,address,uint256)", 1, users.steward, users.steward, 0);
        callDatas[8] = abi.encodeCall(ALMVaultSync.sweep, ());
        bytes memory callData = callDatas[bound(seed, 0, callDatas.length - 1)];

        // When: Calling it.
        // Then: It reverts on the guard.
        vm.expectRevert(ReentrancyGuardTransient.Reentrancy.selector);
        (bool success,) = address(vault).call(callData);
        assertTrue(success);
    }
}
