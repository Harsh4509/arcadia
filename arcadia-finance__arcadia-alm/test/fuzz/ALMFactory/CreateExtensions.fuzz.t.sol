/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory } from "../../../src/factory/ALMFactory.sol";
import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { ALMFactoryExtension } from "../../utils/extensions/ALMFactoryExtension.sol";
import { BaseFactory } from "../../../src/factory/abstracts/base/BaseFactory.sol";
import { Constants } from "../../utils/Constants.sol";
import { CoreParameters } from "../../../src/core/types/CoreParameters.sol";
import { Deployment } from "../../../src/factory/types/Deployment.sol";
import { Ownable } from "@solady/auth/Ownable.sol";

/**
 * @notice Fuzz tests for the function "createExtensions" of contract "ALMFactory".
 */
contract CreateExtensions_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_createExtensions_Unauthorized(PoolState memory poolState, address caller) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: The caller is not the steward.
        vm.assume(caller != users.steward);
        Deployment[] memory deployments = extensionDeployments(creationCodes());

        // When: Calling createExtensions().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.createExtensions(deployments);
    }

    function testFuzz_Revert_createExtensions_InvalidContracts_PoolContract(PoolState memory poolState, uint8 contract_)
        public
    {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A deployment naming a contract of a pool, with its creation code.
        contract_ = uint8(bound(contract_, Constants.CONTRACT_SYNC_VAULT0, Constants.CONTRACT_ASYNC_VAULT1 + 1));
        if (contract_ > Constants.CONTRACT_ASYNC_VAULT1) contract_ = Constants.CONTRACT_CORE;
        Deployment[] memory deployments = deploymentsFor(uint8(1 << contract_), creationCodes());

        // When: The steward creates the extensions with it.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseFactory.InvalidContracts.selector);
        almFactory.createExtensions(deployments);
    }

    function testFuzz_Revert_createExtensions_ContractExists(PoolState memory poolState, uint8 contract_) public {
        // Given: A factory over a pool at a fuzzed price, its extensions created.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A deployment naming one of the extensions.
        contract_ = uint8(bound(contract_, Constants.CONTRACT_SYNC_EXTENSION, Constants.CONTRACT_ADMIN_EXTENSION));
        Deployment[] memory deployments = deploymentsFor(uint8(1 << contract_), creationCodes());

        // When: The steward creates it again.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseFactory.ContractExists.selector);
        almFactory.createExtensions(deployments);
    }

    function testFuzz_Success_createExtensions_EachExtensionAtItsAddress(PoolState memory poolState) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A second factory without extensions.
        CreationCodes memory codes = creationCodes();
        ALMFactoryExtension factory_ = new ALMFactoryExtension(
            address(POSITION_MANAGER),
            address(routerTrampoline),
            address(leafVoter),
            address(clGaugeFactory),
            rewardToken,
            false,
            users.owner,
            codeHashesOf(codes)
        );
        vm.prank(users.owner);
        factory_.setSteward(users.steward);

        // When: The steward creates the extensions.
        vm.prank(users.steward);
        factory_.createExtensions(extensionDeployments(codes));

        // Then: Each extension has code at its CREATE2 address under the zero pool.
        for (
            uint8 contract_ = Constants.CONTRACT_SYNC_EXTENSION;
            contract_ <= Constants.CONTRACT_ADMIN_EXTENSION;
            ++contract_
        ) {
            bytes memory code = deploymentsFor(uint8(1 << contract_), codes)[0].creationCode;
            address predicted = contractAddress(address(factory_), address(0), contract_, code);
            assertGt(predicted.code.length, 0);
            assertEq(factory_.computeAddress(address(0), contract_), predicted);
        }

        // And: The core parameters point every core at the keeper and admin extensions.
        CoreParameters memory params = factory_.parameters();
        assertEq(
            params.keeperExtension,
            contractAddress(address(factory_), address(0), Constants.CONTRACT_KEEPER_EXTENSION, codes.keeperExtension)
        );
        assertEq(
            params.adminExtension,
            contractAddress(address(factory_), address(0), Constants.CONTRACT_ADMIN_EXTENSION, codes.adminExtension)
        );
    }
}
