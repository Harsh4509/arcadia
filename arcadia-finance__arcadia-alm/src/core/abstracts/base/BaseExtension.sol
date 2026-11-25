/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { CalldataLogic } from "../../libraries/logic/CalldataLogic.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { RewardCheckpoint } from "../mixins/RewardCheckpoint.sol";

/**
 * @title Base Extension.
 * @author Pragma Labs
 * @notice The per-pool code a core delegates to.
 */
abstract contract BaseExtension is RewardCheckpoint {
    /* //////////////////////////////////////////////////////////////
                               IMMUTABLES
    ////////////////////////////////////////////////////////////// */

    // This extension's own address.
    address internal immutable SELF;

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error OnlyDelegated();

    /* //////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////// */

    modifier onlyDelegated() {
        _requireDelegated();
        _;
    }

    /**
     * @notice Reverts unless a core delegated the call.
     */
    function _requireDelegated() internal view {
        if (address(this) == SELF) revert OnlyDelegated();
    }

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor() {
        SELF = address(this);
    }

    /* //////////////////////////////////////////////////////////////
                               CHECKPOINT
    ////////////////////////////////////////////////////////////// */

    /**
     * @inheritdoc RewardCheckpoint
     */
    function _checkpoint() internal virtual override {
        _state()
            .checkpoint(
                totalSupply(), REWARD_TOKEN, CalldataLogic.decodeCoreImmutables().gauge, GAUGE_FACTORY, LEAF_VOTER
            );
    }

    /* //////////////////////////////////////////////////////////////
                              SHARE TOKEN
    ////////////////////////////////////////////////////////////// */

    /**
     * @inheritdoc ERC20
     */
    function name() public pure override returns (string memory name_) {
        name_ = "";
    }

    /**
     * @inheritdoc ERC20
     */
    function symbol() public pure override returns (string memory symbol_) {
        symbol_ = "";
    }

    /**
     * @inheritdoc ERC20
     */
    function allowance(address, address) public pure override returns (uint256) {
        revert NotSupported();
    }

    /**
     * @inheritdoc ERC20
     */
    function approve(address, uint256) public pure override returns (bool) {
        revert NotSupported();
    }

    /**
     * @inheritdoc ERC20
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert NotSupported();
    }

    /**
     * @inheritdoc ERC20
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert NotSupported();
    }
}
