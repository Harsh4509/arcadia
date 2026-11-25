/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { Vaults } from "../../../src/core/types/Vaults.sol";

/**
 * @notice Fuzz tests for the function "getVaults" of contract "ALMFactory".
 */
contract GetVaults_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getVaults_EmptyForAnythingNotCreated(PoolState memory poolState, address candidate)
        public
    {
        // Given: A factory with a core over the pool.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // And: A candidate that is not that core.
        vm.assume(candidate != address(core));

        // When: Reading its vaults.
        Vaults memory read = almFactory.getVaults(candidate);

        // Then: All four are zero.
        assertEq(read.syncVault0, address(0));
        assertEq(read.syncVault1, address(0));
        assertEq(read.asyncVault0, address(0));
        assertEq(read.asyncVault1, address(0));
    }

    function testFuzz_Success_getVaults_TheFourVaultsOfACreatedCore(PoolState memory poolState) public {
        // Given: A factory with a core over the pool.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();

        // When: Reading the core's vaults.
        Vaults memory read = almFactory.getVaults(address(core));

        // Then: Each is its vault's CREATE2 address, salted on the pool and contract.
        CreationCodes memory codes = creationCodes();
        assertEq(
            read.syncVault0,
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_SYNC_VAULT0, codes.syncVault)
        );
        assertEq(
            read.syncVault1,
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_SYNC_VAULT1, codes.syncVault)
        );
        assertEq(
            read.asyncVault0,
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_ASYNC_VAULT0, codes.asyncVault)
        );
        assertEq(
            read.asyncVault1,
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_ASYNC_VAULT1, codes.asyncVault)
        );
    }
}
