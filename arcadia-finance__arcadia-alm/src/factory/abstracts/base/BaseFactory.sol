/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { CodeHashes } from "../../types/CodeHashes.sol";
import { CoreParameters } from "../../../core/types/CoreParameters.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { Deployment } from "../../types/Deployment.sol";
import { ILeafVoter } from "../../../interfaces/ILeafVoter.sol";
import { IMetadexCLPool } from "../../../interfaces/IMetadexCLPool.sol";
import { PendingCreation } from "../../types/PendingCreation.sol";
import { VaultParameters } from "../../../vaults/types/VaultParameters.sol";
import { Vaults } from "../../../core/types/Vaults.sol";

/**
 * @title Base Factory.
 * @author Pragma Labs
 * @notice Deploys the contracts of a pool from hash-checked creation code.
 */
// forge-lint: disable-next-item(require-revert-in-loop, uninitialized-local)
abstract contract BaseFactory {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract of a pool that is its synchronous vault over token0.
    uint8 internal constant CONTRACT_SYNC_VAULT0 = 0;
    // The contract of a pool that is its synchronous vault over token1.
    uint8 internal constant CONTRACT_SYNC_VAULT1 = 1;
    // The contract of a pool that is its asynchronous vault over token0.
    uint8 internal constant CONTRACT_ASYNC_VAULT0 = 2;
    // The contract of a pool that is its asynchronous vault over token1.
    uint8 internal constant CONTRACT_ASYNC_VAULT1 = 3;
    // The sync extension of every synchronous vault, created once.
    uint8 internal constant CONTRACT_SYNC_EXTENSION = 4;
    // The keeper extension of every core, created once.
    uint8 internal constant CONTRACT_KEEPER_EXTENSION = 5;
    // The admin extension of every core, created once.
    uint8 internal constant CONTRACT_ADMIN_EXTENSION = 6;
    // The contract of a pool that is its core, created last.
    uint8 internal constant CONTRACT_CORE = 7;
    // The contracts of a pool that are synchronous vaults.
    uint8 internal constant SYNC_VAULT_CONTRACTS =
        (uint8(1) << CONTRACT_SYNC_VAULT0) | (uint8(1) << CONTRACT_SYNC_VAULT1);
    // The contracts of a pool that are asynchronous vaults.
    uint8 internal constant ASYNC_VAULT_CONTRACTS =
        (uint8(1) << CONTRACT_ASYNC_VAULT0) | (uint8(1) << CONTRACT_ASYNC_VAULT1);
    // Every contract of a pool but its core.
    uint8 internal constant CORE_DEPENDENCIES = SYNC_VAULT_CONTRACTS | ASYNC_VAULT_CONTRACTS;
    // The extensions, created once for every pool.
    uint8 internal constant EXTENSION_CONTRACTS = (uint8(1) << CONTRACT_SYNC_EXTENSION)
        | (uint8(1) << CONTRACT_KEEPER_EXTENSION) | (uint8(1) << CONTRACT_ADMIN_EXTENSION);

    /* //////////////////////////////////////////////////////////////
                                 STORAGE
    ////////////////////////////////////////////////////////////// */

    // The creation in progress of each pool, deleted when its core deploys.
    mapping(address pool => PendingCreation creation) public pending;
    // The pool a contract is being created for, zero outside a creation call.
    address internal transient deployingPool;
    // The contract being created.
    uint8 internal transient deployingContract;

    /* //////////////////////////////////////////////////////////////
                               IMMUTABLES
    ////////////////////////////////////////////////////////////// */

    // The keccak256 of the creation code of ALMAdminExtension.
    bytes32 public immutable ADMIN_EXTENSION_CODE_HASH;
    // The keccak256 of the creation code of ALMVaultAsync.
    bytes32 public immutable ASYNC_VAULT_CODE_HASH;
    // The keccak256 of the creation code of ALMCore.
    bytes32 public immutable CORE_CODE_HASH;
    // The keccak256 of the creation code of ALMKeeperExtension.
    bytes32 public immutable KEEPER_EXTENSION_CODE_HASH;
    // The keccak256 of the creation code of ALMSyncExtension.
    bytes32 public immutable SYNC_EXTENSION_CODE_HASH;
    // The keccak256 of the creation code of ALMVaultSync.
    bytes32 public immutable SYNC_VAULT_CODE_HASH;
    // True when the chain's gauges count blocks with ArbSys.arbBlockNumber.
    bool internal immutable ARB_BLOCK_NUMBER;
    // The registry that maps gauges to their target pool.
    address internal immutable FACTORY_REGISTRY;
    // The factory that created every gauge on the chain.
    address internal immutable GAUGE_FACTORY;
    // The LeafVoter of the chain.
    address internal immutable LEAF_VOTER;
    // The Metadex CL position manager.
    address public immutable POSITION_MANAGER;
    // The token the emissions handler delivers on a claim.
    address internal immutable REWARD_TOKEN;
    // The router trampoline keeper swaps run through.
    address public immutable ROUTER_TRAMPOLINE;

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error CodeMismatch();
    error ContractExists();
    error ContractsMissing();
    error InvalidContracts();
    error ZeroAddress();

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(
        address positionManager,
        address routerTrampoline,
        address leafVoter,
        address gaugeFactory,
        address rewardToken,
        bool arbBlockNumber,
        CodeHashes memory codeHashes
    ) {
        // Checks.
        if (positionManager == address(0)) revert ZeroAddress();
        if (routerTrampoline == address(0)) revert ZeroAddress();
        if (leafVoter == address(0)) revert ZeroAddress();
        if (gaugeFactory == address(0)) revert ZeroAddress();
        if (rewardToken == address(0)) revert ZeroAddress();

        // Set the external contracts.
        POSITION_MANAGER = positionManager;
        ROUTER_TRAMPOLINE = routerTrampoline;
        LEAF_VOTER = leafVoter;
        GAUGE_FACTORY = gaugeFactory;
        REWARD_TOKEN = rewardToken;
        ARB_BLOCK_NUMBER = arbBlockNumber;

        // Get the factory registry from the leaf voter.
        FACTORY_REGISTRY = ILeafVoter(leafVoter).FACTORY_REGISTRY();

        // Set the creation code hashes.
        CORE_CODE_HASH = codeHashes.core;
        KEEPER_EXTENSION_CODE_HASH = codeHashes.keeperExtension;
        ADMIN_EXTENSION_CODE_HASH = codeHashes.adminExtension;
        SYNC_VAULT_CODE_HASH = codeHashes.syncVault;
        ASYNC_VAULT_CODE_HASH = codeHashes.asyncVault;
        SYNC_EXTENSION_CODE_HASH = codeHashes.syncExtension;
    }

    /* //////////////////////////////////////////////////////////////
                               PARAMETERS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The immutables of the core or extension under creation.
     * @return params The parameters, with the pool fields zero outside a pool creation.
     */
    function parameters() external view returns (CoreParameters memory params) {
        // Set the parameters every core and extension shares.
        params.positionManager = POSITION_MANAGER;
        params.routerTrampoline = ROUTER_TRAMPOLINE;
        params.leafVoter = LEAF_VOTER;
        params.gaugeFactory = GAUGE_FACTORY;
        params.rewardToken = REWARD_TOKEN;
        params.arbBlockNumber = ARB_BLOCK_NUMBER;
        params.keeperExtension = computeAddress(address(0), CONTRACT_KEEPER_EXTENSION);
        params.adminExtension = computeAddress(address(0), CONTRACT_ADMIN_EXTENSION);

        // If no pool is under creation, return the shared parameters only.
        address pool = deployingPool;
        if (pool == address(0)) return params;

        // Set the parameters of the pool under creation.
        params.pool = pool;
        params.token0 = IMetadexCLPool(pool).token0();
        params.token1 = IMetadexCLPool(pool).token1();
        params.gauge = IMetadexCLPool(pool).gauge();
        params.tickSpacing = IMetadexCLPool(pool).tickSpacing();
        params.feeRecipient = pending[pool].feeRecipient;
        params.vaults = _vaults(pool);
    }

    /**
     * @notice The immutables of the vault under creation.
     * @return params The parameters, zero outside a creation call.
     */
    function vaultParameters() external view returns (VaultParameters memory params) {
        // If no pool is under creation, return zero parameters.
        address pool = deployingPool;
        if (pool == address(0)) return params;

        // Set the parameters of the vault under creation.
        uint8 contract_ = deployingContract;
        params.core = computeAddress(pool, CONTRACT_CORE);
        params.pool = pool;
        params.assetIsToken0 = contract_ == CONTRACT_SYNC_VAULT0 || contract_ == CONTRACT_ASYNC_VAULT0;

        // If the vault is a sync vault, set its sync extension.
        if (contract_ <= CONTRACT_SYNC_VAULT1) {
            params.syncExtension = computeAddress(address(0), CONTRACT_SYNC_EXTENSION);
        }
    }

    /* //////////////////////////////////////////////////////////////
                                CREATION
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The address a contract of a pool is created at.
     * @param pool The Metadex CL pool.
     * @param contract_ The contract, from CONTRACT_SYNC_VAULT0 to CONTRACT_CORE.
     * @return addr The address.
     */
    function computeAddress(address pool, uint8 contract_) public view returns (address addr) {
        addr = Create2.computeAddress(_salt(pool, contract_), _codeHashOf(contract_));
    }

    /**
     * @notice The creation code hash a contract is created from.
     * @param contract_ The contract, from CONTRACT_SYNC_VAULT0 to CONTRACT_CORE.
     * @return codeHash The keccak256 of its creation code.
     */
    function _codeHashOf(uint8 contract_) internal view returns (bytes32 codeHash) {
        if (contract_ <= CONTRACT_SYNC_VAULT1) codeHash = SYNC_VAULT_CODE_HASH;
        else if (contract_ <= CONTRACT_ASYNC_VAULT1) codeHash = ASYNC_VAULT_CODE_HASH;
        else if (contract_ == CONTRACT_SYNC_EXTENSION) codeHash = SYNC_EXTENSION_CODE_HASH;
        else if (contract_ == CONTRACT_KEEPER_EXTENSION) codeHash = KEEPER_EXTENSION_CODE_HASH;
        else if (contract_ == CONTRACT_ADMIN_EXTENSION) codeHash = ADMIN_EXTENSION_CODE_HASH;
        else if (contract_ == CONTRACT_CORE) codeHash = CORE_CODE_HASH;
        else revert InvalidContracts();
    }

    /**
     * @notice The CREATE2 salt of a contract of a pool.
     * @param pool The Metadex CL pool.
     * @param contract_ The contract.
     * @return salt The salt.
     */
    function _salt(address pool, uint8 contract_) internal pure returns (bytes32 salt) {
        salt = keccak256(abi.encode(pool, contract_));
    }

    /**
     * @notice Deploys the contracts the deployments name.
     * @param pool The Metadex CL pool.
     * @param deployments The creation code of each kind, with the contracts it deploys.
     * @return core The core, zero when the deployments do not deploy it.
     */
    function _deploy(address pool, Deployment[] calldata deployments) internal returns (address core) {
        // Cache the contracts already deployed for the pool.
        uint8 contractsDeployed = pending[pool].contractsDeployed;

        // Mark the pool as under creation.
        deployingPool = pool;

        // Deploy the contracts of each deployment.
        for (uint256 i; i < deployments.length; ++i) {
            // Cache the contracts of the deployment.
            uint8 contracts = deployments[i].contracts;

            // Checks.
            if (contracts == 0) revert InvalidContracts();
            if (pool == address(0) ? contracts & ~EXTENSION_CONTRACTS != 0 : contracts & EXTENSION_CONTRACTS != 0) {
                revert InvalidContracts();
            }

            // Calculate the code hash of the deployment.
            bytes32 codeHash;
            for (uint8 contract_; contract_ <= CONTRACT_CORE; ++contract_) {
                if (contracts & (1 << contract_) == 0) continue;
                bytes32 contractHash = _codeHashOf(contract_);
                if (codeHash == 0) codeHash = contractHash;
                else if (contractHash != codeHash) revert InvalidContracts();
            }

            // Cache the creation code of the deployment.
            bytes memory creationCode = deployments[i].creationCode;

            // Checks.
            if (keccak256(creationCode) != codeHash) revert CodeMismatch();

            // Deploy each contract of the deployment from the creation code.
            for (uint8 contract_; contract_ <= CONTRACT_CORE; ++contract_) {
                // If the deployment does not name the contract, skip it.
                if (contracts & (1 << contract_) == 0) continue;

                // Checks.
                if (contractsDeployed & (1 << contract_) != 0) revert ContractExists();
                if (contract_ == CONTRACT_CORE && contractsDeployed != CORE_DEPENDENCIES) revert ContractsMissing();

                // Mark the contract as under creation.
                deployingContract = contract_;

                // Deploy the contract at its CREATE2 address.
                address deployed = Create2.deploy(0, _salt(pool, contract_), creationCode);

                // Mark the contract as deployed.
                contractsDeployed |= uint8(1 << contract_);

                // If the contract is the core, set the core to its address.
                if (contract_ == CONTRACT_CORE) core = deployed;
            }
        }

        // Clear the pool and the contract under creation.
        deployingPool = address(0);
        deployingContract = 0;

        // Update State.
        if (core == address(0)) pending[pool].contractsDeployed = contractsDeployed;
        else delete pending[pool];
    }

    /**
     * @notice The four vaults of a pool.
     * @param pool The Metadex CL pool.
     * @return vaults The addresses the vaults are created at.
     */
    function _vaults(address pool) internal view returns (Vaults memory vaults) {
        vaults.syncVault0 = computeAddress(pool, CONTRACT_SYNC_VAULT0);
        vaults.syncVault1 = computeAddress(pool, CONTRACT_SYNC_VAULT1);
        vaults.asyncVault0 = computeAddress(pool, CONTRACT_ASYNC_VAULT0);
        vaults.asyncVault1 = computeAddress(pool, CONTRACT_ASYNC_VAULT1);
    }
}
