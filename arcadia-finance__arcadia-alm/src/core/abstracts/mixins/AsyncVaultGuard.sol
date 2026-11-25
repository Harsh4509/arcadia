/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { BaseCore } from "../base/BaseCore.sol";

/**
 * @title Async Vault Guard.
 * @author Pragma Labs
 * @notice The asynchronous vault check.
 */
// forge-lint: disable-next-item(require-revert-in-loop)
abstract contract AsyncVaultGuard is BaseCore {
    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error OnlyAsyncVault();

    /* //////////////////////////////////////////////////////////////
                                  GUARD
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Identifies the asynchronous vault that is calling, reverting for any other caller.
     * @param caller The caller to check.
     * @return asset The vault's asset.
     * @return isToken0 True when that asset is token0.
     */
    function _requireAsyncVault(address caller) internal view returns (address asset, bool isToken0) {
        (asset, isToken0) = _requireAsyncVault(caller, ASYNC_VAULT0, ASYNC_VAULT1, TOKEN0, TOKEN1);
    }

    /**
     * @notice Identifies the asynchronous vault that is calling, reverting for any other caller.
     * @param caller The caller to check.
     * @param asyncVault0 The asynchronous vault over token0.
     * @param asyncVault1 The asynchronous vault over token1.
     * @param token0 The token0 of the pool.
     * @param token1 The token1 of the pool.
     * @return asset The vault's asset.
     * @return isToken0 True when that asset is token0.
     */
    function _requireAsyncVault(
        address caller,
        address asyncVault0,
        address asyncVault1,
        address token0,
        address token1
    ) internal pure returns (address asset, bool isToken0) {
        isToken0 = caller == asyncVault0;
        if (!isToken0 && caller != asyncVault1) revert OnlyAsyncVault();
        asset = isToken0 ? token0 : token1;
    }
}
