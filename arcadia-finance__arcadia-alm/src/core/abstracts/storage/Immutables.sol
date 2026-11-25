/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { CoreParameters } from "../../types/CoreParameters.sol";
import { IBaseFactory } from "../../../interfaces/IBaseFactory.sol";

/**
 * @title Immutables.
 * @author Pragma Labs
 * @notice The immutables of a core and its extensions.
 */
abstract contract Immutables {
    /* //////////////////////////////////////////////////////////////
                               IMMUTABLES
    ////////////////////////////////////////////////////////////// */

    // The tick spacing of the pool.
    int24 internal immutable TICK_SPACING;
    // The extension the core delegates governance and maintenance to.
    address internal immutable ADMIN_EXTENSION;
    // The asynchronous vault over token0.
    address internal immutable ASYNC_VAULT0;
    // The asynchronous vault over token1.
    address internal immutable ASYNC_VAULT1;
    // The ALMFactory that deployed this core.
    address internal immutable FACTORY;
    // The CL gauge of the pool.
    address internal immutable GAUGE;
    // The factory that created every gauge on the chain.
    address internal immutable GAUGE_FACTORY;
    // The extension the core delegates keeper plans to.
    address internal immutable KEEPER_EXTENSION;
    // The LeafVoter of the chain.
    address internal immutable LEAF_VOTER;
    // The Metadex CL pool.
    address internal immutable POOL;
    // The Metadex CL position manager.
    address internal immutable POSITION_MANAGER;
    // The token the emissions handler delivers on a claim.
    address internal immutable REWARD_TOKEN;
    // The router trampoline the keeper swaps through.
    address internal immutable ROUTER_TRAMPOLINE;
    // The synchronous vault over token0.
    address internal immutable SYNC_VAULT0;
    // The synchronous vault over token1.
    address internal immutable SYNC_VAULT1;
    // The token0 of the pool.
    address internal immutable TOKEN0;
    // The token1 of the pool.
    address internal immutable TOKEN1;

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor() {
        CoreParameters memory params = IBaseFactory(msg.sender).parameters();

        FACTORY = msg.sender;
        POSITION_MANAGER = params.positionManager;
        ROUTER_TRAMPOLINE = params.routerTrampoline;
        LEAF_VOTER = params.leafVoter;
        GAUGE_FACTORY = params.gaugeFactory;
        REWARD_TOKEN = params.rewardToken;
        POOL = params.pool;
        TOKEN0 = params.token0;
        TOKEN1 = params.token1;
        GAUGE = params.gauge;
        TICK_SPACING = params.tickSpacing;
        SYNC_VAULT0 = params.vaults.syncVault0;
        SYNC_VAULT1 = params.vaults.syncVault1;
        ASYNC_VAULT0 = params.vaults.asyncVault0;
        ASYNC_VAULT1 = params.vaults.asyncVault1;
        KEEPER_EXTENSION = params.keeperExtension;
        ADMIN_EXTENSION = params.adminExtension;
    }
}
