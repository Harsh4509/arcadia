/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic } from "../../../src/core/libraries/logic/ALMCoreViewLogic.sol";
import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { IALMCore } from "../../../src/interfaces/IALMCore.sol";

contract ALMVaultSyncExtension is ALMVaultSync {
    using ALMCoreViewLogic for IALMCore;

    function lock_() external {
        _lock();
    }

    function quotable_() external view returns (bool quotable) {
        (quotable,,) = ALM_CORE.quotable(POOL, ASSET_IS_TOKEN0, paused);
    }
}
