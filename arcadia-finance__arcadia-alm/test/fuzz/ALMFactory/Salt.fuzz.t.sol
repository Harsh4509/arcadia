/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_salt" of contract "BaseFactory".
 */
contract Salt_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_salt_HashesThePoolAndTheContract(
        PoolState memory poolState,
        address pool_,
        uint8 contract_
    ) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // When: Reading the salt of a contract of a pool.
        bytes32 salt = almFactory.salt_(pool_, contract_);

        // Then: It is the keccak256 of the pool and the contract, ABI-encoded.
        assertEq(salt, keccak256(abi.encode(pool_, contract_)));
    }
}
