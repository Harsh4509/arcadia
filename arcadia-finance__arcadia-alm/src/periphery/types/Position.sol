/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

/**
 * @notice An account's position on a core, in the field order of LpSugar's position.
 */
struct Position {
    uint256 id;
    address lp;
    uint256 liquidity;
    uint256 staked;
    uint256 amount0;
    uint256 amount1;
    uint256 staked0;
    uint256 staked1;
    uint256 unstakedEarned0;
    uint256 unstakedEarned1;
    uint256 emissionsEarned;
    int24 tickLower;
    int24 tickUpper;
    uint160 sqrtRatioLower;
    uint160 sqrtRatioUpper;
}
