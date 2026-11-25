/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ALMCoreViewLogic } from "../../../core/libraries/logic/ALMCoreViewLogic.sol";
import { ERC7540Operator } from "../tokens/ERC7540Operator.sol";
import { IALMCore } from "../../../interfaces/IALMCore.sol";
import { IBaseFactory } from "../../../interfaces/IBaseFactory.sol";
import { IMetadexCLPool } from "../../../interfaces/IMetadexCLPool.sol";
import { VaultParameters } from "../../types/VaultParameters.sol";

/**
 * @title Base Vault.
 * @author Pragma Labs
 * @notice What an entry point over one pool token holds and how it values the share it issues.
 */
// forge-lint: disable-next-item(reentrancy-events, unused-return)
abstract contract BaseVault is ERC7540Operator {
    using ALMCoreViewLogic for IALMCore;

    /* //////////////////////////////////////////////////////////////
                                 STORAGE
    ////////////////////////////////////////////////////////////// */

    // Blocks entries, and on the sync vault exits too.
    bool public paused;

    /* //////////////////////////////////////////////////////////////
                               IMMUTABLES
    ////////////////////////////////////////////////////////////// */

    // True when this vault's asset is token0.
    bool internal immutable ASSET_IS_TOKEN0;
    // The pool token this vault takes and pays.
    address internal immutable ASSET;
    // The factory that deployed this vault and forwards every governed call.
    address internal immutable FACTORY;
    // The Metadex CL pool.
    address internal immutable POOL;
    // The core that issues the share this vault is an entry point to.
    IALMCore internal immutable ALM_CORE;

    /* //////////////////////////////////////////////////////////////
                                 EVENTS
    ////////////////////////////////////////////////////////////// */

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event PausedSet(bool paused);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error Paused();

    /* //////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////// */

    modifier onlyFactory() {
        _requireFactory();
        _;
    }

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @notice Reverts unless the factory is calling.
     */
    function _requireFactory() internal view {
        if (msg.sender != FACTORY) revert Unauthorized();
    }

    /**
     * @notice Reverts while the vault is paused.
     */
    function _requireNotPaused() internal view {
        if (paused) revert Paused();
    }

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor() {
        VaultParameters memory params = IBaseFactory(msg.sender).vaultParameters();

        FACTORY = msg.sender;
        ALM_CORE = IALMCore(params.core);
        POOL = params.pool;

        ASSET_IS_TOKEN0 = params.assetIsToken0;
        ASSET = params.assetIsToken0 ? IMetadexCLPool(params.pool).token0() : IMetadexCLPool(params.pool).token1();
    }

    /* //////////////////////////////////////////////////////////////
                               GOVERNANCE
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets whether the vault is paused.
     * @param paused_ True to pause, false to lift the pause.
     */
    function setPaused(bool paused_) external onlyFactory {
        paused = paused_;

        emit PausedSet(paused_);
    }

    /* //////////////////////////////////////////////////////////////
                                OPERATORS
    ////////////////////////////////////////////////////////////// */

    /**
     * @inheritdoc ERC7540Operator
     * @dev One approval through any of this core's vaults covers all of them.
     */
    function _setOperator(address controller, address operator, bool approved) internal override {
        ALM_CORE.setOperator(controller, operator, approved);
    }

    /**
     * @inheritdoc ERC7540Operator
     */
    function _isOperator(address controller, address operator) internal view override returns (bool status) {
        status = ALM_CORE.isOperator(controller, operator);
    }

    /* //////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The share this vault is an entry point to.
     * @return share_ The share.
     */
    function share() external view override returns (address share_) {
        share_ = address(ALM_CORE);
    }

    /**
     * @notice The pool token this vault takes and pays.
     * @return asset_ The asset.
     */
    function asset() external view override returns (address asset_) {
        asset_ = ASSET;
    }
}
