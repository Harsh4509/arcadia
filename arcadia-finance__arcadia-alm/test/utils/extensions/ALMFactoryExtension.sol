/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory } from "../../../src/factory/ALMFactory.sol";
import { CodeHashes } from "../../../src/factory/types/CodeHashes.sol";
import { VaultParameters } from "../../../src/vaults/types/VaultParameters.sol";

contract ALMFactoryExtension is ALMFactory {
    constructor(
        address positionManager,
        address routerTrampoline,
        address leafVoter,
        address gaugeFactory,
        address rewardToken,
        bool arbBlockNumber,
        address owner_,
        CodeHashes memory codeHashes
    )
        ALMFactory(
            positionManager, routerTrampoline, leafVoter, gaugeFactory, rewardToken, arbBlockNumber, owner_, codeHashes
        )
    { }

    function setIsKeeper(address core, address keeper, bool approved) external {
        isKeeper[core][keeper] = approved;
    }

    function LEAF_VOTER_() external view returns (address leafVoter) {
        leafVoter = LEAF_VOTER;
    }

    function GAUGE_FACTORY_() external view returns (address gaugeFactory) {
        gaugeFactory = GAUGE_FACTORY;
    }

    function FACTORY_REGISTRY_() external view returns (address factoryRegistry) {
        factoryRegistry = FACTORY_REGISTRY;
    }

    function REWARD_TOKEN_() external view returns (address rewardToken) {
        rewardToken = REWARD_TOKEN;
    }

    function codeHashOf_(uint8 contract_) external view returns (bytes32 codeHash) {
        codeHash = _codeHashOf(contract_);
    }

    function salt_(address pool, uint8 contract_) external pure returns (bytes32 salt) {
        salt = _salt(pool, contract_);
    }

    function vaultParametersDuring_(address pool, uint8 contract_) external returns (VaultParameters memory params) {
        deployingPool = pool;
        deployingContract = contract_;
        params = this.vaultParameters();
        deployingPool = address(0);
        deployingContract = 0;
    }
}
