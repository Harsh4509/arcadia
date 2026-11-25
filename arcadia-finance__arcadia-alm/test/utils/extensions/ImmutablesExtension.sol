/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Immutables } from "../../../src/core/abstracts/storage/Immutables.sol";

abstract contract ImmutablesExtension is Immutables {
    function immutables_() external view returns (address[16] memory values, int24 tickSpacing_) {
        values = [
            FACTORY,
            POSITION_MANAGER,
            ROUTER_TRAMPOLINE,
            LEAF_VOTER,
            GAUGE_FACTORY,
            REWARD_TOKEN,
            POOL,
            TOKEN0,
            TOKEN1,
            GAUGE,
            SYNC_VAULT0,
            SYNC_VAULT1,
            ASYNC_VAULT0,
            ASYNC_VAULT1,
            KEEPER_EXTENSION,
            ADMIN_EXTENSION
        ];
        tickSpacing_ = TICK_SPACING;
    }
}
