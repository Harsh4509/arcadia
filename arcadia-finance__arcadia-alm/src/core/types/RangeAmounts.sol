/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

/**
 * @notice The most token amounts the position manager may take for a range's liquidity owed.
 */
struct RangeAmounts {
    uint256 amount0;
    uint256 amount1;
}
