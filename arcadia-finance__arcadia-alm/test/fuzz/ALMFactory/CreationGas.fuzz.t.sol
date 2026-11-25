/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory } from "../../../src/factory/ALMFactory.sol";
import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { ALMFactoryExtension } from "../../utils/extensions/ALMFactoryExtension.sol";
import { Deployment } from "../../../src/factory/types/Deployment.sol";

/**
 * @notice Gas of the extension creation and of the creation transactions of a pool, read with --isolate.
 */
contract CreationGas_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The gas a transaction may use under EIP-7825.
    uint256 internal constant MAX_CREATION_GAS = 1 << 24;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_creationGas_Extensions(PoolState memory poolState) public {
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

        // When: The steward creates the keeper, admin and sync extensions.
        Deployment[] memory deployments = extensionDeployments(codes);
        vm.prank(users.steward);
        factory_.createExtensions(deployments);
        uint256 used = transactionGasUsed(
            vm.lastFrameGas().gasTotalUsed, abi.encodeCall(ALMFactory.createExtensions, (deployments))
        );

        // Then: The transaction fits the creation budget.
        emit log_named_uint("gas creation extensions", used);
        assertLe(used, MAX_CREATION_GAS);
    }

    function testFuzz_Success_creationGas_SyncVaults(PoolState memory poolState) public {
        // Given: A creation opened.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreStarted();

        // When: The steward creates both synchronous vaults.
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());
        vm.prank(users.steward);
        almFactory.resumeCore(address(pool), deployments);
        uint256 used = transactionGasUsed(
            vm.lastFrameGas().gasTotalUsed, abi.encodeCall(ALMFactory.resumeCore, (address(pool), deployments))
        );

        // Then: The transaction fits the creation budget.
        emit log_named_uint("gas creation sync vaults", used);
        assertLe(used, MAX_CREATION_GAS);
    }

    function testFuzz_Success_creationGas_AsyncVaultsAndCore(PoolState memory poolState) public {
        // Given: A creation with both synchronous vaults.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setSyncVaultsCreated();

        // When: The steward creates both asynchronous vaults and the core.
        Deployment[] memory deployments = asyncVaultAndCoreDeployments(creationCodes());
        vm.prank(users.steward);
        almFactory.resumeCore(address(pool), deployments);
        uint256 used = transactionGasUsed(
            vm.lastFrameGas().gasTotalUsed, abi.encodeCall(ALMFactory.resumeCore, (address(pool), deployments))
        );

        // Then: The transaction fits the creation budget.
        emit log_named_uint("gas creation async vaults and core", used);
        assertLe(used, MAX_CREATION_GAS);
    }
}
