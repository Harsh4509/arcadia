/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

/**
 * @notice The immutables of a core that its extensions use.
 */
struct CoreImmutables {
    int24 tickSpacing;
    address pool;
    address token0;
    address token1;
    address gauge;
    address asyncVault0;
    address asyncVault1;
    address syncVault0;
    address syncVault1;
}
