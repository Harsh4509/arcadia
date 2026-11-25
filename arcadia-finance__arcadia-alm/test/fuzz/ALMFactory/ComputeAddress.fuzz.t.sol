/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { BaseFactory } from "../../../src/factory/abstracts/base/BaseFactory.sol";
import { Constants } from "../../utils/Constants.sol";

/**
 * @notice Fuzz tests for the function "computeAddress" of contract "ALMFactory".
 */
contract ComputeAddress_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_computeAddress_InvalidContracts(PoolState memory poolState, address pool_, uint8 contract_)
        public
    {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A contract past the core.
        contract_ = uint8(bound(contract_, Constants.CONTRACT_CORE + 1, type(uint8).max));

        // When: Computing its address.
        // Then: It reverts.
        vm.expectRevert(BaseFactory.InvalidContracts.selector);
        almFactory.computeAddress(pool_, contract_);
    }

    function testFuzz_Success_computeAddress(PoolState memory poolState, address pool_, uint8 contract_) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A contract from the first synchronous vault to the core.
        contract_ = uint8(bound(contract_, Constants.CONTRACT_SYNC_VAULT0, Constants.CONTRACT_CORE));

        // When: Computing its address.
        address computed = almFactory.computeAddress(pool_, contract_);

        // Then: It is the contract's CREATE2 address, salted on the pool and contract.
        assertEq(
            computed,
            contractAddress(
                address(almFactory),
                pool_,
                contract_,
                deploymentsFor(uint8(1 << contract_), creationCodes())[0].creationCode
            )
        );
    }
}
