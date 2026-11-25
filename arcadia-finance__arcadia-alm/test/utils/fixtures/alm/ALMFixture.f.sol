/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMAdminExtensionExtension } from "../../extensions/ALMAdminExtensionExtension.sol";
import { ALMCoreExtension } from "../../extensions/ALMCoreExtension.sol";
import { ALMFactory } from "../../../../src/factory/ALMFactory.sol";
import { ALMFactoryExtension } from "../../extensions/ALMFactoryExtension.sol";
import { ALMKeeperExtensionExtension } from "../../extensions/ALMKeeperExtensionExtension.sol";
import { ALMSyncExtension } from "../../../../src/vaults/ALMSyncExtension.sol";
import { ALMVaultAsync } from "../../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultSync } from "../../../../src/vaults/ALMVaultSync.sol";
import { CodeHashes } from "../../../../src/factory/types/CodeHashes.sol";
import { Constants } from "../../Constants.sol";
import { Deployment } from "../../../../src/factory/types/Deployment.sol";
import { MetadexCLFixture } from "../metadex/MetadexCLFixture.f.sol";

/**
 * @notice Deploys the ALM factory and creates cores through it, on top of the Metadex CL stack.
 */
abstract contract ALMFixture is MetadexCLFixture {
    /* //////////////////////////////////////////////////////////////
                                 STRUCTS
    ////////////////////////////////////////////////////////////// */

    struct CreationCodes {
        bytes core;
        bytes keeperExtension;
        bytes adminExtension;
        bytes syncVault;
        bytes asyncVault;
        bytes syncExtension;
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function deployFactory(CreationCodes memory codes, address routerTrampoline, address owner, address steward)
        internal
        returns (ALMFactoryExtension factory_)
    {
        factory_ = new ALMFactoryExtension(
            address(POSITION_MANAGER),
            routerTrampoline,
            address(leafVoter),
            address(clGaugeFactory),
            rewardToken,
            false,
            owner,
            codeHashesOf(codes)
        );
        vm.prank(owner);
        factory_.setSteward(steward);
        vm.prank(steward);
        factory_.createExtensions(extensionDeployments(codes));
    }

    function createInThreeTransactions(
        ALMFactory factory_,
        address pool_,
        CreationCodes memory codes,
        address steward,
        address feeRecipient
    ) internal returns (address payable core_) {
        vm.startPrank(steward);
        factory_.createCore(pool_, feeRecipient, new Deployment[](0));
        factory_.resumeCore(pool_, syncVaultDeployments(codes));
        factory_.resumeCore(pool_, asyncVaultAndCoreDeployments(codes));
        vm.stopPrank();
        core_ = payable(factory_.getCore(pool_));
    }

    function extensionCreationCodes() internal pure returns (CreationCodes memory codes) {
        codes = CreationCodes({
            core: type(ALMCoreExtension).creationCode,
            keeperExtension: type(ALMKeeperExtensionExtension).creationCode,
            adminExtension: type(ALMAdminExtensionExtension).creationCode,
            syncVault: type(ALMVaultSync).creationCode,
            asyncVault: type(ALMVaultAsync).creationCode,
            syncExtension: type(ALMSyncExtension).creationCode
        });
    }

    function codeHashesOf(CreationCodes memory codes) internal pure returns (CodeHashes memory hashes) {
        hashes = CodeHashes({
            core: keccak256(codes.core),
            keeperExtension: keccak256(codes.keeperExtension),
            adminExtension: keccak256(codes.adminExtension),
            syncVault: keccak256(codes.syncVault),
            asyncVault: keccak256(codes.asyncVault),
            syncExtension: keccak256(codes.syncExtension)
        });
    }

    function extensionDeployments(CreationCodes memory codes) internal pure returns (Deployment[] memory deployments) {
        deployments = new Deployment[](3);
        deployments[0] = Deployment({
            contracts: uint8(1 << Constants.CONTRACT_KEEPER_EXTENSION), creationCode: codes.keeperExtension
        });
        deployments[1] = Deployment({
            contracts: uint8(1 << Constants.CONTRACT_ADMIN_EXTENSION), creationCode: codes.adminExtension
        });
        deployments[2] =
            Deployment({ contracts: uint8(1 << Constants.CONTRACT_SYNC_EXTENSION), creationCode: codes.syncExtension });
    }

    function syncVaultDeployments(CreationCodes memory codes) internal pure returns (Deployment[] memory deployments) {
        deployments = new Deployment[](1);
        deployments[0] = Deployment({
            contracts: uint8((1 << Constants.CONTRACT_SYNC_VAULT0) | (1 << Constants.CONTRACT_SYNC_VAULT1)),
            creationCode: codes.syncVault
        });
    }

    function asyncVaultAndCoreDeployments(CreationCodes memory codes)
        internal
        pure
        returns (Deployment[] memory deployments)
    {
        deployments = new Deployment[](2);
        deployments[0] = Deployment({
            contracts: uint8((1 << Constants.CONTRACT_ASYNC_VAULT0) | (1 << Constants.CONTRACT_ASYNC_VAULT1)),
            creationCode: codes.asyncVault
        });
        deployments[1] = Deployment({ contracts: uint8(1 << Constants.CONTRACT_CORE), creationCode: codes.core });
    }

    function contractAddress(address factory_, address pool_, uint8 contract_, bytes memory creationCode)
        internal
        pure
        returns (address predicted)
    {
        predicted = vm.computeCreate2Address(keccak256(abi.encode(pool_, contract_)), keccak256(creationCode), factory_);
    }
}
