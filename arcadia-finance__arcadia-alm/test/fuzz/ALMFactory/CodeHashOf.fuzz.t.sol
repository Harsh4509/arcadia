/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { BaseFactory } from "../../../src/factory/abstracts/base/BaseFactory.sol";
import { Constants } from "../../utils/Constants.sol";

/**
 * @notice Fuzz tests for the function "_codeHashOf" of contract "BaseFactory".
 */
contract CodeHashOf_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_codeHashOf_InvalidContracts(PoolState memory poolState, uint8 contract_) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A contract past the core.
        contract_ = uint8(bound(contract_, Constants.CONTRACT_CORE + 1, type(uint8).max));

        // When: Reading its creation code hash.
        // Then: It reverts.
        vm.expectRevert(BaseFactory.InvalidContracts.selector);
        almFactory.codeHashOf_(contract_);
    }

    function testFuzz_Success_codeHashOf_IsTheHashOfItsKind(PoolState memory poolState, uint8 contract_) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A contract up to the core.
        contract_ = uint8(bound(contract_, 0, Constants.CONTRACT_CORE));

        // When: Reading its creation code hash.
        bytes32 codeHash = almFactory.codeHashOf_(contract_);

        // Then: It is the keccak256 of the creation code of the contract's kind.
        bytes memory expected;
        if (contract_ <= Constants.CONTRACT_SYNC_VAULT1) expected = creationCodes().syncVault;
        else if (contract_ <= Constants.CONTRACT_ASYNC_VAULT1) expected = creationCodes().asyncVault;
        else if (contract_ == Constants.CONTRACT_SYNC_EXTENSION) expected = creationCodes().syncExtension;
        else if (contract_ == Constants.CONTRACT_KEEPER_EXTENSION) expected = creationCodes().keeperExtension;
        else if (contract_ == Constants.CONTRACT_ADMIN_EXTENSION) expected = creationCodes().adminExtension;
        else expected = creationCodes().core;
        assertEq(codeHash, keccak256(expected));
    }
}
