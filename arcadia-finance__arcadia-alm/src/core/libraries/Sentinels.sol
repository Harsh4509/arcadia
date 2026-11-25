/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

/**
 * @title Sentinels.
 * @author Pragma Labs
 * @notice Sentinel values used by the keeper's step encoding.
 */
library Sentinels {
    // Resolves to its bps share of the token's open buffer.
    uint256 internal constant OPEN_BALANCE = 1 << 255;
    // Resolves to the swap input moving the open buffer to its bps share of token0 by value.
    uint256 internal constant TO_TARGET_RATIO = 1 << 254;
    // Resolves to the liquidity on the side of the range the step decreases.
    uint128 internal constant RANGE_LIQUIDITY = type(uint128).max;
    // Resolves to the range the plan opened at the step's index.
    uint96 internal constant OPENED = type(uint96).max;
}
